/// One property-test run.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'bindings.g.dart' as raw;
import 'marshal.dart';
import 'run_result.dart';
import 'session.dart';
import 'settings.dart';
import 'test_case.dart';

/// Where a run is in its lifecycle.
enum _RunState { idle, caseInFlight, finished, disposed }

/// Delivers the engine's output lines to a Dart callback.
///
/// The engine calls back synchronously, on the thread already inside a call,
/// which is exactly what an isolate-local callable supports. A listener
/// callable would deliver asynchronously and break the contract that output
/// arrives during the call that produced it.
final class OutputSink {
  /// Wraps a callback in a callable the engine can invoke.
  OutputSink(this._onOutput) {
    _callable =
        ffi.NativeCallable<
          ffi.Void Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
            ffi.Size,
          )
        >.isolateLocal(_receive);
  }

  final void Function(String line) _onOutput;
  late final ffi.NativeCallable<
    ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, ffi.Size)
  >
  _callable;

  /// The first error [_onOutput] threw, with the stack it threw from.
  (Object, StackTrace)? failure;

  /// The function pointer to hand the engine.
  ffi.Pointer<
    ffi.NativeFunction<
      ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, ffi.Size)
    >
  >
  get pointer => _callable.nativeFunction;

  void _receive(
    ffi.Pointer<ffi.Void> userData,
    ffi.Pointer<ffi.Char> line,
    int length,
  ) {
    // Nothing may escape into the engine's frames, so everything is caught
    // and re-raised by whoever called into the engine, once it has returned.
    if (failure != null) return;
    try {
      _onOutput(utf8FromBuffer(line, length));
    } on Object catch (error, stack) {
      failure = (error, stack);
    }
  }

  /// Releases the callable.
  void close() => _callable.close();
}

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
  Run._(this._session, this._handle, this._sink);

  /// Starts a run configured by [settings].
  ///
  /// No test case exists until [nextTestCase] is called; this only sets the
  /// run up. Settings are copied by the engine, so the handle behind them is
  /// freed before this returns.
  static Run start(
    Settings settings, {
    Libhegel? session,
    void Function(String line)? onOutput,
  }) {
    final active = session ?? Libhegel.instance;
    // Null leaves the engine writing to stderr, which is its own default.
    final sink = onOutput == null ? null : OutputSink(onOutput);
    try {
      return settings.withNative(active, (
        ffi.Pointer<raw.hegel_settings_t> handle,
      ) {
        final out = calloc<ffi.Pointer<raw.hegel_run_t>>();
        try {
          active.check(
            active.bindings.hegel_run_start(
              active.context,
              handle,
              sink?.pointer ?? ffi.nullptr,
              ffi.nullptr,
              out,
            ),
            'hegel_run_start',
          );
          return Run._(active, out.value, sink);
        } finally {
          calloc.free(out);
        }
      });
    } on Object {
      // A run that never started still has a callable to release.
      sink?.close();
      rethrow;
    }
  }

  final Libhegel _session;
  final ffi.Pointer<raw.hegel_run_t> _handle;
  final OutputSink? _sink;
  _RunState _state = _RunState.idle;
  bool _inEngineCall = false;

  /// Refuses re-entry into a run already inside an engine call.
  ///
  /// The engine calls the output callback from inside `hegel_next_test_case`,
  /// and the ABI forbids calling back into the same run from there. This is
  /// checked always rather than behind an assert, because in a release build
  /// the same mistake is undefined behaviour instead of an error.
  void _enter() {
    if (_inEngineCall) {
      throw StateError(
        'this Run is already inside an engine call; the output callback must '
        'not call back into the run it belongs to',
      );
    }
    _inEngineCall = true;
  }

  /// Rethrows whatever the output callback threw, with its own stack.
  ///
  /// Called only once the engine has returned. Any handle the call produced is
  /// released first, and the run is disposed: a callback that failed mid-case
  /// leaves the run holding an in-flight case it can never be told about.
  Never _rethrowCallbackFailure(
    (Object, StackTrace) failure,
    ffi.Pointer<raw.hegel_test_case_t> produced,
  ) {
    if (produced != ffi.nullptr) {
      _session.bindings.hegel_test_case_free(_session.context, produced);
    }
    dispose();
    Error.throwWithStackTrace(failure.$1, failure.$2);
  }

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
      _enter();
      final int code;
      try {
        code = _session.bindings.hegel_next_test_case(
          _session.context,
          _handle,
          out,
        );
      } finally {
        _inEngineCall = false;
      }
      // Checked before the result code: if the callback failed, its error is
      // the one that matters and the engine's view of the call is moot.
      if (_sink?.failure case final failure?) {
        _rethrowCallbackFailure(failure, out.value);
      }
      _session.check(code, 'hegel_next_test_case');
      if (out.value == ffi.nullptr) {
        _state = _RunState.finished;
        return null;
      }
      _state = _RunState.caseInFlight;
      return TestCase(
        _session,
        out.value,
        TestCaseFamily(),
        // Only if the run is still alive. Disposing with a case in flight
        // frees the handle, and a late completion must not move the run back
        // to idle: a second dispose would then free it again, and
        // nextTestCase would read through a dangling pointer.
        onComplete: () {
          if (_state != _RunState.disposed) _state = _RunState.idle;
        },
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
    // Freeing the run may still emit, so the callable outlives the free.
    _session.bindings.hegel_run_free(_session.context, _handle);
    _sink?.close();
  }
}
