@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

/// The value a property that fails above fifty shrinks to.
const int shrunkAboveFifty = 51;

Settings settingsFor({Database database = Database.disabled, int seed = 5}) =>
    Settings(
      testCases: 100,
      seed: seed,
      derandomize: true,
      database: database,
      verbosity: Verbosity.quiet,
      suppressHealthChecks: machineSpeedChecks,
    );

/// Fails whenever the value it draws is above fifty, recording every draw.
FutureOr<void> Function(TestCase) failsAboveFifty(List<int> drawn) =>
    (TestCase testCase) {
      final value = testCase.draw(integers(min: 0, max: 1000), name: 'value');
      drawn.add(value);
      if (value > 50) throw StateError('$value is too big');
    };

/// Runs a failing property and returns the blob it told the reader about.
///
/// The round trip is the point: the hint is only worth printing if what it
/// prints is what `reproduce:` takes.
Future<String> blobFromAFailure() async {
  final said = <String>[];
  await expectLater(
    runProperty(
      failsAboveFifty(<int>[]),
      settings: settingsFor(),
      onDiagnostic: said.add,
    ),
    throwsStateError,
  );
  final hint = RegExp("reproduce: '([^']+)'").firstMatch(said.join('\n'));
  expect(hint, isNotNull, reason: 'the failure report should offer a blob');
  return hint!.group(1)!;
}

void main() {
  group('reproduce', () {
    test('replays the one case the blob encodes', () async {
      final blob = await blobFromAFailure();
      final drawn = <int>[];

      await expectLater(
        runProperty(
          failsAboveFifty(drawn),
          settings: settingsFor(),
          reproduce: blob,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            '$shrunkAboveFifty is too big',
          ),
        ),
      );
      expect(
        drawn,
        <int>[shrunkAboveFifty],
        reason:
            'one case, no generation and no shrinking: the blob is '
            'already the minimal one',
      );
    });

    test('prints what it drew, with no blob hint to give back', () async {
      final blob = await blobFromAFailure();
      final said = <String>[];

      await expectLater(
        runProperty(
          failsAboveFifty(<int>[]),
          settings: settingsFor(),
          reproduce: blob,
          onDiagnostic: said.add,
        ),
        throwsStateError,
      );

      expect(said.single, contains('value = $shrunkAboveFifty'));
      expect(
        said.single,
        isNot(contains('reproduce:')),
        reason: 'whoever passed the blob has it already',
      );
    });

    test('returns when the case it replays no longer fails', () async {
      final blob = await blobFromAFailure();

      // What a fixed bug looks like from here. Not an error: the case was
      // checked and it held.
      await runProperty(
        (TestCase testCase) => testCase.draw(integers(min: 0, max: 1000)),
        settings: settingsFor(),
        reproduce: blob,
      );
    });

    test('reports a blob the body no longer fits', () async {
      final blob = await blobFromAFailure();

      await expectLater(
        runProperty(
          (TestCase testCase) {
            testCase.draw(integers(min: 0, max: 1000));
            testCase.draw(integers(min: 0, max: 1000));
          },
          settings: settingsFor(),
          reproduce: blob,
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('ran out of choices'),
          ),
        ),
      );
    });

    test('reports a blob the body rejects', () async {
      final blob = await blobFromAFailure();

      await expectLater(
        runProperty(
          (TestCase testCase) {
            testCase.assume(testCase.draw(integers(min: 0, max: 1000)) < 0);
          },
          settings: settingsFor(),
          reproduce: blob,
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('rejected as invalid'),
          ),
        ),
      );
    });

    test('reports a blob it cannot read at all', () async {
      await expectLater(
        runProperty(
          failsAboveFifty(<int>[]),
          settings: settingsFor(),
          reproduce: 'not a blob',
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('could not be read'),
          ),
        ),
      );
    });
  });

  group('the example database', () {
    test('keeps a counterexample and replays it before anything new', () async {
      final directory = Directory.systemTemp.createTempSync('hegel-property');
      addTearDown(() => directory.deleteSync(recursive: true));
      final settings = settingsFor(database: Database.at(directory.path));

      final first = <int>[];
      await expectLater(
        runProperty(
          failsAboveFifty(first),
          settings: settings,
          databaseKey: 'the same property, twice',
        ),
        throwsStateError,
      );

      final second = <int>[];
      await expectLater(
        runProperty(
          failsAboveFifty(second),
          settings: settings,
          databaseKey: 'the same property, twice',
        ),
        throwsStateError,
      );

      // The whole point of the database: a bug found once keeps being found,
      // and immediately, rather than waiting on the generator to stumble on
      // it again.
      expect(second.first, shrunkAboveFifty);
      expect(first.length, greaterThan(second.length));
    });
  });
}
