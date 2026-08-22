@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_case.dart';
import '../support/scripted_context.dart';
import '../support/tree.dart';

/// A session for the group below, closed when its last test ends.
Libhegel openSession() {
  final session = Libhegel.open();
  addTearDown(session.dispose);
  return session;
}

void main() {
  group('composite', () {
    test('groups its draws under a span of its own', () {
      final context = ScriptedContext(<int>[2, 7]);

      final value = TestCase(context).draw(
        composite((TestCase testCase) {
          final low = testCase.draw(integers(min: 0, max: 9));
          final high = testCase.draw(integers(min: low, max: 9));
          return (low, high);
        }),
      );

      expect(value, (2, 7));
      expect(context.calls, <String>[
        'start ${SpanLabel.firstAvailable}',
        'draw 0..9',
        'draw 2..9',
        'stop',
      ]);
    });

    test('mints a label the engine has not reserved', () {
      expect(
        SpanLabel.firstAvailable,
        greaterThan(SpanLabel.concurrency.value),
      );
    });

    test('reports what it built, not what it built it out of', () {
      final testCase = TestCase(ScriptedContext(<int>[1, 2]));

      testCase.draw(
        composite(
          (TestCase inner) =>
              inner.draw(integers(min: 0, max: 9)) +
              inner.draw(integers(min: 0, max: 9)),
        ),
        name: 'total',
      );

      expect(testCase.draws, <Drawn>[(name: 'total', value: 3)]);
    });

    test('nests, one span per composite', () {
      final context = ScriptedContext(<int>[1, 2, 3]);
      final inner = composite(
        (TestCase testCase) => testCase.draw(integers(min: 0, max: 9)),
      );

      final value = TestCase(context).draw(
        composite(
          (TestCase testCase) =>
              testCase.draw(inner) +
              testCase.draw(inner) +
              testCase.draw(inner),
        ),
      );

      expect(value, 6);
      expect(context.calls, <String>[
        'start ${SpanLabel.firstAvailable}',
        for (int i = 0; i < 3; i++) ...<String>[
          'start ${SpanLabel.firstAvailable}',
          'draw 0..9',
          'stop',
        ],
        'stop',
      ]);
    });

    test('rejects the case when what it built assumed something false', () {
      final testCase = TestCase(ScriptedContext(<int>[5]));

      expect(
        () => testCase.draw(
          composite((TestCase inner) {
            final value = inner.draw(integers(min: 0, max: 9));
            inner.assume(value.isEven);
            return value;
          }),
        ),
        throwsA(isA<AssumptionFailed>()),
      );
    });

    test('builds values whose parts depend on each other, over a run', () {
      final ranges = drawEveryCase(
        openSession(),
        composite((TestCase testCase) {
          final low = testCase.draw(integers(min: 0, max: 100));
          final high = testCase.draw(integers(min: low, max: 200));
          return (low, high);
        }),
      );

      expect(ranges, isNotEmpty);
      expect(
        ranges,
        everyElement(
          isA<(int, int)>().having(
            ((int, int) range) => range.$1 <= range.$2,
            'low no higher than high',
            isTrue,
          ),
        ),
      );
    });
  });

  group('deferred', () {
    test('draws from whatever it was defined as', () {
      final generator = deferred<int>();
      generator.define(integers(min: 0, max: 9));

      final context = ScriptedContext(<int>[4]);

      expect(TestCase(context).draw(generator), 4);
      expect(
        context.calls,
        <String>['draw 0..9'],
        reason:
            'no span of its own: it is a name for another generator rather '
            'than a value made of parts',
      );
    });

    test('refuses to be defined twice', () {
      final generator = deferred<int>()..define(integers(min: 0, max: 9));

      expect(
        () => generator.define(integers(min: 0, max: 9)),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('already defined'),
          ),
        ),
      );
    });

    test('refuses to be drawn from before it is defined', () {
      expect(
        () => TestCase(ScriptedContext(<int>[1])).draw(deferred<int>()),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('has not been defined yet'),
          ),
        ),
      );
    });

    test('builds a recursive value that terminates', () {
      final grown = drawEveryCase(openSession(), trees(), testCases: 50);

      expect(grown, isNotEmpty);
      expect(
        grown.map((Tree tree) => tree.leaves),
        contains(greaterThan(1)),
        reason: 'a recursion that never recursed would prove nothing',
      );
      // The engine's choice budget is what ends the recursion, so this is
      // the assertion that it does end: every case finished, and none of
      // them ran the process out of stack on the way.
      expect(grown, hasLength(greaterThan(1)));
    });
  });
}
