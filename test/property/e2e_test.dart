@Tags(<String>['e2e'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The fixture suite, run as a subprocess.
///
/// Everything else in this suite asks the package what it did. This asks
/// `dart test` what a person sees, which is the only question a test
/// framework's failure output can be asked honestly.
const String fixturePath = 'test/fixture/property_fixture.dart';

/// A fixture whose property checks how many cases it was given.
const String environmentFixturePath = 'test/fixture/environment_fixture.dart';

Future<ProcessResult> runFixture(
  List<String> arguments, {
  String fixture = fixturePath,
  Map<String, String>? environment,
}) => Process.run(Platform.resolvedExecutable, <String>[
  'test',
  fixture,
  ...arguments,
], environment: environment);

/// The line the fixture writes `property('<name>'` on.
int lineOf(String name) {
  final lines = File(fixturePath).readAsLinesSync();
  return lines.indexWhere((String line) => line.contains("property('$name'")) +
      1;
}

void main() {
  test('a property that holds prints nothing but its name', () async {
    final result = await runFixture(<String>['-N', 'is an integer']);

    expect(result.exitCode, 0);
    expect(result.stdout, contains('All tests passed'));
    expect(result.stdout, contains('+1'));
    expect(
      result.stdout,
      isNot(contains('every drawn value is below fifty')),
      reason: '-N selects one property out of the file',
    );
    // No draws, no engine chatter, no seeds: a property that held has
    // nothing to report, and reporting it anyway is how a test suite becomes
    // unreadable.
    expect(result.stdout, isNot(contains('hegel')));
    expect(result.stderr, isEmpty);
  });

  test('a failing property fails the run with its own error', () async {
    final result = await runFixture(<String>['-N', 'below fifty']);

    expect(result.exitCode, isNot(0));
    expect(result.stdout, contains('every drawn value is below fifty'));
    // The matcher's own rendering of the counterexample the engine shrank
    // to: the error object the body raised is what package:test is given,
    // not a description of it.
    expect(result.stdout, contains('Expected: a value less than <50>'));
    expect(result.stdout, contains('Actual: <50>'));
  });

  test('a failing property shows the counterexample and its notes', () async {
    final result = await runFixture(<String>['-N', 'below fifty']);

    // package:test prints what was buffered after the error rather than
    // before it, so this is the order a reader sees rather than the order
    // the plan drew.
    expect(result.stdout, contains('value = 50'));
    expect(result.stdout, contains('about to check 50'));
    expect(
      result.stdout,
      contains('The example database is off'),
      reason:
          'the fixture turns it off, and a reader who does not know that '
          'would wait for a replay that never comes',
    );
  });

  test('the reporter points at the line the property was written on', () async {
    final result = await runFixture(<String>[
      '-N',
      'below fifty',
      '--reporter',
      'json',
    ]);

    final events = <Map<String, Object?>>[
      for (final String line in const LineSplitter().convert(
        '${result.stdout}',
      ))
        if (line.startsWith('{')) jsonDecode(line) as Map<String, Object?>,
    ];
    final started = <Map<String, Object?>>[
      for (final Map<String, Object?> event in events)
        if (event['type'] == 'testStart')
          event['test']! as Map<String, Object?>,
    ];
    final property = started.firstWhere(
      (Map<String, Object?> test) => '${test['name']}'.contains('below fifty'),
    );

    // Without a location the runner reports the frame inside this package,
    // and an editor's run button and failure link land there instead of on
    // the test.
    expect('${property['url']}', endsWith('/$fixturePath'));
    expect(property['line'], lineOf('every drawn value is below fifty'));
  });

  test(
    'the environment outranks the settings a property was written with',
    () async {
      final overridden = await runFixture(
        <String>[],
        fixture: environmentFixturePath,
        environment: <String, String>{'HEGEL_TEST_CASES': '3'},
      );

      expect(overridden.exitCode, 0, reason: '${overridden.stdout}');
    },
  );

  test(
    'and the fixture that proves it fails without the environment',
    () async {
      // The control. Without it, a property that quietly ignored the variable
      // and a property that honoured it would look the same from here.
      final untouched = await runFixture(
        <String>[],
        fixture: environmentFixturePath,
      );

      expect(untouched.exitCode, isNot(0));
    },
  );

  test('the environment can put the example database somewhere', () async {
    final directory = Directory.systemTemp.createTempSync('hegel-e2e');
    addTearDown(() => directory.deleteSync(recursive: true));

    final result = await runFixture(
      <String>['-N', 'below fifty'],
      environment: <String, String>{'HEGEL_DATABASE': directory.path},
    );

    expect(result.exitCode, isNot(0));
    expect(
      directory.listSync(recursive: true).whereType<File>(),
      isNotEmpty,
      reason:
          'the fixture turns the database off and the environment turns '
          'it back on, which is what a CI job that wants to keep its '
          'counterexamples has to do',
    );
  });
}
