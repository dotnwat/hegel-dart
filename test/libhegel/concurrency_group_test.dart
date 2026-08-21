@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/state_machine.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

const Settings settings = Settings(
  testCases: 6,
  seed: 67,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  statefulStepCount: 8,
  suppressHealthChecks: machineSpeedChecks,
);

const List<String> rules = <String>['push', 'pop', 'clear'];

/// One round of a machine: the group the engine announced, and every rule it
/// handed out before the round closed.
typedef Round = ({int group, List<int> rules});

void main() {
  late Libhegel session;
  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  /// Drives a two-worker machine and records every round.
  ///
  /// The workers are pulled round-robin from this isolate rather than spawned.
  /// The engine's rule is that one handle may only be driven by one thread at
  /// a time, which separate clones satisfy; nothing here needs the workers to
  /// run at the same instant, only to be inside the same round. Interleaving
  /// them for real is what concurrent_state_machine_test covers.
  List<Round> driveGrouped(List<int>? groups) {
    final rounds = <Round>[];
    final run = Run.start(settings, session: session);
    try {
      while (true) {
        final rootCase = run.nextTestCase();
        if (rootCase == null) break;
        final StateMachine machine;
        try {
          machine = rootCase.newStateMachine(
            ruleNames: rules,
            ruleGroups: groups,
            minConcurrency: 2,
            maxConcurrency: 2,
          );
        } on AssumptionFailed {
          // The engine refuses the first concurrent machine on a run and
          // allows it from the next case on.
          rootCase
            ..markComplete(TestCaseStatus.invalid)
            ..dispose();
          continue;
        }
        final clones = <TestCase>[
          for (var i = 0; i < machine.concurrency; i++) rootCase.clone(),
        ];
        try {
          while (true) {
            final group = machine.nextGroup(rootCase);
            if (group == null) break;
            final applied = <int>[];
            final finished = List<bool>.filled(machine.concurrency, false);
            while (finished.any((bool done) => !done)) {
              for (var worker = 0; worker < machine.concurrency; worker++) {
                if (finished[worker]) continue;
                final rule = machine.nextRule(clones[worker], worker);
                if (rule == null) {
                  finished[worker] = true;
                } else {
                  applied.add(rule);
                }
              }
            }
            rounds.add((group: group, rules: applied));
          }
          rootCase.markComplete(TestCaseStatus.valid);
        } finally {
          for (final clone in clones) {
            clone.dispose();
          }
          machine.dispose();
          rootCase.dispose();
        }
      }
    } finally {
      run.dispose();
    }
    return rounds;
  }

  int roundsMixingGroups(List<Round> rounds, List<int> groups) => rounds
      .where((Round r) => r.rules.any((int i) => groups[i] != r.group))
      .length;

  int roundsWithSeveralRuleKinds(List<Round> rounds) =>
      rounds.where((Round r) => r.rules.toSet().length > 1).length;

  group('a round', () {
    // The contract: rules in one group may overlap, rules in different groups
    // never do. A round is what "may overlap" means from the outside -- every
    // rule handed out before the round closes is a rule that may run
    // alongside the others.
    for (final grouping in <List<int>>[
      <int>[7, 7, 9],
      <int>[5, 5, 5],
      <int>[1, 2, 3],
    ]) {
      test('hands out rules from one group only, given $grouping', () {
        final rounds = driveGrouped(grouping);

        expect(rounds, isNotEmpty);
        expect(roundsMixingGroups(rounds, grouping), 0);
        // Without this the assertion above would hold on a machine that only
        // ever ran one group and never reached the others.
        expect(
          rounds.map((Round r) => r.group).toSet(),
          grouping.toSet(),
          reason: 'every declared group should have had a turn',
        );
      });
    }
  });

  group('the grouping', () {
    test('is what decides which rules can overlap', () {
      // One group: any rule may follow any other inside a round.
      final together = driveGrouped(const <int>[5, 5, 5]);
      expect(
        roundsWithSeveralRuleKinds(together),
        greaterThan(0),
        reason: 'rules sharing a group are exactly the ones allowed to overlap',
      );

      // A group each: a round can only ever hold repeats of its one rule.
      final apart = driveGrouped(const <int>[1, 2, 3]);
      expect(
        roundsWithSeveralRuleKinds(apart),
        0,
        reason: 'no two rules share a group, so no round can hold two kinds',
      );

      // The comparison is the point: same rules, same seed, same settings,
      // and the only difference is how they were grouped. Ignore the grouping
      // and both of these look alike.
      expect(apart.length, together.length);
    });

    test('defaults to putting every rule in one group', () {
      final defaulted = driveGrouped(null);

      expect(defaulted, isNotEmpty);
      expect(
        defaulted.map((Round r) => r.group).toSet(),
        hasLength(1),
        reason: 'one group for everything when none is given',
      );
      expect(roundsWithSeveralRuleKinds(defaulted), greaterThan(0));
    });
  });
}
