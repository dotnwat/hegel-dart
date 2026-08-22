@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/stateful.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/scripted_context.dart';
import '../support/shrink_pin.dart';

/// A context that hands out a fixed script of rules instead of choosing.
///
/// Which rule runs next is the engine's decision, and that is exactly what a
/// test of the driver cannot ask it for: the cases worth pinning are the ones
/// where a particular rule comes up at a particular point -- the rejected
/// one, the one after it, the round that ends.
final class _ScriptedMachine extends FakeDrawContext implements DrawMachine {
  _ScriptedMachine(this.rounds);

  /// The rule indices to hand out, one list per round.
  final List<List<int>> rounds;

  /// Whether the engine has ended the case out from under the driver.
  bool aborted = false;

  int _round = -1;
  int _within = 0;

  @override
  bool get isAborted => aborted;

  @override
  DrawMachine startStateMachine({
    required List<String> ruleNames,
    required List<String> invariantNames,
  }) {
    calls.add('machine ${ruleNames.join(',')} / ${invariantNames.join(',')}');
    return this;
  }

  @override
  int get concurrency => 1;

  @override
  int? nextGroup() {
    _round++;
    _within = 0;
    return _round < rounds.length ? 0 : null;
  }

  @override
  int? nextRule() {
    final round = rounds[_round];
    return _within < round.length ? round[_within++] : null;
  }

  // The engine would hand the slot back and choose again; the script just
  // goes on to whatever it says comes next, which is what keeps it finite.
  @override
  void ruleRejected() => calls.add('rejected');

  @override
  void dispose() => calls.add('machine freed');
}

/// A machine built out of the rules and invariants a test hands it.
final class _Machine extends StateMachine {
  _Machine(this.rules, {this.invariants = const <Invariant>[]});

  @override
  final List<Rule> rules;

  @override
  final List<Invariant> invariants;
}

/// A counter with a bug planted in it: past ten, it stops counting.
final class _Counter {
  int value = 0;

  void add(int by) {
    if (value + by > 10) return;
    value += by;
  }

  void reset() => value = 0;
}

/// The counter, its model, and the two things you can do to either.
final class _CounterMachine extends StateMachine {
  final _Counter counter = _Counter();
  int model = 0;

  @override
  List<Rule> get rules => <Rule>[
    Rule('increment', (TestCase tc) {
      final by = tc.draw(integers(min: 1, max: 10), name: 'by');
      counter.add(by);
      model += by;
    }),
    Rule('reset', (TestCase tc) {
      counter.reset();
      model = 0;
    }),
  ];

  @override
  List<Invariant> get invariants => <Invariant>[
    Invariant('matches the model', (TestCase tc) {
      expect(counter.value, model);
    }),
  ];
}

