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

/// A context whose every draw ends the case with [signal].
///
/// The engine latches the signal that ended a case and re-raises it on the
/// next draw, so a combinator that retried past one would spin against a case
/// that is already over. This is that case, without the engine.
final class _AbortedContext implements DrawContext {
  _AbortedContext(this.signal);

  /// What every draw throws.
  final Object signal;

  /// Every call made, so a test can show that no retry followed.
  final List<String> calls = <String>[];

  @override
  int drawInteger({required int min, required int max}) {
    calls.add('draw');
    throw signal;
  }

  @override
  void startSpan(SpanLabel label) => calls.add('start ${label.value}');

  @override
  void stopSpan({bool discard = false}) =>
      calls.add(discard ? 'discard' : 'stop');
}

/// A session for the group below, closed when its last test ends.
Libhegel openSession() {
  final session = Libhegel.open();
  addTearDown(session.dispose);
  return session;
}

void main() {
  group('map', () {
    test('hands the source value to the transform', () {
      final testCase = TestCase(ScriptedContext(<int>[6]));

      expect(testCase.draw(integers(min: 0, max: 9).map((int n) => n * 3)), 18);
    });

    test('draws the source inside a mapped span', () {
      final context = ScriptedContext(<int>[1]);

      TestCase(context).draw(integers(min: 0, max: 9).map((int n) => '$n'));

      expect(context.calls, <String>[
        'start ${SpanLabel.mapped.value}',
        'draw 0..9',
        'stop',
      ]);
    });

    test('reports the mapped value rather than what it was made of', () {
      final testCase = TestCase(ScriptedContext(<int>[4]));

      testCase.draw(integers(min: 0, max: 9).map((int n) => n * 2), name: 'x');

      expect(testCase.draws, <Drawn>[(name: 'x', value: 8)]);
    });

    test('composes, one span for each map', () {
      final context = ScriptedContext(<int>[2]);

      final value = TestCase(
        context,
      ).draw(integers(min: 0, max: 9).map((int n) => n + 1).map((int n) => -n));

      expect(value, -3);
      expect(context.calls, <String>[
        'start ${SpanLabel.mapped.value}',
        'start ${SpanLabel.mapped.value}',
        'draw 0..9',
        'stop',
        'stop',
      ], reason: 'the outer map composes the inner one, so it encloses it');
    });

    test('transforms every value of a whole run', () {
      final values = drawEveryCase(
        openSession(),
        integers(min: 0, max: 9).map((int n) => n * 2),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(isA<int>().having((int n) => n.isEven, 'even', isTrue)),
      );
      expect(values, everyElement(inInclusiveRange(0, 18)));
    });
  });

  group('where', () {
    test('takes the first value the predicate accepts', () {
      final context = ScriptedContext(<int>[5, 4]);

      final value = TestCase(context)
          .draw(integers(min: 0, max: 9).where((int n) => n.isEven));

      expect(value, 4);
      expect(context.calls, <String>[
        'start ${SpanLabel.filter.value}',
        'draw 0..9',
        // Discarded rather than closed: the engine retries from here, so the
        // choices behind the rejected 5 are not left in the case.
        'discard',
        'start ${SpanLabel.filter.value}',
        'draw 0..9',
        'stop',
      ]);
    });

    test('keeps the value where the predicate holds first time', () {
      final context = ScriptedContext(<int>[8]);

      expect(
        TestCase(context).draw(integers(min: 0, max: 9).where((int n) => true)),
        8,
      );
      expect(context.calls, hasLength(3));
    });

    test('rejects the case after three attempts', () {
      final context = ScriptedContext(<int>[1, 3, 5, 7]);

      expect(
        () =>
            TestCase(context)
                .draw(integers(min: 0, max: 9).where((int n) => n.isEven)),
        throwsA(isA<AssumptionFailed>()),
      );
      expect(
        context.calls.where((String call) => call == 'draw 0..9'),
        hasLength(3),
        reason: 'three, and the fourth value in the script is untouched',
      );
      expect(
        context.calls.where((String call) => call == 'discard'),
        hasLength(3),
      );
    });

    test('does not retry a case the engine has already ended', () {
      final context = _AbortedContext(const StopTest());

      expect(
        () =>
            TestCase(context)
                .draw(integers(min: 0, max: 9).where((int n) => true)),
        throwsA(isA<StopTest>()),
        reason:
            'the signal is the case ending, not a value being turned down; '
            'retrying would draw against a case that is over',
      );
      expect(
        context.calls.where((String call) => call == 'draw'),
        hasLength(1),
      );
    });

    test('does not retry a draw that rejected the case itself', () {
      // What a self-rejecting draw looks like from here: a generator that
      // gave up on the case rather than a value the predicate turned down.
      final context = _AbortedContext(const AssumptionFailed());

      expect(
        () =>
            TestCase(context)
                .draw(integers(min: 0, max: 9).where((int n) => true)),
        throwsA(isA<AssumptionFailed>()),
      );
      expect(
        context.calls.where((String call) => call == 'draw'),
        hasLength(1),
      );
    });

    test('yields only values the predicate accepts, over a whole run', () {
      final values = drawEveryCase(
        openSession(),
        integers(min: 0, max: 100).where((int n) => n % 3 == 0),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(isA<int>().having((int n) => n % 3, 'n % 3', 0)),
      );
    });

    test('rejects the cases it cannot satisfy, rather than failing them', () {
      // One value in a hundred, so almost every case is rejected: the run
      // still finishes, and the few values that come back all hold.
      final values = drawEveryCase(
        openSession(),
        integers(min: 0, max: 99).where((int n) => n == 7),
        testCases: 20,
      );

      expect(values, everyElement(7));
    });
  });

  group('flatMap', () {
    test('draws from the generator the first value chose', () {
      final context = ScriptedContext(<int>[3, 30]);

      final value = TestCase(context).draw(
        integers(
          min: 0,
          max: 9,
        ).flatMap((int n) => integers(min: n * 10, max: n * 10 + 9)),
      );

      expect(value, 30);
      expect(context.calls, <String>[
        'start ${SpanLabel.flatMap.value}',
        'draw 0..9',
        'draw 30..39',
        'stop',
      ]);
    });

    test('reports the second value, which is the one it produced', () {
      final testCase = TestCase(ScriptedContext(<int>[1, 5]));

      testCase.draw(
        integers(min: 0, max: 9).flatMap((int n) => integers(min: 0, max: 9)),
        name: 'value',
      );

      expect(testCase.draws, <Drawn>[(name: 'value', value: 5)]);
    });

    test('respects the bound the first draw chose, over a whole run', () {
      final pairs = <(int, int)>[];
      driveCases(openSession(), (TestCase testCase) {
        late int bound;
        final value = testCase.draw(
          integers(min: 1, max: 5).flatMap((int n) {
            bound = n;
            return integers(min: 0, max: n);
          }),
        );
        pairs.add((bound, value));
      });

      expect(pairs, isNotEmpty);
      expect(
        pairs,
        everyElement(
          isA<(int, int)>().having(
            ((int, int) pair) => pair.$2 <= pair.$1,
            'value within the bound it drew',
            isTrue,
          ),
        ),
      );
      expect(
        pairs.map(((int, int) pair) => pair.$1).toSet(),
        hasLength(greaterThan(1)),
        reason: 'a run that only ever chose one bound would prove nothing',
      );
    });
  });
}
