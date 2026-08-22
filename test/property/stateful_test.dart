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
    required List<int> ruleGroups,
    required List<String> invariantNames,
    required int minConcurrency,
    required int maxConcurrency,
  }) {
    calls.add(
      'machine ${ruleNames.join(',')} in ${ruleGroups.join(',')} / '
      '${invariantNames.join(',')} over $minConcurrency..$maxConcurrency',
    );
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
  int? nextRule(DrawContext from, int worker) {
    final round = rounds[_round];
    return _within < round.length ? round[_within++] : null;
  }

  // The engine would hand the slot back and choose again; the script just
  // goes on to whatever it says comes next, which is what keeps it finite.
  @override
  void ruleRejected(DrawContext from, int worker) => calls.add('rejected');

  @override
  void dispose() => calls.add('machine freed');
}

/// A scripted machine that hands out a round to several workers at once.
///
/// Which worker gets which rule, and which of two simultaneous endings the
/// engine sees first, are the things a real run will not repeat on request --
/// and they are exactly what the rules below the join point turn on.
final class _ConcurrentMachine extends FakeDrawContext implements DrawMachine {
  _ConcurrentMachine(this.perWorker);

  /// The rules to hand each worker, in the one round there is.
  final List<List<int>> perWorker;

  @override
  int get concurrency => perWorker.length;

  /// Whether the engine has ended the case out from under the workers.
  bool aborted = false;

  @override
  bool get isAborted => aborted;

  final List<int> _within = <int>[];
  bool _roundTaken = false;

  // Every worker draws through the same fake, which has no engine behind it
  // and so nothing to keep apart. What does have to be kept apart is each
  // worker's log, and the driver gives every worker a case of its own for
  // that.
  @override
  ({DrawContext context, void Function() release}) cloneForWorker() =>
      (context: this, release: () => calls.add('worker released'));

  @override
  DrawMachine startStateMachine({
    required List<String> ruleNames,
    required List<int> ruleGroups,
    required List<String> invariantNames,
    required int minConcurrency,
    required int maxConcurrency,
  }) {
    _within.addAll(List<int>.filled(perWorker.length, 0));
    return this;
  }

  @override
  int? nextGroup() {
    if (_roundTaken) return null;
    _roundTaken = true;
    return 0;
  }

  @override
  int? nextRule(DrawContext from, int worker) {
    final round = perWorker[worker];
    final at = _within[worker];
    if (at >= round.length) return null;
    _within[worker] = at + 1;
    return round[at];
  }

  @override
  void ruleRejected(DrawContext from, int worker) =>
      calls.add('rejected $worker');

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

      expect(context.calls.first, 'machine push,pop in 0,0 / sorted over 1..1');
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
        'machine push in 0 /  over 1..1',
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
        'machine pop in 0 /  over 1..1',
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

  group('a rule that turns itself down, having already said something', () {
    test('leaves nothing of itself in the script', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0, 1],
      ]);
      final testCase = TestCase(context);

      await runStateful(
        testCase,
        _Machine(<Rule>[
          Rule('pop', (TestCase tc) {
            // A note before the precondition is an ordinary thing to write:
            // it is how a rule says what it was about to do.
            tc.note('about to pop');
            tc.assume(false);
          }),
          Rule('push', (TestCase tc) {}),
        ]),
      );

