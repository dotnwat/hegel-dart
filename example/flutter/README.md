# hegel_flutter

Property-based testing for Flutter user interfaces, powered by
[hegel](../..).

This is the Flutter half of hegel, parked in the example directory of the
pure Dart package. It is shaped as the package it is meant to become — the
library is under `lib/`, the demonstrations are its tests — because a package
that depends on Flutter cannot also be the pure Dart one. Lifting it out is a
`git mv` and a change of the path dependency to a version constraint.

```console
$ flutter test
```

## What a property over an interface is

A property is a claim about every input. For an interface the inputs are
everything a user brings to it — the screen they have, the text size they set,
the words they type, and the order they do things in — and the hard part is not
generating those. It is knowing what "correct" means. Three answers, and the
three demonstrations here are one apiece.

### The configuration sweep — `test/layout_test.dart`

Generate the world rather than the actions: screen size, text scale, and the
content the screen is asked to show. The oracle is Flutter itself, which
reports an error for a frame it cannot lay out.

```dart
widgetProperty('a profile card fits every supported screen', (testCase, tester) async {
  final device = testCase.draw(
    deviceProfiles(size: screenSizes(), textScale: textScales(max: 2.0)),
    name: 'device',
  );
  final name = testCase.draw(hostileText(), name: 'name');
  await UiSurface.open(tester, profileScreen(ProfileCard(name: name)), device: device);
});
```

Nothing has to be written down for this to find something, which makes it the
one to point at an app that has never been tested this way. The card in the
demonstration overflows, and the counterexample is the mildest configuration
that still breaks it:

```
device = 320x568, text 1.0x
name = ''
```

An empty name on the smallest phone anyone ships, at the text size nobody
changed. The bounds of the sweep are a specification: this property says the
card is promised to survive every shipped screen at up to twice the text size,
and a card promised more is a different property.

### The model — `test/counter_ui_test.dart`

Generate the actions, and compare the screen against a model of what it should
be showing. Rules tap; an invariant holds the two together.

```dart
Rule('reset', (testCase) async {
  await ui.tap(find.byKey(const Key('reset')));
  count = 0;
  canDecrement = false;
}),
```

The counter in the demonstration has a bug that no single action reveals:
`reset` sets the count back to zero but leaves the permission to decrement
that an increment granted. Out of a hundred random walks, the engine reports
the three taps that had to happen:

```
Step 1: add one
Step 2: reset
Step 3: take one
Invariant 'the display matches the model' does not hold
```

### The monkey — `test/monkey_test.dart`

Generate the actions and know nothing about them. `MonkeyMachine` reads the
semantics tree — the same tree a screen reader walks — to find what can be
tapped and typed into, does one of those things, and insists only that the app
goes on working.

```dart
final ui = await UiSurface.open(tester, const NotesApp(), advance: oneFrame);
await runStateful(testCase, MonkeyMachine(ui));
```

No model, nothing declared. It finds that the notes app will move the first
note up past a note that is not there, and shrinks the walk to the two taps
that had to happen. Give it `accessibilityChecks` and the same walk becomes an
audit of every state the app can reach, rather than of the three states
somebody screenshotted.

## The one thing that is easy to get wrong

Flutter *captures* errors rather than throwing them at the code that caused
them, and it reports a given render object's overflow **once** and then keeps
quiet about it. Both together mean that a property which pumps a new widget
into the same tester each case gets a different answer depending on which case
met the broken layout first — so the case that finds the bug passes on the
replay, and the engine correctly reports a flaky test rather than a
counterexample.

`UiSurface.open` is the answer: it tears the previous tree down to nothing,
puts the view and the platform overrides back, applies the case's device,
pumps, and raises whatever Flutter reported. `test/surface_test.dart` pins both
halves — that Flutter reports an overflow once, and that a surface reports it
every time.

Everything else follows from it. A case has to mean the same thing on the run
that finds it and on the shrink that minimises it, which is also why action
discovery is in traversal order rather than in whatever order the tree
happened to be walked in.

## What it costs

A configuration sweep is cheap: a case is a teardown, a pump and a check,
about three milliseconds. A property that drives the interface is not, because
every step is a real frame — thirty milliseconds for a case of a dozen steps,
and shrinking replays a case many hundreds of times. The knobs are
`Settings.testCases` and `Settings.statefulStepCount`, and a three-tap bug does
not need a fifty-tap walk to be found in. The demonstrations here run in about
a minute together.

## What is out of reach

The engine ships for Linux, macOS and Windows. `flutter test` runs on the
host, so an app built for a phone is tested here exactly like one built for a
desktop — but an on-device `integration_test` on Android or iOS has no engine
to load and is out. Desktop `integration_test` should work and is untried.
