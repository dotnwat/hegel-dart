# Changelog

## 0.2.0

- `oneOf` takes optional `weights`, pairing one to one with its options: an
  option is drawn in proportion to its share, and a counterexample still
  shrinks toward the first option — weight shapes the distribution, never
  the shrink. Each weight is at least one and their total has to fit a
  draw; anything else is refused where it was written. The first consumer's
  document generators are what pulled this out of the deferred list.
- `TestCase.collect(value, label: ...)` tallies observations per label
  across the valid cases of a run, and the distribution prints at the end
  from `Verbosity.verbose` up — the answer to "did the generators actually
  produce the shapes this property is supposed to exercise?". Observations
  made by a case `assume` rejected, or inside a stateful rule that declined,
  are discarded with their case.

## 0.1.0

First release.

### Writing properties

- `property()` registers an ordinary `package:test` test, so groups, `-N`,
  tags, skips and the IDE's run button all work on it. `runProperty()` is the
  same runner for harnesses that are not `package:test`.
- Draw with `tc.draw(generator, name: ...)`, narrow a case with `tc.assume`,
  explain one with `tc.note`, and steer generation with `tc.target`.
- Failures are reported as the error your own `expect` raised, with its own
  stack, under the counterexample the engine shrank to. A run that finds
  several distinct bugs reports all of them.
- Counterexamples are kept in an example database and replayed ahead of
  anything new, so a property keeps failing until the bug is fixed;
  `reproduce:` replays one from a blob, which is how a CI failure comes back
  to a machine with a debugger.
- `HEGEL_TEST_CASES` and `HEGEL_DATABASE` override a run without editing it.

### Generators

- Numbers, text, and time: `integers`, `bigIntegers`, `doubles`, `booleans`,
  `durations`, `text`, `characters`, `fromRegex`, `emails`, `urls`, `domains`,
  `bytes`, `dates`, `times`, `dateTimes`, `uuids`, `ipAddresses`.
- Collections: `lists` with optional uniqueness, `sets`, `maps`, all with
  length bounds.
- Composition: `map`, `where`, `flatMap` on every generator, plus `just`,
  `sampledFrom`, `oneOf`, `optional`, `tuple2`–`tuple4`, `composite`, and
  `deferred` for recursive shapes.
- `package:hegel/generators.dart` is the catalog on its own, for prefixing.

### Stateful testing

- `StateMachine`, `Rule`, `Invariant` and `runStateful`: the engine picks the
  rules, and shrinks the *sequence* to the shortest script that still breaks
  an invariant.
- `Rule.precondition` keeps a rule off the table until it can run; `Pool<T>`
  holds what one step made for a later step to act on, and the engine chooses
  and shrinks over which.
- `maxConcurrency:` above one runs the rules several at a time, interleaving at
  every `await` in a rule body, with each worker's steps tagged in the report.
  `Rule.group` says what may overlap with what.

### The engine

- Distributed through a build hook: the pinned release is downloaded, verified
  against a checked-in SHA-256, and published as a code asset, with a
  local-engine override via pub user-defines. Nothing to install.
- Linux x64 and arm64, macOS arm64, Windows x64 and arm64 — the targets
  hegel-rust publishes.
- Use `dart build cli` rather than `dart compile exe` to bundle an application
  that depends on this package; `dart run` and `dart test` need nothing.

### Notes

- Pure-Dart properties run under `flutter test` today. Widget-level property
  testing is planned as a separate `hegel_flutter` package, because
  `flutter_test` pins `test_api` exactly.
- Requires Dart 3.13 or later, for build hooks and code assets.
