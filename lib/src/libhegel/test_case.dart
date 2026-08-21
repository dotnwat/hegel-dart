/// One execution of a test body, and the values drawn for it.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'errors.dart';
import 'marshal.dart';
import 'session.dart';
import 'settings.dart';

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
  TestCase(this.session, this._handle, this.family, {this.onComplete});

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
    final out = calloc<ffi.Pointer<raw.hegel_test_case_t>>();
    try {
      session.check(
        session.bindings.hegel_test_case_clone(session.context, handle, out),
        'hegel_test_case_clone',
      );
      return TestCase(session, out.value, family);
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
  }) {
    final active = session ?? Libhegel.instance;
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
              ffi.nullptr,
              ffi.nullptr,
              out,
            ),
            'hegel_test_case_from_blob',
          );
          return TestCase(active, out.value, TestCaseFamily());
        } finally {
          calloc.free(out);
        }
      });
    });
  }

  /// Runs [draw], latching whichever signal ends the case.
  ///
  /// Once a case has been aborted, later draws re-raise the *same* signal
  /// without calling the engine. Re-raising StopTest unconditionally would be
  /// wrong: a draw made while an assumption failure unwinds would turn an
  /// invalid case into an overrun one, and the runner would report the wrong
  /// outcome.
  T _guarded<T>(T Function() draw) {
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
    if (probability < 0 || probability > 1 || probability.isNaN) {
      throw RangeError.value(probability, 'probability', 'must be in [0, 1]');
    }
    return _guarded(() {
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
    if (min > max) {
      throw ArgumentError.value(min, 'min', 'exceeds max ($max)');
    }
    return _guarded(() {
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
    });
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
    return _guarded(() {
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
    if (_disposed) return;
    _disposed = true;
    session.bindings.hegel_test_case_free(session.context, _handle);
  }
}
