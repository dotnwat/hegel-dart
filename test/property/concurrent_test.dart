@TestOn('vm')
library;

import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/stateful.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

/// Settings for a concurrent run.
///
/// More cases than a sequential test needs, because the first is spent on the
/// engine's handshake and the interleaving that loses an update does not
/// happen on every one of the rest.
Settings concurrentSettings({int testCases = 40, int seed = 11}) => Settings(
  testCases: testCases,
  seed: seed,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  statefulStepCount: 8,
  suppressHealthChecks: machineSpeedChecks,
);

/// A balance behind an interface that makes reading and writing separable.
///
/// The await is the whole point: it is where another worker gets a turn, and
/// so where a read-modify-write stops being one thing.
final class _Account {
  int balance = 0;

  Future<int> read() async {
    await Future<void>.delayed(Duration.zero);
    return balance;
  }

  Future<void> write(int value) async {
    await Future<void>.delayed(Duration.zero);
    balance = value;
  }
}

/// Deposits, counted twice: once by the account and once by a model.
final class _AccountMachine extends StateMachine {
  final _Account account = _Account();
  int model = 0;

  @override
  List<Rule> get rules => <Rule>[
    Rule('deposit', (TestCase tc) async {
      final seen = await account.read();
      await account.write(seen + 1);
      model++;
    }),
  ];

  @override
  List<Invariant> get invariants => <Invariant>[
    Invariant('the balance is every deposit', (TestCase tc) {
      expect(account.balance, model);
    }),
  ];
}

/// Records which rules are running at the same time as which.
final class _OverlapMachine extends StateMachine {
  /// How many copies of each rule are in flight right now.
  ///
  /// Counted rather than collected, because two workers running the *same*
  /// rule is exactly the overlap a shared group is supposed to allow, and a
  /// set of names cannot tell one of those from two.
  final Map<String, int> running = <String, int>{};

  /// Every pair that was ever in flight together, each pair sorted.
  final Set<String> overlaps = <String>{};

  Rule _rule(String name, {String? group}) => Rule(name, (TestCase tc) async {
    running.update(name, (int count) => count + 1, ifAbsent: () => 1);
    running.forEach((String other, int count) {
      if (count == 0) return;
      if (other == name && count < 2) return;
      overlaps.add((<String>[name, other]..sort()).join('+'));
    });
    await Future<void>.delayed(Duration.zero);
    running.update(name, (int count) => count - 1);
  }, group: group);

  @override
  List<Rule> get rules => <Rule>[
    _rule('shared'),
    _rule('alone', group: 'solo'),
  ];
}

void main() {
  group('a concurrent machine', () {
    test('finds the update that one worker could not lose', () async {
      // The bug every sibling suite plants: a read and a write that were
      // never meant to be separable. Two workers read the same balance, both
      // write one more than it, and one deposit is gone -- which the model,
      // counting deposits rather than balances, notices.
      await expectLater(
        runProperty(
          (TestCase testCase) => runStateful(
            testCase,
            _AccountMachine(),
            minConcurrency: 4,
            maxConcurrency: 4,
          ),
          settings: concurrentSettings(),
        ),
        throwsA(isA<TestFailure>()),
      );
    });

    test('and the same machine holds when nothing overlaps', () async {
      // The other half, and the one that makes the first mean something: the
      // rules are correct, the model is right, and only the interleaving is
      // wrong. One worker, and there is no interleaving.
      await runProperty(
        (TestCase testCase) => runStateful(testCase, _AccountMachine()),
        settings: concurrentSettings(),
      );
    });

    test('reports the case that found it, with no blob to replay', () async {
      final said = <String>[];

      await expectLater(
        runProperty(
          (TestCase testCase) => runStateful(
            testCase,
            _AccountMachine(),
            minConcurrency: 4,
            maxConcurrency: 4,
          ),
          settings: concurrentSettings(),
          onDiagnostic: said.add,
        ),
        throwsA(isA<TestFailure>()),
      );

      final report = said.join('\n');
      // A run that cannot promise to repeat itself keeps no counterexample,
      // so what is reported is what the discovering case captured -- and the
      // reader is told that rather than sent to a database that has never
      // heard of it.
      expect(report, isNot(contains('reproduce:')));
      expect(
        report,
        contains('did not promise to repeat itself'),
        reason: 'a counterexample with no way back needs to say why',
      );
      // Whose steps they were, since the order they ran in is the bug.
      expect(report, contains('[worker '));
      expect(report, contains(': deposit'));
    });

    test('keeps rules in different groups from overlapping', () async {
      final machines = <_OverlapMachine>[];

      await runProperty((TestCase testCase) async {
        final machine = _OverlapMachine();
        machines.add(machine);
        await runStateful(
          testCase,
          machine,
          minConcurrency: 3,
          maxConcurrency: 3,
        );
      }, settings: concurrentSettings());

      final overlaps = <String>{
        for (final _OverlapMachine machine in machines) ...machine.overlaps,
      };
      // Something overlapped, or the assertion below holds of a run in which
      // nothing ran at once and grouping was never tested.
      expect(overlaps, contains('shared+shared'));
      // And never across the group boundary, which is what a group is for.
      expect(overlaps, isNot(contains('shared+alone')));
      expect(overlaps, isNot(contains('alone+shared')));
    });

    test('reports only its own failure, however the race lands', () async {
      // A genuinely racy machine may pass or fail on any given seed --
      // that is what racy means -- and both endings are fine. What must
      // never come out of one is the framework second-guessing itself: a
      // nondeterministic run promised no repeat, so there is no flakiness
      // to detect and no generation mismatch to report. Anything but the
      // invariant's own failure propagates and fails this test.
      final failures = <TestFailure>[];

      for (var seed = 1; seed <= 5; seed++) {
        try {
          await runProperty(
            (TestCase testCase) => runStateful(
              testCase,
              _AccountMachine(),
              minConcurrency: 1,
              maxConcurrency: 4,
            ),
            settings: concurrentSettings(testCases: 20, seed: seed),
          );
        } on TestFailure catch (failure) {
          failures.add(failure);
        }
      }

      expect(
        failures,
        isNotEmpty,
        reason: 'five seeded runs of a lost update find it at least once',
      );
      for (final TestFailure failure in failures) {
        expect(failure.message, contains('Expected:'));
      }
    });
  });

  group('the concurrency bounds', () {
    test('refuse fewer than one worker', () {
      expect(
        () => runProperty(
          (TestCase testCase) =>
              runStateful(testCase, _AccountMachine(), minConcurrency: 0),
          settings: concurrentSettings(testCases: 1),
        ),
        throwsRangeError,
      );
    });

    test('refuse a maximum below the minimum', () {
      expect(
        () => runProperty(
          (TestCase testCase) => runStateful(
            testCase,
            _AccountMachine(),
            minConcurrency: 3,
            maxConcurrency: 2,
          ),
          settings: concurrentSettings(testCases: 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
