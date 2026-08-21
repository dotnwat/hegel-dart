/// Engine-driven variable-length sequences.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'marshal.dart';
import 'session.dart';
import 'test_case.dart';

/// A sequence whose length the engine chooses.
///
/// The caller loops on [more], drawing one element each time it answers true,
/// and reports an element it cannot use with [reject]. Both take the test case
/// whose stream the decision should be drawn from: the handle is shared by a
/// whole test-case family, so which member drives it decides where the choice
/// is recorded, and that matters once workers drive clones.
///
/// The handle is independent of the test case and run it came from. Release it
/// with [dispose] exactly once, in any order relative to them.
final class Collection implements ffi.Finalizable {
  @internal
  Collection(this._session, this._handle);

  final Libhegel _session;
  final ffi.Pointer<raw.hegel_collection_t> _handle;
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  ffi.Pointer<raw.hegel_collection_t> get _live {
    if (_disposed) {
      throw StateError('this Collection has been disposed');
    }
    return _handle;
  }

  /// Whether the engine wants another element, drawn from [testCase].
  bool more(TestCase testCase) {
    return testCase.guarded(() {
      final out = calloc<ffi.Bool>();
      try {
        _session.check(
          _session.bindings.hegel_collection_more(
            _session.context,
            testCase.handle,
            _live,
            out,
          ),
          'hegel_collection_more',
        );
        return out.value;
      } finally {
        calloc.free(out);
      }
    });
  }

  /// Reports that the element just produced cannot be used.
  ///
  /// [why] is accepted and validated but the engine does not use it yet.
  void reject(TestCase testCase, {String? why}) {
    testCase.guarded(() {
      using((Arena arena) {
        _session.check(
          _session.bindings.hegel_collection_reject(
            _session.context,
            testCase.handle,
            _live,
            toCString(arena, why, 'why'),
          ),
          'hegel_collection_reject',
        );
      });
    });
  }

  /// Releases the collection. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session.bindings.hegel_collection_free(_session.context, _handle);
  }
}
