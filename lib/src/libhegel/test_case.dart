/// One execution of a test body, and the values drawn for it.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'codec/bigint.dart';
import 'collection.dart';
import 'errors.dart';
import 'marshal.dart';
import 'pool.dart';
import 'run.dart';
import 'session.dart';
import 'settings.dart';
import 'span.dart';
import 'state_machine.dart';
import 'string_generator.dart';

/// A drawn calendar date.
///
/// A record rather than a `DateTime` because the engine's range -- years from
/// -999999 to 999999 -- is wider than `DateTime` accepts, and deciding how to
/// narrow it is the generator layer's business, not this one's.
typedef HegelDate = ({int year, int month, int day});

/// A drawn time of day, to microsecond resolution.
typedef HegelTime = ({int hour, int minute, int second, int microsecond});

/// A drawn date and time of day, with no time zone.
typedef HegelDateTime = ({HegelDate date, HegelTime time});

/// How a test case ended.
enum TestCaseStatus {
  /// The body ran to completion without issue.
  valid(raw.hegel_status_t.HEGEL_STATUS_VALID),

  /// An assumption was violated, so the case does not count.
  invalid(raw.hegel_status_t.HEGEL_STATUS_INVALID),

  /// The engine ran out of choice budget mid-case; the case is inconclusive.
  overrun(raw.hegel_status_t.HEGEL_STATUS_OVERRUN),

  /// The property failed and this case is a counterexample.
  interesting(raw.hegel_status_t.HEGEL_STATUS_INTERESTING);

  const TestCaseStatus(this.native);

  /// The value the ABI expects.
  final int native;
}

/// State shared by every handle onto one test case.
///
/// Cloning yields more handles onto the same case, and completion applies to
/// the case rather than the handle, so it is tracked here rather than per
/// wrapper. The abort latch will live here too, for the same reason.
final class TestCaseFamily {
  /// Whether any handle has already reported this case complete.
  bool completed = false;

  /// The signal that ended this case early, once one has been raised.
  ///
  /// Held per case rather than per handle so a clone cannot keep drawing from
  /// a case the engine has already given up on. Only meaningful within one
  /// isolate: cancelling a case whose clones are being driven elsewhere needs
  /// an explicit message, which is the runner's problem rather than this
  /// layer's.
  Object? abort;
}

/// A handle onto one test case.
///
/// Drive it with the draw primitives, conclude it with [markComplete], and
/// release it with [dispose]. Every handle must be disposed exactly once, and
/// the case must be marked complete before the run can advance.
final class TestCase implements ffi.Finalizable {
  @internal
  TestCase(
    this.session,
    this._handle,
    this.family, {
    this.onComplete,
    this.borrowed = false,
  });

  /// Whether this is a borrowed view rather than the owning handle.
  ///
  /// A borrowed view never frees; the isolate that made the handle does.
  final bool borrowed;

  /// The session this handle belongs to.
  @internal
  final Libhegel session;

  /// State shared with every other handle onto the same case.
  @internal
  final TestCaseFamily family;

  /// Run when this case is first reported complete, so the run can advance.
  @internal
  final void Function()? onComplete;

  final ffi.Pointer<raw.hegel_test_case_t> _handle;
  bool _disposed = false;

  /// Whether [dispose] has been called on this handle.
  bool get isDisposed => _disposed;

  /// The engine-side handle.
  @internal
  ffi.Pointer<raw.hegel_test_case_t> get handle {
    if (_disposed) {
      throw StateError('this TestCase handle has been disposed');
    }
    return _handle;
  }

