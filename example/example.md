# Examples

Two complete programs live in this directory, and one package of its own.

The programs run with `dart run` from a checkout of this package and print
what the engine found. Both use `runProperty()`, the runner without
`package:test` around it, so that a failure can be shown being found and
shrunk without failing anything. In a test suite you would write `property()`
instead, which registers an ordinary `package:test` test; the README shows
that form.

The package, `flutter/`, is the same idea pointed at a user interface, and
needs a Flutter SDK rather than `dart run`.

## `echo.dart` — a property that holds, and one that does not

    dart run example/echo.dart

The first claim is that sorting a copy of a list keeps its length. That is
true, and the run says only that it held, two hundred times.

The second is that joining words with commas and splitting them again gives
the words back:

```dart
final words = testCase.draw(
  lists(text(maxLength: 4, maxCodepoint: 0x7a)),
  name: 'words',
);
final roundTripped = words.join(',').split(',');
```

Nearly true. A word with a comma in it comes back as two words, and the
empty list comes back as one empty word. The engine finds a failing case,
shrinks it to the smallest one that still fails, and reports each draw by
name — the shape of every hegel failure, here printed rather than raised.

## `counter.dart` — a stateful property

    dart run example/counter.dart

A property over one value at a time cannot say much about something that
remembers. This one tests a counter with a bug in it — past ten it stops
counting — against a model of what it should hold. Rules say what a step
does to both, and an invariant says how they must agree:

```dart
Rule('increment', (TestCase testCase) {
  final by = testCase.draw(integers(min: 1, max: 10), name: 'by');
  counter.add(by);
  model += by;
}),
```

The engine picks the rules and runs them in an order of its choosing, and
when the invariant breaks it shrinks the *sequence*: the report is the
shortest script of steps that still drives the counter and its model apart.

Both programs turn the example database off (`Database.disabled`), so a run
never remembers a counterexample and behaves the same the second time.

## `flutter/` — property testing a user interface

    cd example/flutter && flutter test

A package of its own, shaped as the one it is meant to become: hegel's
generators, shrinking and stateful testing pointed at a Flutter app. Three
demonstrations, one for each answer to the question of what a user-interface
property is claiming — a configuration sweep whose oracle is Flutter's own
error reporting, a model the screen is held against, and a monkey that reads
the semantics tree to find what it can do and insists only that the app go on
working. Each finds a real bug and shrinks it: a card that overflows on the
smallest phone with an empty name in it, three taps that drive a counter and
its model apart, two taps that move a note up past a note that is not there.

It is not published with this package — Flutter cannot be a dependency of a
pure Dart one — and `example/flutter/README.md` says what it costs and what it
cannot reach.
