# hegel

Property-based testing for Dart, powered by the [Hegel](https://hegel.dev)
engine.

> **Status: early.** The runner, the failure reporting and the example
> database work end to end, but the generator catalog is one entry long —
> `integers()`. Combinators, collections, strings and stateful testing are
> next; `docs/property-testing-plan.md` is the plan and says what lands when.

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

## Under it: the engine

The engine is fully reachable from Dart on its own: configure a run, pull test
cases, draw values, report outcomes, read results, shrink failures, and replay
them from a reproduce blob. Every function the C ABI exposes is bound and
exercised. That layer is private (`lib/src/libhegel/`) and documented in
`docs/libhegel-bindings-plan.md`.

`example/echo.dart` drives a complete run through it:

```console
$ dart run example/echo.dart
libhegel 0.33.0
ran 50 valid test cases, passed
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

## Licence

MIT. The engine binary this package downloads is separately licensed; its
notice is vendored at `third_party/libhegel/LICENSE`.
