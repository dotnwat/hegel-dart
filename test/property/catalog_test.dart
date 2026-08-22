@TestOn('vm')
library;

import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:test/test.dart';

import '../support/property_case.dart';

/// A session for the group below, closed when its last test ends.
Libhegel openSession() {
  final session = Libhegel.open();
  addTearDown(session.dispose);
  return session;
}

void main() {
  group('integers', () {
    test('draws inside the requested bounds', () {
      final values = drawEveryCase(openSession(), integers(min: -20, max: 20));

      expect(values, isNotEmpty);
      expect(values, everyElement(inInclusiveRange(-20, 20)));
    });

    test('draws the only value a single-value range allows', () {
      final values = drawEveryCase(openSession(), integers(min: 7, max: 7));

      expect(values, everyElement(7));
    });

    test('reaches beyond a machine word when no bounds are given', () {
      final values = drawEveryCase(openSession(), integers());

      // The engine leans toward small values, so this is not a claim that
      // unbounded means uniform. It is the weaker claim that matters: the
      // default range is the type's, not some quiet small window, which is
      // what a missing bound silently becoming zero would look like.
      expect(values, contains(greaterThan(1 << 32)));
      expect(values, contains(lessThan(-(1 << 32))));
    });

    test('refuses an inverted range where it was written', () {
      expect(
        () => integers(min: 5, max: 1),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('exceeds max'),
          ),
        ),
      );
    });
  });
}
