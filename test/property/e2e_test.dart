@Tags(<String>['e2e'])
@TestOn('vm')
// Windows cannot run these at all, and not for a reason about this package.
// Every `dart test` copies the engine into `.dart_tool/lib/` before it starts,
// and Windows will not let it delete a DLL that the outer `dart test` -- the
// one running this file -- already has loaded:
//
//     PathAccessException: Cannot delete file, path =
//     '...\.dart_tool\lib\libhegel-windows-amd64.dll'
//     (OS Error: Access is denied, errno = 5)
//
// So a nested run fails before reaching the fixture, whatever the fixture
// says. Skipped rather than quietly excluded, so that the matrix shows the
// gap; what a Windows user sees is covered by everything else in the suite,
// which does run there.
@OnPlatform(<String, Object>{
  'windows': Skip('a nested `dart test` cannot re-copy the engine DLL'),
})
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

/// A fixture that says which value its property drew first.
const String databaseFixturePath = 'test/fixture/database_fixture.dart';

/// The first value the database fixture drew, as it printed it.
///
/// A subprocess that failed to start says so in its own output, so anything
/// that cannot find what it is looking for shows that output rather than
/// dying on a null check that names nothing.
int firstDrawnBy(ProcessResult result) {
  final printed = RegExp(r'FIRST=(\d+)').firstMatch('${result.stdout}');
  if (printed == null) {
    fail('the fixture printed no FIRST= line\n${describe(result)}');
  }
  return int.parse(printed.group(1)!);
}

/// What a subprocess said, for a failure message.
String describe(ProcessResult result) =>
    'exit ${result.exitCode}\n--- stdout ---\n${result.stdout}'
    '\n--- stderr ---\n${result.stderr}';

/// Runs [fixture] as a subprocess, with the reporter pinned.
///
/// Pinned because package:test picks a reporter from its environment: under
/// GitHub Actions it switches to one that writes `🎉 1 test passed.` where
/// the default writes `All tests passed!`, and folds the rest into log
/// groups. What these tests read is this package's own output, so the chrome
/// around it should be the same everywhere rather than depending on who is
/// watching.
Future<ProcessResult> runFixture(
  List<String> arguments, {
  String fixture = fixturePath,
  String reporter = 'expanded',
  Map<String, String>? environment,
}) => Process.run(Platform.resolvedExecutable, <String>[
  'test',
  '--reporter',
  reporter,
  fixture,
  ...arguments,
], environment: environment);

/// The line the fixture opens its `property(` call for [name] on.
///
/// Found by locating the description and walking back to the call that takes
/// it, because the two are only on the same line until `dart format` decides
/// otherwise -- which it already has in database_fixture.dart. Searching for
/// them together would then quietly find nothing, and an anchor that fails
/// by returning a line number is worse than one that fails loudly.
int lineOf(String name, {String path = fixturePath}) {
  final lines = File(path).readAsLinesSync();
  final described = lines.indexWhere((String line) => line.contains("'$name'"));
  if (described < 0) {
    fail('no line of $path mentions "$name"');
  }
  for (var index = described; index >= 0; index--) {
    if (lines[index].contains('property(')) return index + 1;
  }
  return fail('no property( call at or above line ${described + 1}');
}

