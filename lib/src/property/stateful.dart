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
  const Rule(this.name, this.body, {this.precondition});

  /// What this rule is called, in the report and to the engine.
  final String name;

  /// What the rule does.
  final FutureOr<void> Function(TestCase testCase) body;

  /// Whether this rule can run at all right now.
  final bool Function()? precondition;
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
Future<void> runStateful(TestCase testCase, StateMachine machine) async {
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
    invariantNames: <String>[
      for (final Invariant invariant in invariants) invariant.name,
    ],
  );
  try {
    var step = 0;
    // Before the first rule as well as after each round: a machine whose
    // invariants do not hold of its initial state is broken before it starts,
    // and finding that out after three steps names the wrong step.
    await _check(testCase, invariants);
    while (driver.nextGroup() != null) {
      while (true) {
        final index = driver.nextRule();
        if (index == null) break;
        final rule = rules[index];
        if (rule.precondition case final allowed? when !allowed()) {
          driver.ruleRejected();
          continue;
        }
        step++;
        testCase.note('Step $step: ${rule.name}');
        try {
          await testCase.step(
            SpanLabel.statefulRule,
            () => rule.body(testCase),
          );
        } on AssumptionFailed {
          // The step turned itself down, or the engine ended the case
          // underneath it. The latch is what tells them apart: an assumption
          // the engine raised is held against the whole case, so there is
          // nothing left to run and this has to go on unwinding.
          if (testCase.context.isAborted) rethrow;
          // Not counted as a step, because it did not take one: the note
          // named a rule that then declined to run.
          testCase.undoNote();
          step--;
          driver.ruleRejected();
        }
      }
      await _check(testCase, invariants);
    }
  } finally {
    driver.dispose();
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
