@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

const Settings settings = Settings(
  testCases: 40,
  seed: 13,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: machineSpeedChecks,
);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  List<Uint8List> drawAll(Uint8List Function(TestCase testCase) draw) {
    final run = Run.start(settings, session: session);
    final drawn = <Uint8List>[];
    try {
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          drawn.add(draw(testCase));
          testCase.markComplete(TestCaseStatus.valid);
        } on StopTest {
          testCase.markComplete(TestCaseStatus.overrun);
        } finally {
          testCase.dispose();
        }
      }
    } finally {
      run.dispose();
    }
    return drawn;
  }

  test('draws byte strings within the requested length bounds', () {
    final drawn = drawAll(
      (TestCase c) => c.drawBytes(minLength: 2, maxLength: 8),
    );
    expect(drawn, isNotEmpty);
    expect(
      drawn.map((Uint8List b) => b.length),
      everyElement(allOf(greaterThanOrEqualTo(2), lessThanOrEqualTo(8))),
    );
    expect(drawn.map((Uint8List b) => b.length).toSet().length, greaterThan(1));
  });

  test('draws empty byte strings when allowed', () {
    final drawn = drawAll(
      (TestCase c) => c.drawBytes(minLength: 0, maxLength: 3),
    );
    expect(drawn.any((Uint8List b) => b.isEmpty), isTrue);
  });

  test('leaves the length to the engine when there is no upper bound', () {
    final drawn = drawAll((TestCase c) => c.drawBytes(minLength: 0));

    expect(drawn, isNotEmpty);
    // Unbounded is the engine's own sizing rather than an invitation to
    // allocate: the same thing a string generator means by it.
    expect(drawn.map((Uint8List b) => b.length), everyElement(lessThan(1000)));
    expect(drawn.map((Uint8List b) => b.length).toSet().length, greaterThan(1));
  });

  test('handles a fixed length', () {
    final drawn = drawAll(
      (TestCase c) => c.drawBytes(minLength: 4, maxLength: 4),
    );
    expect(drawn.map((Uint8List b) => b.length), everyElement(4));
  });

  // The engine frees its buffer as the draw returns, so what comes back has
  // to be a copy that outlives it.
  test('returns memory the engine no longer owns', () {
    final run = Run.start(settings, session: session);
    addTearDown(run.dispose);
    final testCase = run.nextTestCase()!;
    addTearDown(testCase.dispose);

    final first = testCase.drawBytes(minLength: 8, maxLength: 8);
    final snapshot = Uint8List.fromList(first);
    // Draw again so the engine allocates and frees more buffers, then check
    // the earlier result is untouched.
    for (var i = 0; i < 20; i++) {
      testCase.drawBytes(minLength: 8, maxLength: 8);
    }
    expect(first, snapshot);
    testCase.markComplete(TestCaseStatus.valid);
  });

  test('is reproducible from a seed', () {
    List<List<int>> sequence() =>
        drawAll((TestCase c) => c.drawBytes(minLength: 0, maxLength: 6))
            .map((Uint8List b) => b.toList())
            .toList();
    expect(sequence(), sequence());
  });

  group('validation', () {
    late TestCase testCase;

    setUp(() {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);
    });

    test('rejects inverted length bounds', () {
      expect(
        () => testCase.drawBytes(minLength: 5, maxLength: 1),
        throwsArgumentError,
      );
    });

    test('rejects a negative minimum', () {
      expect(
        () => testCase.drawBytes(minLength: -1, maxLength: 4),
        throwsRangeError,
      );
    });
  });
}
