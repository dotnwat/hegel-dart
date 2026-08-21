@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

const Settings settings = Settings(
  testCases: 30,
  seed: 47,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: machineSpeedChecks,
);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  /// Draws one list per test case with the given bounds.
  ({List<List<int>> lists, RunStatus status}) drawLists({
    required int minSize,
    int? maxSize,
    bool Function(int element)? accept,
  }) {
    final run = Run.start(settings, session: session);
    final lists = <List<int>>[];
    try {
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          final list = <int>[];
          final collection = testCase.startCollection(
            minSize: minSize,
            maxSize: maxSize,
          );
          try {
            testCase.span(SpanLabel.list, () {
              while (collection.more(testCase)) {
                final element = testCase.span(
                  SpanLabel.listElement,
                  () => testCase.drawInteger(min: 0, max: 50),
                );
                if (accept != null && !accept(element)) {
                  collection.reject(testCase, why: 'not acceptable');
                  continue;
                }
                list.add(element);
              }
            });
          } finally {
            collection.dispose();
          }
          lists.add(list);
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
      return (lists: lists, status: status);
    } finally {
      run.dispose();
    }
  }

  test('the engine chooses the length, within the bounds asked for', () {
    final drawn = drawLists(minSize: 1, maxSize: 4);
    expect(drawn.status, RunStatus.passed);
    expect(drawn.lists, isNotEmpty);
    expect(
      drawn.lists.map((List<int> l) => l.length),
      everyElement(allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(4))),
    );
    // The whole point of letting the engine decide is that it varies.
    expect(
      drawn.lists.map((List<int> l) => l.length).toSet().length,
      greaterThan(1),
    );
  });

  test('a fixed length produces exactly that many elements', () {
    final drawn = drawLists(minSize: 3, maxSize: 3);
    expect(drawn.lists.map((List<int> l) => l.length), everyElement(3));
  });

  test('an empty collection is allowed', () {
    final drawn = drawLists(minSize: 0, maxSize: 2);
    expect(drawn.lists.any((List<int> l) => l.isEmpty), isTrue);
  });

  test('an unbounded collection still terminates', () {
    // null maxSize marshals the unbounded sentinel; the engine still decides
    // when to stop, so the run has to finish rather than draw forever.
    final drawn = drawLists(minSize: 0);
    expect(drawn.status, RunStatus.passed);
    expect(drawn.lists, isNotEmpty);
  });

  test('rejected elements are left out and the run still passes', () {
    final drawn = drawLists(
      minSize: 2,
      maxSize: 5,
      accept: (int element) => element.isEven,
    );
    expect(drawn.status, RunStatus.passed);
    expect(
      drawn.lists.expand((List<int> l) => l),
      everyElement(predicate<int>((int e) => e.isEven, 'is even')),
    );
  });

  group('lifecycle', () {
    test('dispose is idempotent and use afterwards throws', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);

      final collection = testCase.startCollection(minSize: 0, maxSize: 2)
        ..dispose();
      expect(collection.isDisposed, isTrue);
      expect(collection.dispose, returnsNormally);
      expect(() => collection.more(testCase), throwsStateError);
      testCase.markComplete(TestCaseStatus.valid);
    });

    // The handle is independent of the case and run it came from, so freeing
    // it after them has to be safe.
    test('outlives the test case it was created from', () {
      final run = Run.start(settings, session: session);
      final testCase = run.nextTestCase()!;
      final collection = testCase.startCollection(minSize: 0, maxSize: 2);
      testCase
        ..markComplete(TestCaseStatus.valid)
        ..dispose();
      run.dispose();
      expect(collection.dispose, returnsNormally);
    });

    test('rejects bounds it can see are wrong', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);

      expect(() => testCase.startCollection(minSize: -1), throwsRangeError);
      expect(
        () => testCase.startCollection(minSize: 5, maxSize: 2),
        throwsArgumentError,
      );
    });
  });
}
