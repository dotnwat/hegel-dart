@TestOn('vm')
library;

import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart' as engine;
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';
import '../support/scripted_context.dart';

/// A run of [testCases] cases over [phases], seeded so it is the same twice.
Settings settingsOver(Set<Phase> phases, {int testCases = 60, int seed = 29}) =>
    Settings(
      testCases: testCases,
      seed: seed,
      derandomize: true,
      database: Database.disabled,
      verbosity: Verbosity.quiet,
      suppressHealthChecks: machineSpeedChecks,
      phases: phases,
    );

/// Every value [body] returned, one call per case of a whole run.
///
/// The public handle over a real run, which is the only way to see steering:
/// what targeting changes is which case the engine generates next, so nothing
/// short of a run shows it at all.
List<int> everyCase(
  Libhegel session,
  Settings settings,
  int Function(TestCase testCase) body,
) {
  final run = Run.start(settings, session: session);
  final values = <int>[];
  try {
    while (true) {
      final engineCase = run.nextTestCase();
      if (engineCase == null) break;
      try {
        values.add(body(TestCase(EngineDrawContext(engineCase))));
        engineCase.markComplete(engine.TestCaseStatus.valid);
      } finally {
        engineCase.dispose();
      }
    }
    run.result().dispose();
  } finally {
    run.dispose();
  }
  return values;
}

void main() {
  late Libhegel session;
  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  group('an observation', () {
    test('reaches the engine with the label it was given', () {
      final context = ScriptedContext(<int>[]);

      TestCase(context).target(12.5, label: 'size');

      expect(context.calls, <String>['target 12.5 as size']);
    });

    test('carries a default label, for the one-objective case', () {
      final context = ScriptedContext(<int>[]);

      TestCase(context).target(1);

      expect(context.calls, <String>['target 1.0 as target']);
    });

    test('is refused when there is no ordering to put it in', () {
      // NaN sits nowhere in an ordering and an infinity is a score nothing
      // beats, so a hill-climb over either is not a worse search but no
      // search. Refused where it was written, which is inside the body.
      for (final double value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => everyCase(
            session,
            settingsOver(<Phase>{Phase.generate}, testCases: 5),
            (TestCase testCase) {
              testCase.target(value);
              return 0;
            },
          ),
          throwsArgumentError,
          reason: '$value is not something to steer by',
        );
      }
    });
  });

  group('targeting', () {
    test('steers the run toward the scores it is given', () {
      // Hill-climbing, seen from outside: the same body over the same seed,
      // once with the phase and once without.
      //
      // Counted rather than maximised. The best score of a run is the wrong
      // measure here, because plain generation deliberately tries the bounds
      // of a range and so reaches 1000000 on its own, on the first case that
      // happens to be a boundary probe. What steering changes is where the
      // rest of the cases go: the engine builds later cases out of the ones
      // that scored well, so high scores stop being the occasional accident
      // and become most of the run.
      //
      // A pinned seed, like the shrink pins, and for the same reason: this
      // is an assertion about what the engine did, and it is only worth
      // making if it is the same question each time it is asked.
      int highScores(Set<Phase> phases) {
        final values = everyCase(session, settingsOver(phases), (
          TestCase testCase,
        ) {
          final value = testCase.draw(integers(min: 0, max: 1000000));
          testCase.target(value.toDouble(), label: 'size');
          return value;
        });
        expect(values, hasLength(60));
        return values.where((int value) => value > 900000).length;
      }

      expect(
        highScores(<Phase>{Phase.generate, Phase.target}),
        greaterThan(highScores(<Phase>{Phase.generate})),
      );
    });

    test('does nothing at all when its phase is left out', () {
      // Not an error: a property that reports an observation is still a
      // correct property when nobody is steering by it, and a `phases:` set
      // written to isolate one part of the loop should not have to be
      // rewritten to keep running.
      final values = everyCase(
        session,
        settingsOver(<Phase>{Phase.generate}, testCases: 5, seed: 31),
        (TestCase testCase) {
          testCase.target(1, label: 'ignored');
          return testCase.draw(integers(min: 0, max: 10));
        },
      );

      expect(values, hasLength(5));
    });

    test('never spends more cases than the budget it was given', () {
      // Hill-climbing runs extra experiments, and the place they must come
      // from is the same budget as everything else: a target phase that
      // exceeded `testCases` would make a slow property slower the moment
      // someone added an observation to it.
      for (final int budget in <int>[5, 25]) {
        final values = everyCase(
          session,
          settingsOver(<Phase>{
            Phase.generate,
            Phase.target,
          }, testCases: budget),
          (TestCase testCase) {
            final value = testCase.draw(integers(min: 0, max: 1000000));
            testCase.target(value.toDouble(), label: 'size');
            return value;
          },
        );

        expect(values, hasLength(budget), reason: 'budget $budget');
      }
    });

    test('refuses the same label twice in one case', () async {
      // One observation per label per case is the engine's rule -- a second
      // would silently overwrite the first -- and breaking it is a mistake
      // in the property, so it ends the run in the engine's own words
      // rather than becoming a counterexample.
      await expectLater(
        runProperty((TestCase testCase) {
          testCase.draw(integers(min: 0, max: 10));
          testCase.target(1, label: 'size');
          testCase.target(2, label: 'size');
        }, settings: settingsOver(<Phase>{Phase.generate, Phase.target})),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            allOf(
              contains('asked the engine for something it refused'),
              contains('at most once'),
            ),
          ),
        ),
      );
    });
  });
}
