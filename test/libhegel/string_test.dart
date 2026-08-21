@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/string_generator.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

const Settings settings = Settings(
  testCases: 30,
  seed: 17,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: machineSpeedChecks,
);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  /// Draws once per case with [generator] and returns every string drawn.
  List<String> drawAll(StringGenerator generator) {
    final run = Run.start(settings, session: session);
    final drawn = <String>[];
    try {
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          drawn.add(testCase.drawString(generator));
          testCase.markComplete(TestCaseStatus.valid);
        } on StopTest {
          testCase.markComplete(TestCaseStatus.overrun);
        } on AssumptionFailed {
          testCase.markComplete(TestCaseStatus.invalid);
        } finally {
          testCase.dispose();
        }
      }
    } finally {
      run.dispose();
    }
    return drawn;
  }

  StringGenerator owned(StringGenerator generator) {
    addTearDown(generator.dispose);
    return generator;
  }

  group('text', () {
    test('respects length bounds and the ascii codec', () {
      final drawn = drawAll(
        owned(
          StringGenerator.text(
            minSize: 2,
            maxSize: 6,
            codec: 'ascii',
            session: session,
          ),
        ),
      );
      expect(drawn, isNotEmpty);
      expect(
        drawn.map((String s) => s.length),
        everyElement(allOf(greaterThanOrEqualTo(2), lessThanOrEqualTo(6))),
      );
      expect(
        drawn.every((String s) => s.codeUnits.every((int u) => u < 128)),
        isTrue,
      );
    });

    test('restricts to the named Unicode categories', () {
      final drawn = drawAll(
        owned(
          StringGenerator.text(
            minSize: 3,
            maxSize: 3,
            categories: const <String>['Nd'],
            session: session,
          ),
        ),
      );
      expect(drawn, isNotEmpty);
      for (final value in drawn) {
        expect(
          value.runes.every((int r) {
            final digit = String.fromCharCode(r);
            return int.tryParse(digit) != null || r > 127;
          }),
          isTrue,
          reason: 'expected decimal digits, got $value',
        );
      }
    });

    // The distinction the marshalling layer exists to preserve: absent means
    // no restriction, present-and-empty means an alphabet with nothing in it.
    test('tells an absent category list from an empty one', () {
      expect(
        () => owned(
          StringGenerator.text(minSize: 0, maxSize: 4, session: session),
        ),
        returnsNormally,
      );
      expect(
        () => StringGenerator.text(
          minSize: 1,
          maxSize: 4,
          categories: const <String>[],
          session: session,
        ),
        throwsA(isA<HegelException>()),
        reason: 'an empty alphabet cannot fill a non-empty string',
      );
    });

    test('accepts an empty alphabet when nothing needs drawing', () {
      final drawn = drawAll(
        owned(
          StringGenerator.text(
            minSize: 0,
            maxSize: 0,
            categories: const <String>[],
            session: session,
          ),
        ),
      );
      expect(drawn, everyElement(isEmpty));
    });

    test('draws characters given to it, U+0000 included', () {
      final drawn = drawAll(
        owned(
          StringGenerator.text(
            minSize: 4,
            maxSize: 4,
            categories: const <String>[],
            includeCharacters: 'a${String.fromCharCode(0)}',
            session: session,
          ),
        ),
      );
      expect(drawn, isNotEmpty);
      expect(drawn.map((String s) => s.length), everyElement(4));
      // Read by length rather than as a C string, so an interior NUL survives
      // instead of truncating the value.
      expect(drawn.any((String s) => s.codeUnits.contains(0)), isTrue);
    });

    test('round-trips astral characters', () {
      final drawn = drawAll(
        owned(
          StringGenerator.text(
            minSize: 2,
            maxSize: 2,
            categories: const <String>[],
            includeCharacters: '\u{1F600}\u{1F601}',
            session: session,
          ),
        ),
      );
      expect(drawn, isNotEmpty);
      for (final value in drawn) {
        expect(value.runes.length, 2);
        expect(
          value.runes.every((int r) => r >= 0x1F600 && r <= 0x1F601),
          isTrue,
        );
      }
    });

    test('rejects an unpaired surrogate before the engine sees it', () {
      expect(
        () => StringGenerator.text(
          includeCharacters: String.fromCharCode(0xD800),
          session: session,
        ),
        throwsArgumentError,
      );
    });
  });

  group('the specialised generators', () {
    test('regex produces matching strings', () {
      final generator = owned(
        StringGenerator.regex(
          r'[a-f]{3}-[0-9]{2}',
          fullMatch: true,
          session: session,
        ),
      );
      final drawn = drawAll(generator);
      expect(drawn, isNotEmpty);
      expect(drawn, everyElement(matches(RegExp(r'^[a-f]{3}-[0-9]{2}$'))));
    });

    test('email produces addresses with a single at sign', () {
      final drawn = drawAll(owned(StringGenerator.email(session: session)));
      expect(drawn, isNotEmpty);
      expect(
        drawn,
        everyElement(
          predicate<String>(
            (String s) => s.split('@').length == 2 && s.length <= 320,
            'looks like an address',
          ),
        ),
      );
    });

    test('url produces http or https', () {
      final drawn = drawAll(owned(StringGenerator.url(session: session)));
      expect(drawn, isNotEmpty);
      expect(
        drawn,
        everyElement(
          predicate<String>(
            (String s) => s.startsWith('http://') || s.startsWith('https://'),
            'is an http(s) URL',
          ),
        ),
      );
    });

    test('domain honours its length cap', () {
      final drawn = drawAll(
        owned(StringGenerator.domain(maxLength: 32, session: session)),
      );
      expect(drawn, isNotEmpty);
      expect(
        drawn.map((String s) => s.length),
        everyElement(allOf(greaterThan(0), lessThanOrEqualTo(32))),
      );
      // Not every domain has a dot: a bare top-level domain is a domain, and
      // the engine draws those too.
      expect(drawn.any((String s) => s.contains('.')), isTrue);
    });

    test('domain refuses a cap below the shortest possible name', () {
      // Four is legal -- two-letter top-level domains make `a.am` fit -- so
      // a refusal only starts below the documented minimum.
      expect(
        () => StringGenerator.domain(maxLength: 4, session: session)..dispose(),
        returnsNormally,
      );
      expect(
        () => StringGenerator.domain(maxLength: 3, session: session),
        throwsA(isA<HegelException>()),
      );
    });
  });

  group('lifecycle', () {
    test('a generator is reusable across runs', () {
      final generator = owned(
        StringGenerator.text(
          minSize: 1,
          maxSize: 3,
          codec: 'ascii',
          session: session,
        ),
      );
      expect(drawAll(generator), isNotEmpty);
      expect(drawAll(generator), isNotEmpty);
    });

    test('dispose is idempotent and use after it throws', () {
      final generator = StringGenerator.email(session: session)..dispose();
      expect(generator.isDisposed, isTrue);
      expect(generator.dispose, returnsNormally);
      expect(() => generator.handle, throwsStateError);
    });
  });

  test('is reproducible from a seed', () {
    final generator = owned(
      StringGenerator.text(
        minSize: 0,
        maxSize: 8,
        codec: 'ascii',
        session: session,
      ),
    );
    expect(drawAll(generator), drawAll(generator));
  });
}