  /// Whether this case belongs to a run already known to be nondeterministic.
  bool get isNondeterministic {
    final out = calloc<ffi.Bool>();
    try {
      session.check(
        session.bindings.hegel_test_case_is_nondeterministic(
          session.context,
          handle,
          out,
        ),
        'hegel_test_case_is_nondeterministic',
      );
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Another handle onto the same case, with its own choice stream.
  ///
  /// Clones share the case's outcome and budget but draw independently, which
  /// is what lets separate workers drive one case.
  TestCase clone() {
    _refuseIfComplete();
    final out = calloc<ffi.Pointer<raw.hegel_test_case_t>>();
    try {
      session.check(
        session.bindings.hegel_test_case_clone(session.context, handle, out),
        'hegel_test_case_clone',
      );
      // Carries the run-completion notification: a clone may be the handle
      // that reports the case, and the run has to learn about it either way.
      // Without this a worker's clone completing first leaves the run stuck
      // in flight, unable to advance or produce a result.
      return TestCase(session, out.value, family, onComplete: onComplete);
    } finally {
      calloc.free(out);
    }
  }

  /// Reports how this case ended.
  ///
  /// [origin] identifies a failure and must be supplied when [status] is
  /// [TestCaseStatus.interesting] and omitted otherwise; the engine groups
  /// failures by it, so two cases sharing one origin are the same bug.
  ///
  /// Completion applies to the whole case rather than this handle, so a second
  /// call throws [StateError] before reaching the engine.
  void markComplete(TestCaseStatus status, {String? origin}) {
    if (status == TestCaseStatus.interesting && origin == null) {
      throw ArgumentError.notNull('origin');
    }
    if (status != TestCaseStatus.interesting && origin != null) {
      throw ArgumentError.value(
        origin,
        'origin',
        'is only meaningful for an interesting test case',
      );
    }
    if (family.completed) {
      throw StateError('this test case has already been marked complete');
    }

    using((Arena arena) {
      session.check(
        session.bindings.hegel_mark_complete(
          session.context,
          handle,
          status.native,
          toCString(arena, origin, 'origin'),
        ),
        'hegel_mark_complete',
      );
    });
    family.completed = true;
    onComplete?.call();
  }

  /// Replays the test case a reproduce blob encodes.
  ///
  /// There is no run and no loop: drive the returned case with the usual
  /// primitives and decide for yourself whether the failure reproduced. A
  /// blob whose choices no longer match the caller's generators raises
  /// [StopTest] from the draw that overruns, and one that is corrupt or from
  /// an incompatible engine version is rejected outright.
  static TestCase fromBlob(
    Settings settings,
    String blob, {
    Libhegel? session,
    void Function(String line)? onOutput,
  }) {
    final active = session ?? Libhegel.instance;
    // The ABI says this callback need not outlive the call, so unlike a run's
    // it is released as soon as the replay has been set up.
    final sink = onOutput == null ? null : OutputSink(onOutput);
    try {
      return settings.withNative(active, (
        ffi.Pointer<raw.hegel_settings_t> handle,
      ) {
        final out = calloc<ffi.Pointer<raw.hegel_test_case_t>>();
        return using((Arena arena) {
          try {
            active.check(
              active.bindings.hegel_test_case_from_blob(
                active.context,
                handle,
                toCString(arena, blob, 'blob'),
                sink?.pointer ?? ffi.nullptr,
                ffi.nullptr,
                out,
              ),
              'hegel_test_case_from_blob',
            );
            if (sink?.failure case final failure?) {
              active.bindings.hegel_test_case_free(active.context, out.value);
              Error.throwWithStackTrace(failure.$1, failure.$2);
            }
            return TestCase(active, out.value, TestCaseFamily());
          } finally {
            calloc.free(out);
          }
        });
      });
    } finally {
      sink?.close();
    }
  }

  void _refuseIfComplete() {
    if (family.completed) {
      throw StateError('this test case has already been marked complete');
    }
  }

  /// Runs [draw], latching whichever signal ends the case.
  ///
  /// Once a case has been aborted, later draws re-raise the *same* signal
  /// without calling the engine. Re-raising StopTest unconditionally would be
  /// wrong: a draw made while an assumption failure unwinds would turn an
  /// invalid case into an overrun one, and the runner would report the wrong
  /// outcome.
  T _guarded<T>(T Function() draw) {
    if (_disposed) {
      throw StateError('this TestCase handle has been disposed');
    }
    _refuseIfComplete();
    if (family.abort case final signal?) throw signal;
    try {
      return draw();
    } on StopTest catch (signal) {
      family.abort = signal;
      rethrow;
    } on AssumptionFailed catch (signal) {
      family.abort = signal;
      rethrow;
    }
  }

  /// Draws a boolean that is true with probability [probability].
  ///
  /// [forced] overrides the draw without consuming entropy, which the engine
  /// uses when replaying.
  bool drawBoolean({double probability = 0.5, bool? forced}) {
    return _guarded(() {
      if (probability < 0 || probability > 1 || probability.isNaN) {
        throw RangeError.value(probability, 'probability', 'must be in [0, 1]');
      }
      final out = calloc<ffi.Bool>();
      try {
        session.check(
          session.bindings.hegel_generate_boolean(
            session.context,
            handle,
            probability,
            forced ?? false,
            forced != null,
            out,
          ),
          'hegel_generate_boolean',
        );
        return out.value;
      } finally {
        calloc.free(out);
      }
    });
  }

  /// Draws an integer in the inclusive range [min] to [max].
  int drawInteger({required int min, required int max}) {
    return _guarded(() {
      if (min > max) {
        throw ArgumentError.value(min, 'min', 'exceeds max ($max)');
      }
      return _generateInteger(min, max);
    });
  }

  /// Runs [body] under this case's guards and abort latch.
  ///
  /// Collections, pools, and state machines are driven through a test case's
  /// stream, so their operations belong under the same guards as a draw.
  @internal
  T guarded<T>(T Function() body) => _guarded(body);

  /// Starts an engine-driven sequence of [minSize] to [maxSize] elements.
  ///
  /// The engine decides how many elements to produce: loop on
  /// [Collection.more] and draw one element each time it answers true. A null
  /// [maxSize] leaves the length unbounded.
  Collection startCollection({required int minSize, int? maxSize}) {
    return _guarded(() {
      checkFitsUnsigned(minSize, 'minSize');
      if (maxSize != null && minSize > maxSize) {
        throw ArgumentError.value(minSize, 'minSize', 'exceeds maxSize');
      }
      final out = calloc<ffi.Pointer<raw.hegel_collection_t>>();
      try {
        session.check(
          session.bindings.hegel_new_collection(
            session.context,
            handle,
            minSize,
            sizeOrUnbounded(maxSize, 'maxSize'),
            out,
          ),
          'hegel_new_collection',
        );
        return Collection(session, out.value);
      } finally {
        calloc.free(out);
      }
    });
  }

  /// Registers a state machine and lets the engine sequence its rules.
  ///
  /// [ruleGroups] assigns each rule to a concurrency group, defaulting to one
  /// group for everything; rules in a group may overlap, rules in different
  /// groups never do. The engine draws the concurrency level somewhere in
  /// [minConcurrency] to [maxConcurrency] and the caller must run exactly that
  /// many workers.
  ///
  /// Asking for more than one worker declares the run nondeterministic. The
  /// first such request on a run raises [AssumptionFailed]: abandon the body
  /// and report the case invalid, and the engine will allow it from the next
  /// case onward.
  StateMachine newStateMachine({
    required List<String> ruleNames,
    List<int>? ruleGroups,
    List<String> invariantNames = const <String>[],
    int minConcurrency = 1,
    int maxConcurrency = 1,
  }) {
    return _guarded(() {
      if (ruleNames.isEmpty) {
        throw ArgumentError.value(ruleNames, 'ruleNames', 'must not be empty');
      }
      if (ruleGroups != null && ruleGroups.length != ruleNames.length) {
        throw ArgumentError.value(
          ruleGroups,
          'ruleGroups',
          'must have one entry per rule (${ruleNames.length})',
        );
      }
      if (ruleGroups != null &&
          ruleGroups.contains(raw.HEGEL_STATE_MACHINE_DONE)) {
        // The engine reserves that value to mean "finished", so a group using
        // it would be indistinguishable from the end of the machine.
        throw ArgumentError.value(
          ruleGroups,
          'ruleGroups',
          'must not use the reserved termination value',
        );
      }
      if (minConcurrency < 1) {
        throw RangeError.value(
          minConcurrency,
          'minConcurrency',
          'must be >= 1',
        );
      }
      if (maxConcurrency < minConcurrency) {
        throw ArgumentError.value(
          maxConcurrency,
          'maxConcurrency',
          'is below minConcurrency ($minConcurrency)',
        );
      }

      return using((Arena arena) {
        final rules = toStringArray(arena, ruleNames, 'ruleNames');
        final invariants = toStringArray(
          arena,
          invariantNames,
          'invariantNames',
        );
        final groups = arena<ffi.Int64>(ruleNames.length);
        for (var i = 0; i < ruleNames.length; i++) {
          groups[i] = ruleGroups?[i] ?? 0;
        }

        final out = arena<ffi.Pointer<raw.hegel_state_machine_t>>();
        final concurrency = arena<ffi.Int64>();
        session.check(
          session.bindings.hegel_new_state_machine(
            session.context,
            handle,
            rules.data,
            groups,
            ruleNames.length,
            invariants.data,
            invariantNames.length,
            minConcurrency,
            maxConcurrency,
            out,
            concurrency,
          ),
          'hegel_new_state_machine',
        );
        return StateMachine(session, out.value, concurrency.value);
      });
    });
  }

  /// An address for this handle, to hand to a worker isolate.
  ///
  /// Conveys no ownership: this wrapper still frees the handle, and must
  /// outlive every borrower.
  @internal
  HandleToken get token => HandleToken(_handle.address);

  /// Reconstructs a borrowed view of a test case in another isolate.
  ///
  /// The view gets its own family state, since a Dart object cannot be shared
  /// across isolates. Cancelling a case whose clones are being driven
  /// elsewhere therefore needs an explicit message; the abort latch only
  /// covers handles within one isolate.
  @internal
  static TestCase adopt(Libhegel session, HandleToken token) => TestCase(
    session,
    ffi.Pointer<raw.hegel_test_case_t>.fromAddress(token.address),
    TestCaseFamily(),
    borrowed: true,
  );

  /// Creates a set of variable identifiers the engine can choose among.
  Pool newPool() {
    return _guarded(() {
      final out = calloc<ffi.Pointer<raw.hegel_pool_t>>();
      try {
        session.check(
          session.bindings.hegel_new_pool(session.context, handle, out),
          'hegel_new_pool',
        );
        return Pool(session, out.value);
      } finally {
        calloc.free(out);
      }
    });
  }

  /// Opens a span grouping the draws made until [stopSpan].
  ///
  /// Spans tell the shrinker which draws belong together, so it can delete or
  /// simplify a whole compound value rather than picking at its pieces. Every
  /// compound generator should wrap itself in one.
  void startSpan(SpanLabel label) {
    _guarded(() {
      session.check(
        session.bindings.hegel_start_span(session.context, handle, label.value),
        'hegel_start_span',
      );
    });
  }

  /// Closes the most recently opened span.
  ///
  /// With [discard] the span is marked rejected -- a filter that did not
  /// hold -- and the engine retries from where it opened.
  ///
  /// Unlike a draw, this is a no-op once the case has been aborted rather than
  /// an error. Spans are closed from `finally` blocks while the stack unwinds,
  /// and that unwinding must not itself raise.
  void stopSpan({bool discard = false}) {
    if (_disposed || family.completed || family.abort != null) return;
    session.check(
      session.bindings.hegel_stop_span(session.context, handle, discard),
      'hegel_stop_span',
    );
  }

  /// Runs [body] inside a span labelled [label].
  ///
  /// Closes the span however [body] ends, which is the reason [stopSpan]
  /// tolerates an aborted case.
  T span<T>(SpanLabel label, T Function() body) {
    startSpan(label);
    try {
      return body();
    } finally {
      stopSpan();
    }
  }

  /// Draws the sixteen bytes of a UUID, most significant first.
  ///
  /// With [version] set, the RFC 4122 version and variant bits are forced;
  /// without it all 128 bits are drawn, except that the nil UUID never comes
  /// back. Returned as bytes rather than a formatted string because how to
  /// present a UUID is the generator layer's decision.
  Uint8List drawUuid({int? version}) {
    return _guarded(() {
      if (version != null && (version < 0 || version > 15)) {
        throw RangeError.value(version, 'version', 'must be in 0..15');
      }
      return using((Arena arena) {
        final out = arena<ffi.Uint8>(16);
        session.check(
          session.bindings.hegel_generate_uuid(
            session.context,
            handle,
            version ?? 0,
            version != null,
            out,
          ),
          'hegel_generate_uuid',
        );
        return Uint8List.fromList(out.asTypedList(16));
      });
    });
  }

  /// Draws the four bytes of an IPv4 address, in network order.
  Uint8List drawIpv4() => _drawAddress(4, 'hegel_generate_ipv4');

  /// Draws the sixteen bytes of an IPv6 address, in network order.
  Uint8List drawIpv6() => _drawAddress(16, 'hegel_generate_ipv6');

  Uint8List _drawAddress(int length, String operation) {
    return _guarded(() {
      return using((Arena arena) {
        final out = arena<ffi.Uint8>(length);
        session.check(
          length == 4
              ? session.bindings.hegel_generate_ipv4(
                  session.context,
                  handle,
                  out,
                )
              : session.bindings.hegel_generate_ipv6(
                  session.context,
                  handle,
                  out,
                ),
          operation,
        );
        return Uint8List.fromList(out.asTypedList(length));
      });
    });
  }

  /// Records a numeric observation the engine should steer toward.
  ///
  /// Higher is more interesting. Each [label] may be recorded once per test
  /// case, and the whole thing is a no-op unless the targeting phase is on.
  void target(double value, {required String label}) {
    _guarded(() {
      if (!value.isFinite) {
        throw ArgumentError.value(value, 'value', 'must be finite');
      }
      using((Arena arena) {
        session.check(
          session.bindings.hegel_target(
            session.context,
            handle,
            value,
            toCString(arena, label, 'label'),
          ),
          'hegel_target',
        );
      });
    });
  }

  /// Draws a date between [min] and [max] inclusive.
  ///
  /// Shrinks toward 2000-01-01, or the nearest bound when that is out of
  /// range.
  HegelDate drawDate({
    HegelDate min = (year: 1, month: 1, day: 1),
    HegelDate max = (year: 9999, month: 12, day: 31),
  }) {
    return _guarded(() {
      _checkDate(min, 'min');
      _checkDate(max, 'max');
      return using((Arena arena) {
        final out = arena<raw.hegel_date_t>();
        session.check(
          session.bindings.hegel_generate_date(
            session.context,
            handle,
            _date(arena, min).ref,
            _date(arena, max).ref,
            out,
          ),
          'hegel_generate_date',
        );
        return _readDate(out.ref);
      });
    });
  }

  /// Draws a time of day between [min] and [max] inclusive.
  HegelTime drawTime({
    HegelTime min = (hour: 0, minute: 0, second: 0, microsecond: 0),
    HegelTime max = (hour: 23, minute: 59, second: 59, microsecond: 999999),
  }) {
    return _guarded(() {
      _checkTime(min, 'min');
      _checkTime(max, 'max');
      return using((Arena arena) {
        final out = arena<raw.hegel_time_t>();
        session.check(
          session.bindings.hegel_generate_time(
            session.context,
            handle,
            _time(arena, min).ref,
            _time(arena, max).ref,
            out,
          ),
          'hegel_generate_time',
        );
        return _readTime(out.ref);
      });
    });
  }

  /// Draws a date and time of day between [min] and [max] inclusive.
  HegelDateTime drawDateTime({
    HegelDateTime min = (
      date: (year: 1, month: 1, day: 1),
      time: (hour: 0, minute: 0, second: 0, microsecond: 0),
    ),
    HegelDateTime max = (
      date: (year: 9999, month: 12, day: 31),
      time: (hour: 23, minute: 59, second: 59, microsecond: 999999),
    ),
  }) {
    return _guarded(() {
      _checkDate(min.date, 'min.date');
      _checkTime(min.time, 'min.time');
      _checkDate(max.date, 'max.date');
      _checkTime(max.time, 'max.time');
      return using((Arena arena) {
        ffi.Pointer<raw.hegel_datetime_t> both(HegelDateTime value) {
          final pointer = arena<raw.hegel_datetime_t>();
          pointer.ref.date
            ..year = value.date.year
            ..month = value.date.month
            ..day = value.date.day;
          pointer.ref.time
            ..hour = value.time.hour
            ..minute = value.time.minute
            ..second = value.time.second
            ..microsecond = value.time.microsecond;
          return pointer;
        }

        final out = arena<raw.hegel_datetime_t>();
        session.check(
          session.bindings.hegel_generate_datetime(
            session.context,
            handle,
            both(min).ref,
            both(max).ref,
            out,
          ),
          'hegel_generate_datetime',
        );
        return (date: _readDate(out.ref.date), time: _readTime(out.ref.time));
      });
    });
  }

  /// Rejects a date the struct fields would silently reshape.
  ///
  /// Month and day are single bytes, so 257 would arrive as 1 and the engine
  /// would validate a bound nobody asked for.
  static void _checkDate(HegelDate value, String name) {
    checkInRange(value.year, '$name.year', -999999, 999999);
    checkInRange(value.month, '$name.month', 1, 12);
    checkInRange(value.day, '$name.day', 1, 31);
  }

  /// Rejects a time the struct fields would silently reshape.
  static void _checkTime(HegelTime value, String name) {
    checkInRange(value.hour, '$name.hour', 0, 23);
    checkInRange(value.minute, '$name.minute', 0, 59);
    checkInRange(value.second, '$name.second', 0, 59);
    checkInRange(value.microsecond, '$name.microsecond', 0, 999999);
  }

  static ffi.Pointer<raw.hegel_date_t> _date(Arena arena, HegelDate value) =>
      arena<raw.hegel_date_t>()
        ..ref.year = value.year
        ..ref.month = value.month
        ..ref.day = value.day;

  static ffi.Pointer<raw.hegel_time_t> _time(Arena arena, HegelTime value) =>
      arena<raw.hegel_time_t>()
        ..ref.hour = value.hour
        ..ref.minute = value.minute
        ..ref.second = value.second
        ..ref.microsecond = value.microsecond;

  static HegelDate _readDate(raw.hegel_date_t value) =>
      (year: value.year, month: value.month, day: value.day);

  static HegelTime _readTime(raw.hegel_time_t value) => (
    hour: value.hour,
    minute: value.minute,
    second: value.second,
    microsecond: value.microsecond,
  );

  /// Draws a string described by [generator].
  ///
  /// Raises [AssumptionFailed] when the draw rejects itself, which some
  /// specifications can do — an email address that would exceed the RFC length
  /// cap, for instance.
  String drawString(StringGenerator generator) {
    return _guarded(() {
      final out = calloc<raw.hegel_generate_string_result_t>();
      try {
        session.check(
          session.bindings.hegel_generate_string(
            session.context,
            handle,
            generator.handle,
            out,
          ),
          'hegel_generate_string',
        );
        // Read by length, never as a C string: the drawn alphabet may include
        // U+0000, which would truncate anything that stopped at a NUL.
        return utf8FromBuffer(out.ref.data, out.ref.len);
      } finally {
        session.bindings.hegel_generate_string_result_free(
          session.context,
          out,
        );
        calloc.free(out);
      }
    });
  }

  /// Draws a byte string whose length is in [minLength] to [maxLength].
  Uint8List drawBytes({required int minLength, required int maxLength}) {
    return _guarded(() {
      if (minLength < 0) {
        throw RangeError.value(minLength, 'minLength', 'must not be negative');
      }
      if (minLength > maxLength) {
        throw ArgumentError.value(
          minLength,
          'minLength',
          'exceeds maxLength ($maxLength)',
        );
      }

      final out = calloc<raw.hegel_generate_bytes_result_t>();
      try {
        session.check(
          session.bindings.hegel_generate_bytes(
            session.context,
            handle,
            minLength,
            maxLength,
            out,
          ),
          'hegel_generate_bytes',
        );
        // Copied before the buffer is released just below; the engine owns
        // that memory and takes it back with the matching free.
        return bytesFromBuffer(out.ref.data, out.ref.len);
      } finally {
        // calloc zeroed the struct and the ABI documents its free as safe on
        // a zeroed one, so this runs on the failure path too rather than
        // needing to know whether the draw got far enough to allocate.
        session.bindings.hegel_generate_bytes_result_free(session.context, out);
        calloc.free(out);
      }
    });
  }

  /// Draws an integer in the inclusive range [min] to [max], of any width.
  ///
  /// Bounds that fit in a machine integer take the cheaper fixed-width call;
  /// wider ones are exchanged as two's-complement little-endian buffers.
  BigInt drawBigInteger({required BigInt min, required BigInt max}) {
    return _guarded(() {
      if (min > max) {
        throw ArgumentError.value(min, 'min', 'exceeds max ($max)');
      }
      if (_fitsInt64(min) && _fitsInt64(max)) {
        return BigInt.from(_generateInteger(min.toInt(), max.toInt()));
      }

      final minBytes = twosComplementBytes(min);
      final maxBytes = twosComplementBytes(max);
      // The header guarantees a buffer this wide always suffices, since the
      // drawn value lies between the bounds.
      final capacity = minBytes.length > maxBytes.length
          ? minBytes.length
          : maxBytes.length;

      return using((Arena arena) {
        ffi.Pointer<ffi.Uint8> copy(Uint8List bytes) {
          final pointer = arena<ffi.Uint8>(bytes.length);
          pointer.asTypedList(bytes.length).setAll(0, bytes);
          return pointer;
        }

        final out = arena<ffi.Uint8>(capacity);
        session.check(
          session.bindings.hegel_generate_integer_big(
            session.context,
            handle,
            copy(minBytes),
            minBytes.length,
            copy(maxBytes),
            maxBytes.length,
            out,
            capacity,
            arena<ffi.Size>(),
          ),
          'hegel_generate_integer_big',
        );
        // The engine sign-fills the whole buffer, so the full width decodes
        // to the drawn value and the returned length is redundant.
        return bigIntFromTwosComplement(out.asTypedList(capacity));
      });
    });
  }

  static final BigInt _int64Min = BigInt.parse('-9223372036854775808');
  static final BigInt _int64Max = BigInt.parse('9223372036854775807');

  static bool _fitsInt64(BigInt value) =>
      value >= _int64Min && value <= _int64Max;

  int _generateInteger(int min, int max) {
    final out = calloc<ffi.Int64>();
    try {
      session.check(
        session.bindings.hegel_generate_integer(
          session.context,
          handle,
          min,
          max,
          out,
        ),
        'hegel_generate_integer',
      );
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Draws a floating-point number.
  ///
  /// [width] is 32 or 64. Bounds are inclusive unless excluded, and may be
  /// infinite for an open end. [smallestNonzeroMagnitude] suppresses nonzero
  /// magnitudes below it; the default is the smallest subnormal at [width],
  /// which suppresses nothing.
  double drawFloat({
    int width = 64,
    double min = double.negativeInfinity,
    double max = double.infinity,
    bool allowNan = false,
    bool allowInfinity = false,
    bool excludeMin = false,
    bool excludeMax = false,
    double? smallestNonzeroMagnitude,
  }) {
    return _guarded(() {
      if (width != 32 && width != 64) {
        throw ArgumentError.value(width, 'width', 'must be 32 or 64');
      }
      if (min > max) {
        throw ArgumentError.value(min, 'min', 'exceeds max ($max)');
      }
      final smallest =
          smallestNonzeroMagnitude ?? (width == 32 ? 1.4e-45 : 5e-324);
      if (smallest <= 0 || !smallest.isFinite) {
        throw ArgumentError.value(
          smallest,
          'smallestNonzeroMagnitude',
          'must be positive and finite',
        );
      }
      final out = calloc<ffi.Double>();
      try {
        session.check(
          session.bindings.hegel_generate_float(
            session.context,
            handle,
            width,
            min,
            max,
            allowNan,
            allowInfinity,
            excludeMin,
            excludeMax,
            smallest,
            out,
          ),
          'hegel_generate_float',
        );
        return out.value;
      } finally {
        calloc.free(out);
      }
    });
  }

  /// Releases this handle.
  ///
  /// Idempotent. Each handle holds one reference to the underlying case; the
  /// case itself is released when the last one goes.
  void dispose() {
    if (_disposed || borrowed) return;
    _disposed = true;
    session.bindings.hegel_test_case_free(session.context, _handle);
  }
}
