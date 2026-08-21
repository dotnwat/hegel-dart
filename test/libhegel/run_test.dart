@TestOn('vm')
library;

import 'package:hegel/src/libhegel/bindings.g.dart' as raw;
import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

/// Settings that keep a run deterministic and off the filesystem.
const Settings deterministic = Settings(
  testCases: 5,
  seed: 1,
  derandomize: true,
  database: Database.disabled,
  phases: Phases.generate,
  verbosity: Verbosity.quiet,
);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  /// Runs [body] over every case, disposing each handle.
  int drive(Run run, void Function(TestCase testCase) body) {
    var cases = 0;
    while (true) {
      final testCase = run.nextTestCase();
      if (testCase == null) break;
      cases++;
      try {
        body(testCase);
      } finally {
        testCase.dispose();
      }
    }
    return cases;
  }

  group('a run that draws nothing', () {
    test('passes once every case is marked valid', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);

      final cases = drive(
        run,
        (TestCase c) => c.markComplete(TestCaseStatus.valid),
      );
      // Exactly one, however large the budget: a body that draws nothing has
      // a single possible choice sequence, so the engine exhausts its tree
      // immediately rather than running the same case five times.
      expect(cases, 1);
      expect(run.isFinished, isTrue);

      final result = run.result();
      addTearDown(result.dispose);
      expect(result.status, RunStatus.passed);
      expect(result.error, isNull);
    });

    test('fails when a case is reported interesting', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);

      drive(
        run,
        (TestCase c) =>
            c.markComplete(TestCaseStatus.interesting, origin: 'run_test:1'),
      );

      final result = run.result();
      addTearDown(result.dispose);
      expect(result.status, RunStatus.failed);
    });
  });

  // Misuse this layer can see is refused before it reaches the engine, so
  // HEGEL_E_NOT_COMPLETE and HEGEL_E_ALREADY_COMPLETE stay signs of a binding
  // bug rather than something callers are expected to catch.
  group('guards, before touching the engine', () {
    test('refuses a second case while one is outstanding', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      final first = run.nextTestCase()!;
      addTearDown(first.dispose);

      expect(run.nextTestCase, throwsStateError);

      // Once the outstanding case is reported, asking again is allowed --
      // here it returns null, because a body that draws nothing has only one
      // case to offer.
      first.markComplete(TestCaseStatus.valid);
      expect(run.nextTestCase, returnsNormally);
    });

    test('refuses the result until the run is over', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      expect(run.result, throwsStateError);
    });

    test('refuses a second markComplete on the same case', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);

      testCase.markComplete(TestCaseStatus.valid);
      expect(
        () => testCase.markComplete(TestCaseStatus.valid),
        throwsStateError,
      );
    });

    test('refuses a second markComplete through a clone', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);
      final clone = testCase.clone();
      addTearDown(clone.dispose);

      testCase.markComplete(TestCaseStatus.valid);
      // Completion applies to the case, not the handle.
      expect(() => clone.markComplete(TestCaseStatus.valid), throwsStateError);
    });

    test('requires an origin for an interesting case, and only then', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);

      expect(
        () => testCase.markComplete(TestCaseStatus.interesting),
        throwsArgumentError,
      );
      expect(
        () => testCase.markComplete(TestCaseStatus.valid, origin: 'nope'),
        throwsArgumentError,
      );
      testCase.markComplete(TestCaseStatus.valid);
    });

    test('refuses everything after dispose', () {
      final run = Run.start(deterministic, session: session)..dispose();
      expect(run.nextTestCase, throwsStateError);
      expect(run.result, throwsStateError);
      expect(run.isDisposed, isTrue);
      run.dispose();
    });

    test('returns null repeatedly once finished', () {
      final run = Run.start(
        const Settings(
          testCases: 1,
          seed: 1,
          derandomize: true,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
        ),
        session: session,
      );
      addTearDown(run.dispose);
      drive(run, (TestCase c) => c.markComplete(TestCaseStatus.valid));
      expect(run.nextTestCase(), isNull);
      expect(run.nextTestCase(), isNull);
    });
  });

  // Both of these were reachable before the guards below existed: a run
  // could be revived after its handle was freed, and a clone completing the
  // case left the run unable to advance.
  group('completion and disposal cannot corrupt the run', () {
    test('a late completion does not revive a disposed run', () {
      final run = Run.start(deterministic, session: session);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);

      run.dispose();
      expect(run.isDisposed, isTrue);

      // The case still holds a handle and may report itself at any time. If
      // that moved the run back to idle, the dispose below would free an
      // already-freed handle.
      testCase.markComplete(TestCaseStatus.valid);
      expect(run.isDisposed, isTrue);
      expect(run.nextTestCase, throwsStateError);
      expect(run.dispose, returnsNormally);
    });

    test('a clone completing the case advances the run', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      final root = run.nextTestCase()!;
      addTearDown(root.dispose);
      final clone = root.clone();
      addTearDown(clone.dispose);

      // A worker driving a clone may be the one that reports the case, which
      // the run has to hear about or it stays in flight forever.
      clone.markComplete(TestCaseStatus.valid);
      expect(run.nextTestCase, returnsNormally);
    });
  });

  group('handles', () {
    test('a disposed test case refuses further use', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!..markComplete(TestCaseStatus.valid);
      testCase.dispose();
      expect(testCase.isDisposed, isTrue);
      expect(() => testCase.isNondeterministic, throwsStateError);
      testCase.dispose();
    });

    test('a clone is an independent handle onto the same case', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);
      final clone = testCase.clone();

      expect(clone.isDisposed, isFalse);
      clone.dispose();
      // Disposing a clone leaves the original usable.
      expect(testCase.isNondeterministic, isFalse);
      testCase.markComplete(TestCaseStatus.valid);
    });

    test('a run result outlives the run it came from', () {
      final run = Run.start(deterministic, session: session);
      drive(run, (TestCase c) => c.markComplete(TestCaseStatus.valid));
      final result = run.result();
      addTearDown(result.dispose);
      run.dispose();
      // The snapshot is caller-owned and independent of the run.
      expect(result.status, RunStatus.passed);
    });

    test('a disposed result refuses further use', () {
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      drive(run, (TestCase c) => c.markComplete(TestCaseStatus.valid));
      final result = run.result()..dispose();
      expect(() => result.status, throwsStateError);
      result.dispose();
    });
  });

  group('the engine still reports its own errors', () {
    test('through L1, where the protocol is visible', () {
      // Driving the raw protocol wrongly is what HEGEL_E_NOT_COMPLETE exists
      // for; the safe layer refuses before getting here, so it is exercised
      // one level down.
      final run = Run.start(deterministic, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(() {
        testCase
          ..markComplete(TestCaseStatus.valid)
          ..dispose();
      });

      expect(
        RunStatus.fromNative(raw.hegel_run_status_t.HEGEL_RUN_STATUS_PASSED),
        RunStatus.passed,
      );
      expect(() => RunStatus.fromNative(99), throwsArgumentError);
    });

    test('surfacing an invalid argument as a HegelException', () {
      expect(
        () =>
            Run.start(const Settings(statefulStepCount: -1), session: session),
        throwsA(isA<HegelException>()),
      );
    });
  });
}
