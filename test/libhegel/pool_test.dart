@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

const Settings settings = Settings(
  testCases: 25,
  seed: 53,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: everyHealthCheck,
);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  RunStatus drive(void Function(TestCase testCase) body) {
    final run = Run.start(settings, session: session);
    try {
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          body(testCase);
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
      return status;
    } finally {
      run.dispose();
    }
  }

  test('adds distinct identifiers and draws them back', () {
    final added = <int>[];
    final drawn = <int>[];
    final status = drive((TestCase c) {
      final pool = c.newPool();
      try {
        final mine = <int>[for (var i = 0; i < 3; i++) pool.add(c)];
        added.addAll(mine);
        expect(mine.toSet(), hasLength(3), reason: 'identifiers are distinct');
        // Whatever comes back has to be something that was put in.
        final chosen = pool.draw(c);
        expect(mine, contains(chosen));
        drawn.add(chosen);
      } finally {
        pool.dispose();
      }
    });
    expect(status, RunStatus.passed);
    expect(added, isNotEmpty);
    expect(drawn, isNotEmpty);
  });

  test('drawing from an empty pool is a failed assumption', () {
    var rejections = 0;
    final status = drive((TestCase c) {
      final pool = c.newPool();
      try {
        // Nothing added: the engine has nothing to choose, which is a
        // precondition failure rather than an error.
        pool.draw(c);
      } on AssumptionFailed {
        rejections++;
        rethrow;
      } finally {
        pool.dispose();
      }
    });
    expect(rejections, greaterThan(0));
    // Every case was rejected, so the engine reached no verdict to speak of;
    // what matters is that it did not error.
    expect(status, isNot(RunStatus.error));
  });

  test('consuming removes the identifier from the pool', () {
    final status = drive((TestCase c) {
      final pool = c.newPool();
      try {
        final only = pool.add(c);
        expect(pool.draw(c, consume: true), only);
        // The pool is empty again, so the next draw has nothing to choose.
        expect(() => pool.draw(c), throwsA(isA<AssumptionFailed>()));
      } finally {
        pool.dispose();
      }
    });
    expect(status, isNot(RunStatus.error));
  });

  test('leaving an identifier lets it be chosen again', () {
    final status = drive((TestCase c) {
      final pool = c.newPool();
      try {
        final only = pool.add(c);
        expect(pool.draw(c), only);
        expect(pool.draw(c), only);
      } finally {
        pool.dispose();
      }
    });
    expect(status, RunStatus.passed);
  });

  group('lifecycle', () {
    test('dispose is idempotent and use afterwards throws', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);

      final pool = testCase.newPool()..dispose();
      expect(pool.isDisposed, isTrue);
      expect(pool.dispose, returnsNormally);
      expect(() => pool.add(testCase), throwsStateError);
      testCase.markComplete(TestCaseStatus.valid);
    });

    test('outlives the test case it was created from', () {
      final run = Run.start(settings, session: session);
      final testCase = run.nextTestCase()!;
      final pool = testCase.newPool();
      testCase
        ..markComplete(TestCaseStatus.valid)
        ..dispose();
      run.dispose();
      expect(pool.dispose, returnsNormally);
    });
  });
}
