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

    test('reaches both ends of a bounded range', () {
      final values = drawEveryCase(openSession(), integers(min: -20, max: 20));

      // Bounds are where bugs live, so the engine leans on them rather than
      // leaving them to luck. A run that never touched either end would
      // mean that weighting was lost somewhere between here and the draw.
      expect(values, contains(-20));
      expect(values, contains(20));
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

  group('booleans', () {
    test('produces both answers across a run', () {
      final values = drawEveryCase(openSession(), booleans());

      expect(values, contains(isTrue));
      expect(values, contains(isFalse));
    });

    test('leans the way its probability says', () {
      final always = drawEveryCase(openSession(), booleans(probability: 1));
      final never = drawEveryCase(openSession(), booleans(probability: 0));

      expect(always, everyElement(isTrue));
      expect(never, everyElement(isFalse));
    });

    test('passes the probability through as given', () {
      final context = ScriptedContext(<int>[], booleans: <bool>[true]);

      TestCase(context).draw(booleans(probability: 0.25));

      expect(context.calls, <String>['draw boolean 0.25']);
    });

    test('refuses a probability that is not one, where it was written', () {
      for (final bad in <double>[-0.1, 1.5, double.nan]) {
        expect(
          () => booleans(probability: bad),
          throwsA(
            isA<RangeError>().having(
              (RangeError error) => error.message,
              'message',
              contains('must be in 0..1'),
            ),
          ),
          reason: '$bad is not a probability',
        );
      }
    });
  });

  group('doubles', () {
    test('draws inside the requested bounds', () {
      final values = drawEveryCase(openSession(), doubles(min: -2.5, max: 7.5));

      expect(values, isNotEmpty);
      expect(values, everyElement(inInclusiveRange(-2.5, 7.5)));
    });

    test('produces NaN when nothing was bounded', () {
      final values = drawEveryCase(openSession(), doubles(), testCases: 200);

      expect(
        values.where((double value) => value.isNaN),
        isNotEmpty,
        reason:
            'an unbounded double includes NaN, and a run of two hundred '
            'that never saw one would mean the default resolved the other way',
      );
    });

    test('produces both infinities when nothing was bounded', () {
      final values = drawEveryCase(openSession(), doubles(), testCases: 300);

      // The other two edges of the type. Allowing infinity is checked on
      // the wire below; that a run actually reaches both is the claim a
      // frontend can quietly lose, and the one a bug at an edge needs.
      expect(values, contains(double.infinity));
      expect(values, contains(double.negativeInfinity));
    });

    test('holds an excluded infinite endpoint out of the run', () {
      // The default minimum is negative infinity, so excluding it is a
      // legal ask about a single value: everything else stays, including
      // the other infinity, and only the named endpoint goes. The run
      // above is the control that reaches both.
      final values = drawEveryCase(
        openSession(),
        doubles(excludeMin: true),
        testCases: 300,
      );

      expect(values, isNot(contains(double.negativeInfinity)));
      expect(values, contains(double.infinity));
    });

    test('keeps NaN out once a bound is given', () {
      final values = drawEveryCase(
        openSession(),
        doubles(min: 0),
        testCases: 200,
      );

      expect(values, everyElement(isNot(isNaN)));
      expect(values, everyElement(greaterThanOrEqualTo(0)));
    });

    test('keeps NaN out when asked, even unbounded', () {
      final values = drawEveryCase(
        openSession(),
        doubles(allowNan: false),
        testCases: 200,
      );

      expect(values, everyElement(isNot(isNaN)));
    });

    test('resolves the defaults the way Hypothesis does', () {
      // The one thing a run can only answer statistically: what an unset
      // allowNan and allowInfinity became.
      String constraintFor(Generator<double> generator) {
        final context = ScriptedContext(<int>[], floats: <double>[0]);
        TestCase(context).draw(generator);
        return context.calls.single;
      }

      expect(
        constraintFor(doubles()),
        contains('nan=true inf=true'),
        reason: 'both ends open: nothing to violate',
      );
      expect(
        constraintFor(doubles(min: 0)),
        contains('nan=false inf=true'),
        reason:
            'NaN would walk through the bound it compares false against, '
            'but the open end can still reach infinity',
      );
      expect(
        constraintFor(doubles(min: 0, max: 1)),
        contains('nan=false inf=false'),
      );
      expect(
        constraintFor(doubles(allowNan: true, allowInfinity: false)),
        contains('nan=true inf=false'),
        reason: 'said explicitly, so nothing is resolved',
      );
    });

    test('passes its exclusions through', () {
      final context = ScriptedContext(<int>[], floats: <double>[0.5]);

      TestCase(context)
          .draw(doubles(min: 0, max: 1, excludeMin: true, excludeMax: true));

      expect(context.calls.single, contains('exclude=true/true'));
    });

    test('holds an excluded bound open over a run', () {
      final values = drawEveryCase(
        openSession(),
        doubles(min: 0, max: 1, excludeMin: true),
        testCases: 200,
      );

      expect(values, isNotEmpty);
      expect(values, everyElement(greaterThan(0)));
      expect(values, everyElement(lessThanOrEqualTo(1)));
    });

    test('refuses a range only signed zero tells apart', () {
      // -0.0 == 0.0, so `>` reads this as a range in order and the engine
      // meets it as an internal error. It is an inverted range: the engine
      // orders the two zeros apart even though Dart's operators do not.
      expect(
        () => doubles(min: 0.0, max: -0.0),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('exceeds max'),
          ),
        ),
      );
      expect(doubles(min: -0.0, max: 0.0), isA<Generator<double>>());
    });

    test('refuses an exclusion that empties a single-value range', () {
      expect(
        () => doubles(min: 1, max: 1, excludeMin: true),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('leaves nothing to draw'),
          ),
        ),
      );
      expect(
        () => doubles(
          min: double.infinity,
          max: double.infinity,
          excludeMax: true,
        ),
        throwsArgumentError,
        reason:
            'the engine answers this one with the value it was told to '
            'exclude, which is worse than refusing it',
      );
      expect(doubles(min: 1, max: 1), isA<Generator<double>>());
    });

    test('refuses NaN and infinity where no bound could hold them', () {
      // The engine refuses both, on every case rather than at the line that
      // asked, so they are refused here instead.
      expect(
        () => doubles(min: 0, max: 1, allowNan: true),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('needs both bounds open'),
          ),
        ),
      );
      expect(() => doubles(min: 0, allowNan: true), throwsArgumentError);
      expect(
        () => doubles(min: 0, max: 1, allowInfinity: true),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('needs an open bound'),
          ),
        ),
      );
    });

    test('allows what the bounds can still hold', () {
      // The other side of the same rule: turning either off is always
      // allowed, and turning them on is allowed where a bound is open.
      expect(doubles(allowNan: true), isA<Generator<double>>());
      expect(
        doubles(min: 0, max: 1, allowNan: false),
        isA<Generator<double>>(),
      );
      expect(doubles(min: 0, allowInfinity: true), isA<Generator<double>>());
      expect(
        doubles(min: 0, max: 1, allowInfinity: false),
        isA<Generator<double>>(),
      );
    });

    test('refuses a bound that is not a number', () {
      expect(
        () => doubles(min: double.nan),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('is not a number'),
          ),
        ),
      );
      expect(() => doubles(max: double.nan), throwsArgumentError);
    });

    test('refuses an inverted range where it was written', () {
      expect(
        () => doubles(min: 1, max: 0),
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

  group('bigIntegers', () {
    test('draws inside the requested bounds', () {
      final low = BigInt.parse('-100000000000000000000000000');
      final high = BigInt.parse('100000000000000000000000000');
      final values = drawEveryCase(
        openSession(),
        bigIntegers(min: low, max: high),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          predicate<BigInt>((BigInt v) => v >= low && v <= high, 'in range'),
        ),
      );
    });

    test('reaches past what a machine word holds when unbounded', () {
      final values = drawEveryCase(openSession(), bigIntegers());

      // The claim that matters: an unbounded big integer is wide, rather
      // than an int64 draw wearing a BigInt.
      final int64Max = BigInt.parse('9223372036854775807');
      expect(
        values,
        contains(predicate<BigInt>((BigInt v) => v.abs() > int64Max, 'wide')),
      );
    });

    test('takes the narrow path when both bounds fit a machine word', () {
      // The engine has two integer draws and picks by width; bounds this
      // small go down the fixed-width one. Proven at L2 already, and
      // re-proven here because the public generator is what chooses the
      // bounds it is proven with.
      final values = drawEveryCase(
        openSession(),
        bigIntegers(min: BigInt.zero, max: BigInt.from(10)),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          predicate<BigInt>(
            (BigInt v) => v >= BigInt.zero && v <= BigInt.from(10),
            'in range',
          ),
        ),
      );
    });

    test('passes its bounds through as given', () {
      final context = ScriptedContext(
        <int>[],
        bigIntegers: <BigInt>[BigInt.zero],
      );

      TestCase(context)
          .draw(bigIntegers(min: BigInt.from(-5), max: BigInt.from(5)));

      expect(context.calls, <String>['draw big -5..5']);
    });

    test('refuses an inverted range where it was written', () {
      expect(
        () => bigIntegers(min: BigInt.two, max: BigInt.one),
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

  group('durations', () {
    test('draws inside the requested bounds', () {
      final values = drawEveryCase(
        openSession(),
        durations(
          min: const Duration(seconds: 1),
          max: const Duration(minutes: 1),
        ),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          predicate<Duration>(
            (Duration d) =>
                d >= const Duration(seconds: 1) &&
                d <= const Duration(minutes: 1),
            'in range',
          ),
        ),
      );
    });

    test('reaches both directions when unbounded', () {
      final values = drawEveryCase(openSession(), durations());

      expect(values, contains(greaterThan(Duration.zero)));
      expect(values, contains(lessThan(Duration.zero)));
    });

    test('draws whole microseconds, over the whole microsecond range', () {
      final context = ScriptedContext(<int>[1500]);

      final value = TestCase(context).draw(durations());

      expect(value, const Duration(microseconds: 1500));
      expect(context.calls, <String>[
        'draw ${-0x8000000000000000}..${0x7fffffffffffffff}',
      ]);
    });

    test('refuses an inverted range where it was written', () {
      expect(
        () => durations(
          min: const Duration(days: 2),
          max: const Duration(days: 1),
        ),
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
