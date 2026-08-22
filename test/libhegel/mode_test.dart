@TestOn('vm')
library;

import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

Settings settingsFor(Mode? mode) => Settings(
  testCases: 100,
  seed: 3,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  mode: mode,
  suppressHealthChecks: machineSpeedChecks,
);

/// What the full loop shrinks the shared property down to.
///
/// The point of comparison for [Mode.singleTestCase]: reaching this value
/// takes a thousand test cases of searching, so a mode that reports it would
/// not be doing one case without shrinking.
const int shrunk = 51;

void main() {
  late Libhegel session;
  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  Drive run(Mode? mode, {int threshold = 50}) {
    final drive = driveIntegerProperty(
      session,
      settings: settingsFor(mode),
      threshold: threshold,
    );
    addTearDown(drive.result.dispose);
    return drive;
  }

  group('Mode.singleTestCase', () {
    test('produces exactly one test case', () {
      final single = run(Mode.singleTestCase);

      expect(single.testCases, 1);
      expect(single.draws, hasLength(1));

      // The budget was a hundred and the loop would have spent it many times
      // over, so one case is the mode and not the property running out.
      final loop = run(Mode.testRun);
      expect(loop.testCases, greaterThan(100));
    });

    test('does not shrink what it finds', () {
      final single = run(Mode.singleTestCase);
      final loop = run(Mode.testRun);

      expect(single.result.status, RunStatus.failed);
      expect(single.result.failureCount, 1);
      expect(loop.draws.last, shrunk);
      expect(
        single.draws.single,
        isNot(shrunk),
        reason: 'reporting the minimum would mean it had searched for it',
      );
      expect(
        single.draws.single,
        greaterThan(shrunk),
        reason: 'the first failing value it happened to draw, left as it was',
      );
    });

    test('reports a passing case as a passing run', () {
      // Nothing in range can exceed this, so the one case succeeds.
      final single = run(Mode.singleTestCase, threshold: 1000);

      expect(single.result.status, RunStatus.passed);
      expect(single.result.failureCount, 0);
      expect(single.testCases, 1);
    });
  });

  group('Mode.testRun', () {
    test('is what a run does when no mode is given', () {
      final unset = run(null);
      final explicit = run(Mode.testRun);

      expect(unset.testCases, explicit.testCases);
      expect(unset.draws, explicit.draws);
      expect(unset.result.status, explicit.result.status);
    });
  });
}
