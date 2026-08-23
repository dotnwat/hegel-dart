@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/string_generator.dart' as engine;
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_case.dart';
import '../support/scripted_context.dart';

/// A context whose string draws reject the case, as the engine's can.
///
/// Some string specifications refuse the value they just drew -- an email
/// that would break the RFC's length cap -- and the engine reports that as a
/// rejection rather than an error. It does not happen on demand, and the
/// question here is only whether this layer passes one along, so it is asked
/// where the answer can be arranged.
final class _RejectingContext extends FakeDrawContext {
  @override
  String drawString(engine.StringGenerator generator) =>
      throw const AssumptionFailed();
}

/// A session for the group below, closed when its last test ends.
Libhegel openSession() {
  final session = Libhegel.open();
  addTearDown(session.dispose);
  return session;
}

void main() {
  group('text', () {
    test('counts its length bounds in characters, not code units', () {
      final values = drawEveryCase(
        openSession(),
        text(minLength: 3, maxLength: 3),
        testCases: 40,
      );

      expect(values, isNotEmpty);
      expect(values.map((String value) => value.runes.length).toSet(), <int>{
        3,
      });
      // The distinction the bounds are about: three characters out of the
      // whole of Unicode is anywhere from three to six UTF-16 code units,
      // which is what Dart's own `length` counts.
      expect(
        values.map((String value) => value.length).toSet(),
        contains(greaterThan(3)),
      );
    });

    test('reaches beyond ASCII when nothing was restricted', () {
      final values = drawEveryCase(openSession(), text());

      // The default alphabet is Unicode, not the bottom of it. A frontend
      // that quietly narrowed the default -- a codec applied where none was
      // asked for -- would pass every bounds test here and fail only this.
      expect(
        values.any((String value) => value.runes.any((int rune) => rune > 127)),
        isTrue,
      );
    });

    test('stays inside a range of code points', () {
      final values = drawEveryCase(
        openSession(),
        text(minCodepoint: 97, maxCodepoint: 99, maxLength: 8),
      );

      expect(values, isNotEmpty);
      expect(
        values.expand((String value) => value.runes).toSet(),
        everyElement(inInclusiveRange(97, 99)),
      );
    });

    test('stays inside a Unicode category', () {
      final values = drawEveryCase(
        openSession(),
        text(categories: <String>['Nd'], maxLength: 5),
      );

      expect(values, isNotEmpty);
      // Checked over ASCII, where a decimal digit is a thing this test can
      // recognise without carrying a Unicode table of its own. The rest of
      // what Nd draws is digits in other scripts, which is the point of
      // asking for a category rather than a code-point range.
      expect(
        values.expand((String value) => value.runes).where((int r) => r < 128),
        everyElement(inInclusiveRange(0x30, 0x39)),
      );
    });

    test('leaves out a Unicode category it was told to exclude', () {
      final values = drawEveryCase(
        openSession(),
        text(codec: 'ascii', excludeCategories: <String>['Nd'], maxLength: 8),
      );

      expect(values, isNotEmpty);
      expect(values, everyElement(isNot(matches(RegExp(r'[0-9]')))));
    });

    test('takes an alphabet of exactly the characters it was given', () {
      // An empty category list is an empty alphabet, which the included
      // characters are then added to. Null would have meant no restriction,
      // which is the opposite.
      final values = drawEveryCase(
        openSession(),
        text(categories: <String>[], includeCharacters: 'xy', maxLength: 6),
      );

      expect(values, isNotEmpty);
      expect(values, everyElement(matches(RegExp(r'^[xy]*$'))));
    });

    test('removes the characters it was told to exclude', () {
      final values = drawEveryCase(
        openSession(),
        text(minCodepoint: 97, maxCodepoint: 99, excludeCharacters: 'b'),
      );

      expect(values, isNotEmpty);
      expect(values, everyElement(isNot(contains('b'))));
    });

    test('holds to a codec', () {
      final values = drawEveryCase(
        openSession(),
        text(codec: 'ascii', maxLength: 8),
      );

      expect(values, isNotEmpty);
      expect(
        values.expand((String value) => value.codeUnits).toSet(),
        everyElement(lessThan(128)),
      );
    });

    test('stays finite when no length was given', () {
      final values = drawEveryCase(openSession(), text());

      expect(values, isNotEmpty);
      // The engine sizes collections itself, so unbounded means "the engine
      // decides" rather than "as long as memory allows".
      expect(
        values.map((String value) => value.runes.length),
        everyElement(lessThan(1000)),
      );
    });

    test('refuses lengths that are not lengths, where they were written', () {
      expect(
        () => text(minLength: -1),
        throwsA(
          isA<RangeError>().having(
            (RangeError error) => error.message,
            'message',
            contains('must not be negative'),
          ),
        ),
      );
      expect(
        () => text(minLength: 5, maxLength: 2),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('exceeds maxLength'),
          ),
        ),
      );
    });
  });

  group('characters', () {
    test('produces exactly one character', () {
      final values = drawEveryCase(openSession(), characters(), testCases: 40);

      expect(values, isNotEmpty);
      expect(values.map((String value) => value.runes.length).toSet(), <int>{
        1,
      });
      // And one character is not one code unit: Dart has no character type,
      // so what comes back is the string a character is.
      expect(
        values.map((String value) => value.length).toSet(),
        contains(2),
        reason: 'a run that never left the basic plane would not show this',
      );
    });

    test('takes the same alphabet arguments as text', () {
      final values = drawEveryCase(
        openSession(),
        characters(minCodepoint: 97, maxCodepoint: 99),
      );

      expect(values, isNotEmpty);
      expect(values, everyElement(matches(RegExp(r'^[abc]$'))));
    });
  });

  group('fromRegex', () {
    test('matches the whole string by default', () {
      final values = drawEveryCase(
        openSession(),
        fromRegex(r'[0-9]{3}-[0-9]{4}'),
      );

      expect(values, isNotEmpty);
      expect(values, everyElement(matches(RegExp(r'^[0-9]{3}-[0-9]{4}$'))));
    });

    test('pads around the match when the whole string need not match', () {
      final values = drawEveryCase(
        openSession(),
        fromRegex('abc', fullMatch: false),
      );

      expect(values, isNotEmpty);
      expect(values, everyElement(contains('abc')));
      expect(
        values,
        contains(isNot('abc')),
        reason:
            'padding that never appeared would make this the full-match '
            'case under another name',
      );
    });

    test('draws its padding from the alphabet it was given', () {
      final values = drawEveryCase(
        openSession(),
        fromRegex(
          'abc',
          fullMatch: false,
          alphabet: text(minCodepoint: 97, maxCodepoint: 122),
        ),
      );

      expect(values, isNotEmpty);
      expect(values, everyElement(matches(RegExp(r'^[a-z]*abc[a-z]*$'))));
    });

    test('rejects every case when the alphabet cannot spell the pattern', () {
      // The engine draws the whole string from the alphabet, match included,
      // so an alphabet without a, b or c can never produce this and refuses
      // each draw instead. That refusal is a rejected case rather than an
      // error -- the same thing `assume` does -- which is what makes it
      // survivable and what makes it easy to miss.
      final values = drawEveryCase(
        openSession(),
        fromRegex(
          'abc',
          fullMatch: false,
          alphabet: text(minCodepoint: 120, maxCodepoint: 122),
        ),
        testCases: 10,
      );

      expect(
        values,
        isEmpty,
        reason: 'every case rejected, and the run still finished',
      );
    });

    test('carries the everyday shapes through whole', () {
      // A sweep across the constructs a pattern is usually made of. The
      // regex engine itself lives behind the ABI and is tested there; what
      // this guards is the trip -- the pattern string, its flags and its
      // escapes arriving intact -- which is exactly the part a marshalling
      // slip would break one construct at a time.
      final shapes = <(String, bool Function(String))>[
        ('abc', RegExp(r'^abc$').hasMatch),
        ('a|bc', RegExp(r'^(a|bc)$').hasMatch),
        ('ab*c', RegExp(r'^ab*c$').hasMatch),
        ('ab+c', RegExp(r'^ab+c$').hasMatch),
        ('ab?c', RegExp(r'^ab?c$').hasMatch),
        ('a{2,4}', RegExp(r'^a{2,4}$').hasMatch),
        ('(?:xy){2}', RegExp(r'^(?:xy){2}$').hasMatch),
        (r'(a)\1', RegExp(r'^(a)\1$').hasMatch),
        ('a(?=b)b', RegExp(r'^ab$').hasMatch),
        ('(?i)abc', RegExp(r'^abc$', caseSensitive: false).hasMatch),
        // Verified over runes rather than by RegExp: the complement reaches
        // past the basic plane, where a code-unit dot mismatches.
        (
          '[^b-z]',
          (String value) {
            final runes = value.runes.toList();
            return runes.length == 1 &&
                (runes.single < 0x62 || runes.single > 0x7a);
          },
        ),
      ];

      for (final (pattern, accepts) in shapes) {
        final values = drawEveryCase(
          openSession(),
          fromRegex(pattern),
          testCases: 10,
        );

        expect(values, isNotEmpty, reason: 'pattern $pattern');
        for (final String value in values) {
          expect(
            accepts(value),
            isTrue,
            reason: 'pattern $pattern drew $value',
          );
        }
      }
    });

    test('honours a case flag rather than flattening it', () {
      // `(?i)` is the flag most worth its own assertion: a frontend that
      // lost it would still produce matching strings, just never the other
      // case, and the sweep above could not tell.
      final values = drawEveryCase(
        openSession(),
        fromRegex('(?i)abc'),
        testCases: 20,
      );

      expect(values.toSet(), hasLength(greaterThan(1)));
      expect(
        values.map((String value) => value.toLowerCase()).toSet(),
        <String>{'abc'},
      );
    });
  });

  group('the ready-made shapes', () {
    test('emails look like email addresses', () {
      final values = drawEveryCase(openSession(), emails(), testCases: 30);

      expect(values, isNotEmpty);
      expect(values, everyElement(contains('@')));
    });

    test('urls look like http urls', () {
      final values = drawEveryCase(openSession(), urls(), testCases: 20);

      expect(values, isNotEmpty);
      expect(values, everyElement(startsWith('http')));
    });

    test('domains hold to their length cap', () {
      final values = drawEveryCase(
        openSession(),
        domains(maxLength: 20),
        testCases: 20,
      );

      expect(values, isNotEmpty);
      expect(
        values.map((String value) => value.length),
        everyElement(lessThanOrEqualTo(20)),
      );
    });

    test('domains refuse a length that is not one', () {
      expect(
        () => domains(maxLength: -1),
        throwsA(
          isA<RangeError>().having(
            (RangeError error) => error.message,
            'message',
            contains('must not be negative'),
          ),
        ),
      );
    });
  });

  group('the native generator behind a string generator', () {
    /// How many natives [body] caused to be built.
    ///
    /// The cache is process-wide and outlives any one test, so what a test
    /// can say is how much it added to it.
    int nativesBuiltBy(void Function() body) {
      final before = nativeStringGeneratorCount;
      body();
      return nativeStringGeneratorCount - before;
    }

    test('is not built until a draw asks for it', () {
      expect(text().isNativeBuilt, isFalse);
      expect(nativesBuiltBy(() => text(maxLength: 41)), 0);
    });

    test('is built once for a generator drawn from twice', () {
      final session = openSession();
      final generator = text(maxLength: 42);

      expect(
        nativesBuiltBy(() {
          drawEveryCase(session, generator, testCases: 10);
          drawEveryCase(session, generator, testCases: 10);
        }),
        1,
      );
      expect(generator.isNativeBuilt, isTrue);
    });

    test('is built once for a generator written inside the body', () {
      // The shape a property is actually written in, and the one that made
      // per-object caching the wrong idea: a fresh generator per test case,
      // each of which would otherwise compile its own alphabet and keep it
      // forever.
      final session = openSession();

      expect(
        nativesBuiltBy(() {
          driveCases(session, (TestCase testCase) {
            testCase.draw(text(maxLength: 43));
          }, testCases: 25);
        }),
        1,
      );
    });

    test('is shared by every pattern built over the same alphabet', () {
      final session = openSession();
      // A specification no other test uses, since the cache outlives them
      // all and a warm entry would make this measure nothing.
      final alphabet = text(
        minCodepoint: 120,
        maxCodepoint: 122,
        maxLength: 47,
      );

      expect(
        nativesBuiltBy(() {
          drawEveryCase(
            session,
            fromRegex('a', fullMatch: false, alphabet: alphabet),
            testCases: 5,
          );
          drawEveryCase(
            session,
            fromRegex('b', fullMatch: false, alphabet: alphabet),
            testCases: 5,
          );
          // Two patterns and the alphabet under them: three specifications,
          // and the alphabet is the one they share.
        }),
        3,
      );
      expect(alphabet.isNativeBuilt, isTrue);
    });

    test('is not shared by generators that differ anywhere', () {
      final session = openSession();

      // Pairs a careless key would collide: a field's content against the
      // next field's, an empty string against a missing one, the same
      // category list under two different names.
      expect(
        nativesBuiltBy(() {
          for (final generator in <Generator<String>>[
            text(maxLength: 44, includeCharacters: 'ab'),
            text(maxLength: 44, includeCharacters: 'a', excludeCharacters: 'b'),
            text(maxLength: 44, excludeCharacters: ''),
            text(maxLength: 44),
            text(maxLength: 44, categories: <String>['Lu']),
            text(maxLength: 44, excludeCategories: <String>['Lu']),
            text(maxLength: 44, codec: 'ascii'),
          ]) {
            drawEveryCase(session, generator, testCases: 2);
          }
        }),
        7,
      );
    });

    test('tells two ready-made shapes apart, and two of one shape', () {
      final session = openSession();

      // Measured as increments that must be zero, plus parameters no other
      // test uses: emails() and urls() take no arguments, so whether they
      // are already cached depends on what ran first.
      drawEveryCase(session, emails(), testCases: 2);
      expect(
        nativesBuiltBy(() => drawEveryCase(session, emails(), testCases: 2)),
        0,
      );
      expect(
        nativesBuiltBy(
          () => drawEveryCase(session, domains(maxLength: 45), testCases: 2),
        ),
        1,
      );
      expect(
        nativesBuiltBy(
          () => drawEveryCase(session, domains(maxLength: 46), testCases: 2),
        ),
        1,
      );
    });

    test('does not go on watching the list it was given', () {
      final categories = <String>['Nd'];
      final generator = text(
        categories: categories,
        codec: 'ascii',
        maxLength: 6,
      );
      categories.add('Lu');

      final values = drawEveryCase(openSession(), generator);

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(isNot(matches(RegExp('[A-Z]')))),
        reason: 'the letters were added after the generator was written',
      );
    });

    test('passes a draw that rejects its own case straight through', () {
      expect(
        () => TestCase(_RejectingContext()).draw(emails()),
        throwsA(isA<AssumptionFailed>()),
      );
    });
  });
}
