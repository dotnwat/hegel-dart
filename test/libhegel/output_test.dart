@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

const Settings verbose = Settings(
  testCases: 5,
  seed: 73,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.verbose,
  suppressHealthChecks: machineSpeedChecks,
);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  /// Drives a whole run, drawing once per case.
  RunStatus drive(Run run) {
    while (true) {
      final testCase = run.nextTestCase();
      if (testCase == null) break;
      try {
        testCase.drawInteger(min: 0, max: 10);
        testCase.markComplete(TestCaseStatus.valid);
      } on StopTest {
        testCase.markComplete(TestCaseStatus.overrun);
      } finally {
        testCase.dispose();
      }
    }
    final result = run.result();
    final status = result.status;
    result.dispose();
    return status;
  }

  test('captures the engine output that would otherwise reach stderr', () {
    final lines = <String>[];
    final run = Run.start(verbose, session: session, onOutput: lines.add);
    addTearDown(run.dispose);

    expect(drive(run), RunStatus.passed);
    expect(lines, isNotEmpty);
    // Lines arrive without a trailing newline, one per call.
    expect(lines, everyElement(isNot(contains('\n'))));
  });

  test('leaves output on stderr when no callback is given', () {
    final run = Run.start(verbose, session: session);
    addTearDown(run.dispose);
    expect(drive(run), RunStatus.passed);
  });

  test('delivers output during the call that produced it', () {
    // Isolate-local rather than a listener, so lines arrive inside
    // nextTestCase rather than on some later turn of the event loop.
    final lines = <String>[];
    final run = Run.start(verbose, session: session, onOutput: lines.add);
    addTearDown(run.dispose);

    final first = run.nextTestCase();
    expect(lines, isNotEmpty, reason: 'output arrived synchronously');
    first
      ?..markComplete(TestCaseStatus.valid)
      ..dispose();
  });

  group('when the callback throws', () {
    test('the original error and stack reach the caller', () {
      final run = Run.start(
        verbose,
        session: session,
        onOutput: (String line) => throw const FormatException('from output'),
      );
      addTearDown(run.dispose);

      expect(
        run.nextTestCase,
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'from output',
          ),
        ),
      );
    });

    test('the run is disposed rather than left holding a case', () {
      final run = Run.start(
        verbose,
        session: session,
        onOutput: (String line) => throw StateError('nope'),
      );
      expect(run.nextTestCase, throwsStateError);
      // A callback that failed mid-case leaves a case the run can never be
      // told about, so the run is torn down rather than wedged.
      expect(run.isDisposed, isTrue);
      expect(run.dispose, returnsNormally);
    });

    test('only the first failure is kept', () {
      var calls = 0;
      final run = Run.start(
        verbose,
        session: session,
        onOutput: (String line) {
          calls++;
          throw FormatException('failure $calls');
        },
      );
      addTearDown(run.dispose);
      expect(
        run.nextTestCase,
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'failure 1',
          ),
        ),
      );
    });
  });

  // The ABI forbids calling back into a run from its own output callback. In a
  // release build that is undefined behaviour, so the guard is always on
  // rather than an assert.
  test('re-entering the run from the callback is refused', () {
    late Run run;
    Object? seen;
    run = Run.start(
      verbose,
      session: session,
      onOutput: (String line) {
        try {
          run.nextTestCase();
        } on Object catch (error) {
          seen ??= error;
          rethrow;
        }
      },
    );
    addTearDown(run.dispose);

    expect(run.nextTestCase, throwsStateError);
    expect(seen, isA<StateError>());
    expect((seen! as StateError).message, contains('cannot pull a test case'));
  });

  group('re-entering the run from the callback', () {
    // Every one of these frees or mutates a run the engine is still executing
    // in. Left unguarded, disposing this way crashed the process outright
    // rather than raising, because the callable being closed is the one
    // currently running.
    test('is refused for dispose', () {
      late Run run;
      Object? seen;
      run = Run.start(
        verbose,
        session: session,
        onOutput: (String line) {
          try {
            run.dispose();
          } on Object catch (error) {
            seen ??= error;
          }
        },
      );
      addTearDown(run.dispose);

      final testCase = run.nextTestCase();
      expect(seen, isA<StateError>());
      expect((seen! as StateError).message, contains('cannot dispose'));
      expect(run.isDisposed, isFalse, reason: 'the run survived intact');
      testCase
        ?..markComplete(TestCaseStatus.valid)
        ..dispose();
    });

    test('is refused for reading the result', () {
      late Run run;
      Object? seen;
      run = Run.start(
        verbose,
        session: session,
        onOutput: (String line) {
          try {
            run.result();
          } on Object catch (error) {
            seen ??= error;
          }
        },
      );
      addTearDown(run.dispose);

      final testCase = run.nextTestCase();
      expect(seen, isA<StateError>());
      expect((seen! as StateError).message, contains('cannot read the result'));
      testCase
        ?..markComplete(TestCaseStatus.valid)
        ..dispose();
    });
  });

  test('a replay can capture its own output', () {
    final lines = <String>[];
    final run = Run.start(
      const Settings(
        testCases: 30,
        seed: 79,
        derandomize: true,
        database: Database.disabled,
        verbosity: Verbosity.quiet,
        suppressHealthChecks: machineSpeedChecks,
      ),
      session: session,
    );
    addTearDown(run.dispose);

    while (true) {
      final testCase = run.nextTestCase();
      if (testCase == null) break;
      try {
        final value = testCase.drawInteger(min: 0, max: 100);
        testCase.markComplete(
          value > 50 ? TestCaseStatus.interesting : TestCaseStatus.valid,
          origin: value > 50 ? 'output_test: too large' : null,
        );
      } finally {
        testCase.dispose();
      }
    }

    final result = run.result();
    addTearDown(result.dispose);
    expect(result.status, RunStatus.failed);
    final failure = result.failure(0);
    addTearDown(failure.dispose);

    final replayed = TestCase.fromBlob(
      const Settings(database: Database.disabled, verbosity: Verbosity.verbose),
      failure.reproductionBlob!,
      session: session,
      onOutput: lines.add,
    );
    addTearDown(replayed.dispose);
    expect(replayed.drawInteger(min: 0, max: 100), 51);
    replayed.markComplete(TestCaseStatus.valid);
  });
}
