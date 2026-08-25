# hegel

Property-based testing for Dart, powered by the [Hegel](https://hegel.dev)
engine.

> **Status: 0.3.0.** The generator catalog, the combinators, the collections,
> the failure reporting, the example database and stateful testing all work
> end to end; 0.2.0 added weighted `oneOf` and `collect` statistics, and
> 0.3.0 fixes the build hook under Flutter.
> `docs/property-testing-plan.md` is the plan and says what landed when.

## Writing a property

A property is a claim about every input. Write one with `property()`, which
registers an ordinary `package:test` test, and draw the inputs from the
`TestCase` it hands you:

```dart
import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

void main() {
  property('a sum is at least its largest part', (tc) {
    final a = tc.draw(integers(min: 0, max: 1000), name: 'a');
    final b = tc.draw(integers(min: -10, max: 1000), name: 'b');
    expect(a + b, greaterThanOrEqualTo(a));
  });
}
```

The body may be synchronous or asynchronous, may draw as many values as it
likes, and fails the way any test fails. Everything `dart test` does with
tests it does with this one: `group()` nesting, `-N` by name, tags, skips, the
IDE's run button.

That property does not hold, and when it fails the engine shrinks the failing
case to the smallest one that still fails before anything is printed:

```console
$ dart test
00:00 +0 -1: a sum is at least its largest part [E]
  Expected: a value greater than or equal to <0>
    Actual: <-1>
     Which: is not a value greater than or equal to <0>

  package:matcher                 expect
  test/sum_test.dart 11:5         main.<fn>
  ...

a = 0
b = -1

Kept in the example database and replayed first next time, unless the engine turned persistence off (it does under CI).
To reproduce anywhere: property(..., reproduce: 'AXicY2IAAi5GBjj1HwACBAEY')
```

The error is the one your own `expect` raised, with its own stack. The named
draws below it are the minimal counterexample. It is kept in `.hegel/examples`
and replayed ahead of anything new next time, so the property keeps failing
until the bug is fixed — and the blob reproduces it anywhere, which is how a
failure from CI comes back to a machine with a debugger:

```dart
property('a sum is at least its largest part', (tc) {
  // ...
}, reproduce: 'AXicY2IAAi5GBjj1HwACBAEY');
```

`runProperty()` is the same runner without `package:test`, for harnesses that
are not it. `HEGEL_TEST_CASES` and `HEGEL_DATABASE` override how many cases a
run gets and where counterexamples are kept, without editing the source.

## What you can draw

Everything the engine can generate is reachable by name. Integers, big
integers, doubles, booleans and durations; text, characters, regex matches,
emails, URLs and domains; bytes, dates, times, date-times, UUIDs and IP
addresses; lists, sets and maps, with bounds and uniqueness; and tuples.

Generators compose rather than multiply. `map`, `where` and `flatMap` are on
every one of them, `oneOf` and `optional` and `sampledFrom` pick between
things, and `composite` builds a value out of several draws when none of those
fit:

```dart
final users = composite((tc) => User(
  name: tc.draw(text(minLength: 1, maxLength: 20)),
  age: tc.draw(integers(min: 0, max: 120)),
));
```

`oneOf` weights its options when you ask it to, for the case where the
interesting shape is the rare one:

```dart
final blocks = oneOf([
  paragraphs,
  headings,
  tables,
], weights: [8, 3, 1]);
```

Weight shapes the distribution and nothing else: a counterexample still
shrinks toward the first option, so put the simplest one first and the report
will tell you whether the bug needed the complicated case or merely tolerated
it. Every weight has to be at least one, and their total has to fit a draw.

`import 'package:hegel/generators.dart' as gen;` if you would rather prefix
them than import forty names.

## What the generators actually produced

A property that passes says less than it looks like if every case was
trivial.
`collect` tallies an observation per case, and the distribution prints at the
end of a verbose run:

```dart
property('reversing twice gets the list back', (tc) {
  final items = tc.draw(lists(integers()), name: 'items');
  tc.collect(switch (items.length) {
    0 => 'empty',
    < 5 => 'short',
    _ => 'long',
  }, label: 'length');
  expect(items.reversed.toList().reversed.toList(), items);
}, settings: const Settings(verbosity: Verbosity.verbose));
```

```console
Statistics:
  length (100 observed):
    56% (56) long
    43% (43) short
    1% (1) empty
```

One empty list in a hundred cases — worth knowing before you trust the
property to have covered the empty case. Only valid cases are counted: what a
case observed before `assume` rejected it, or inside a stateful rule that
declined, is discarded along with the case.

## Testing something that remembers

A property over one value at a time says little about a cache, a queue, or a
connection pool. For those, describe the steps and what must stay true between
them, and let the engine pick the order:

```dart
final class CounterMachine extends StateMachine {
  final counter = Counter();
  int model = 0;

  @override
  List<Rule> get rules => [
    Rule('increment', (tc) {
      final by = tc.draw(integers(min: 1, max: 10), name: 'by');
      counter.add(by);
      model += by;
    }),
    Rule('reset', (tc) {
      counter.reset();
      model = 0;
    }),
  ];

  @override
  List<Invariant> get invariants => [
    Invariant('the counter matches its model',
        (tc) => expect(counter.value, model)),
  ];
}

property('a counter matches its model', (tc) async {
  await runStateful(tc, CounterMachine());
});
```

When an invariant breaks, the engine shrinks the *sequence*, so what comes
back is the shortest script that still breaks it:

```
step 1 by = 1
step 2 by = 10

Step 1: increment
Step 2: increment
Invariant 'the counter matches its model' does not hold
```

Rules that cannot run yet are kept off the table with `precondition:`, and
resources one step makes for a later step to act on go in a `Pool`, which the
engine chooses from and shrinks over.

Pass `maxConcurrency:` above one and the rules run several at a time,
interleaving at every `await` in a rule body — which is the concurrency an
ordinary Dart program has, and enough to find a read and a write that were
never meant to be separable. The first such case is spent telling the engine
the run cannot promise to repeat itself; from then on a failure is reported
against the case that found it, with each worker's steps tagged.

`example/counter.dart` is the machine above, bug and all:

```console
$ dart run example/counter.dart
```

## Flutter

Pure-Dart properties run under `flutter test` today, unchanged. `flutter test`
runs build hooks for the host, so the engine arrives the same way it does
anywhere else, and `property()` needs nothing from Flutter.

Widget-level property testing is not in this package. `testWidgets` bodies run
inside a `FakeAsync` zone, and the package would inherit `flutter_test`'s exact
`test_api` pin, so it has to be a separate package rather than a dependency
inside this one. It is planned as `hegel_flutter`.

`example/flutter` is where that package is being worked out, and it runs
today: three demonstrations of what a user-interface property can claim — a
configuration sweep held against Flutter's own error reporting, a model the
screen is checked against, and a monkey that reads the semantics tree to find
what it can do. Each finds a real bug and shrinks it. It lives in the
repository rather than the published archive; `example/flutter/README.md` says
what it costs and what it cannot reach.

## Under it: the engine

The engine is fully reachable from Dart on its own: configure a run, pull test
cases, draw values, report outcomes, read results, shrink failures, and replay
them from a reproduce blob. Every function the C ABI exposes is bound and
exercised. That layer is private (`lib/src/libhegel/`) and documented in
`docs/libhegel-bindings-plan.md`.

`example/echo.dart` runs two properties through the public API, one that
holds and one that does not, and prints what a counterexample looks like:

```console
$ dart run example/echo.dart
```

## The engine binary

Nothing needs installing. A build hook downloads the pinned libhegel release
for your platform, checks it against a SHA-256 recorded in this repository, and
hands it to the Dart SDK as a code asset. `dart test` and `dart run` do this on
their own.

Supported targets are the ones hegel-rust publishes: Linux x64 and arm64, macOS
arm64, and Windows x64 and arm64. Intel macOS is not published upstream.

### Compiling an application that uses hegel

Use `dart build cli`, not `dart compile exe`:

```console
$ dart build cli --target bin/my_app.dart
```

`dart compile exe` does not run build hooks and does not bundle code assets.
It compiles without complaint and the binary then fails on its first call into
the engine:

```
Couldn't resolve native function 'hegel_version' in 'package:hegel/libhegel':
No asset with id 'package:hegel/libhegel' found. No available native assets.
```

`dart build cli` produces a bundle with the engine beside the executable:

```
bundle/
  bin/my_app
  lib/libhegel-linux-amd64.so
```

Nothing needs doing for `dart run` or `dart test`; both run the hook.

### Using a locally built engine

To test against an engine you built yourself, name it in the **root package's**
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    hegel:
      libhegel_path: ../hegel-rust/target/release/libhegel_c.so
      # Optional: share downloaded engines between projects.
      cache_dir: /shared/engine-cache
```

An environment variable cannot do this. Build hooks run in a filtered
environment — on Linux the hook process sees only `HOME` and `PATH` — so
`HEGEL_LIBHEGEL_PATH`, which other Hegel frontends honour, never reaches the
hook. User-defines are also declared inputs, so changing one re-runs the hook
instead of reusing a stale result.

An override skips the checksum, since there is nothing to check it against, but
the engine's version is still compared with the pin when a session opens.

## Development

```console
just lint        # format check and analyze
just test        # the suite
just coverage    # coverage against the floors
just regen       # regenerate the bindings (needs libclang)
```

Moving the pin to a new engine release:

```console
dart run tool/update_libhegel.dart --version 0.33.0
just regen
just test
```

## A note on the name

There is a separate `hegeltest` package on pub.dev, published by a third party
shortly before this one, with an API in the same family. It is not this
package and neither is upstream of the other; both are independent Dart
frontends to the same engine. This one is `hegel`.

## Licence

MIT. The engine binary this package downloads is separately licensed; its
notice is vendored at `third_party/libhegel/LICENSE`.
