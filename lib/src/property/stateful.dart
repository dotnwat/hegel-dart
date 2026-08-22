/// Stateful testing: rules the engine sequences, invariants that must hold.
library;

import 'dart:async';

import '../libhegel/errors.dart';
import '../libhegel/span.dart';
import 'test_case.dart';

/// One thing a stateful test can do.
///
/// A rule is a step: it draws whatever parameters it needs from the case it
/// is given, does something to the system under test, and updates whatever
/// model the machine keeps alongside it. The engine decides which rules run
/// and in what order, and when the property fails it shrinks that sequence
/// the way it shrinks anything else -- so a counterexample is the shortest
/// script of steps that still breaks the invariants.
final class Rule {
  /// A rule called [name], which runs [body].
  ///
  /// [precondition] is asked before [body] runs and before anything is
  /// drawn. A rule it turns down is put back rather than spent: it does not
  /// count against the step budget, and the engine picks something else. This
  /// is the form to reach for whenever the answer depends only on the model
  /// -- "there is nothing in the queue to pop" -- because it costs nothing.
  /// [group] decides what this rule may overlap with when a machine runs
  /// with more than one worker. Rules in the same group may run at the same
  /// time; rules in different groups never do, so a rule that cannot tolerate
  /// company gets a group of its own. Ungrouped rules share one group, which
  /// is the permissive answer and the right default: a machine that says
  /// nothing about grouping is one whose rules are all meant to interleave.
  /// At one worker it decides nothing, because nothing overlaps.
  const Rule(this.name, this.body, {this.precondition, this.group});

  /// What this rule is called, in the report and to the engine.
  final String name;

  /// What the rule does.
  final FutureOr<void> Function(TestCase testCase) body;

  /// Whether this rule can run at all right now.
  final bool Function()? precondition;

  /// What this rule may overlap with, or null for the common group.
  final String? group;
}

/// Something that must be true between steps.
///
/// Checked before the first rule runs and at every point where the engine
/// pauses the machine, so a violation is caught at the step that caused it
/// rather than at the end of a case whose middle is where it went wrong. An
/// invariant fails the way anything else does: it throws, and the property
/// reports that error against the sequence of steps that led to it.
final class Invariant {
  /// An invariant called [name], checked by [body].
  const Invariant(this.name, this.body);

  /// What this invariant is called, in the report and to the engine.
  final String name;

  /// What has to hold. Throws if it does not.
  final FutureOr<void> Function(TestCase testCase) body;
}

/// A system under test, its model, and the steps between them.
///
/// Subclass it, hold the system and whatever model you are comparing it
/// against as fields, and list the [rules] that act on both. The instance is
/// the state: build a fresh one inside the property body, which runs once per
/// test case, and every case starts from nothing.
///
/// ```dart
/// final class CounterMachine extends StateMachine {
///   int model = 0;
///   final Counter counter = Counter();
///
///   @override
///   List<Rule> get rules => <Rule>[
///     Rule('increment', (TestCase tc) async {
///       final by = tc.draw(integers(min: 1, max: 10), name: 'by');
///       await counter.add(by);
///       model += by;
///     }),
///     Rule('reset', (TestCase tc) async {
///       await counter.reset();
///       model = 0;
///     }),
///   ];
///
///   @override
///   List<Invariant> get invariants => <Invariant>[
///     Invariant('matches the model', (TestCase tc) async {
///       expect(await counter.value, model);
///     }),
///   ];
/// }
///
/// property('a counter matches its model', (TestCase tc) async {
///   await runStateful(tc, CounterMachine());
/// });
/// ```
abstract base class StateMachine {
  /// For subclasses.
  const StateMachine();

  /// The steps this machine can take. At least one.
  List<Rule> get rules;

  /// What must hold between steps. None, by default.
  List<Invariant> get invariants => const <Invariant>[];
}

