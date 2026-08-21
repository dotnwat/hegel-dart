@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every function the pinned header declares.
///
/// Read from `third_party/libhegel/hegel.h` rather than from anything
/// generated, so this stays an independent opinion about what the ABI is. A
/// declaration is a line beginning at column zero that names a `hegel_`
/// function; everything else in the header is documentation, a struct, or an
/// enum.
Set<String> headerFunctions() {
  final header = File('third_party/libhegel/hegel.h').readAsStringSync();
  return RegExp(
    r'^[A-Za-z_][A-Za-z0-9_ ]*\**\s*\b(hegel_[a-z0-9_]+)\s*\(',
    multiLine: true,
  ).allMatches(header).map((RegExpMatch m) => m.group(1)!).toSet();
}

/// Every function the binding surface declares.
Set<String> boundFunctions() {
  final bindings = File('lib/src/libhegel/bindings.dart').readAsStringSync();
  final interface = bindings.substring(
    bindings.indexOf('abstract interface class Bindings {'),
    bindings.indexOf('final class NativeBindings'),
  );
  return RegExp(
    r'\b(hegel_[a-z0-9_]+)\s*\(',
    multiLine: true,
  ).allMatches(interface).map((RegExpMatch m) => m.group(1)!).toSet();
}

/// Everything the safe layer says, with the raw layers left out.
String safeLayerSource() {
  final buffer = StringBuffer();
  for (final entity in Directory(
    'lib/src/libhegel',
  ).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('bindings.dart') ||
        entity.path.endsWith('bindings.g.dart')) {
      continue;
    }
    buffer.writeln(entity.readAsStringSync());
  }
  return buffer.toString();
}

void main() {
  test('the header parser finds a plausible ABI', () {
    // A guard on the audit itself: a regex that quietly matched nothing would
    // make every assertion below pass for the wrong reason.
    expect(headerFunctions(), hasLength(greaterThan(60)));
    expect(headerFunctions(), contains('hegel_version'));
    expect(headerFunctions(), contains('hegel_run_start'));
    expect(headerFunctions(), contains('hegel_state_machine_next_rule'));
  });

  test('every function in the pinned header is bound', () {
    final missing = headerFunctions().difference(boundFunctions());
    expect(
      missing,
      isEmpty,
      reason:
          'the header declares these but the binding surface does not: '
          '${missing.join(', ')}',
    );
  });

  test('nothing is bound that the header does not declare', () {
    final extra = boundFunctions().difference(headerFunctions());
    expect(
      extra,
      isEmpty,
      reason: 'bound but absent from the header: ${extra.join(', ')}',
    );
  });

  // The question the eager symbol check cannot answer. Resolving a symbol
  // proves the engine exports it; this proves something above actually calls
  // it, so a function cannot be bound, linked, and silently unused.
  test('every bound function is reached from the safe layer', () {
    final source = safeLayerSource();
    final unused =
        boundFunctions().where((String name) => !source.contains(name)).toList()
          ..sort();
    expect(
      unused,
      isEmpty,
      reason: 'bound but never called by the safe layer: ${unused.join(', ')}',
    );
  });
}
