@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

const Settings shrinking = Settings(
  testCases: 100,
  seed: 3,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: HealthChecks.all,
);

/// Runs a property that fails whenever the drawn integer exceeds [threshold],
/// and returns the finished result.
RunResult runFailing(
  Libhegel session, {
  int threshold = 50,
  Settings settings = shrinking,
  List<int>? drawn,
}) {
  final run = Run.start(settings, session: session);
  try {
    while (true) {
      final testCase = run.nextTestCase();
      if (testCase == null) break;
      try {
        final value = testCase.drawInteger(min: 0, max: 1000);
        drawn?.add(value);
        if (value > threshold) {
          testCase.markComplete(
            TestCaseStatus.interesting,
            origin: 'failure_test: value above threshold',
          );
        } else {
          testCase.markComplete(TestCaseStatus.valid);
        }
      } on StopTest {
        testCase.markComplete(TestCaseStatus.overrun);
      } finally {
        testCase.dispose();
      }
    }
    return run.result();
  } finally {
    run.dispose();
  }
}

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  group('a failing run', () {
    test('reports one failure carrying the origin it was given', () {
      final result = runFailing(session);
      addTearDown(result.dispose);

      expect(result.status, RunStatus.failed);
      expect(result.failureCount, 1);

      final failure = result.failure(0);
      addTearDown(failure.dispose);
      expect(failure.origin, contains('value above threshold'));
    });

    test('shrinks the counterexample toward the boundary', () {
      final drawn = <int>[];
      final result = runFailing(session, drawn: drawn);
      addTearDown(result.dispose);
      final failure = result.failure(0);
      addTearDown(failure.dispose);

      final replayed = TestCase.fromBlob(
        shrinking,
        failure.reproductionBlob!,
        session: session,
      );
      addTearDown(replayed.dispose);
      final minimal = replayed.drawInteger(min: 0, max: 1000);
      replayed.markComplete(
        TestCaseStatus.interesting,
        origin: 'failure_test: value above threshold',
      );

      // The shrinker should land on the smallest failing value, not merely
      // some failing value.
      expect(minimal, 51);
      expect(
        drawn.any((int v) => v > 51),
        isTrue,
        reason: 'the run should have seen larger values first',
      );
    });

    test('hands back a blob that replays the same case', () {
      final result = runFailing(session);
      addTearDown(result.dispose);
      final failure = result.failure(0);
      addTearDown(failure.dispose);

      final blob = failure.reproductionBlob;
      expect(blob, isNotNull);
      expect(blob, isNotEmpty);

      int replay() {
        final testCase = TestCase.fromBlob(shrinking, blob!, session: session);
        try {
          final value = testCase.drawInteger(min: 0, max: 1000);
          testCase.markComplete(
            TestCaseStatus.interesting,
            origin: 'failure_test: value above threshold',
          );
          return value;
        } finally {
          testCase.dispose();
        }
      }

      expect(replay(), replay());
    });

    test('groups distinct origins as distinct bugs', () {
      final run = Run.start(
        const Settings(
          testCases: 100,
          seed: 5,
          derandomize: true,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
          suppressHealthChecks: HealthChecks.all,
          reportMultipleFailures: true,
        ),
        session: session,
      );
      try {
        while (true) {
          final testCase = run.nextTestCase();
          if (testCase == null) break;
          try {
            final value = testCase.drawInteger(min: 0, max: 100);
            if (value > 90) {
              testCase.markComplete(TestCaseStatus.interesting, origin: 'high');
            } else if (value < 10) {
              testCase.markComplete(TestCaseStatus.interesting, origin: 'low');
            } else {
              testCase.markComplete(TestCaseStatus.valid);
            }
          } on StopTest {
            testCase.markComplete(TestCaseStatus.overrun);
          } finally {
            testCase.dispose();
          }
        }
        final result = run.result();
        addTearDown(result.dispose);

        expect(result.status, RunStatus.failed);
        expect(result.failureCount, 2);
        final origins = <String>{};
        for (var i = 0; i < result.failureCount; i++) {
          final failure = result.failure(i);
          origins.add(failure.origin);
          failure.dispose();
        }
        expect(origins, containsAll(<String>['high', 'low']));
      } finally {
        run.dispose();
      }
    });
  });

  group('reading failures', () {
    test('refuses an index outside the range', () {
      final result = runFailing(session);
      addTearDown(result.dispose);
      expect(() => result.failure(-1), throwsRangeError);
      expect(() => result.failure(result.failureCount), throwsRangeError);
    });

    test('refuses use after dispose', () {
      final result = runFailing(session);
      addTearDown(result.dispose);
      final failure = result.failure(0)..dispose();
      expect(() => failure.origin, throwsStateError);
      expect(() => failure.reproductionBlob, throwsStateError);
      expect(failure.isDisposed, isTrue);
      failure.dispose();
    });

    test('a passing run has none', () {
      final result = runFailing(session, threshold: 100000);
      addTearDown(result.dispose);
      expect(result.status, RunStatus.passed);
      expect(result.failureCount, 0);
    });
  });

  group('replaying a blob', () {
    test('rejects one that is not a blob at all', () {
      expect(
        () => TestCase.fromBlob(shrinking, 'not-a-blob', session: session),
        throwsA(isA<HegelException>()),
      );
    });

    test('rejects one containing an interior NUL before the call', () {
      expect(
        () => TestCase.fromBlob(
          shrinking,
          'abc${String.fromCharCode(0)}def',
          session: session,
        ),
        throwsArgumentError,
      );
    });

    test('overruns when the draws no longer match the blob', () {
      final result = runFailing(session);
      addTearDown(result.dispose);
      final failure = result.failure(0);
      addTearDown(failure.dispose);

      final testCase = TestCase.fromBlob(
        shrinking,
        failure.reproductionBlob!,
        session: session,
      );
      addTearDown(testCase.dispose);

      // The blob encodes one integer draw. Drawing far more than it recorded
      // runs off the end of the recorded choices.
      expect(() {
        for (var i = 0; i < 1000; i++) {
          testCase.drawInteger(min: 0, max: 1000);
        }
      }, throwsA(isA<StopTest>()));
      testCase.markComplete(TestCaseStatus.overrun);
    });
  });
}