/// Runs [machine] against test cases the engine sequences.
///
/// Call it from a property body and give it that body's [testCase]. The
/// engine chooses which rules run and how many, subject to
/// `Settings.statefulStepCount`; the invariants are checked before the first
/// rule and between rounds; and a failure is reported against the shortest
/// sequence of steps that still produces it.
///
/// Every step is noted, so a counterexample reads as a script:
///
/// ```
/// Step 1: increment
/// Step 2: increment
/// Step 3: reset
/// ```
///
/// A rule may also turn itself down from inside its body, with
/// [TestCase.assume], for a precondition that depends on what the step drew
/// rather than only on the model. That rejection costs the draws it took but
/// not the step. What it cannot do is stand in for an assumption the *engine*
/// raised -- drawing from an empty pool, or a string generator that rejected
/// its own draw -- because by then the case is over rather than the step:
/// the engine has latched it, every later draw would raise the same signal,
/// and the case ends invalid. Guard those with [Rule.precondition], which is
/// asked before anything is drawn.
///
/// ## Concurrency
///
/// With [maxConcurrency] above one the engine draws how many workers to run
/// and the machine's rules are pulled by that many at once. Each worker gets
/// its own handle on the case, so their draws do not collide; within a worker
/// rules still run one after another, and *across* workers they interleave at
/// every await in a rule body. That is exactly the concurrency an ordinary
/// Dart program has, and it is enough to find the bugs that come of it: a
/// read and a write that were never meant to be separable, a check that
/// stopped being true between the checking and the acting.
///
/// [Rule.group] says what may overlap with what. A worker's notes are kept to
/// itself while a round runs and flushed at the join point tagged
/// `[worker N]`, because two workers writing into one log interleave into
/// something no one can read.
///
/// The first concurrent machine on a run is refused: the engine raises
/// [AssumptionFailed], that case ends invalid, and every case after it is
/// allowed. This is the engine being told, once, that the run cannot promise
/// to repeat itself -- which is also why a concurrent failure comes back
/// without a reproduce blob and is reported from the case that found it. Let
/// the signal through; the runner already knows what to do with it.
Future<void> runStateful(
  TestCase testCase,
  StateMachine machine, {
  int minConcurrency = 1,
  int maxConcurrency = 1,
}) async {
  if (minConcurrency < 1) {
    throw RangeError.value(
      minConcurrency,
      'minConcurrency',
      'must be at least one',
    );
  }
  if (maxConcurrency < minConcurrency) {
    throw ArgumentError.value(
      maxConcurrency,
      'maxConcurrency',
      'is below minConcurrency ($minConcurrency)',
    );
  }
  // Read once rather than per step. `rules` is a getter, and the natural way
  // to write one builds a fresh list on every call; the engine identifies a
  // rule by its position in the list it was registered with, so asking twice
  // would leave those positions meaning whatever the second answer said.
  final rules = List<Rule>.of(machine.rules);
  final invariants = List<Invariant>.of(machine.invariants);
  if (rules.isEmpty) {
    throw ArgumentError.value(
      machine,
      'machine',
      'has no rules, so there is nothing for the engine to sequence',
    );
  }

  final driver = testCase.context.startStateMachine(
    ruleNames: <String>[for (final Rule rule in rules) rule.name],
    ruleGroups: _groupsOf(rules),
    invariantNames: <String>[
      for (final Invariant invariant in invariants) invariant.name,
    ],
    minConcurrency: minConcurrency,
    maxConcurrency: maxConcurrency,
  );
  try {
    final workers = _workersFor(testCase, driver.concurrency);
    try {
      final steps = _Steps();
      // Before the first rule as well as after each round: a machine whose
      // invariants do not hold of its initial state is broken before it
      // starts, and finding that out after three steps names the wrong step.
      await _check(testCase, invariants);
      while (driver.nextGroup() != null) {
        try {
          await _round(testCase, driver, rules, workers, steps);
        } finally {
          // In a finally, because the round that ends badly is the one whose
          // script the reader most needs: a worker's log left behind on the
          // worker is a step that happened and is not reported.
          if (workers.length > 1) {
            for (final _Worker worker in workers) {
              testCase.absorb(worker.testCase, '[worker ${worker.index}]');
            }
          }
        }
        await _check(testCase, invariants);
      }
    } finally {
      for (final _Worker worker in workers) {
        worker.release();
      }
    }
  } finally {
    driver.dispose();
  }
}

/// One worker's turn at the rules, and where its report goes meanwhile.
final class _Worker {
  _Worker(this.index, this.testCase, this.context, {required this.release});

  /// Which worker this is, as the engine numbers them.
  final int index;

  /// What its rules are handed, and where its notes go until the join point.
  final TestCase testCase;

  /// The handle its rule selections are drawn from.
  final DrawContext context;

  /// Gives the handle back. A no-op for the worker that is the root case.
  final void Function() release;
}

/// The step counter, shared so that a script numbers steps once.
final class _Steps {
  int taken = 0;
}

/// The workers for a machine the engine wants run [concurrency] wide.
///
/// At one worker there is nothing to clone: the root case is the worker, its
/// notes are already the case's, and nothing is tagged. Above one, each
/// worker gets a handle and a log of its own.
List<_Worker> _workersFor(TestCase testCase, int concurrency) {
  if (concurrency == 1) {
    return <_Worker>[_Worker(0, testCase, testCase.context, release: () {})];
  }
  return <_Worker>[
    for (var index = 0; index < concurrency; index++)
      () {
        final clone = testCase.context.cloneForWorker();
        return _Worker(
          index,
          TestCase(clone.context),
          clone.context,
          release: clone.release,
        );
      }(),
  ];
}

