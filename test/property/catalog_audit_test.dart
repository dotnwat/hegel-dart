@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every draw the binding layer offers.
///
/// Read from the source rather than from a list kept here, so that a draw
/// added to the binding layer is a draw this audit starts asking about
/// without anyone remembering to add it. A declaration is a member of
/// `TestCase` whose name begins with `draw` and a capital; the private
/// helper behind the address draws is not one.
Set<String> engineDraws() {
  final source = File('lib/src/libhegel/test_case.dart').readAsStringSync();
  return RegExp(
    r'^  [\w<>?, ]+ (draw[A-Z]\w*)\(',
    multiLine: true,
  ).allMatches(source).map((RegExpMatch match) => match.group(1)!).toSet();
}

/// Everything the property layer says, apart from the seam.
///
/// `test_case.dart` is left out on purpose: it forwards every draw the seam
/// declares, so counting it would make every draw look reached whether or not
/// any generator asks for one. What this audit is about is the catalog.
String catalogSource() {
  final buffer = StringBuffer();
  for (final entity in Directory('lib/src/property').listSync()) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('test_case.dart')) continue;
    buffer.writeln(entity.readAsStringSync());
  }
  return buffer.toString();
}

/// Whether [source] calls [name], as opposed to mentioning it.
bool callsDraw(String source, String name) =>
    RegExp('\\.\\s*${RegExp.escape(name)}\\s*\\(').hasMatch(source);

void main() {
  test('the draw parser finds a plausible set', () {
    // A guard on the audit itself: a regex that quietly matched nothing
    // would make the assertion below pass for the wrong reason.
    final draws = engineDraws();

    expect(draws, hasLength(greaterThan(10)));
    expect(draws, contains('drawInteger'));
    expect(draws, contains('drawUuid'));
    expect(draws, contains('drawString'));
    expect(
      draws,
      isNot(contains('drawAddress')),
      reason: 'the private helper is not a draw the catalog could reach',
    );
  });

  group('the reached-from check', () {
    test('accepts an invocation', () {
      expect(
        callsDraw('testCase.context.drawUuid(version: 4)', 'drawUuid'),
        isTrue,
      );
    });

    test('rejects a name that only appears in prose', () {
      expect(
        callsDraw('/// Draws through [drawUuid] eventually.', 'drawUuid'),
        isFalse,
      );
    });

    test('does not mistake one name for a longer one', () {
      expect(callsDraw('context.drawIntegerBig(x);', 'drawInteger'), isFalse);
    });
  });

  // The claim P3 exists to make: every way the engine can produce a value is
  // one a property can ask for by name, without reaching past the catalog
  // into the binding layer.
  test('every engine draw is reachable through a public generator', () {
    final source = catalogSource();
    final unreached =
        engineDraws().where((String name) => !callsDraw(source, name)).toList()
          ..sort();

    expect(
      unreached,
      isEmpty,
      reason:
          'the binding layer can draw these and no generator does: '
          '${unreached.join(', ')}',
    );
  });
}
