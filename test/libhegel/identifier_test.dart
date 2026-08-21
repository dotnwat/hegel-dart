@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

const Settings settings = Settings(
  testCases: 40,
  seed: 23,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: everyHealthCheck,
);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  List<T> drawAll<T>(T Function(TestCase testCase) draw, {Settings? using}) {
    final run = Run.start(using ?? settings, session: session);
    final drawn = <T>[];
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

  group('uuids', () {
    test('are sixteen bytes and never the nil uuid', () {
      final drawn = drawAll((TestCase c) => c.drawUuid());
      expect(drawn, isNotEmpty);
      expect(drawn.map((Uint8List u) => u.length), everyElement(16));
      expect(
        drawn.any((Uint8List u) => u.every((int b) => b == 0)),
        isFalse,
        reason: 'the nil uuid is never produced',
      );
      expect(drawn.toSet().length, greaterThan(1));
    });

    test('carry the requested version and variant bits', () {
      for (final version in <int>[1, 4, 5]) {
        final drawn = drawAll((TestCase c) => c.drawUuid(version: version));
        expect(drawn, isNotEmpty);
        for (final uuid in drawn) {
          // Version lives in the high nibble of byte 6, variant in the top
          // bits of byte 8.
          expect(uuid[6] >> 4, version);
          expect(uuid[8] >> 6, 0x2);
        }
      }
    });

    test('reject a version outside the nibble', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);
      expect(() => testCase.drawUuid(version: 16), throwsRangeError);
      expect(() => testCase.drawUuid(version: -1), throwsRangeError);
    });
  });

  group('ip addresses', () {
    test('ipv4 is four bytes and varies', () {
      final drawn = drawAll((TestCase c) => c.drawIpv4());
      expect(drawn, isNotEmpty);
      expect(drawn.map((Uint8List a) => a.length), everyElement(4));
      expect(
        drawn.map((Uint8List a) => a.join('.')).toSet().length,
        greaterThan(1),
      );
    });

    test('ipv6 is sixteen bytes and varies', () {
      final drawn = drawAll((TestCase c) => c.drawIpv6());
      expect(drawn, isNotEmpty);
      expect(drawn.map((Uint8List a) => a.length), everyElement(16));
      expect(
        drawn.map((Uint8List a) => a.join(':')).toSet().length,
        greaterThan(1),
      );
    });

    test('both are reproducible from a seed', () {
      List<String> sequence() => drawAll(
        (TestCase c) => '${c.drawIpv4().join('.')}/${c.drawIpv6().join(':')}',
      );
      expect(sequence(), sequence());
    });
  });

  group('targeting', () {
    test('accepts an observation and steers the run', () {
      // With targeting on, the engine hill-climbs toward higher scores, so
      // the best value it finds should beat what it started with.
      final drawn = drawAll(
        (TestCase c) {
          final value = c.drawInteger(min: 0, max: 1000000);
          c.target(value.toDouble(), label: 'size');
          return value;
        },
        using: const Settings(
          testCases: 60,
          seed: 29,
          derandomize: true,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
          suppressHealthChecks: everyHealthCheck,
          phases: {Phase.generate, Phase.target},
        ),
      );
      expect(drawn, isNotEmpty);
      expect(
        drawn.reduce((int a, int b) => a > b ? a : b),
        greaterThan(drawn.first),
      );
    });

    test('is a no-op when the targeting phase is off', () {
      final drawn = drawAll(
        (TestCase c) {
          c.target(1.0, label: 'ignored');
          return c.drawInteger(min: 0, max: 10);
        },
        using: const Settings(
          testCases: 5,
          seed: 31,
          derandomize: true,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
          phases: {Phase.generate},
        ),
      );
      expect(drawn, isNotEmpty);
    });

    test('refuses a non-finite observation before the call', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);
      expect(
        () => testCase.target(double.nan, label: 'x'),
        throwsArgumentError,
      );
      expect(
        () => testCase.target(double.infinity, label: 'x'),
        throwsArgumentError,
      );
    });

    test('refuses a label the engine could not read', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);
      expect(
        () => testCase.target(1, label: 'a${String.fromCharCode(0)}b'),
        throwsArgumentError,
      );
    });

    test('a run using targeting still reaches a verdict', () {
      final run = Run.start(
        const Settings(
          testCases: 20,
          seed: 37,
          derandomize: true,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
          suppressHealthChecks: everyHealthCheck,
          phases: {Phase.generate, Phase.target},
        ),
        session: session,
      );
      addTearDown(run.dispose);
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          testCase.target(
            testCase.drawInteger(min: 0, max: 100).toDouble(),
            label: 'value',
          );
          testCase.markComplete(TestCaseStatus.valid);
        } finally {
          testCase.dispose();
        }
      }
      final result = run.result();
      addTearDown(result.dispose);
      expect(result.status, RunStatus.passed);
    });
  });
}
