/// Stateful property-based testing with hegel: a thing, and a model of it.
///
///     dart run example/counter.dart
///
/// A property over one value at a time cannot say much about something that
/// remembers. This can: the engine picks the rules, runs them in an order of
/// its choosing, and when an invariant breaks it shrinks the *sequence* to
/// the shortest script that still breaks it.
library;

import 'dart:io';

import 'package:hegel/hegel.dart';

/// The thing under test, with a bug in it: past ten it stops counting.
///
/// The kind of mistake a bounds check makes when it is written for the value
/// going in rather than the total coming out.
final class Counter {
  int value = 0;

  void add(int by) {
    if (value + by > 10) return;
    value += by;
  }

  void reset() => value = 0;
}

/// The counter, a model of what it should hold, and the steps between them.
final class CounterMachine extends StateMachine {
  final Counter counter = Counter();

  /// What the counter would hold if it were right.
  int model = 0;

  @override
  List<Rule> get rules => <Rule>[
    Rule('increment', (TestCase testCase) {
      final by = testCase.draw(integers(min: 1, max: 10), name: 'by');
      counter.add(by);
      model += by;
    }),
    Rule('reset', (TestCase testCase) {
      counter.reset();
      model = 0;
    }),
  ];

  @override
  List<Invariant> get invariants => <Invariant>[
    Invariant('the counter matches its model', (TestCase testCase) {
      if (counter.value != model) {
        throw StateError('counter is ${counter.value}, model is $model');
      }
    }),
  ];
}

Future<void> main() async {
  stdout.writeln('hegel: a stateful property');
  try {
    await runProperty(
      // A fresh machine per test case, since the machine *is* the state.
      (TestCase testCase) => runStateful(testCase, CounterMachine()),
      settings: const Settings(
        testCases: 200,
        database: Database.disabled,
        verbosity: Verbosity.quiet,
      ),
      onDiagnostic: (String line) => stdout.writeln('  $line'),
    );
  } on Object catch (error) {
    stdout.writeln('  $error');
  }
}