void main() {
  test('a property that holds prints nothing but its name', () async {
    final result = await runFixture(<String>['-N', 'is an integer']);

    expect(result.exitCode, 0, reason: describe(result));
    expect(result.stdout, contains('All tests passed'));
    expect(result.stdout, contains('+1'));
    expect(
      result.stdout,
      isNot(contains('every drawn value is below fifty')),
      reason: '-N selects one property out of the file',
    );
    // A property that held has nothing to report, and reporting it anyway is
    // how a test suite becomes unreadable. Named by what a report is made of
    // rather than by the package's name, which also appears in a checkout
    // path and in nothing this asserts about.
    for (final reported in <String>[
      'value = ',
      'reproduce:',
      'example database',
      'Seed:',
    ]) {
      expect(result.stdout, isNot(contains(reported)));
    }
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

  group('a property that fails in more than one way', () {
    test('reports every failure, not just the one that ended it', () async {
      final result = await runFixture(<String>['-N', 'whichever kind']);

      expect(result.exitCode, isNot(0));
      // Both errors, each rendered by package:test out of the object the
      // body raised. The odd branch is the one thrown and the even branch is
      // the one registered, but a reader is not meant to be able to tell
      // which was which, so both are asserted the same way.
      expect(result.stdout, contains('Expected: a value less than <200>'));
      expect(result.stdout, contains('an odd value went large'));
      expect(result.stdout, contains('Expected: a value less than <100>'));
      expect(result.stdout, contains('an even value went large'));
    });

    test('shrinks each failure on its own', () async {
      final result = await runFixture(<String>['-N', 'whichever kind']);

      // The smallest failing value of each kind, which is the whole reason
      // the two are kept apart: shrunk together, one of them would drag the
      // other off its own minimum.
      expect(result.stdout, contains('value = 201'));
      expect(result.stdout, contains('value = 100'));
    });

    test('names both origins in one place', () async {
      final result = await runFixture(<String>['-N', 'whichever kind']);

      expect(result.stdout, contains('The property failed in 2 distinct ways'));
      final even = lineOf('small values stay small, whichever kind they are');
      // The two assertion sites, by line, since that is what the engine
      // groups on and what a reader has to go and look at.
      expect(result.stdout, contains('property_fixture.dart:${even + 3}'));
      expect(result.stdout, contains('property_fixture.dart:${even + 5}'));
    });

    test('counts as one failing test, not two', () async {
      final result = await runFixture(<String>['-N', 'whichever kind']);

      // A property is one test however many bugs it found. Two would mean
      // the extra failures had been registered against something other than
      // the test that was running.
      expect(result.stdout, contains('-1: Some tests failed'));
    });
  });

  test('the reporter points at the line the property was written on', () async {
    final result = await runFixture(<String>[
      '-N',
      'below fifty',
    ], reporter: 'json');

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
      orElse: () => fail('the run started no such test\n${describe(result)}'),
    );

    // Without a location the runner reports the frame inside this package,
    // and an editor's run button and failure link land there instead of on
    // the test.
    expect('${property['url']}', endsWith('/$fixturePath'));
    expect(property['line'], lineOf('every drawn value is below fifty'));

    // The same lookup against a file dart format has already split, which is
    // what the fixture above turns into the moment it grows an argument.
    final split = lineOf(
      'every drawn value is below fifty',
      path: databaseFixturePath,
    );
    expect(
      File(databaseFixturePath).readAsLinesSync()[split - 1],
      contains('property('),
    );
  });

  test('a case count of zero is refused rather than obeyed', () async {
    // A run with no cases checks nothing and reports that the property held,
    // so before this was refused a leftover variable on a CI job turned a
    // whole suite green -- including suites full of properties that fail.
    final zero = await runFixture(
      <String>['-N', 'is an integer'],
      environment: <String, String>{'HEGEL_TEST_CASES': '0'},
    );

    expect(zero.exitCode, isNot(0), reason: describe(zero));
    expect(zero.stdout, contains('HEGEL_TEST_CASES'));
  });

  test(
    'the environment outranks the settings a property was written with',
    () async {
      final overridden = await runFixture(
        <String>[],
        fixture: environmentFixturePath,
        environment: <String, String>{'HEGEL_TEST_CASES': '3'},
      );

      expect(overridden.exitCode, 0, reason: describe(overridden));
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

  test(
    'a counterexample comes back on the next run of the same test',
    () async {
      // The end of the loop the whole layer exists to close: a property fails,
      // the counterexample is filed under a key derived from the test's own
      // identity, and the next run of that test -- a separate process, with a
      // separate engine, deriving the key again from scratch -- is handed it
      // before anything is generated.
      final directory = Directory.systemTemp.createTempSync('hegel-e2e-db');
      addTearDown(() => directory.deleteSync(recursive: true));
      final environment = <String, String>{'HEGEL_DATABASE': directory.path};

      final searched = await runFixture(
        <String>[],
        fixture: databaseFixturePath,
        environment: environment,
      );
      final replayed = await runFixture(
        <String>[],
        fixture: databaseFixturePath,
        environment: environment,
      );

      expect(searched.exitCode, isNot(0));
      expect(replayed.exitCode, isNot(0));
      expect(
        firstDrawnBy(replayed),
        50,
        reason: 'the second run starts on the value the first one shrank to',
      );
      expect(
        firstDrawnBy(searched),
        isNot(50),
        reason: 'and the first run had to look for it, or this proves nothing',
      );
    },
  );
}
