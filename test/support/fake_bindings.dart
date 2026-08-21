/// A [Bindings] that answers from a script instead of a real engine.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:hegel/src/libhegel/bindings.dart';
import 'package:hegel/src/libhegel/bindings.g.dart' as raw;

/// Writes [version] into the out-parameter of a `hegel_version` call.
///
/// Sessions read the version while opening, so almost every fake needs this.
void writeVersion(Invocation invocation, String version) {
  final text = version.toNativeUtf8();
  _versionStrings.add(text);
  (invocation.positionalArguments.last as ffi.Pointer<ffi.Pointer<ffi.Char>>)
      .value = text
      .cast<ffi.Char>();
}

final List<ffi.Pointer<Utf8>> _versionStrings = <ffi.Pointer<Utf8>>[];

/// Frees every string [writeVersion] allocated.
void releaseVersionStrings() {
  for (final text in _versionStrings) {
    calloc.free(text);
  }
  _versionStrings.clear();
}

/// Turns `Symbol("hegel_version")` back into `hegel_version`.
///
/// Avoids dart:mirrors; symbol names survive because tests run in the JIT.
String _nameOf(Symbol symbol) {
  final text = symbol.toString();
  final start = text.indexOf('"');
  if (start < 0) return text;
  return text.substring(start + 1, text.lastIndexOf('"'));
}

/// A scriptable stand-in for the engine.
///
/// It exists for the result codes a real engine cannot be driven to produce on
/// demand — HEGEL_E_BACKEND, HEGEL_E_INTERNAL, HEGEL_E_CONCURRENT_USE — and
/// for asserting the exact sequence of calls the safe layer makes. Everything
/// a real engine *can* be made to do is tested against the real engine.
///
/// Implemented with [noSuchMethod] rather than 71 stubs: the point is to
/// script a handful of calls, not to reimplement libhegel.
final class FakeBindings implements Bindings {
  /// Result code to answer with, per C function name. Absent means success.
  final Map<String, int> results = <String, int>{};

  /// Every call made, in order, by C function name.
  final List<String> calls = <String>[];

  /// Runs before each call answers, so a test can fill in out-parameters.
  void Function(String name, Invocation invocation)? onCall;

  /// Handed back by `hegel_context_new`. Non-null so callers see a success.
  ffi.Pointer<raw.hegel_context_t> context =
      ffi.Pointer<raw.hegel_context_t>.fromAddress(0x1000);

  /// Handed back by `hegel_context_last_error`.
  ffi.Pointer<ffi.Char> lastError = ffi.nullptr;

  /// The names of calls made, cleared.
  void clearCalls() => calls.clear();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = _nameOf(invocation.memberName);
    calls.add(name);
    onCall?.call(name, invocation);
    return switch (name) {
      'hegel_context_new' => context,
      'hegel_context_last_error' => lastError,
      _ => results[name] ?? raw.hegel_result_t.HEGEL_OK,
    };
  }
}
