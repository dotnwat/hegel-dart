@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/state_machine.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

const Settings settings = Settings(
  testCases: 20,
  seed: 59,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  statefulStepCount: 12,
  suppressHealthChecks: everyHealthCheck,
);

const List<String> rules = <String>['push', 'pop', 'clear'];

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  /// Runs a sequential machine, recording which rules ran.
  ({List<int> applied, RunStatus status, List<int> concurrencies})
  driveMachine({bool Function(int ruleIndex)? precondition}) {
    final run = Run.start(settings, session: session);
    final applied = <int>[];
    final concurrencies = <int>[];
    try {
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          final machine = testCase.newStateMachine(ruleNames: rules);
          concurrencies.add(machine.concurrency);
          try {
            while (machine.nextGroup(testCase) != null) {
              while (true) {
                final rule = machine.nextRule(testCase, 0);
                if (rule == null) break;
                if (precondition != null && !precondition(rule)) {
                  machine.ruleRejected(testCase, 0);
                  continue;
                }
                applied.add(rule);
              }
            }
          } finally {
            machine.dispose();
          }
          testCase.markComplete(TestCaseStatus.valid);
        } on StopTest {
          testCase.markComplete(TestCaseStatus.overrun);
        } on AssumptionFailed {
          testCase.markComplete(TestCaseStatus.invalid);
        } finally {
          testCase.dispose();
        }
      }
      final result = run.result();
      final status = result.status;
      result.dispose();
      return (applied: applied, status: status, concurrencies: concurrencies);
    } finally {
      run.dispose();
    }
  }

  group('a sequential machine', () {
    test('runs rules the engine chooses and terminates', () {
      final outcome = driveMachine();
      expect(outcome.status, RunStatus.passed);
      expect(outcome.applied, isNotEmpty);
      // Every index the engine hands back has to name a rule that exists.
      expect(
        outcome.applied,
        everyElement(allOf(greaterThanOrEqualTo(0), lessThan(rules.length))),
      );
      // Swarm testing means a case may enable only some rules, but across a
      // whole run more than one should show up.
      expect(outcome.applied.toSet().length, greaterThan(1));
    });

    test('draws a concurrency of one when that is all it may have', () {
      final outcome = driveMachine();
      expect(outcome.concurrencies, everyElement(1));
    });

    test('a rejected rule gives the slot back', () {
      // Rejecting every odd rule should still leave even ones running, and
      // rejections must not count against the step budget.
      final outcome = driveMachine(precondition: (int rule) => rule.isEven);
      expect(outcome.status, RunStatus.passed);
      expect(
        outcome.applied,
        everyElement(
          predicate<int>((int r) => r.isEven, 'is an even rule index'),
        ),
      );
      expect(outcome.applied, isNotEmpty);
    });

    test('respects the step budget', () {
      final outcome = driveMachine();
      // statefulStepCount is 12 per case, over 20 cases; nothing should run
      // away, and the engine stops rather than looping forever.
      expect(outcome.applied.length, lessThan(20 * 12 + 1));
    });
  });

  group('construction', () {
    late TestCase testCase;
    late Run run;

    setUp(() {
      run = Run.start(settings, session: session);
      testCase = run.nextTestCase()!;
    });

    tearDown(() {
      testCase.dispose();
      run.dispose();
    });

    test('needs at least one rule', () {
      expect(
        () => testCase.newStateMachine(ruleNames: const <String>[]),
        throwsArgumentError,
      );
    });

    test('needs one group per rule when groups are given', () {
      expect(
        () => testCase.newStateMachine(
          ruleNames: rules,
          ruleGroups: const <int>[0, 0],
        ),
        throwsArgumentError,
      );
    });

    // The engine reserves that value for "finished", so a group using it
    // would be indistinguishable from the end of the machine.
    test('refuses the reserved termination value as a group', () {
      expect(
        () => testCase.newStateMachine(
          ruleNames: const <String>['only'],
          ruleGroups: const <int>[-9223372036854775808],
        ),
        throwsArgumentError,
      );
    });

    test('refuses impossible concurrency bounds', () {
      expect(
        () => testCase.newStateMachine(ruleNames: rules, minConcurrency: 0),
        throwsRangeError,
      );
      expect(
        () => testCase.newStateMachine(
          ruleNames: rules,
          minConcurrency: 3,
          maxConcurrency: 2,
        ),
        throwsArgumentError,
      );
    });

    test('accepts invariant names and rule groups', () {
      final machine = testCase.newStateMachine(
        ruleNames: rules,
        ruleGroups: const <int>[7, 7, 9],
        invariantNames: const <String>['balanced', 'nonNegative'],
      );
      addTearDown(machine.dispose);
      expect(machine.concurrency, 1);
    });

    test('refuses a worker index outside the drawn concurrency', () {
      final machine = testCase.newStateMachine(ruleNames: rules);
      addTearDown(machine.dispose);
      expect(() => machine.nextRule(testCase, 1), throwsRangeError);
      expect(() => machine.nextRule(testCase, -1), throwsRangeError);
      expect(() => machine.ruleRejected(testCase, 5), throwsRangeError);
    });
  });

  group('lifecycle', () {
    test('dispose is idempotent and use afterwards throws', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);

      final machine = testCase.newStateMachine(ruleNames: rules)..dispose();
      expect(machine.isDisposed, isTrue);
      expect(machine.dispose, returnsNormally);
      expect(() => machine.nextGroup(testCase), throwsStateError);
      testCase.markComplete(TestCaseStatus.valid);
    });

    // A borrowed view is what a worker isolate gets; it must never free a
    // handle the coordinator still owns.
    test('a borrowed view never frees the handle', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);

      final machine = testCase.newStateMachine(ruleNames: rules);
      addTearDown(machine.dispose);
      final borrowed = StateMachine.adopt(
        session,
        machine.token,
        machine.concurrency,
      );

      expect(borrowed.isBorrowed, isTrue);
      borrowed.dispose();
      expect(borrowed.isDisposed, isFalse);
      // The owner's handle is untouched, so it still works.
      expect(machine.nextGroup(testCase), isNotNull);
      testCase.markComplete(TestCaseStatus.valid);
    });
  });
}
