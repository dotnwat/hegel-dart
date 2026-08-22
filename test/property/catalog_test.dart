@TestOn('vm')
library;

import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/property/generator.dart';
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

  group('just', () {
    test('produces its value without drawing anything', () {
      final context = ScriptedContext(<int>[]);

      expect(TestCase(context).draw(just('always')), 'always');
      expect(
        context.calls,
        isEmpty,
        reason:
            'not even a span: there is nothing to group and nothing to '
            'shrink, and a choice spent here is one the shrinker has to '
            'work through everywhere else',
      );
    });

    test('produces the same value on every case of a run', () {
      final values = drawEveryCase(openSession(), just(7));

      expect(values, isNotEmpty);
      expect(values, everyElement(7));
    });
  });

  group('sampledFrom', () {
    test('picks by an index drawn over the whole list', () {
      final context = ScriptedContext(<int>[2]);

      final value = TestCase(context)
          .draw(sampledFrom(<String>['ant', 'bee', 'cow']));

      expect(value, 'cow');
      expect(context.calls, <String>[
        'start ${SpanLabel.sampledFrom.value}',
        'draw 0..2',
        'stop',
      ]);
    });

    test('refuses an empty list where it was written', () {
      expect(
        () => sampledFrom(<int>[]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('is empty'),
          ),
        ),
      );
    });

    test('keeps the values it was given, not the list they came in', () {
      final values = <String>['ant', 'bee'];
      final generator = sampledFrom(values);
      values.add('cow');

      // Drawing index 1 twice: if the generator held the caller's list, the
      // second draw would be over a list of three and could reach 'cow'.
      expect(TestCase(ScriptedContext(<int>[1])).draw(generator), 'bee');
      expect(
        () => TestCase(ScriptedContext(<int>[2])).draw(generator),
        throwsRangeError,
      );
    });

    test('reaches every value across a run', () {
      final values = drawEveryCase(
        openSession(),
        sampledFrom(<String>['ant', 'bee', 'cow']),
      );

      expect(values.toSet(), <String>{'ant', 'bee', 'cow'});
    });
  });

  group('oneOf', () {
    test('draws the chosen option inside the span that chose it', () {
      final context = ScriptedContext(<int>[1, 5]);

      final value = TestCase(context).draw(
        oneOf(<Generator<int>>[
          integers(min: 0, max: 9),
          integers(min: 0, max: 9).map((int n) => -n),
        ]),
      );

      expect(value, -5);
      expect(context.calls, <String>[
        'start ${SpanLabel.oneOf.value}',
        'draw 0..1',
        'start ${SpanLabel.mapped.value}',
        'draw 0..9',
        'stop',
        'stop',
      ]);
    });

    test('refuses an empty list of options where it was written', () {
      expect(
        () => oneOf(<Generator<int>>[]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('is empty'),
          ),
        ),
      );
    });

    test('takes every option across a run', () {
      final values = drawEveryCase(
        openSession(),
        oneOf(<Generator<int>>[
          just(-1),
          integers(min: 10, max: 19),
          integers(min: 100, max: 109),
        ]),
      );

      expect(values, contains(-1));
      expect(values, contains(inInclusiveRange(10, 19)));
      expect(values, contains(inInclusiveRange(100, 109)));
    });
  });

  group('optional', () {
    test('produces null without drawing the value it did not need', () {
      final context = ScriptedContext(<int>[0]);

      expect(
        TestCase(context).draw(optional(integers(min: 0, max: 9))),
        isNull,
      );
      expect(context.calls, <String>[
        'start ${SpanLabel.optional.value}',
        'draw 0..1',
        'stop',
      ]);
    });

    test('produces the value when the choice went the other way', () {
      final context = ScriptedContext(<int>[1, 4]);

      expect(TestCase(context).draw(optional(integers(min: 0, max: 9))), 4);
    });

    test('produces both a value and null across a run', () {
      final values = drawEveryCase(
        openSession(),
        optional(integers(min: 0, max: 9)),
      );

      expect(values, contains(isNull));
      expect(values, contains(isNotNull));
    });
  });

  group('tuples', () {
    test('draws its parts in order, inside one span', () {
      final context = ScriptedContext(<int>[1, 2]);

      final (first, second) = TestCase(context)
          .draw(tuple2(integers(min: 0, max: 9), integers(min: 10, max: 19)));

      expect((first, second), (1, 2));
      expect(context.calls, <String>[
        'start ${SpanLabel.tuple.value}',
        'draw 0..9',
        'draw 10..19',
        'stop',
      ]);
    });

    test('reports the whole tuple as the one value it is', () {
      final testCase = TestCase(ScriptedContext(<int>[1, 2]));

      testCase.draw(
        tuple2(integers(min: 0, max: 9), integers(min: 0, max: 9)),
        name: 'pair',
      );

      expect(testCase.draws, <Drawn>[(name: 'pair', value: (1, 2))]);
    });

    test('carries the types of its parts', () {
      final context = ScriptedContext(<int>[3, 1, 8]);

      final (count, flag, letter) = TestCase(context).draw(
        tuple3(
          integers(min: 0, max: 9),
          sampledFrom(<bool>[false, true]),
          integers(min: 0, max: 9).map((int n) => 'x$n'),
        ),
      );

      expect(count, 3);
      expect(flag, isTrue);
      expect(letter, 'x8');
    });

    test('goes as far as four parts', () {
      final context = ScriptedContext(<int>[1, 2, 3, 4]);

      final drawn = TestCase(context).draw(
        tuple4(
          integers(min: 0, max: 9),
          integers(min: 0, max: 9),
          integers(min: 0, max: 9),
          integers(min: 0, max: 9),
        ),
      );

      expect(drawn, (1, 2, 3, 4));
      expect(
        context.calls.where((String call) => call.startsWith('start')),
        hasLength(1),
      );
    });

    test('keeps every part inside its own bounds over a run', () {
      final values = drawEveryCase(
        openSession(),
        tuple2(integers(min: 0, max: 9), integers(min: 100, max: 109)),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          isA<(int, int)>()
              .having(
                ((int, int) pair) => pair.$1,
                'first',
                inInclusiveRange(0, 9),
              )
              .having(
                ((int, int) pair) => pair.$2,
                'second',
                inInclusiveRange(100, 109),
              ),
        ),
      );
    });
  });
}
