/// The per-isolate libhegel session: bindings, the error context, and the
/// engine version check.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.dart';
import 'bindings.g.dart' as raw;
import 'errors.dart';
import 'leaks.dart';
import 'version.g.dart';

/// Whether [engine] and [pinned] agree closely enough to be used together.
///
/// libhegel is pre-1.0, so its ABI may change between minor releases but not
/// between patches: `0.33.1` satisfies a pin of `0.33.0`, `0.34.0` does not.
/// An unparseable version is treated as incompatible rather than waved
/// through, since there is no way to tell what it is.
@visibleForTesting
bool versionsCompatible(String engine, String pinned) {
  List<String>? parts(String version) {
    final fields = version.split('.');
    return fields.length < 2 ? null : fields;
  }

  final engineParts = parts(engine);
  final pinnedParts = parts(pinned);
  if (engineParts == null || pinnedParts == null) return false;
  return engineParts[0] == pinnedParts[0] && engineParts[1] == pinnedParts[1];
}

/// One isolate's connection to the engine.
///
/// The ABI forbids sharing an error context across threads, since every
/// fallible call overwrites the message it holds. Dart statics are per-isolate,
/// so [instance] gives each isolate its own context without any coordination.
///
/// A session must outlive every handle created from it. Worker isolates should
/// dispose their handles and then their session in a `finally`; the main
/// isolate may simply hold one for the life of the program.
final class Libhegel {
  Libhegel._(this.bindings, this._context, this.engineVersion) {
    // A session owns a context, which is a handle like any other. The
    // process-wide instance is rooted in a static and never collected; a
    // session opened by hand and dropped is exactly what this should catch.
    assert(trackHandle(this, 'Libhegel'));
  }

  static Libhegel? _instance;

  /// This isolate's session, opened on first use.
  static Libhegel get instance => _instance ??= open();

  /// Opens a session over [bindings].
  ///
  /// Resolves every symbol, allocates the context, and checks the engine's
  /// version against the pin. A mismatch frees the context it just allocated
  /// before it throws, so a failed open leaks nothing.
  static Libhegel open([Bindings bindings = const NativeBindings()]) {
    bindings.verifySymbols();
    final context = bindings.hegel_context_new();
    if (context == ffi.nullptr) {
      throw HegelException('hegel_context_new', 0, 'returned no context');
    }

    final String version;
    try {
      version = _readVersion(bindings, context);
    } on Object {
      bindings.hegel_context_free(context);
      rethrow;
    }

    if (!versionsCompatible(version, libhegelVersion)) {
      bindings.hegel_context_free(context);
      throw HegelException(
        'hegel_version',
        0,
        'the loaded engine reports $version but this package is built '
            'against $libhegelVersion. Their ABIs may differ. If the '
            'hegel.libhegel_path user-define points at a local build, it is '
            'probably stale.',
      );
    }

    return Libhegel._(bindings, context, version);
  }

  static String _readVersion(
    Bindings bindings,
    ffi.Pointer<raw.hegel_context_t> context,
  ) {
    final out = calloc<ffi.Pointer<ffi.Char>>();
    try {
      final code = bindings.hegel_version(context, out);
      if (code != raw.hegel_result_t.HEGEL_OK) {
        throwForResult(code, 'hegel_version', _errorOn(bindings, context));
      }
      if (out.value == ffi.nullptr) {
        throw HegelException('hegel_version', 0, 'returned no version');
      }
      return out.value.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  static String _errorOn(
    Bindings bindings,
    ffi.Pointer<raw.hegel_context_t> context,
  ) {
    final message = bindings.hegel_context_last_error(context);
    return message == ffi.nullptr ? '' : message.cast<Utf8>().toDartString();
  }

  /// How this session reaches the engine.
  final Bindings bindings;

  /// The version the loaded engine reports.
  final String engineVersion;

  final ffi.Pointer<raw.hegel_context_t> _context;
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// The error context to pass as the first argument of any call.
  ffi.Pointer<raw.hegel_context_t> get context {
    if (_disposed) {
      throw StateError('this Libhegel session has been disposed');
    }
    return _context;
  }

  /// The engine's diagnostic for the most recent failed call on this context.
  ///
  /// Invalidated by the next call on the same context, so it is copied into a
  /// Dart string immediately.
  String lastError() => _errorOn(bindings, context);

  /// Returns normally when [code] is success, and raises otherwise.
  void check(int code, String operation) =>
      checkResult(code, operation, lastError);

  /// Frees the context.
  ///
  /// Idempotent. Every handle created from this session must already be
  /// disposed; the ABI pairs one context with every call that used it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    assert(releaseHandle(this));
    bindings.hegel_context_free(_context);
    if (identical(_instance, this)) _instance = null;
  }

  /// Installs [bindings] as this isolate's session, disposing any predecessor.
  @visibleForTesting
  static Libhegel overrideForTesting(Bindings bindings) {
    _instance?.dispose();
    return _instance = open(bindings);
  }

  /// Drops this isolate's session so the next use opens a fresh one.
  @visibleForTesting
  static void resetForTesting() {
    _instance?.dispose();
    _instance = null;
  }
}
