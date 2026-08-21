/// Engine-owned rule selection for stateful testing.
///
/// @docImport 'errors.dart';
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'leaks.dart';
import 'session.dart';
import 'test_case.dart';

/// A non-owning address of a native handle.
///
/// Plain integers cross between isolates, which handles and wrappers do not.
/// A token conveys no ownership: whoever created the handle keeps it and frees
/// it once every borrower has finished.
extension type const HandleToken(int address) {}

/// The engine's rule sequencer for a stateful test.
///
/// The caller drives rounds. On the root test case it asks [nextGroup] whether
/// another round should run; then each worker asks [nextRule] which rule to
/// apply until that returns null, which is the join point for the round.
///
/// Rule selection, swarm testing, and the concurrency level all belong to the
/// engine. The caller supplies names and runs what it is told.
final class StateMachine implements ffi.Finalizable {
  @internal
  StateMachine(
    this._session,
    this._handle,
    this.concurrency, {
    this.isBorrowed = false,
  }) {
    assert(isBorrowed || trackHandle(this, 'StateMachine'));
  }

  /// Reconstructs a borrowed view of a machine in another isolate.
  ///
  /// The view never frees the handle; the isolate that created the machine
  /// does, once its workers have joined.
  @internal
  static StateMachine adopt(
    Libhegel session,
    HandleToken token,
    int concurrency,
  ) => StateMachine(
    session,
    ffi.Pointer<raw.hegel_state_machine_t>.fromAddress(token.address),
    concurrency,
    isBorrowed: true,
  );

  /// How many workers the engine wants pulling rules.
  ///
  /// Drawn when the machine was created, somewhere in the range it was given.
  /// Exactly this many workers must run.
  final int concurrency;

  /// Whether this is a borrowed view rather than the owning wrapper.
  final bool isBorrowed;

  final Libhegel _session;
  final ffi.Pointer<raw.hegel_state_machine_t> _handle;
  bool _disposed = false;

  /// An address for this machine, to hand to a worker isolate.
  @internal
  HandleToken get token => HandleToken(_live.address);

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  ffi.Pointer<raw.hegel_state_machine_t> get _live {
    if (_disposed) {
      throw StateError('this StateMachine has been disposed');
    }
    return _handle;
  }

  /// Begins the next round, or returns null when the machine is finished.
  ///
  /// Ask on the root test case, at every join point, including before the
  /// first rule. The value identifies the round's concurrency group; rules in
  /// one group may overlap, rules in different groups never do.
  int? nextGroup(TestCase rootCase) {
    return rootCase.guarded(() {
      final out = calloc<ffi.Int64>();
      try {
        _session.check(
          _session.bindings.hegel_state_machine_next_group(
            _session.context,
            rootCase.handle,
            _live,
            out,
          ),
          'hegel_state_machine_next_group',
        );
        return out.value == raw.HEGEL_STATE_MACHINE_DONE ? null : out.value;
      } finally {
        calloc.free(out);
      }
    });
  }

  /// The next rule for [workerIndex], or null once its round is over.
  ///
  /// [workerCase] is the stream the selection is drawn from. At concurrency 1
  /// the root handle does for everything; above it, each worker draws from its
  /// own clone, since one handle may only be driven by one thread at a time.
  int? nextRule(TestCase workerCase, int workerIndex) {
    _checkWorker(workerIndex);
    return workerCase.guarded(() {
      final out = calloc<ffi.Int64>();
      try {
        _session.check(
          _session.bindings.hegel_state_machine_next_rule(
            _session.context,
            workerCase.handle,
            _live,
            workerIndex,
            out,
          ),
          'hegel_state_machine_next_rule',
        );
        return out.value == raw.HEGEL_STATE_MACHINE_DONE ? null : out.value;
      } finally {
        calloc.free(out);
      }
    });
  }

  /// Reports the rule most recently given to [workerIndex] as rejected.
  ///
  /// A rejected rule does not count against the step budget, so the worker
  /// gets the slot back rather than spending it on something it could not run.
  void ruleRejected(TestCase workerCase, int workerIndex) {
    _checkWorker(workerIndex);
    workerCase.guarded(() {
      _session.check(
        _session.bindings.hegel_state_machine_rule_rejected(
          _session.context,
          workerCase.handle,
          _live,
          workerIndex,
        ),
        'hegel_state_machine_rule_rejected',
      );
    });
  }

  void _checkWorker(int workerIndex) {
    if (workerIndex < 0 || workerIndex >= concurrency) {
      throw RangeError.range(workerIndex, 0, concurrency - 1, 'workerIndex');
    }
  }

  /// Releases the machine. Idempotent, and a no-op on a borrowed view.
  void dispose() {
    if (_disposed || isBorrowed) return;
    _disposed = true;
    assert(releaseHandle(this));
    _session.bindings.hegel_state_machine_free(_session.context, _handle);
  }
}
