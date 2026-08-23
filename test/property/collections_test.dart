@TestOn('vm')
library;

import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_case.dart';
import '../support/scripted_context.dart';

/// A session for the group below, closed when its last test ends.
Libhegel openSession() {
  final session = Libhegel.open();
  addTearDown(session.dispose);
  return session;
}

/// What one element under [label], drawn from [ranges], looks like on the wire.
///
/// Spelled out once rather than at every call, because the point of the pins
/// below is the shape around the elements -- where the collection is started,
/// where each element's span opens and closes, where the handle is released
/// -- and repeating the middle of it would bury that. A map entry passes two
/// ranges, since its key and its value are drawn inside the one span.
List<String> element(SpanLabel label, List<String> ranges) => <String>[
  'more true',
  'start ${label.value}',
  for (final String range in ranges) 'draw $range',
  'stop',
];

/// [element] for the list generator, whose pins came first.
List<String> listElement(String range) =>
    element(SpanLabel.listElement, <String>[range]);

void main() {
  group('lists', () {
    test('draws as many elements as the engine asks for', () {
      final context = ScriptedContext(
        <int>[1, 2],
        more: <bool>[true, true, false],
      );

      final value = TestCase(context)
          .draw(lists(integers(min: 0, max: 9), maxLength: 4));

      expect(value, <int>[1, 2]);
    });

    test('builds the sequence in the shape the engine expects', () {
      final context = ScriptedContext(
        <int>[1, 2],
        more: <bool>[true, true, false],
      );

      TestCase(context).draw(lists(integers(min: 0, max: 9), maxLength: 4));

      // The collection is started inside the list's own span, so the length
      // decisions belong to the value the same way its elements do: a
      // shrinker that deleted the span would take the whole sequence, not
      // leave a length behind with nothing to count.
      expect(context.calls, <String>[
        'start ${SpanLabel.list.value}',
        'collection 0..4',
        ...listElement('0..9'),
        ...listElement('0..9'),
        'more false',
        'free',
        'stop',
      ]);
    });

    test('leaves the length to the engine when no maximum is given', () {
      final context = ScriptedContext(<int>[7], more: <bool>[true, false]);

      TestCase(context).draw(lists(integers(min: 0, max: 9), minLength: 1));

      expect(context.calls, contains('collection 1..*'));
    });

    test('reports the list, not the elements it is made of', () {
      final testCase = TestCase(
        ScriptedContext(<int>[4, 5], more: <bool>[true, true, false]),
      );

      testCase.draw(lists(integers(min: 0, max: 9)), name: 'xs');

      // Field by field rather than against a whole `Drawn`: a record compares
      // its fields with `==`, and for a `List` that is identity, so an
      // equality on the record would fail on the list it was handed back.
      expect(testCase.draws, hasLength(1));
      expect(testCase.draws.single.name, 'xs');
      expect(testCase.draws.single.value, <int>[4, 5]);
    });

    test('keeps repeated elements when uniqueness was not asked for', () {
      final context = ScriptedContext(
        <int>[3, 3],
        more: <bool>[true, true, false],
      );

      final value = TestCase(context).draw(lists(integers(min: 0, max: 9)));

      expect(value, <int>[3, 3]);
      expect(context.calls, isNot(contains('reject duplicate element')));
    });

    group('with uniqueness', () {
      test('refuses a repeat and takes what comes instead', () {
        final context = ScriptedContext(
          <int>[3, 3, 5],
          more: <bool>[true, true, true, false],
        );

        final value = TestCase(context)
            .draw(lists(integers(min: 0, max: 9), unique: true));

        expect(value, <int>[3, 5]);
      });

      test('refuses it only once its own span has closed', () {
        final context = ScriptedContext(
          <int>[3, 3, 5],
          more: <bool>[true, true, true, false],
        );

        TestCase(context).draw(lists(integers(min: 0, max: 9), unique: true));

        // The engine's protocol is that a rejection names the last element
        // produced, so the span that produced it has to be over first. A
        // reject inside the span would be about a value the engine does not
        // consider finished.
        expect(context.calls, <String>[
          'start ${SpanLabel.list.value}',
          'collection 0..*',
          ...listElement('0..9'),
          ...listElement('0..9'),
          'reject duplicate element',
          ...listElement('0..9'),
          'more false',
          'free',
          'stop',
        ]);
      });

      test('goes by what the element type calls equal', () {
        // Two lists that are equal to a reader and not to Dart: `List` has no
        // structural equality, so neither of these is a repeat of the other
        // and both are kept. Documented rather than worked around, since the
        // alternative is a second notion of equality this library invents.
        // One queue for both collections, so the answers interleave the way
        // the draws do: the outer list asks for an element, the inner one
        // asks twice to produce its single element, and so on.
        final context = ScriptedContext(
          <int>[1, 1],
          more: <bool>[true, true, false, true, true, false, false],
        );

        final value = TestCase(context).draw(
          lists(
            lists(integers(min: 0, max: 9), minLength: 1, maxLength: 1),
            unique: true,
          ),
        );

        expect(value, <List<int>>[
          <int>[1],
          <int>[1],
        ]);
      });
    });

    group('bounds', () {
      test('refuse a negative minimum where it was written', () {
        expect(
          () => lists(integers(), minLength: -1),
          throwsA(isA<RangeError>()),
        );
      });

      test('refuse a minimum above the maximum', () {
        expect(
          () => lists(integers(), minLength: 3, maxLength: 2),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('over a run', () {
      test('draws inside the requested length bounds', () {
        final values = drawEveryCase(
          openSession(),
          lists(integers(min: 0, max: 50), minLength: 1, maxLength: 4),
        );

        expect(values, isNotEmpty);
        expect(
          values.map((List<int> value) => value.length),
          everyElement(allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(4))),
        );
        // The engine choosing the length is the whole point of not drawing
        // one, so a run that produced a single length would mean the
        // collection was not driving anything.
        expect(
          values.map((List<int> value) => value.length).toSet(),
          hasLength(greaterThan(1)),
        );
      });

      test('draws exactly the length asked for when it is fixed', () {
        final values = drawEveryCase(
          openSession(),
          lists(integers(min: 0, max: 50), minLength: 3, maxLength: 3),
        );

        expect(values, isNotEmpty);
        expect(values.map((List<int> value) => value.length), everyElement(3));
      });

      test('produces the empty list when the bounds allow one', () {
        final values = drawEveryCase(
          openSession(),
          lists(integers(min: 0, max: 50), maxLength: 3),
        );

        expect(values.any((List<int> value) => value.isEmpty), isTrue);
      });

      test('terminates when the length is unbounded', () {
        final values = drawEveryCase(openSession(), lists(booleans()));

        expect(values, isNotEmpty);
      });

      test('produces a repeated element when nothing forbids one', () {
        // The witness behind the uniqueness tests: a plain list over a
        // narrow range does repeat itself, so `unique: true` never doing so
        // is a real claim about the rejection path and not about luck.
        final values = drawEveryCase(
          openSession(),
          lists(integers(min: 0, max: 3), minLength: 2),
        );

        expect(
          values.any((List<int> value) => value.toSet().length < value.length),
          isTrue,
        );
      });

      test('never repeats an element when uniqueness was asked for', () {
        // A range narrow enough that repeats are what the engine will mostly
        // produce: the rejection path is the one under test, so the test has
        // to make the engine take it.
        final values = drawEveryCase(
          openSession(),
          lists(integers(min: 0, max: 3), maxLength: 4, unique: true),
        );

        expect(values, isNotEmpty);
        expect(
          values,
          everyElement(
            predicate<List<int>>(
              (List<int> value) => value.toSet().length == value.length,
              'has no repeated element',
            ),
          ),
        );
      });

      test('does not count a refused element against the length', () {
        // Two distinct values out of two possible ones, so every case has to
        // reject its way past at least one repeat to get there. A rejection
        // that counted would leave lists of one element, or none.
        final values = drawEveryCase(
          openSession(),
          lists(booleans(), minLength: 2, maxLength: 2, unique: true),
        );

        expect(values, isNotEmpty);
        expect(values, everyElement(hasLength(2)));
        expect(
          values,
          everyElement(
            predicate<List<bool>>(
              (List<bool> value) => value.toSet().length == 2,
              'holds both booleans',
            ),
          ),
        );
      });

      test('ends the run rather than looping when uniqueness cannot '
          'be had', () async {
        // Three distinct booleans do not exist, so every case dies refusing
        // repeats, and the only way out is the engine noticing. What this
        // pins is that there is a way out: the reject loop ends in the
        // filtering health check, in bounded time, not in a hang a user
        // has to kill.
        await expectLater(
          runProperty((TestCase testCase) {
            testCase.draw(lists(booleans(), minLength: 3, unique: true));
          }, settings: caseSettings()),
          throwsA(
            isA<PropertyError>().having(
              (PropertyError error) => error.message,
              'message',
              contains('FilterTooMuch'),
            ),
          ),
        );
      });
    });
  });

  group('sets', () {
    test('draws as many distinct elements as the engine asks for', () {
      final context = ScriptedContext(
        <int>[1, 2],
        more: <bool>[true, true, false],
      );

      final value = TestCase(context).draw(sets(integers(min: 0, max: 9)));

      expect(value, <int>{1, 2});
    });

    test('builds the set in the shape the engine expects', () {
      final context = ScriptedContext(
        <int>[1, 2],
        more: <bool>[true, true, false],
      );

      TestCase(context).draw(sets(integers(min: 0, max: 9), maxLength: 4));

      expect(context.calls, <String>[
        'start ${SpanLabel.set.value}',
        'collection 0..4',
        ...element(SpanLabel.setElement, <String>['0..9']),
        ...element(SpanLabel.setElement, <String>['0..9']),
        'more false',
        'free',
        'stop',
      ]);
    });

    test('refuses a repeat once its own span has closed', () {
      final context = ScriptedContext(
        <int>[3, 3, 5],
        more: <bool>[true, true, true, false],
      );

      final value = TestCase(context).draw(sets(integers(min: 0, max: 9)));

      expect(value, <int>{3, 5});
      expect(context.calls, <String>[
        'start ${SpanLabel.set.value}',
        'collection 0..*',
        ...element(SpanLabel.setElement, <String>['0..9']),
        ...element(SpanLabel.setElement, <String>['0..9']),
        'reject duplicate element',
        ...element(SpanLabel.setElement, <String>['0..9']),
        'more false',
        'free',
        'stop',
      ]);
    });

    test('reports the set, not the elements it is made of', () {
      final testCase = TestCase(
        ScriptedContext(<int>[4, 5], more: <bool>[true, true, false]),
      );

      testCase.draw(sets(integers(min: 0, max: 9)), name: 'xs');

      expect(testCase.draws, hasLength(1));
      expect(testCase.draws.single.name, 'xs');
      expect(testCase.draws.single.value, <int>{4, 5});
    });

    group('bounds', () {
      test('refuse a negative minimum where it was written', () {
        expect(
          () => sets(integers(), minLength: -1),
          throwsA(isA<RangeError>()),
        );
      });

      test('refuse a minimum above the maximum', () {
        expect(
          () => sets(integers(), minLength: 3, maxLength: 2),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('over a run', () {
      test('draws inside the requested size bounds', () {
        final values = drawEveryCase(
          openSession(),
          sets(integers(min: 0, max: 50), minLength: 1, maxLength: 4),
        );

        expect(values, isNotEmpty);
        expect(
          values.map((Set<int> value) => value.length),
          everyElement(allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(4))),
        );
        expect(
          values.map((Set<int> value) => value.length).toSet(),
          hasLength(greaterThan(1)),
        );
      });

      test('reaches its minimum out of a narrow element range', () {
        // Three of the four booleans-and-a-bit are not available: two
        // distinct elements out of two possible ones means every case has to
        // refuse its way past a repeat, and a refusal that counted against
        // the size would leave a set that cannot reach two.
        final values = drawEveryCase(
          openSession(),
          sets(booleans(), minLength: 2, maxLength: 2),
        );

        expect(values, isNotEmpty);
        expect(values, everyElement(hasLength(2)));
      });

      test('terminates when the size is unbounded', () {
        final values = drawEveryCase(
          openSession(),
          sets(integers(min: 0, max: 50)),
        );

        expect(values, isNotEmpty);
      });

      test('ends the run rather than looping when the elements cannot '
          'fill it', () async {
        // The set the type system will happily ask for and no run can
        // produce: three distinct booleans. Every case refuses repeats
        // until the engine calls the filtering, which is the ending this
        // pins -- a verdict about the asking, in bounded time.
        await expectLater(
          runProperty((TestCase testCase) {
            testCase.draw(sets(booleans(), minLength: 3));
          }, settings: caseSettings()),
          throwsA(
            isA<PropertyError>().having(
              (PropertyError error) => error.message,
              'message',
              contains('FilterTooMuch'),
            ),
          ),
        );
      });
    });
  });

  group('maps', () {
    test('draws the key and the value of each entry', () {
      final context = ScriptedContext(
        <int>[1, 10, 2, 20],
        more: <bool>[true, true, false],
      );

      final value = TestCase(context)
          .draw(maps(integers(min: 0, max: 9), integers(min: 0, max: 99)));

      expect(value, <int, int>{1: 10, 2: 20});
    });

    test('builds each entry as one span, key and value inside it', () {
      final context = ScriptedContext(
        <int>[1, 10, 2, 20],
        more: <bool>[true, true, false],
      );

      TestCase(context).draw(
        maps(integers(min: 0, max: 9), integers(min: 0, max: 99), maxLength: 3),
      );

      // Both draws inside the one entry span, so an entry is a unit the
      // shrinker takes out whole: a key deleted without its value would be a
      // map with half an entry in it.
      expect(context.calls, <String>[
        'start ${SpanLabel.map.value}',
        'collection 0..3',
        ...element(SpanLabel.mapEntry, <String>['0..9', '0..99']),
        ...element(SpanLabel.mapEntry, <String>['0..9', '0..99']),
        'more false',
        'free',
        'stop',
      ]);
    });

    test('refuses a repeated key without drawing a value for it', () {
      final context = ScriptedContext(
        <int>[1, 10, 1, 2, 20],
        more: <bool>[true, true, true, false],
      );

      final value = TestCase(context)
          .draw(maps(integers(min: 0, max: 9), integers(min: 0, max: 99)));

      expect(value, <int, int>{1: 10, 2: 20});
      // The refused entry drew its key and stopped there: a value drawn for
      // an entry nothing will hold is entropy the shrinker has to work
      // through for no one.
      expect(context.calls, <String>[
        'start ${SpanLabel.map.value}',
        'collection 0..*',
        ...element(SpanLabel.mapEntry, <String>['0..9', '0..99']),
        ...element(SpanLabel.mapEntry, <String>['0..9']),
        'reject duplicate key',
        ...element(SpanLabel.mapEntry, <String>['0..9', '0..99']),
        'more false',
        'free',
        'stop',
      ]);
    });

    test('keeps the first value a repeated key was given', () {
      final context = ScriptedContext(
        <int>[1, 10, 1, 2, 20],
        more: <bool>[true, true, true, false],
      );

      final value = TestCase(context)
          .draw(maps(integers(min: 0, max: 9), integers(min: 0, max: 99)));

      // The refusal is not an overwrite: what the map holds for 1 is the
      // value drawn with it, not one drawn later for a key that was turned
      // away.
      expect(value[1], 10);
    });

    test('reports the map, not the entries it is made of', () {
      final testCase = TestCase(
        ScriptedContext(<int>[4, 40], more: <bool>[true, false]),
      );

      testCase.draw(
        maps(integers(min: 0, max: 9), integers(min: 0, max: 99)),
        name: 'xs',
      );

      expect(testCase.draws, hasLength(1));
      expect(testCase.draws.single.name, 'xs');
      expect(testCase.draws.single.value, <int, int>{4: 40});
    });

    group('bounds', () {
      test('refuse a negative minimum where it was written', () {
        expect(
          () => maps(integers(), integers(), minLength: -1),
          throwsA(isA<RangeError>()),
        );
      });

      test('refuse a minimum above the maximum', () {
        expect(
          () => maps(integers(), integers(), minLength: 3, maxLength: 2),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('over a run', () {
      test('draws inside the requested size bounds, with distinct keys', () {
        final values = drawEveryCase(
          openSession(),
          maps(
            integers(min: 0, max: 50),
            integers(min: 0, max: 50),
            minLength: 1,
            maxLength: 4,
          ),
        );

        expect(values, isNotEmpty);
        expect(
          values.map((Map<int, int> value) => value.length),
          everyElement(allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(4))),
        );
        expect(
          values.map((Map<int, int> value) => value.length).toSet(),
          hasLength(greaterThan(1)),
        );
      });

      test('reaches its minimum out of a narrow key range', () {
        final values = drawEveryCase(
          openSession(),
          maps(booleans(), integers(min: 0, max: 50), minLength: 2),
        );

        expect(values, isNotEmpty);
        expect(values, everyElement(hasLength(greaterThanOrEqualTo(2))));
      });

      test('terminates when the size is unbounded', () {
        final values = drawEveryCase(
          openSession(),
          maps(integers(min: 0, max: 50), booleans()),
        );

        expect(values, isNotEmpty);
      });
    });
  });
}
