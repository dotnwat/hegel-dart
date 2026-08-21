/// Engine-tracked sets of variable identifiers.
///
/// @docImport 'errors.dart';
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'session.dart';
import 'state_machine.dart' show HandleToken;
import 'test_case.dart';

/// A set of variable identifiers the engine can choose among and shrink over.
///
/// Mostly for stateful testing, where a rule needs to act on something an
/// earlier rule produced. The pool holds identifiers only; the caller keeps
/// its own map from identifier to whatever it made.
///
/// Like a collection, its operations take the test case whose stream the
/// choice is drawn from, and the handle outlives the case and run it came
/// from. Unlike a collection, a pool may be driven from several workers at
/// once: the ABI serializes concurrent operations on it rather than refusing
/// them, so it can be borrowed the way a state machine can.
final class Pool implements ffi.Finalizable {
  @internal
  Pool(this._session, this._handle, {this.isBorrowed = false});

  /// Reconstructs a borrowed view of a pool in another isolate.
  ///
  /// The view never frees the handle; the isolate that created the pool does,
  /// once its workers have joined.
  @internal
  static Pool adopt(Libhegel session, HandleToken token) => Pool(
    session,
    ffi.Pointer<raw.hegel_pool_t>.fromAddress(token.address),
    isBorrowed: true,
  );

  /// Whether this is a borrowed view rather than the owning wrapper.
  final bool isBorrowed;

  /// An address for this pool, to hand to a worker isolate.
  @internal
  HandleToken get token => HandleToken(_live.address);

  final Libhegel _session;
  final ffi.Pointer<raw.hegel_pool_t> _handle;
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  ffi.Pointer<raw.hegel_pool_t> get _live {
    if (_disposed) {
      throw StateError('this Pool has been disposed');
    }
    return _handle;
  }

  /// Adds a fresh identifier, drawn from [testCase], and returns it.
  ///
  /// The identifier is recorded by value rather than by position, so deleting
  /// an earlier addition while shrinking never renumbers the survivors.
  int add(TestCase testCase) {
    return testCase.guarded(() {
      final out = calloc<ffi.Int64>();
      try {
        _session.check(
          _session.bindings.hegel_pool_add(
            _session.context,
            testCase.handle,
            _live,
            out,
          ),
          'hegel_pool_add',
        );
        return out.value;
      } finally {
        calloc.free(out);
      }
    });
  }

  /// Chooses an identifier already in the pool, drawn from [testCase].
  ///
  /// With [consume] the chosen identifier is removed. Raises
  /// [AssumptionFailed] when the pool is empty, which is to be handled like
  /// any other failed precondition rather than as an error.
  int draw(TestCase testCase, {bool consume = false}) {
    return testCase.guarded(() {
      final out = calloc<ffi.Int64>();
      try {
        _session.check(
          _session.bindings.hegel_pool_generate(
            _session.context,
            testCase.handle,
            _live,
            consume,
            out,
          ),
          'hegel_pool_generate',
        );
        return out.value;
      } finally {
        calloc.free(out);
      }
    });
  }

  /// Releases the pool. Idempotent, and a no-op on a borrowed view.
  void dispose() {
    if (_disposed || isBorrowed) return;
    _disposed = true;
    _session.bindings.hegel_pool_free(_session.context, _handle);
  }
}