void main() {
  group('a stateful run', () {
    test('registers what the machine declares', () async {
      final context = _ScriptedMachine(<List<int>>[]);

      await runStateful(
        TestCase(context),
        _Machine(
          <Rule>[Rule('push', (TestCase tc) {}), Rule('pop', (TestCase tc) {})],
          invariants: <Invariant>[Invariant('sorted', (TestCase tc) {})],
        ),
      );

      expect(context.calls.first, 'machine push,pop / sorted');
      expect(context.calls.last, 'machine freed');
    });

    test('runs each rule inside a span of its own', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0],
      ]);

      await runStateful(
        TestCase(context),
        _Machine(<Rule>[Rule('push', (TestCase tc) {})]),
      );

      expect(context.calls, <String>[
        'machine push / ',
        'start ${SpanLabel.statefulRule.value}',
        'stop',
        'machine freed',
      ]);
    });

    test('notes every step, as a script of what happened', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0, 1],
        <int>[0],
      ]);
      final testCase = TestCase(context);

      await runStateful(
        testCase,
        _Machine(<Rule>[
          Rule('push', (TestCase tc) {}),
          Rule('pop', (TestCase tc) {}),
        ]),
      );

      expect(testCase.notes, <String>[
        'Step 1: push',
        'Step 2: pop',
        'Step 3: push',
      ]);
    });

    test('refuses a machine with nothing to do', () {
      expect(
        () => runStateful(
          TestCase(_ScriptedMachine(<List<int>>[])),
          _Machine(<Rule>[]),
        ),
        throwsArgumentError,
      );
    });
  });

  group('a precondition', () {
    test('keeps the rule from running at all', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0],
      ]);
      var ran = 0;

      await runStateful(
        TestCase(context),
        _Machine(<Rule>[
          Rule('pop', (TestCase tc) => ran++, precondition: () => false),
        ]),
      );

      expect(ran, 0);
      // Turned down before anything was drawn, so there is no span either:
      // the point of this form is that it costs nothing.
      expect(context.calls, <String>[
        'machine pop / ',
        'rejected',
        'machine freed',
      ]);
    });

    test('costs no step, so the script stays honest', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0, 1],
      ]);
      final testCase = TestCase(context);

      await runStateful(
        testCase,
        _Machine(<Rule>[
          Rule('pop', (TestCase tc) {}, precondition: () => false),
          Rule('push', (TestCase tc) {}),
        ]),
      );

      expect(testCase.notes, <String>['Step 1: push']);
    });
  });

  group('a rule that turns itself down', () {
    test('is rejected rather than failing the case', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0, 1],
      ]);
      final testCase = TestCase(context);

      await runStateful(
        testCase,
        _Machine(<Rule>[
          Rule('pop', (TestCase tc) => tc.assume(false)),
          Rule('push', (TestCase tc) {}),
        ]),
      );

      // The rejected rule leaves no line behind: it was announced before it
      // ran, because that is what makes a failure inside it readable, and
      // then it did not run.
      expect(testCase.notes, <String>['Step 1: push']);
      expect(context.calls, contains('rejected'));
    });

    test('cannot stand in for the engine ending the case', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0],
      ])..aborted = true;

      // An assumption the engine raised is held against the whole case, not
      // against the step: every later draw would raise it again, so there is
      // nothing left to run and converting it to a rejection would spin
      // against a case that is already over.
      await expectLater(
        runStateful(
          TestCase(context),
          _Machine(<Rule>[Rule('pop', (TestCase tc) => tc.assume(false))]),
        ),
        throwsA(isA<AssumptionFailed>()),
      );
      expect(context.calls, isNot(contains('rejected')));
    });
  });

  group('invariants', () {
    test('are checked before the first rule and after every round', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0],
        <int>[0],
      ]);
      final order = <String>[];

      await runStateful(
        TestCase(context),
        _Machine(
          <Rule>[Rule('push', (TestCase tc) => order.add('rule'))],
          invariants: <Invariant>[
            Invariant('holds', (TestCase tc) => order.add('invariant')),
          ],
        ),
      );

      // A machine whose invariants do not hold of its initial state is broken
      // before it starts, and finding that out after three steps would name
      // the wrong step.
      expect(order, <String>[
        'invariant',
        'rule',
        'invariant',
        'rule',
        'invariant',
      ]);
    });

    test('name themselves when they do not hold', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0],
      ]);
      final testCase = TestCase(context);

      await expectLater(
        runStateful(
          testCase,
          _Machine(
            <Rule>[Rule('push', (TestCase tc) {})],
            invariants: <Invariant>[
              Invariant('stays empty', (TestCase tc) => throw StateError('no')),
            ],
          ),
        ),
        // Raised as it stands: an `expect` mismatch has to reach package:test
        // as the object it is, so the name goes in a note instead.
        throwsA(isA<StateError>()),
      );
      expect(testCase.notes, contains("Invariant 'stays empty' does not hold"));
    });
  });

  group('a machine that keeps its promises', () {
    test('runs to the end of every case without complaint', () async {
      // The counter without the bug: the same rules over a whole run, which
      // is what says the driver terminates, honours the step budget, and does
      // not invent failures of its own.
      var steps = 0;

      await runProperty((TestCase testCase) async {
        final model = <int>[];
        await runStateful(
          testCase,
          _Machine(
            <Rule>[
              Rule('push', (TestCase tc) {
                model.add(tc.draw(integers(min: 0, max: 9)));
                steps++;
              }),
              Rule(
                'pop',
                (TestCase tc) {
                  model.removeLast();
                  steps++;
                },
                // Popping an empty list would throw, and the point of the
                // declarative form is that the rule is never offered when it
                // could not work.
                precondition: () => model.isNotEmpty,
              ),
            ],
            invariants: <Invariant>[
              Invariant(
                'never goes negative',
                (TestCase tc) => expect(model.length, greaterThanOrEqualTo(0)),
              ),
            ],
          ),
        );
      }, settings: pinSettings(testCases: 20));

      expect(steps, greaterThan(0));
    });
  });

  group('a planted bug', () {
    test('is found, and shrunk to the shortest script that shows it', () async {
      final report = await shrunkReport((TestCase testCase) async {
        await runStateful(testCase, _CounterMachine());
      });

      // Two increments and no more: one cannot overshoot ten, because a
      // single `by` is at most ten and ten is still counted. The parameters
      // shrink too -- 1 then 10 is the smallest pair whose sum passes ten
      // with the earlier draw as small as it will go.
      expect(report, contains('Step 1: increment'));
      expect(report, contains('Step 2: increment'));
      expect(report, isNot(contains('Step 3:')));
      expect(report, contains('by = 1'));
      expect(report, contains('by = 10'));
      expect(report, contains("Invariant 'matches the model' does not hold"));
    });
  });
}
