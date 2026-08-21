/// One execution of a test body, and the values drawn for it.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'marshal.dart';
import 'session.dart';

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
