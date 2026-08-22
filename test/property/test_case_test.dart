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

void main() {
  group('a test case', () {
    test('records the values the body drew, in order', () {
      final testCase = TestCase(ScriptedContext(<int>[7, 3]));

      expect(testCase.draw(integers(min: 0, max: 9)), 7);
      expect(testCase.draw(integers(min: 0, max: 9)), 3);

      expect(testCase.draws, <Drawn>[
        (name: null, value: 7),
        (name: null, value: 3),
      ]);
    });

    test('records the name the body gave a draw', () {
      final testCase = TestCase(ScriptedContext(<int>[7]));

      testCase.draw(integers(min: 0, max: 9), name: 'width');

      expect(testCase.draws, <Drawn>[(name: 'width', value: 7)]);
    });

    test('passes the generator its bounds', () {
      final context = ScriptedContext(<int>[0]);
      TestCase(context).draw(integers(min: -5, max: 5));

      expect(context.calls, <String>['draw -5..5']);
    });

    test('leaves out draws that compose a larger value', () {
      final context = ScriptedContext(<int>[1, 2, 3]);
      final testCase = TestCase(context);

      final composed = testCase.span(SpanLabel.list, () {
        return <int>[
          testCase.draw(integers(min: 0, max: 9)),
          testCase.draw(integers(min: 0, max: 9)),
        ];
      });
      testCase.draw(integers(min: 0, max: 9));

      expect(composed, <int>[1, 2]);
      // The list is not among them either: only what the body drew is, and
      // the body drew the list through a generator that had not been written
      // yet at this point in the package's history.
      expect(testCase.draws, <Drawn>[(name: null, value: 3)]);
      expect(context.calls, <String>[
        'start ${SpanLabel.list.value}',
        'draw 0..9',
        'draw 0..9',
        'stop',
        'draw 0..9',
      ]);
    });

    test('counts nested spans, so only the outermost value is recorded', () {
      final testCase = TestCase(ScriptedContext(<int>[1]));

      testCase.span(SpanLabel.list, () {
        testCase.span(SpanLabel.listElement, () {
          testCase.draw(integers(min: 0, max: 9));
        });
      });

      expect(testCase.draws, isEmpty);
    });

    test('closes a span whose body threw, and keeps counting from there', () {
      final context = ScriptedContext(<int>[4]);
      final testCase = TestCase(context);

      expect(
        () => testCase.span<void>(SpanLabel.filter, () => throw StateError('')),
        throwsStateError,
      );
      testCase.draw(integers(min: 0, max: 9));

      expect(context.calls, <String>[
        'start ${SpanLabel.filter.value}',
        'stop',
        'draw 0..9',
      ]);
      expect(testCase.draws, <Drawn>[(name: null, value: 4)]);
    });

    test('keeps an attempt its keeper took, and says so', () {
      final context = ScriptedContext(<int>[6]);
      final testCase = TestCase(context);

      final (:kept, :value) = testCase.attempt(
        SpanLabel.filter,
        () => testCase.draw(integers(min: 0, max: 9)),
        keep: (int drawn) => drawn.isEven,
      );

      expect(kept, isTrue);
      expect(value, 6);
      expect(context.calls, <String>[
        'start ${SpanLabel.filter.value}',
        'draw 0..9',
        'stop',
      ]);
    });

    test('discards an attempt its keeper turned down', () {
      final context = ScriptedContext(<int>[5]);
      final testCase = TestCase(context);

      final (:kept, :value) = testCase.attempt(
        SpanLabel.filter,
        () => testCase.draw(integers(min: 0, max: 9)),
        keep: (int drawn) => drawn.isEven,
      );

      expect(kept, isFalse);
      // Handed back even so: whoever asked decides what to do with a
      // rejected value, and a nullable generator's null is not a rejection.
      expect(value, 5);
      expect(context.calls.last, 'discard');
    });

    test('discards an attempt whose body threw, and closes it once', () {
      final context = ScriptedContext(<int>[]);
      final testCase = TestCase(context);

      expect(
        () => testCase.attempt<int>(
          SpanLabel.filter,
          () => throw StateError(''),
          keep: (int drawn) => true,
        ),
        throwsStateError,
      );

      expect(context.calls, <String>[
        'start ${SpanLabel.filter.value}',
        'discard',
      ]);
    });

    test('leaves an attempt\'s draws out of the report', () {
      final testCase = TestCase(ScriptedContext(<int>[3]));

      testCase.attempt(
        SpanLabel.filter,
        () => testCase.draw(integers(min: 0, max: 9)),
        keep: (int drawn) => true,
      );

      expect(testCase.draws, isEmpty);
    });

    test('records notes as the text they were at the time', () {
      final notes = StringBuffer('before');
      final testCase = TestCase(ScriptedContext(<int>[]));

      testCase.note(notes);
      notes.write(' and after');
      testCase.note(null);

      expect(testCase.notes, <String>['before', 'null']);
    });

    test('rejects the case when an assumption does not hold', () {
      final testCase = TestCase(ScriptedContext(<int>[]));

      expect(() => testCase.assume(false), throwsA(isA<AssumptionFailed>()));
    });

    test('carries on when an assumption holds', () {
      final testCase = TestCase(ScriptedContext(<int>[8]));

      testCase.assume(true);

      expect(testCase.draw(integers(min: 0, max: 9)), 8);
    });
  });

  group('a test case over the engine', () {
    // The scripted context pins the bookkeeping; this pins that the seam is
    // wired to a real engine. What it cannot pin is the engine rejecting an
    // unbalanced span -- checked, and it does not: it tolerates one left
    // open at completion. So the span discipline is this layer's to keep,
    // and shrink quality is what will notice if it stops keeping it.
    test('draws inside a span the engine accepts, and reports the whole', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);

      final sums = <int>[];
      driveCases(session, (TestCase testCase) {
        final pair = testCase.span<int>(SpanLabel.tuple, () {
          return testCase.draw(integers(min: 0, max: 9)) +
              testCase.draw(integers(min: 0, max: 9));
        });
        sums.add(pair);
        expect(testCase.draws, isEmpty);
      }, testCases: 20);

      expect(sums, hasLength(greaterThan(1)));
      expect(sums, everyElement(inInclusiveRange(0, 18)));
    });
  });
}
