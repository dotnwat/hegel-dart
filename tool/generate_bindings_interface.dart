/// Generates `lib/src/libhegel/bindings.dart` from the ffigen output.
///
///     dart run tool/generate_bindings_interface.dart
///
/// The interface is derived rather than hand-written on purpose. Its value is
/// that it is exactly one-to-one with the generated bindings, and deriving it
/// makes that true by construction instead of by discipline; the CI drift job
/// regenerates both and fails on any difference. Hand-maintaining ~1000 lines
/// of forwarding boilerplate across ABI bumps would buy nothing except the
/// chance to get it wrong.
library;

import 'dart:io';

final RegExp _declaration = RegExp(
  r'@ffi\.Native<\s*([\s\S]*?)\s*>\(\)\s*\nexternal\s+([\w.<>, ]+?)\s+'
  r'(hegel_\w+)\(([\s\S]*?)\);',
);

/// Qualifies libhegel's own types with the `raw.` import prefix.
String _qualify(String type) =>
    type.replaceAllMapped(RegExp(r'\bhegel_\w+\b'), (m) => 'raw.${m[0]}');

/// Collapses a multi-line generated type into one line.
String _flatten(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').replaceAll(', )', ')').trim();

({String type, String name}) _parameter(String text) {
  final trimmed = text.trim();
  final split = trimmed.lastIndexOf(' ');
  return (
    type: _qualify(trimmed.substring(0, split).trim()),
    name: trimmed.substring(split + 1).trim(),
  );
}

List<({String type, String name})> _parameters(String text) {
  final parameters = <({String type, String name})>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final rune = text[i];
    if (rune == '<' || rune == '(') depth++;
    if (rune == '>' || rune == ')') depth--;
    if (rune == ',' && depth == 0) {
      parameters.add(_parameter(text.substring(start, i)));
      start = i + 1;
    }
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) parameters.add(_parameter(tail));
  return parameters;
}

void main() {
  final root = Directory.fromUri(Platform.script.resolve('../'));
  final source = File.fromUri(
    root.uri.resolve('lib/src/libhegel/bindings.g.dart'),
  ).readAsStringSync();

  final signatures = <String>[];
  final forwards = <String>[];
  final resolutions = <String>[];

  for (final match in _declaration.allMatches(source)) {
    final nativeType = _qualify(_flatten(match.group(1)!));
    final returns = _qualify(match.group(2)!.trim());
    final name = match.group(3)!;
    final parameters = _parameters(match.group(4)!);

    final declared = parameters.map((p) => '${p.type} ${p.name}').join(', ');
    final passed = parameters.map((p) => p.name).join(', ');

    signatures.add('  $returns $name($declared);');
    forwards.add(
      '  @override\n'
      '  $returns $name($declared) => raw.$name($passed);',
    );
    resolutions.add(
      '    ffi.Native.addressOf<ffi.NativeFunction<$nativeType>>(raw.$name);',
    );
  }

  if (signatures.length < 60) {
    stderr.writeln('only ${signatures.length} declarations found; aborting');
    exitCode = 1;
    return;
  }

  File.fromUri(root.uri.resolve('lib/src/libhegel/bindings.dart'))
      .writeAsStringSync('''
// GENERATED FILE. DO NOT EDIT.
//
// Generated from bindings.g.dart by tool/generate_bindings_interface.dart.
// Regenerate with `just regen`.
//
// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars

/// The seam between the safe layer and the raw FFI bindings.
///
/// Everything above this calls libhegel through [Bindings], never through the
/// generated functions directly. That buys two things: tests can inject a fake
/// to reach result codes the real engine cannot be driven to produce, and
/// [NativeBindings.verifySymbols] resolves every symbol up front so an
/// ABI-skewed engine fails when a session opens rather than mid-test.
library;

import 'dart:ffi' as ffi;

import 'bindings.g.dart' as raw;

/// Every function libhegel exports, one-to-one with the C ABI.
///
/// Names are the C names so this surface diffs cleanly against the header when
/// the ABI moves. No parameter is defaulted or absorbed here; convenience
/// belongs in the safe layer, where it stays visible.
abstract interface class Bindings {
  /// Resolves every symbol, throwing if any is missing.
  ///
  /// Part of the interface rather than only the native implementation so a
  /// session opens the same way whichever bindings it was handed.
  void verifySymbols();

${signatures.join('\n')}
}

/// [Bindings] backed by the real engine.
final class NativeBindings implements Bindings {
  /// Creates a binding onto the loaded engine.
  const NativeBindings();

  /// Resolves every symbol, throwing if any is missing.
  ///
  /// `@Native` resolution is lazy, so without this an engine missing a symbol
  /// would surface at the first call that needs it — somewhere deep in a test
  /// run — instead of at the moment the session opens.
  @override
  void verifySymbols() {
${resolutions.join('\n')}
  }

${forwards.join('\n\n')}
}
''');

  stdout.writeln('generated ${signatures.length} bindings');
}