      // Both lines go, not just the last one. Undoing a single note pops
      // whatever the body said last and leaves the announcement behind --
      // which reads as a step that ran and then said nothing.
      expect(testCase.notes, <String>['Step 1: push']);
    });

    test('takes its drawn parameters with it', () async {
      final context = _ScriptedMachine(<List<int>>[
        <int>[0, 1],
      ]);
      final testCase = TestCase(context);

      await runStateful(
        testCase,
        _Machine(<Rule>[
          Rule('pop', (TestCase tc) {
            tc.draw(just(7), name: 'by');
            tc.assume(false);
          }),
          Rule('push', (TestCase tc) {}),
        ]),
      );

      // A parameter of a step that never happened is not a value the
      // counterexample was built from, and reporting it as one sends the
      // reader looking for a step that is not in the script.
      expect(testCase.draws, isEmpty);
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

  group('a round run by several workers', () {
    test('tags every step with the worker that took it', () async {
      final context = _ConcurrentMachine(<List<int>>[
        <int>[0],
        <int>[1],
      ]);
      final testCase = TestCase(context);

      await runStateful(
        testCase,
        _Machine(<Rule>[
          Rule('push', (TestCase tc) async {
            await Future<void>.delayed(Duration.zero);
          }),
          Rule('pop', (TestCase tc) async {
            await Future<void>.delayed(Duration.zero);
          }),
        ]),
        minConcurrency: 2,
        maxConcurrency: 2,
      );

      // In worker order rather than in the order they finished, because the
      // order they finished in is the thing that will not be the same twice.
      // Each worker numbers its own script, which is what the tag beside the
      // number says the line belongs to.
      expect(testCase.notes, <String>[
        '[worker 0] Step 1: push',
        '[worker 1] Step 1: pop',
      ]);
    });

    test('reports the ending that says the case did not finish', () async {
      final context = _ConcurrentMachine(<List<int>>[
        <int>[0],
        <int>[1],
      ]);

      // Worker 0 says the property is wrong; worker 1 says the engine stopped
      // handing out choices. The second outranks the first, because a
      // conclusion drawn from a case that never ran to the end is not a
      // conclusion.
      await expectLater(
        runStateful(
          TestCase(context),
          _Machine(<Rule>[
            Rule('fails', (TestCase tc) async => throw StateError('wrong')),
            Rule('overruns', (TestCase tc) async => throw const StopTest()),
          ]),
          minConcurrency: 2,
          maxConcurrency: 2,
        ),
        throwsA(isA<StopTest>()),
      );
    });

    test(
      'prefers an overrun to an assumption, and both to a failure',
      () async {
        for (final (List<Rule> rules, Matcher wins) in <(List<Rule>, Matcher)>[
          (
            <Rule>[
              Rule('assumes', (TestCase tc) async => tc.assume(false)),
              Rule('overruns', (TestCase tc) async => throw const StopTest()),
            ],
            isA<StopTest>(),
          ),
          (
            <Rule>[
              Rule('fails', (TestCase tc) async => throw StateError('wrong')),
              Rule('assumes', (TestCase tc) async => tc.assume(false)),
            ],
            isA<AssumptionFailed>(),
          ),
        ]) {
          final context = _ConcurrentMachine(<List<int>>[
            <int>[0],
            <int>[1],
          ])..aborted = true;

          await expectLater(
            runStateful(
              TestCase(context),
              _Machine(rules),
              minConcurrency: 2,
              maxConcurrency: 2,
            ),
            throwsA(wins),
          );
        }
      },
    );

    test('reports the lowest worker when two end the same way', () async {
      final context = _ConcurrentMachine(<List<int>>[
        <int>[0],
        <int>[1],
      ]);

      // Arbitrary, and therefore fixed: whichever of two racing workers is
      // reported cannot depend on which happened to finish first, or the
      // report would not be the same twice.
      await expectLater(
        runStateful(
          TestCase(context),
          _Machine(<Rule>[
            Rule('first', (TestCase tc) async => throw StateError('from 0')),
            Rule('second', (TestCase tc) async => throw StateError('from 1')),
          ]),
          minConcurrency: 2,
          maxConcurrency: 2,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'from 0',
          ),
        ),
      );
    });

    test('says so when a second worker also ended badly', () async {
      final context = _ConcurrentMachine(<List<int>>[
        <int>[0],
        <int>[1],
      ]);
      final testCase = TestCase(context);

      await expectLater(
        runStateful(
          testCase,
          _Machine(<Rule>[
            Rule('first', (TestCase tc) async => throw StateError('from 0')),
            Rule('second', (TestCase tc) async => throw StateError('from 1')),
          ]),
          minConcurrency: 2,
          maxConcurrency: 2,
        ),
        throwsA(isA<StateError>()),
      );

      // One error is raised and the other would otherwise vanish, which would
      // read as though the rest of the round was fine.
      expect(
        testCase.notes,
        contains(contains('Worker 1 also ended with Bad state: from 1')),
      );
    });

    test('keeps the steps of a round that ended badly', () async {
      final context = _ConcurrentMachine(<List<int>>[
        <int>[0],
        <int>[1],
      ]);
      final testCase = TestCase(context);

      await expectLater(
        runStateful(
          testCase,
          _Machine(<Rule>[
            Rule('worked', (TestCase tc) async {
              await Future<void>.delayed(Duration.zero);
            }),
            Rule('failed', (TestCase tc) async => throw StateError('wrong')),
          ]),
          minConcurrency: 2,
          maxConcurrency: 2,
        ),
        throwsA(isA<StateError>()),
      );

      // The round that ends badly is the one whose script the reader most
      // needs, so a worker's log is taken across however the round ended.
      expect(testCase.notes, contains('[worker 0] Step 1: worked'));
      expect(testCase.notes, contains('[worker 1] Step 1: failed'));
    });
  });

  group('what a worker took out', () {
    test('is given back when its round is over', () async {
      // A worker's case is a case: a rule that made something case-scoped
      // registered it on the worker rather than on the root, and only the
      // driver knows to give it back. Nothing else will -- the runner
      // releases the case the property body was handed, and has never heard
      // of the clones underneath it.
      final context = _ConcurrentMachine(<List<int>>[
        <int>[0],
        <int>[0],
      ]);
      var released = 0;

      await runStateful(
        TestCase(context),
        _Machine(<Rule>[
          Rule(
            'makes something',
            (TestCase tc) => tc.onRelease(() => released++),
          ),
        ]),
        minConcurrency: 2,
        maxConcurrency: 2,
      );

      expect(released, 2, reason: 'one per worker');
      // And the handle after the case, not before it.
      expect(context.calls, contains('worker released'));
    });

    test(
      'leaves the root case alone, which is not the driver\'s to end',
      () async {
        // The trap in the other direction. At one worker the worker *is* the
        // root case, and releasing it here would take a pool away from a body
        // that has not finished with it -- the runner releases that one, when
        // the case ends rather than when the machine does.
        final context = _ScriptedMachine(<List<int>>[
          <int>[0],
        ]);
        final testCase = TestCase(context);
        var released = 0;
        testCase.onRelease(() => released++);

        await runStateful(
          testCase,
          _Machine(<Rule>[Rule('push', (TestCase tc) {})]),
        );

        expect(released, 0, reason: 'the body may still be using it');
        testCase.release();
        expect(released, 1);
      },
    );
  });

  group('step numbers under several workers', () {
    test('are never handed out twice', () async {
      // Worker 0 announces a step, worker 1 announces the next, and then
      // worker 0's rule turns itself down. A counter shared between them
      // cannot be wound back at that point: the number it would give up has
      // already been passed, and the next step takes one that is spoken for.
      final context = _ConcurrentMachine(<List<int>>[
        <int>[0, 1],
        <int>[1],
      ]);
      final testCase = TestCase(context);

      await runStateful(
        testCase,
        _Machine(<Rule>[
          Rule('declines', (TestCase tc) async {
            await Future<void>.delayed(Duration.zero);
            tc.assume(false);
          }),
          Rule('runs', (TestCase tc) async {
            await Future<void>.delayed(Duration.zero);
          }),
        ]),
        minConcurrency: 2,
        maxConcurrency: 2,
      );

      // Read per worker, since that is whose script it is once the notes
      // carry a tag saying so. Each one has to run from one without gaps: a
      // script that opens at step two is a reader looking for a step one
      // that was taken by somebody else.
      for (final String tag in <String>['[worker 0]', '[worker 1]']) {
        final mine = <int>[
          for (final String note in testCase.notes)
            if (note.startsWith('$tag Step '))
              int.parse(note.split('Step ')[1].split(':')[0]),
        ];
        expect(mine, isNotEmpty, reason: '$tag took no step');
        expect(mine, <int>[
          for (var n = 1; n <= mine.length; n++) n,
        ], reason: '$tag numbered its steps $mine');
      }
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
