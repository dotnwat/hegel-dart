@TestOn('vm')
library;

import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

/// Health checks are the only way a run reaches [RunStatus.error], and until
/// these existed the whole suite passed [everyHealthCheck] to
/// `suppressHealthChecks`, so no engine complaint could reach an assertion.
/// The property layer has to turn this outcome into something a caller sees:
/// "your property filters out nearly everything" is a mistake people make.
Settings settingsFor({Set<HealthCheck>? suppress, int testCases = 100}) =>
    Settings(
      testCases: testCases,
      seed: 3,
      derandomize: true,
      database: Database.disabled,
      verbosity: Verbosity.quiet,
      suppressHealthChecks: suppress,
    );

/// Rejects every case, as an over-eager `assume` would.
void rejectEverything(TestCase testCase, List<int> draws) {
  draws.add(testCase.drawInteger(min: 0, max: 1000));
  testCase.markComplete(TestCaseStatus.invalid);
}

/// Draws until the engine refuses, which the driver marks as an overrun.
void drawUntilRefused(TestCase testCase, List<int> draws) {
  while (true) {
    draws.add(testCase.drawInteger(min: 0, max: 1 << 40));
  }
}

/// A first case already far larger than the engine wants to start from.
void drawFarTooMuch(TestCase testCase, List<int> draws) {
  for (var i = 0; i < 5000; i++) {
    draws.add(testCase.drawInteger(min: 0, max: 1 << 40));
  }
  testCase.markComplete(TestCaseStatus.valid);
}

void main() {
  late Libhegel session;
  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  Drive run(
    void Function(TestCase, List<int>) body, {
    Set<HealthCheck>? suppress,
  }) {
    final drive = driveProperty(
      session,
      settings: settingsFor(suppress: suppress),
      body: body,
    );
    addTearDown(drive.result.dispose);
    return drive;
  }

  group('a failed health check', () {
    test('ends the run in error and says which check and why', () {
      final drive = run(rejectEverything);

      expect(drive.result.status, RunStatus.error);
      expect(drive.result.error, contains('FilterTooMuch'));
      expect(
        drive.result.error,
        contains('filtering out too many inputs'),
        reason: 'the text is what a caller will be shown',
      );
      expect(
        drive.result.failureCount,
        0,
        reason: 'an unusable run is not a counterexample',
      );
    });

    test('fires when every case overruns the choice budget', () {
      final drive = run(
        drawUntilRefused,
        // Otherwise the first case is itself oversized and pre-empts this.
        suppress: <HealthCheck>{HealthCheck.largeInitialTestCase},
      );

      expect(drive.result.status, RunStatus.error);
      expect(drive.result.error, contains('TestCasesTooLarge'));
    });

    test('fires when the smallest possible case is already huge', () {
      final drive = run(drawFarTooMuch);

      expect(drive.result.status, RunStatus.error);
      expect(drive.result.error, contains('LargeInitialTestCase'));
    });
  });

  group('suppression', () {
    test('turns off the check it names and no other', () {
      // Named: the run completes instead of erroring.
      final suppressed = run(
        rejectEverything,
        suppress: <HealthCheck>{HealthCheck.filterTooMuch},
      );
      expect(suppressed.result.status, RunStatus.passed);
      expect(suppressed.result.error, isNull);

      // Not named: the same body still trips the same check, so passing above
      // was the suppression working rather than the check never firing.
      final unrelated = run(
        rejectEverything,
        suppress: <HealthCheck>{HealthCheck.tooSlow},
      );
      expect(unrelated.result.status, RunStatus.error);
      expect(unrelated.result.error, contains('FilterTooMuch'));
    });

    test('everyHealthCheck covers all four, which is why it hides so much', () {
      expect(everyHealthCheck, HealthCheck.values.toSet());

      final quiet = run(rejectEverything, suppress: everyHealthCheck);
      expect(quiet.result.status, RunStatus.passed);
    });
  });

  group('a run the engine cannot make sense of', () {
    test('reports non-deterministic generation as an error', () {
      // The shape of the draws changes between cases for a reason the engine
      // cannot see. Worth pinning: it is an easy mistake for a generator to
      // make, and it surfaces through the same channel as a health check.
      var seen = 0;
      final drive = run((TestCase testCase, List<int> draws) {
        seen++;
        final length = seen == 1 ? 1 : 20000;
        testCase.drawBytes(minLength: length, maxLength: length);
        testCase.markComplete(TestCaseStatus.valid);
      });

      expect(drive.result.status, RunStatus.error);
      expect(drive.result.error, contains('non-deterministic'));
    });
  });
}