/// A group number per rule: one for each distinct [Rule.group], zero for none.
///
/// Ungrouped rules share group zero rather than getting one each, so a machine
/// that says nothing about grouping is one whose rules may all overlap.
List<int> _groupsOf(List<Rule> rules) {
  final numbers = <String, int>{};
  return <int>[
    for (final Rule rule in rules)
      rule.group == null
          ? 0
          : numbers.putIfAbsent(rule.group!, () => numbers.length + 1),
  ];
}

/// Runs one round, and raises whichever worker's ending speaks for the case.
Future<void> _round(
  TestCase root,
  DrawMachine driver,
  List<Rule> rules,
  List<_Worker> workers,
  _Steps steps,
) async {
  if (workers.length == 1) {
    return _turn(driver, rules, workers.single, steps);
  }
  // Every worker is run to its own end rather than to the first failure.
  // The engine gave out a round and expects it back, and a worker abandoned
  // mid-round would leave the machine waiting on rules nobody will pull.
  final endings = await Future.wait(<Future<_Ending?>>[
    for (final _Worker worker in workers) _ending(driver, rules, worker, steps),
  ]);
  final raised = endings.nonNulls.toList();
  if (raised.isEmpty) return;
  raised.sort(_byPrecedence);
  final winner = raised.first;
  // What the others said is not thrown away: a second worker failing at the
  // same moment is a second thing wrong, and a report that mentioned only the
  // one that won would read as though the rest of the run was fine.
  for (final _Ending dropped in raised.skip(1)) {
    // On the root rather than on a worker: it is not one worker's step, it is
    // the account of a round that ended two ways at once.
    root.note('Worker ${dropped.worker} also ended with ${dropped.error}');
  }
  Error.throwWithStackTrace(winner.error, winner.stack);
}

/// How one worker's round ended, or null if it simply finished.
typedef _Ending = ({int worker, Object error, StackTrace stack});

/// Runs [worker]'s round, catching whatever ends it.
Future<_Ending?> _ending(
  DrawMachine driver,
  List<Rule> rules,
  _Worker worker,
  _Steps steps,
) async {
  try {
    await _turn(driver, rules, worker, steps);
    return null;
  } on Object catch (error, stack) {
    return (worker: worker.index, error: error, stack: stack);
  }
}

/// Which of two simultaneous endings speaks for the case.
///
/// A control signal outranks a verdict, because it says the case did not
/// finish rather than that the property is wrong: an overrun means the engine
/// stopped handing out choices, and an assumption means the case does not
/// count. Reporting a failure over either would be reporting a conclusion
/// drawn from a case that never ran to the end. Overrun outranks an
/// assumption for the same reason one step further. Between two of a kind the
/// lowest worker wins, which is arbitrary and therefore has to be fixed:
/// whichever of two racing workers is reported cannot depend on which
/// happened to finish first, or the report would not be the same twice.
int _byPrecedence(_Ending a, _Ending b) {
  final ranked = _rank(b.error).compareTo(_rank(a.error));
  return ranked != 0 ? ranked : a.worker.compareTo(b.worker);
}

int _rank(Object error) => switch (error) {
  StopTest() => 2,
  AssumptionFailed() => 1,
  _ => 0,
};

/// Pulls rules for one worker until its round is over.
Future<void> _turn(
  DrawMachine driver,
  List<Rule> rules,
  _Worker worker,
  _Steps steps,
) async {
  final testCase = worker.testCase;
  while (true) {
    final index = driver.nextRule(worker.context, worker.index);
    if (index == null) break;
    final rule = rules[index];
    if (rule.precondition case final allowed? when !allowed()) {
      driver.ruleRejected(worker.context, worker.index);
      continue;
    }
    steps.taken++;
    testCase.note('Step ${steps.taken}: ${rule.name}');
    try {
      await testCase.step(SpanLabel.statefulRule, () => rule.body(testCase));
    } on AssumptionFailed {
      // The step turned itself down, or the engine ended the case underneath
      // it. The latch is what tells them apart: an assumption the engine
      // raised is held against the whole case, so there is nothing left to
      // run and this has to go on unwinding.
      if (worker.context.isAborted) rethrow;
      // Not counted as a step, because it did not take one: the note named a
      // rule that then declined to run.
      testCase.undoNote();
      steps.taken--;
      driver.ruleRejected(worker.context, worker.index);
    }
  }
}

/// Checks every invariant, naming the one that failed.
///
/// The error is left exactly as it was raised -- an `expect` mismatch has to
/// reach package:test as the object it is -- so the name goes in a note
/// instead, which is where the rest of the step script already is.
Future<void> _check(TestCase testCase, List<Invariant> invariants) async {
  for (final Invariant invariant in invariants) {
    try {
      await invariant.body(testCase);
    } on Object {
      testCase.note("Invariant '${invariant.name}' does not hold");
      rethrow;
    }
  }
}
