/// The outcome of a finished run.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'marshal.dart';
import 'session.dart';

/// How a run ended.
enum RunStatus {
  /// The property held across every test case.
  passed(raw.hegel_run_status_t.HEGEL_RUN_STATUS_PASSED),

  /// The property failed; there are counterexamples to inspect.
  failed(raw.hegel_run_status_t.HEGEL_RUN_STATUS_FAILED),

  /// The run itself failed and reached no verdict on the property.
  error(raw.hegel_run_status_t.HEGEL_RUN_STATUS_ERROR),

  /// The property failed on a run declared nondeterministic.
  ///
  /// There was no shrinking and no replay, so the failures carry no reproduce
  /// blob and must be reported from whatever the discovering case captured.
  failedNondeterministic(
    raw.hegel_run_status_t.HEGEL_RUN_STATUS_FAILED_NONDETERMINISTIC,
  );

  const RunStatus(this.native);

  /// The value the ABI uses.
  final int native;

  /// The status [value] denotes.
  static RunStatus fromNative(int value) => values.firstWhere(
    (RunStatus status) => status.native == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'unknown status'),
  );
}

/// A finished run's outcome.
///
/// A caller-owned snapshot: it stays valid after the run is disposed and is
/// released separately.
final class RunResult implements ffi.Finalizable {
  @internal
  RunResult(this._session, this._handle);

  final Libhegel _session;
  final ffi.Pointer<raw.hegel_run_result_t> _handle;
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  ffi.Pointer<raw.hegel_run_result_t> get _live {
    if (_disposed) {
      throw StateError('this RunResult has been disposed');
    }
    return _handle;
  }

  /// How the run ended.
  RunStatus get status {
    final out = calloc<ffi.UnsignedInt>();
    try {
      _session.check(
        _session.bindings.hegel_run_result_status(_session.context, _live, out),
        'hegel_run_result_status',
      );
      return RunStatus.fromNative(out.value);
    } finally {
      calloc.free(out);
    }
  }

  /// Why the run errored, or null when it reached a verdict.
  String? get error {
    final out = calloc<ffi.Pointer<ffi.Char>>();
    try {
      _session.check(
        _session.bindings.hegel_run_result_error(_session.context, _live, out),
        'hegel_run_result_error',
      );
      return utf8FromCString(out.value);
    } finally {
      calloc.free(out);
    }
  }

  /// Releases this result and the strings read from it. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session.bindings.hegel_run_result_free(_session.context, _handle);
  }
}
