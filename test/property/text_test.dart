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
    test('is not built until a draw asks for it', () {
      expect(text().isNativeBuilt, isFalse);
    });

    test('is built once, and reused by every later draw and run', () {
      final session = openSession();
      final generator = text(maxLength: 4);

      drawEveryCase(session, generator, testCases: 10);
      expect(generator.isNativeBuilt, isTrue);

      // Two whole runs and one native generator: building costs a regex
      // compile and a Unicode table walk, which is the reason it is kept.
      final first = generator.buildNative;
      drawEveryCase(session, generator, testCases: 10);
      expect(generator.buildNative, first);
    });

    test('is shared by every pattern built over the same alphabet', () {
      final session = openSession();
      final alphabet = text(minCodepoint: 120, maxCodepoint: 122);

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

      expect(alphabet.isNativeBuilt, isTrue);
    });

    test('passes a draw that rejects its own case straight through', () {
      expect(
        () => TestCase(_RejectingContext()).draw(emails()),
        throwsA(isA<AssumptionFailed>()),
      );
    });
  });
}
