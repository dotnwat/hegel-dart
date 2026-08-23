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
  Set<Phase>? phases,
  Set<HealthCheck>? suppress,
  Verbosity? verbosity = Verbosity.quiet,
}) => Settings(
  testCases: testCases,
  mode: mode,
  seed: seed,
  derandomize: true,
  phases: phases,
  database: Database.disabled,
  verbosity: verbosity,
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

    test('prints what the shrunk case drew and what the body said', () async {
      final said = <String>[];

      await expectLater(
        runProperty(
          (TestCase testCase) {
            final value = testCase.draw(
              integers(min: 0, max: 1000),
              name: 'value',
            );
            testCase.note('about to check $value');
            if (value > 50) throw StateError('$value is too big');
          },
          settings: runSettings(),
          onDiagnostic: said.add,
        ),
        throwsStateError,
      );

      expect(
        said.single,
        allOf(
          contains('value = $shrunkAboveFifty'),
          contains('about to check $shrunkAboveFifty'),
          contains('example database'),
        ),
        reason:
            'one block rather than a line at a time, and only the '
            'minimal case: every other case the property tried is noise',
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

    test('registers work that failed after its case was over', () async {
      // The case has been given its verdict, so this cannot be one -- but a
      // future that failed is not nothing, and the buffer a passing test
      // throws away is not where it belongs. registerException is where
      // package:test puts a stray error in any ordinary test; here it is
      // caught by a zone of this test's own so that proving it happens does
      // not require failing.
      final late = <Object>[];

      await runZonedGuarded(() async {
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
          onDiagnostic: (_) {},
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, (Object error, StackTrace stack) => late.add(error));

      expect(late, isNotEmpty);
      expect(
        late.first,
        isA<PropertyError>().having(
          (PropertyError error) => error.message,
          'message',
          allOf(
            contains('leaked async work escaped its test case'),
            contains('late'),
          ),
        ),
      );
    });

    test('registers a failure that arrives after a stray error ended the '
        'case', () async {
      // Both are real. The first to arrive is the verdict, because the case
      // has to end for the run to go on; keeping only that one and dropping
      // the other silently is what would make the report a lie.
      final late = <Object>[];

      await runZonedGuarded(() async {
        await expectLater(
          runProperty(
            (TestCase testCase) async {
              testCase.draw(integers(min: 0, max: 10));
              unawaited(Future<void>(() => throw StateError('the stray one')));
              await Future<void>.delayed(const Duration(milliseconds: 5));
              throw StateError('the real one');
            },
            settings: runSettings(testCases: 2),
            onDiagnostic: (_) {},
          ),
          throwsA(
            isA<StateError>().having(
              (StateError error) => error.message,
              'message',
              'the stray one',
            ),
          ),
        );
        // The body resumes after the case it belonged to is over, so its
        // throw lands after runProperty has already returned.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, (Object error, StackTrace stack) => late.add(error));

      expect(late, isNotEmpty);
      expect(
        late.map((Object error) => '$error'),
        everyElement(
          // Exactly once, not wrapped again by the guard it was reported
          // from: the explanation is the outermost thing in the message.
          'PropertyError: the body failed after its case had ended: '
          'Bad state: the real one',
        ),
      );
    });
  });

  group('a run the engine could not use', () {
    test(
      'reaches the caller as an error, in the engine\'s own words',
      () async {
        // A body that assumes something no case satisfies, which is a mistake
        // people make: the engine notices that almost nothing survives and
        // ends the run rather than reporting a verdict it does not have.
        await expectLater(
          runProperty((TestCase testCase) {
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
      },
    );

    test('is an error rather than a failure, and says nothing else', () async {
      // The distinction the type carries: package:test renders anything that
      // is not a TestFailure as an error, which is the severity that fits a
      // run with no verdict in it. A report block would be worse than
      // useless here -- there is no counterexample to print.
      final said = <String>[];

      await expectLater(
        runProperty(
          (TestCase testCase) {
            testCase.draw(integers(min: 0, max: 1000));
            testCase.assume(false);
          },
          settings: runSettings(),
          onDiagnostic: said.add,
        ),
        throwsA(isNot(isA<TestFailure>())),
      );
      expect(said.where((String line) => line.contains('draw_')), isEmpty);
    });

    test('says so even when the engine gave no reason', () {
      // Not reachable through a run: the engine names every error it
      // reports. Checked on the text alone so that a run which somehow
      // reported nothing still says something.
      expect(
        PropertyError('the run ended without saying why').message,
        contains('without saying why'),
      );
    });

    test('terminates all the same when the checks that would say so '
        'are off', () async {
      // The hang guard from the reference suite: a body that rejects every
      // case, with every health check suppressed, must still end when the
      // engine's budget for invalid cases runs out. Holding is the right
      // verdict -- suppressing the checks asked for exactly this run -- but
      // only if the run actually ends.
      await runProperty((TestCase testCase) {
        testCase.draw(booleans());
        testCase.assume(false);
      }, settings: runSettings(suppress: everyHealthCheck));
    });
  });

  group('a body the engine had to refuse', () {
    test('ends the run in the engine\'s own words, not as a '
        'counterexample', () async {
      // `domains(maxLength: 3)` is a mistake -- no domain name fits in
      // three characters -- and the engine only says so when the generator
      // is first drawn from, which is inside the body. Treated like any
      // other error there it would be shrunk, replayed, and reported as
      // the minimal input to a bug, so the runner ends the run instead:
      // the property was never checked, and the report says what was.
      final said = <String>[];

      await expectLater(
        runProperty(
          (TestCase testCase) {
            testCase.draw(domains(maxLength: 3), name: 'name');
          },
          settings: runSettings(),
          onDiagnostic: said.add,
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            allOf(
              contains('asked the engine for something it refused'),
              contains('leaves no eligible TLDs'),
            ),
          ),
        ),
      );
      expect(
        said,
        isEmpty,
        reason: 'a configuration mistake has no counterexample to print',
      );
    });

    test('leaves a refusal this layer makes to the property', () async {
      // The line the special case does not cross. An ArgumentError raised
      // where a generator was written is Dart code throwing, and Dart code
      // throwing is what a failing property is -- the same error from the
      // code under test must stay a counterexample. So a body that builds
      // an impossible generator out of a drawn value fails like any other
      // body, rather than ending the run.
      await expectLater(
        runProperty((TestCase testCase) {
          final n = testCase.draw(integers(min: 0, max: 10), name: 'n');
          testCase.draw(integers(min: n + 1, max: n));
        }, settings: runSettings()),
        throwsArgumentError,
      );
    });
  });

  group('a bug the checks could have hidden', () {
    test('is reported, not the storm of rejections around it', () async {
      // Half of every range is rejected outright, which is FilterTooMuch
      // territory -- but the other half fails, and a found bug outranks a
      // fired check: the engine stops checking once it has a failure in
      // hand. What reaches the caller is the bug, shrunk as usual to the
      // smallest odd value.
      final said = <String>[];

      await expectLater(
        runProperty(
          (TestCase testCase) {
            final value = testCase.draw(
              integers(min: 0, max: 1000),
              name: 'value',
            );
            if (value.isOdd) throw StateError('the real bug');
            testCase.assume(false);
          },
          settings: runSettings(),
          onDiagnostic: said.add,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'the real bug',
          ),
        ),
      );
      expect(said.join('\n'), contains('value = 1'));
    });
  });

  group('a property that does not fail the same way twice', () {
    // Two detectors, one per phase set. A run that shrinks re-runs the body
    // while probing, so the engine sees the verdict flip and calls the run
    // flaky itself. A run that stops at generation gives the engine no
    // second look, and the runner's own final replay is what notices --
    // `replayedFailure` deciding, driven here through real runs.
    test('is called flaky when the engine sees the flip while '
        'shrinking', () async {
      var calls = 0;

      await expectLater(
        runProperty((TestCase testCase) {
          testCase.draw(booleans(), name: 'flag');
          if (calls++ == 0) throw StateError('fails only on the first call');
        }, settings: runSettings()),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            allOf(
              contains('Flaky test detected'),
              contains('different outcomes'),
            ),
          ),
        ),
      );
    });

    test('is caught by the replay when the run never shrank', () async {
      var calls = 0;

      await expectLater(
        runProperty((TestCase testCase) {
          testCase.draw(booleans(), name: 'flag');
          if (calls++ == 0) throw StateError('fails only on the first call');
        }, settings: runSettings(phases: <Phase>{Phase.generate})),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('did not fail again'),
          ),
        ),
      );
    });

    test('is caught when the replay rejects what was recorded', () async {
      var calls = 0;

      await expectLater(
        runProperty((TestCase testCase) {
          testCase.draw(booleans(), name: 'flag');
          if (calls++ == 0) throw StateError('fails only on the first call');
          testCase.assume(false);
        }, settings: runSettings(phases: <Phase>{Phase.generate})),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('rejected it as invalid'),
          ),
        ),
      );
    });

    test('is caught when the replay outdraws what was recorded', () async {
      var calls = 0;

      await expectLater(
        runProperty((TestCase testCase) {
          testCase.draw(booleans(), name: 'flag');
          if (calls++ == 0) throw StateError('fails only on the first call');
          testCase.draw(booleans(), name: 'extra');
        }, settings: runSettings(phases: <Phase>{Phase.generate})),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('no longer matches its generators'),
          ),
        ),
      );
    });

    test('is caught at the draws when generation reads outside '
        'state', () async {
      // Not the verdict flipping but the choices themselves: a bound that
      // moves with a counter makes the same recorded choices read back
      // differently, and the engine says which choice changed and what
      // that usually means.
      var calls = 0;

      await expectLater(
        runProperty((TestCase testCase) {
          testCase.draw(integers(min: 0, max: 10 + calls++), name: 'value');
          throw StateError('always fails');
        }, settings: runSettings()),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            allOf(
              contains('non-deterministic'),
              contains('global mutable state'),
            ),
          ),
        ),
      );
    });
  });

  group('whether a test is running', () {
    test('is true in here, which is what both branches turn on', () {
      // The one question that decides where a diagnostic goes and where a
      // failure that is not being thrown goes. Its other answer belongs to a
      // process with no package:test in it, which is what
      // test/property/standalone_test.dart drives.
      expect(insideTest(), isTrue);
    });
  });

  group('the default diagnostic sink', () {
    test('buffers until failure at the verbosity a run usually has', () {
      for (final Verbosity? verbosity in <Verbosity?>[
        null,
        Verbosity.quiet,
        Verbosity.normal,
      ]) {
        expect(
          defaultDiagnostic(runSettings(verbosity: verbosity)),
          same(printOnFailure),
          reason: 'a property that holds is meant to be silent',
        );
      }
    });

    test('prints as it goes once the run was asked to narrate', () {
      for (final Verbosity verbosity in <Verbosity>[
        Verbosity.verbose,
        Verbosity.debug,
      ]) {
        expect(
          defaultDiagnostic(runSettings(verbosity: verbosity)),
          same(print),
          reason: 'watching a run happen is the whole point of asking',
        );
      }
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
      final said = <String>[];

      await expectLater(
        runProperty(
          (TestCase testCase) {
            bodies++;
            final value = testCase.draw(integers(), name: 'value');
            throw StateError('case $bodies: $value');
          },
          settings: runSettings(mode: Mode.singleTestCase),
          onDiagnostic: said.add,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            startsWith('case 1:'),
          ),
        ),
      );
      expect(
        said.single,
        contains('value = '),
        reason:
            'the discovering case is the only account there is, so what '
            'it drew is what gets printed',
      );
      expect(
        bodies,
        1,
        reason: 'there was nothing to replay, so the body ran once',
      );
    });
  });

  group('a replayed counterexample, as a value', () {
    const String origin = 'StateError at test/thing_test.dart:9';

    test('hands back the failure and its own stack', () {
      final error = StateError('the property failed');
      final stack = StackTrace.current;

      final replayed = replayedFailure(
        origin: origin,
        error: error,
        stack: stack,
      );

      expect(replayed.error, same(error));
      expect(replayed.stack, same(stack));
    });

    test('hands back an explanation when the replay held', () {
      // The same endings `raiseReplayed` throws, since it is this that
      // decides them. Checked once here rather than once each, because what
      // this adds over the throwing form is that there is something to hold
      // on to -- which is what a second distinct failure needs.
      final replayed = replayedFailure(
        origin: origin,
        error: null,
        stack: null,
      );

      expect(replayed.error, isA<PropertyError>());
      expect(replayed.stack, isNot(StackTrace.empty));
    });
  });

  group('a replayed counterexample', () {
    // A run that shrinks catches a body that changes its mind itself -- the
    // flakiness tests above drive both detectors through real runs -- and
    // what each replay ending turns into is decided here, so it is checked
    // here too, one ending at a time.
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

    test('says so when it asks the engine for something it refuses', () {
      // The ending a generator whose validity depends on outside state
      // produces: fine while the run generated, refused by the time the
      // counterexample replayed. The engine's diagnostic is the part worth
      // keeping, since it says what was asked.
      expect(
        () => raiseReplayed(
          origin: origin,
          error: HegelException(
            'hegel_generate_string',
            -5,
            'the alphabet is empty',
          ),
          stack: StackTrace.current,
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            allOf(
              contains('asked the engine for something it refused'),
              contains('the alphabet is empty'),
            ),
          ),
        ),
      );
    });
  });
}
