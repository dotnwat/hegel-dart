/// One property-test run.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'bindings.g.dart' as raw;
import 'run_result.dart';
import 'session.dart';
import 'settings.dart';
import 'test_case.dart';

/// Where a run is in its lifecycle.
enum _RunState { idle, caseInFlight, finished, disposed }

/// An in-flight property-test run.
///
/// The caller pulls test cases until [nextTestCase] returns null, reports each
/// one's outcome, and then reads [result].
///
/// Misuse this layer can see is refused before reaching the engine: asking for
/// a case while one is outstanding, or reading the result before the run has
/// finished, throws [StateError] rather than surfacing the engine's own
/// HEGEL_E_NOT_COMPLETE. Those codes indicate a bug in this binding, so they
/// are prevented rather than reported.
///
/// A run and the cases it yields belong to the isolate that created them. The
/// ABI allows only one thread at a time on a run, which a single-threaded
/// isolate satisfies by construction.
final class Run implements ffi.Finalizable {
  Run._(this._session, this._handle);

  /// Starts a run configured by [settings].
  ///
  /// No test case exists until [nextTestCase] is called; this only sets the
  /// run up. Settings are copied by the engine, so the handle behind them is
  /// freed before this returns.
  static Run start(Settings settings, {Libhegel? session}) {
    final active = session ?? Libhegel.instance;
    return settings.withNative(active, (
      ffi.Pointer<raw.hegel_settings_t> handle,
    ) {
      final out = calloc<ffi.Pointer<raw.hegel_run_t>>();
      try {
        active.check(
          active.bindings.hegel_run_start(
            active.context,
            handle,
            ffi.nullptr,
            ffi.nullptr,
            out,
          ),
          'hegel_run_start',
        );
        return Run._(active, out.value);
      } finally {
        calloc.free(out);
      }
    });
  }

  final Libhegel _session;
  final ffi.Pointer<raw.hegel_run_t> _handle;
  _RunState _state = _RunState.idle;

  /// Whether [dispose] has been called.
  bool get isDisposed => _state == _RunState.disposed;

  /// Whether the engine has no more test cases to offer.
  bool get isFinished => _state == _RunState.finished;

  /// The next test case, or null once the run is over.
  ///
  /// Throws [StateError] if the previous case has not been marked complete:
  /// the engine cannot advance until it knows how that one ended.
  TestCase? nextTestCase() {
    switch (_state) {
      case _RunState.disposed:
        throw StateError('this Run has been disposed');
      case _RunState.caseInFlight:
        throw StateError('the previous test case has not been marked complete');
      case _RunState.finished:
        return null;
      case _RunState.idle:
        break;
    }

    final out = calloc<ffi.Pointer<raw.hegel_test_case_t>>();
    try {
      _session.check(
        _session.bindings.hegel_next_test_case(_session.context, _handle, out),
        'hegel_next_test_case',
      );
      if (out.value == ffi.nullptr) {
        _state = _RunState.finished;
        return null;
      }
      _state = _RunState.caseInFlight;
      return TestCase(
        _session,
        out.value,
        TestCaseFamily(),
        onComplete: () => _state = _RunState.idle,
      );
    } finally {
      calloc.free(out);
    }
  }

  /// The finished run's outcome, as a caller-owned snapshot.
  ///
  /// Throws [StateError] until [nextTestCase] has reported the run over. Each
  /// call produces a separate snapshot that outlives this run.
  RunResult result() {
    if (_state == _RunState.disposed) {
      throw StateError('this Run has been disposed');
    }
    if (_state != _RunState.finished) {
      throw StateError(
        'the run has not finished; pull test cases until none is left',
      );
    }

    final out = calloc<ffi.Pointer<raw.hegel_run_result_t>>();
    try {
      _session.check(
        _session.bindings.hegel_run_result(_session.context, _handle, out),
        'hegel_run_result',
      );
      return RunResult(_session, out.value);
    } finally {
      calloc.free(out);
    }
  }

  /// Frees the run.
  ///
  /// Idempotent. Leaving the loop early is allowed: the engine marks any
  /// outstanding case complete and drops the rest of its exploration.
  void dispose() {
    if (_state == _RunState.disposed) return;
    _state = _RunState.disposed;
    _session.bindings.hegel_run_free(_session.context, _handle);
  }
}
