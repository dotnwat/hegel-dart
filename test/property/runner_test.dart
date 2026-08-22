@TestOn('vm')
library;

import 'dart:async';

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

/// The value the property below shrinks to, pinned rather than computed.
///
/// The same constant the binding layer's database tests use: the same
/// property, driven through the public runner instead of by hand, shrinks to
/// the same case. That is the point of the assertion -- shrinking is the
/// engine's, and the layer above must not disturb it.
const int shrunkAboveFifty = 51;

Settings runSettings({
  int testCases = 100,
  int seed = 5,
  Mode? mode,
  Set<HealthCheck>? suppress,
}) => Settings(
  testCases: testCases,
  mode: mode,
  seed: seed,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: suppress ?? machineSpeedChecks,
);

/// Fails whenever the value it draws is above fifty.
void aboveFifty(TestCase testCase) {
  final value = testCase.draw(integers(min: 0, max: 1000));
  if (value > 50) throw StateError('$value is too big');
}

void main() {
  group('a property that holds', () {
    test('returns, and says nothing', () async {
      final said = <String>[];

      await runProperty(
        (TestCase testCase) {
          expect(testCase.draw(integers(min: 0, max: 10)), lessThan(11));
        },
        settings: runSettings(),
        onDiagnostic: said.add,
      );

      expect(said, isEmpty);
    });
  });

  group('a property run outside a test', () {
    test(
      'works, with its diagnostics going where the engine\'s would',
      () async {
        // The root zone has no invoker, which is what a script, a soak runner
        // or a `dart run` looks like. The runner is meant to work there --
        // that is the whole reason it is separate from property() -- and its
        // diagnostics fall back to stderr because there is no test to attach
        // them to.
        await Zone.root.run(
          () => runProperty(
            (TestCase testCase) => testCase.draw(integers(min: 0, max: 10)),
            settings: runSettings(testCases: 5),
          ),
        );
      },
    );
  });

  group('a property that fails', () {
    test('throws the body its own error, from the shrunk case', () async {
      await expectLater(
        runProperty(aboveFifty, settings: runSettings()),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            '$shrunkAboveFifty is too big',
          ),
        ),
      );
    });

    test('rethrows it with the stack it was raised from', () async {
      StackTrace? caught;
      try {
        await runProperty(aboveFifty, settings: runSettings());
      } on StateError catch (_, stack) {
        caught = stack;
      }

      // The frame of the throw in this file, not of the rethrow inside the
      // runner: a counterexample is only useful if it points at the code
      // that failed.
      expect(caught.toString(), contains('runner_test.dart'));
      expect(caught.toString(), contains('aboveFifty'));
    });
  });

  group('the catch ladder', () {
    test('does not spend the budget on rejected cases', () async {
      var bodies = 0;

      await runProperty((TestCase testCase) {
        bodies++;
        testCase.assume(testCase.draw(integers(min: 0, max: 1000)).isEven);
      }, settings: runSettings(testCases: 20));

      expect(
        bodies,
        greaterThan(20),
        reason:
            'half the cases are rejected, so twenty valid ones cost more '
            'than twenty bodies -- an assumption that counted would end the '
            'run at exactly twenty',
      );
    });

    test('reports a case that outdrew its budget as an overrun', () async {
      // The engine only complains about oversized cases if it is told they
      // overran. Told they were invalid it would complain about filtering
      // instead, and told they were valid it would say nothing at all, so
      // which check fires is what pins the mapping.
      await expectLater(
        runProperty(
          (TestCase testCase) {
            while (true) {
              testCase.draw(integers(min: 0, max: 1 << 40));
            }
          },
          settings: runSettings(
            suppress: <HealthCheck>{
              HealthCheck.tooSlow,
              HealthCheck.largeInitialTestCase,
            },
          ),
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('TestCasesTooLarge'),
          ),
        ),
      );
    });

    test('surfaces a run the engine gave up on as an error', () async {
      await expectLater(
        runProperty((TestCase testCase) {
          // Drawn before it is rejected, as an over-eager precondition in a
          // real property would be: a case that rejects without drawing is
          // not filtering anything.
          testCase.draw(integers(min: 0, max: 1000));
          testCase.assume(false);
        }, settings: runSettings()),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            allOf(
              contains('FilterTooMuch'),
              contains('filtering out too many inputs'),
            ),
          ),
        ),
      );
    });
  });

  group('an async body', () {
    test('fails through the future it returns', () async {
      await expectLater(
        runProperty((TestCase testCase) async {
          final value = testCase.draw(integers(min: 0, max: 1000));
          await Future<void>.delayed(Duration.zero);
          if (value > 50) throw StateError('$value is too big');
        }, settings: runSettings(testCases: 20)),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            '$shrunkAboveFifty is too big',
          ),
        ),
      );
    });

    test('fails through a future it never awaited', () async {
      // Without the zone this error reaches package:test as a failure of the
      // whole test, mid-run, with the engine still waiting to hear how this
      // case ended.
      await expectLater(
        runProperty((TestCase testCase) async {
          final value = testCase.draw(integers(min: 0, max: 1000));
          if (value > 50) {
            unawaited(
              Future<void>(() => throw StateError('$value is too big')),
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }, settings: runSettings(testCases: 20)),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            '$shrunkAboveFifty is too big',
          ),
        ),
      );
    });

    test('reports work that failed after its case was over', () async {
      final said = <String>[];

      await runProperty(
        (TestCase testCase) {
          testCase.draw(integers(min: 0, max: 10));
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 5),
              () => throw StateError('late'),
            ),
          );
        },
        settings: runSettings(testCases: 2),
        onDiagnostic: said.add,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        said,
        contains(contains('leaked async work escaped its test case')),
      );
      expect(said, contains(contains('late')));
    });
  });

  group('a PropertyError', () {
    test('names itself in its message', () {
      // It reaches the reader through whatever prints a thrown object, so
      // the type has to be in the text rather than only in the type.
      expect(
        PropertyError('the run went nowhere').toString(),
        'PropertyError: the run went nowhere',
      );
    });
  });

  group('a run that stores no counterexample', () {
    // A single test case is never shrunk, so the engine keeps no blob to
    // replay -- the same position a nondeterministic run leaves the runner
    // in. What the failing case captured is then the only account there is,
    // and it is the one the caller gets.
    test('reports the failure the discovering case captured', () async {
      var bodies = 0;

      await expectLater(
        runProperty((TestCase testCase) {
          bodies++;
          throw StateError('case $bodies: ${testCase.draw(integers())}');
        }, settings: runSettings(mode: Mode.singleTestCase)),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            startsWith('case 1:'),
          ),
        ),
      );
      expect(
        bodies,
        1,
        reason: 'there was nothing to replay, so the body ran once',
      );
    });
  });

  group('a replayed counterexample', () {
    // The engine refuses a body that changes its mind during a run -- it
    // reports the flakiness itself -- so a body that changes its mind between
    // the run and the replay is the only way here, and no run produces one on
    // request. The decision is checked where it is made.
    const String origin = 'StateError at test/example_test.dart:12';

    test('raises the property failure when it fails the same way', () {
      final error = StateError('still broken');
      final stack = StackTrace.current;

      expect(
        () => raiseReplayed(origin: origin, error: error, stack: stack),
        throwsA(same(error)),
      );
    });

    test('says so when it does not fail at all', () {
      expect(
        () => raiseReplayed(origin: origin, error: null, stack: null),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            allOf(contains(origin), contains('did not fail again')),
          ),
        ),
      );
    });

    test('says so when it rejects the case instead', () {
      expect(
        () => raiseReplayed(
          origin: origin,
          error: const AssumptionFailed(),
          stack: StackTrace.current,
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('rejected it as invalid'),
          ),
        ),
      );
    });

    test('says so when it draws past what was stored', () {
      expect(
        () => raiseReplayed(
          origin: origin,
          error: const StopTest(),
          stack: StackTrace.current,
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('no longer matches its generators'),
          ),
        ),
      );
    });
  });
}
