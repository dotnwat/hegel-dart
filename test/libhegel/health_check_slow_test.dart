@TestOn('vm')
@Tags(<String>['slow'])
library;

import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

/// The one health check that cannot be driven quickly.
///
/// TooSlow fires when the run has spent more than thirty seconds of wall clock
/// without reaching ten valid cases. Both halves are needed: being slow is not
/// enough on its own, because a run that produces ten valid cases stops being
/// eligible. So the body burns four seconds a case and the check fires on the
/// eighth, a little over the threshold.
///
/// Tagged slow and skipped by the local loop and the pre-commit hook. CI runs
/// it on every platform.
void main() {
  test(
    'TooSlow fires once the run has spent thirty seconds under ten valid cases',
    () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      final elapsed = Stopwatch()..start();

      final drive = driveProperty(
        session,
        settings: const Settings(
          testCases: 100,
          seed: 3,
          derandomize: true,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
          // Everything except TooSlow, so that whatever fires is this check
          // and not one of the cheaper ones getting there first.
          suppressHealthChecks: <HealthCheck>{
            HealthCheck.filterTooMuch,
            HealthCheck.testCasesTooLarge,
            HealthCheck.largeInitialTestCase,
          },
        ),
        body: (TestCase testCase, List<int> draws) {
          draws.add(testCase.drawInteger(min: 0, max: 10));
          // Busy-waiting rather than sleeping: the run loop is synchronous, so
          // an await here would not hold the engine up at all.
          final spin = Stopwatch()..start();
          while (spin.elapsedMilliseconds < 4000) {}
          testCase.markComplete(TestCaseStatus.valid);
        },
      );
      addTearDown(drive.result.dispose);

      expect(drive.result.status, RunStatus.error);
      expect(drive.result.error, contains('TooSlow'));
      expect(drive.result.error, contains('input generation is slow'));
      expect(
        drive.testCases,
        lessThan(10),
        reason: 'ten valid cases would have made the run ineligible',
      );
      expect(
        elapsed.elapsed,
        greaterThan(const Duration(seconds: 30)),
        reason: 'the threshold is wall clock, so this cannot have been quick',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
