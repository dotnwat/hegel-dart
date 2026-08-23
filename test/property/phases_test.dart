@TestOn('vm')
library;

import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

/// A seeded run over exactly [phases].
Settings phasesOnly(Set<Phase> phases, {int testCases = 10, int seed = 5}) =>
    Settings(
      testCases: testCases,
      seed: seed,
      derandomize: true,
      phases: phases,
      database: Database.disabled,
      verbosity: Verbosity.quiet,
      suppressHealthChecks: machineSpeedChecks,
    );

void main() {
  group('the generate phase', () {
    test('tries the all-simplest case before anything random', () async {
      // The pre-trial: the engine's first generated case answers every draw
      // with its minimum, so a property that fails on the trivial input
      // fails immediately rather than after a lucky walk. Every draw in the
      // first case, not just the first draw -- the simplicity is the whole
      // case's.
      final perCase = <List<Object>>[];

      await runProperty((TestCase testCase) {
        perCase.add(<Object>[
          testCase.draw(integers(min: 0, max: 100)),
          testCase.draw(integers(min: 0, max: 1000)),
          testCase.draw(lists(integers(min: 0, max: 9))),
          testCase.draw(booleans()),
        ]);
      }, settings: phasesOnly(<Phase>{Phase.generate}));

      expect(perCase.first, <Object>[0, 0, <int>[], false]);
      // And only the first: a second all-simplest case would mean the run
      // was not generating at all.
      expect(perCase[1], isNot(perCase.first));
    });

    test('alone, stops at the first failure without shrinking', () async {
      // Two body runs and no more: the case that found the failure, and the
      // runner's final replay of it -- which is also what makes the count a
      // pin of the replay happening at all. A third call would be a shrink
      // probe from a phase this run turned off.
      var bodies = 0;

      await expectLater(
        runProperty((TestCase testCase) {
          bodies++;
          testCase.draw(booleans());
          throw StateError('always fails');
        }, settings: phasesOnly(<Phase>{Phase.generate})),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'always fails',
          ),
        ),
      );
      expect(bodies, 2);
    });
  });
}
