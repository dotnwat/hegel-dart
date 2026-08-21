/// Specifications for string draws.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'leaks.dart';
import 'marshal.dart';
import 'session.dart';

/// What a string draw should produce.
///
/// Every parameter is validated when the generator is built, so a malformed
/// specification fails once here rather than on every draw. A generator is
/// immutable afterwards and may be reused across test cases and runs; release
/// it with [dispose] once no draw will use it again.
final class StringGenerator implements ffi.Finalizable {
  StringGenerator._(this._session, this._handle) {
    assert(trackHandle(this, 'StringGenerator'));
  }

  /// Text drawn from a configurable alphabet.
  ///
  /// [codec] picks the starting range: `ascii`, `latin-1`, or `utf-8` (the
  /// default). [categories] restricts to the union of the named Unicode
  /// general categories, and null means no restriction — which is not the same
  /// as an empty list, which means an alphabet with nothing in it.
  /// [maxSize] of null leaves the length unbounded.
  factory StringGenerator.text({
    int minSize = 0,
    int? maxSize,
    String? codec,
    int minCodepoint = 0,
    int maxCodepoint = 0xFFFFFFFF,
    List<String>? categories,
    List<String>? excludeCategories,
    String? includeCharacters,
    String? excludeCharacters,
    Libhegel? session,
  }) {
    // Unsigned on the wire, so a negative size arrives as UINT64_MAX. Asking
    // the engine for a string of that length aborts the process with an
    // allocation panic, taking the test runner with it, so nothing here may
    // reach the ABI unchecked.
    checkFitsUnsigned(minSize, 'minSize');
    if (maxSize != null && minSize > maxSize) {
      throw ArgumentError.value(minSize, 'minSize', 'exceeds maxSize');
    }
    checkFitsUnsigned(minCodepoint, 'minCodepoint', bits: 32);
    checkFitsUnsigned(maxCodepoint, 'maxCodepoint', bits: 32);

    final active = session ?? Libhegel.instance;
    return _build(active, (
      ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out,
    ) {
      return using((Arena arena) {
        final include = toByteBuffer(
          arena,
          includeCharacters,
          'includeCharacters',
        );
        final exclude = toByteBuffer(
          arena,
          excludeCharacters,
          'excludeCharacters',
        );
        final wanted = toStringArray(arena, categories, 'categories');
        final unwanted = toStringArray(
          arena,
          excludeCategories,
          'excludeCategories',
        );
        return active.bindings.hegel_string_generator_text(
          active.context,
          minSize,
          sizeOrUnbounded(maxSize, 'maxSize'),
          toCString(arena, codec, 'codec'),
          minCodepoint,
          maxCodepoint,
          wanted.data,
          wanted.length,
          unwanted.data,
          unwanted.length,
          include.data,
          include.length,
          exclude.data,
          exclude.length,
          out,
        );
      });
    }, 'hegel_string_generator_text');
  }

  /// Strings matching [pattern], in Python `re` syntax.
  ///
  /// With [fullMatch] the whole string matches; otherwise the match may be
  /// padded on either side, and [alphabet] constrains that padding.
  factory StringGenerator.regex(
    String pattern, {
    bool fullMatch = false,
    StringGenerator? alphabet,
    Libhegel? session,
  }) {
    final active = session ?? Libhegel.instance;
    return _build(active, (
      ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out,
    ) {
      return using((Arena arena) {
        return active.bindings.hegel_string_generator_regex(
          active.context,
          toCString(arena, pattern, 'pattern'),
          fullMatch,
          alphabet?.handle ?? ffi.nullptr,
          out,
        );
      });
    }, 'hegel_string_generator_regex');
  }

  /// RFC 5321/5322 email addresses.
  factory StringGenerator.email({Libhegel? session}) {
    final active = session ?? Libhegel.instance;
    return _build(
      active,
      (ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out) =>
          active.bindings.hegel_string_generator_email(active.context, out),
      'hegel_string_generator_email',
    );
  }

  /// RFC 3986 http and https URLs.
  factory StringGenerator.url({Libhegel? session}) {
    final active = session ?? Libhegel.instance;
    return _build(
      active,
      (ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out) =>
          active.bindings.hegel_string_generator_url(active.context, out),
      'hegel_string_generator_url',
    );
  }

  /// Fully-qualified domain names of at most [maxLength] characters.
  factory StringGenerator.domain({int maxLength = 255, Libhegel? session}) {
    checkFitsUnsigned(maxLength, 'maxLength');
    final active = session ?? Libhegel.instance;
    return _build(
      active,
      (ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out) => active
          .bindings
          .hegel_string_generator_domain(active.context, maxLength, out),
      'hegel_string_generator_domain',
    );
  }

  static StringGenerator _build(
    Libhegel session,
    int Function(ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out)
    construct,
    String operation,
  ) {
    final out = calloc<ffi.Pointer<raw.hegel_string_generator_t>>();
    try {
      session.check(construct(out), operation);
      return StringGenerator._(session, out.value);
    } finally {
      calloc.free(out);
    }
  }

  final Libhegel _session;
  final ffi.Pointer<raw.hegel_string_generator_t> _handle;
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// The engine-side handle.
  @internal
  ffi.Pointer<raw.hegel_string_generator_t> get handle {
    if (_disposed) {
      throw StateError('this StringGenerator has been disposed');
    }
    return _handle;
  }

  /// Releases the generator. Idempotent.
  ///
  /// Only once every draw using it has completed: the ABI hands the same
  /// handle to each draw and does not retain it afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    assert(releaseHandle(this));
    _session.bindings.hegel_string_generator_free(_session.context, _handle);
  }
}
