@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_case.dart';

/// A [DrawContext] that answers from a script and records what it was asked.
///
/// The engine cannot be asked to hand back a particular value at a particular
/// point, which is exactly what pinning the bookkeeping around a draw needs.
final class ScriptedContext implements DrawContext {
  ScriptedContext(this.integers);

  /// The values [drawInteger] returns, in order.
  final List<int> integers;

  /// Every call made, as text, so a test can pin the order as well as the
  /// count -- a span closed before its body ran would otherwise look right.
  final List<String> calls = <String>[];

  int _next = 0;

  @override
  int drawInteger({required int min, required int max}) {
    calls.add('draw $min..$max');
    return integers[_next++];
  }

  @override
  void startSpan(SpanLabel label) => calls.add('start ${label.value}');

  @override
  void stopSpan() => calls.add('stop');
}

void main() {
  group('a test case', () {
    test('records the values the body drew, in order', () {
      final testCase = TestCase(ScriptedContext(<int>[7, 3]));

      expect(testCase.draw(integers(min: 0, max: 9)), 7);
      expect(testCase.draw(integers(min: 0, max: 9)), 3);

      expect(testCase.draws, <int>[7, 3]);
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
      expect(testCase.draws, <int>[3]);
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
      expect(testCase.draws, <int>[4]);
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
