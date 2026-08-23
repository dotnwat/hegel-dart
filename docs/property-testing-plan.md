# The hegel property-testing API — implementation plan

**Status:** proposed · **Updated:** 2026-08-21 · **Scope:** the public property-testing layer over the libhegel bindings

This plan covers the second phase of hegel-dart: the user-facing property-based testing framework
built on the completed libhegel binding layer (`docs/libhegel-bindings-plan.md`, all milestones
landed; engine pinned at 0.33.0). The deliverable is the API a Dart test author imports from
`package:hegel/hegel.dart`: the `property()` entry point, the generator library, the runner that
drives the engine loop and integrates with `package:test`, failure reporting and replay, and
stateful testing — sequential and concurrent.

The design question the plan answers: **what does a good Hegel frontend look like when the host
language is Dart** — balancing three inputs that mostly agree and occasionally pull apart:

1. the engine's own surface and semantics (typed draws, spans, collections, pools, state
   machines, origins, blobs, the example database),
2. the conventions shared by the official frontends (hegel-rust, hegel-go, hegel-java,
   hegel-typescript — all studied from source for this plan),
3. Dart's idioms and constraints (package:test's actual extension seams, no macros, no usable
   reflection, records, `FutureOr`, isolates, Flutter's FakeAsync test environment).

---

## 1. Context and goals

**What exists.** The bindings make the full 0.33 C ABI reachable and safe from Dart:
`Run`/`TestCase`/`RunResult` lifecycles, every draw primitive, spans, collections, pools,
concurrency-aware state machines, blob replay, the output callback, a per-isolate session, and a
guard-first misuse contract — with 100% line+branch coverage and the engine never mocked. The
public barrel `lib/hegel.dart` is deliberately empty.

**Goals**

- A property-testing API that a Dart developer recognizes as native — `package:test` in,
  `expect()` works, async bodies work, failures read like Dart failures — and that a Hegel user
  recognizes as Hegel: `tc.draw(generator)`, `assume`, spans, the example database, reproduce
  blobs, engine-owned shrinking.
- The complete engine feature surface exposed: every draw primitive reachable through a public
  generator, targeting, phases, health checks, modes, the database, blob replay, and stateful
  testing including the concurrency-aware API that **no other frontend ships yet** (TypeScript
  and Java expose no stateful API at all; Rust and Go expose it — Rust with two parallel APIs,
  Go with one unified one).
- Failure UX to the standard the sibling frontends set: minimal counterexample draws printed as
  named values, the original assertion error rethrown with its own stack, stable origins derived
  automatically, database-backed fail-fast replay on rerun, and an explicit blob-based reproduce
  path for CI.
- Verification to this repo's standard: real-engine integration tests as the default, pinned
  shrink-quality tests, subprocess end-to-end tests of what users actually see, the coverage
  gate maintained, every commit green.

**Non-goals (deferred, with rationale in §12)**

- A Flutter widget-testing package (`propertyWidgets`) — separate follow-on package; this plan
  keeps `hegel` free of a Flutter dependency but establishes the facts that make the follow-on
  routine (§6.9).
- Derived generators for user classes via codegen (`build_runner`) — macros were cancelled
  upstream (verified: dart.dev, Jan 2025 announcement; augmentations still experimental in Dart
  3.13), and `dart:mirrors` is JIT-only and dead for AOT/Flutter. Explicit `composite()`
  generators are the v1 answer, exactly as in hegel-go.
- Isolate-parallel concurrent stateful testing. The bindings prove two worker isolates work, but
  ordinary Dart model state cannot be shared across isolates; v1 maps engine workers onto
  concurrently interleaved **async tasks in one isolate** (§6.8), which is the concurrency model
  Dart programs actually have.
- A standalone workload runner (Antithesis-style soak, hegel-go's `Workload`) — enabled by the
  `runProperty` seam but not built now.

---

## 2. Ground truth A: what the engine owns, what this layer owns

From the vendored 0.33.0 header (`third_party/libhegel/hegel.h`) and hegel.dev. The site's own
framing (hegel.dev/explanation/how-hegel-works): the engine "implements the core of
property-based testing, including data generation, shrinking, the example database"; the library
implements "the user-facing syntax of properties and generators for a particular language. It
asks libhegel for generated data as your test runs." There is no dedicated porting guide — the
libhegel reference plus the frontends *are* the guidance, and hegel.dev/explanation/why-hegel is
explicit that ports which didn't adopt the core model "don't get the benefits of it."

**Engine-owned (never reimplemented here):** value generation from typed constraints; all
shrinking (span-guided, internal-shrinking model); the run loop as a suspended future resumed by
`nextTestCase` — including which case runs next across the explicit/reuse/generate/target/shrink
phases; collection sizing; pool variable choice; state-machine rule selection including swarm
subsets, rounds, groups, step budget, and the concurrency-level draw; targeting hill-climbing;
health checks; seeds, derandomization, CI detection, backends; blob encode/decode; the example
database.

**Frontend-owned (this plan):**

| Responsibility | Contract it satisfies |
|---|---|
| Generator combinators over the ~15 typed draw primitives | each compound generator wrapped in a span with the right reserved label; "libraries should wrap each compound generator in a span" (header) |
| Executing the user's body per test case; the catch ladder | body completed → `valid`; `AssumptionFailed` → `invalid`; `StopTest` → `overrun`; anything else → `interesting` + origin |
| Stable origin strings | "such as the location of the failing assertion" (header); groups failures into distinct bugs |
| Replaying the shrunk blob to display values and re-raise the user's error | "It reruns the minimal failing test case so it can display the drawn values and re-raise the test's own failure" (hegel.dev/reference/libhegel); the frontend "decides for itself whether the blob reproduced the failure or is stale/flaky" |
| The id→value map for pools; running rules and invariants | engine knows names and indices only; invariants are registration-only in the ABI (verified in the bindings work: nothing engine-side ever asks for one to run) |
| package:test integration, reporting, config plumbing | §6.1, §6.6 |
| Capturing per-case output on nondeterministic runs | `FAILED_NONDETERMINISTIC` failures carry no blob; "the caller should report the bug from whatever it captured while running the discovering test case" (header) |

**The span-label list is the combinator checklist.** The reserved labels enumerate exactly the
compound generators a frontend is expected to build: LIST/LIST_ELEMENT, SET/SET_ELEMENT,
MAP/MAP_ENTRY, TUPLE, ONE_OF, OPTIONAL, FIXED_DICT, FLAT_MAP, FILTER, MAPPED, SAMPLED_FROM,
ENUM_VARIANT — plus STATEFUL_RULE, "opened by the frontend's state-machine driver" (header).
Everything else (INTEGER…CONCURRENCY) the engine emits internally.

**The canonical draw shapes.** hegel-typescript 0.4.x targets the same typed-call ABI
generation as our 0.33 pin, and its `src/generate.ts` is the reference interpreter for how
compound draws must hit the engine (fetched and archived during research). The shapes the Dart
combinators must reproduce, so choice sequences shrink the way the engine expects:

- **list**: `startSpan(LIST)` → `newCollection(min,max)` → loop `collection.more()`, each
  element inside `startSpan(LIST_ELEMENT)`/`stopSpan` → duplicates (when unique) reported via
  `collection.reject('duplicate element')` and re-looped → free collection → `stopSpan`.
- **map**: same protocol under MAP/MAP_ENTRY, key and value drawn inside one entry span,
  duplicate keys rejected via `collection.reject('duplicate key')`.
- **oneOf**: `startSpan(ONE_OF)` → `drawInteger(0, n-1)` → recurse into the chosen branch →
  `stopSpan`.
- **tuple**: `startSpan(TUPLE)` → elements in order → `stopSpan`.
- **filter**: per attempt `startSpan(FILTER)` → draw → predicate; on failure
  `stopSpan(discard: true)` and retry — **3 attempts, then assume-reject** (the constant is
  uniform across Rust, Go, TypeScript, and Java).
- **string family**: build one engine `StringGenerator` per frontend generator instance, reuse
  it across draws. TypeScript caches these per schema object "for the life of the process and
  deliberately never freed — a bounded leak of one native generator per generator instance"
  (generate.ts module doc); §6.4 adopts the same policy with a leak-tracker exemption.
- top-level draws only are user-visible: every frontend counts span depth and reports a draw
  only at depth 0, so combinator internals stay silent components of the parent value.

---

## 3. Ground truth B: what the sibling frontends converge on

All four official frontends were studied from source (hegel-rust and hegel-go at HEAD;
hegel-typescript 0.4.5, engine 0.32.5; hegel-java 0.4.2, engine 0.14.14 — the Java frontend is
two ABI generations behind and its CBOR details are ignored where they conflict). Full source
archives from the research phase: hegel-typescript and hegel-java under the session scratchpad;
repos at github.com/hegeldev/{hegel-rust,hegel-go,hegel-typescript,hegel-java}.

**Uniform across all four — adopt without debate:**

- The body receives a `TestCase` handle (`tc`; Go: `ht *hegel.T`) and calls `draw(generator)`.
  Properties integrate with the *native* test runner (cargo test / go test / vitest / JUnit 5);
  no frontend ships its own runner UI.
- `Generator<T>` with `map` / `flatMap` / `filter`, `oneOf` (uniform), `optional`,
  `sampledFrom`, `just`, collections via the engine's collection protocol, and an imperative
  `composite` escape hatch. The algebra is closed (Go seals the interface) so user code cannot
  bypass span discipline; `composite` is the sanctioned escape.
- `assume(condition)` for preconditions; generator `filter` = 3 span-discarded retries then
  assume-reject.
- Failure output = named top-level draws printed as assignment-like lines on the **final replay
  only**, then the user's own error; `note()` output appears only then too.
- Origin derived automatically from the first non-framework stack frame (Go, TS) or panic
  location (Rust); Java formats `'<ExceptionSimpleName> at <File>:<Line>'`.
- The example database is the primary replay mechanism, keyed by native test identity (Rust
  `module_path::fn`, Go `t.Name()`, Java method name, TS `testFn.toString()`), on by default
  locally, disabled + derandomize in CI (the engine itself detects CI).
- Settings model "not set = engine default" (Go's functional options literally apply nothing;
  our L2 `Settings` already works this way).

**Divergences, and the side this plan takes:**

| Question | Sibling positions | Dart decision (rationale in §5–§6) |
|---|---|---|
| sync/async entry split | TS has `test` + `testAsync` (JS can't overload on return type usefully); others sync-only | one entry point; body is `FutureOr<void> Function(TestCase)` — Dart's `FutureOr` erases the split |
| stateful API | absent (TS, Java); two parallel APIs (Rust sequential vs concurrent); one unified API (Go) | one unified API, Go-style, with async rules (§6.8) |
| blob exposure | user-facing attribute (Rust `#[hegel::reproduce_failure]`), internal-only (TS, Go) | user-facing: `reproduce:` parameter + printed hint (§6.6) — CI has no database, so the blob is the only artifact there |
| draw naming in output | macro rewrite of `let x =` (Rust), runtime source parsing (Go), positional `draw_N` (TS), optional label param (Java) | Java's optional `name:` parameter + positional fallback; no macros exist and runtime source parsing is deferred polish |
| multiple failures | aggregate error (TS), rethrow original + opt-in aggregate (Java) | rethrow the first original error with its stack; surface the rest via `registerException` (§6.6) |
| config surface | attribute args (Rust/Java), options object (TS), functional options (Go); Rust adds `HEGEL_TEST_CASES` / `HEGEL_DATABASE` env overrides | a `Settings` object parameter (reusing the binding layer's) + the two Rust env overrides |

**Also on pub.dev already:** `hegeltest` 0.5.0 (+ `hegeltest_flutter`), published days before
this plan by a third party (repo `LetsTestTools/hegel-dart`), with a `hegelTest('...', (tc) {...})`
API in the same family shape. Verified 2026-08-21: the package name **`hegel` is unclaimed**
(pub.dev API 404) and this repo's pubspec already uses it. The competitor validates demand and
the API direction; it is not upstream (not linked from hegel.dev, whose community list has no
Dart entry). Consequence: publishing early matters more than it did, and API quality — stateful
testing, failure UX, Flutter posture — is the differentiator, since the core shape will look
similar in any faithful frontend.

---

## 4. Ground truth C: Dart facts the design rests on

Verified locally on Dart 3.13.0 stable against test 1.31.2 / test_api 0.7.13 / test_core 0.6.19
sources in the pub cache, plus researched package/Flutter sources (with URLs where noted):

1. **The only sanctioned extension point is wrapping `test()`.** `test_api`'s README says it is
   "not intended to be publicly used"; the architecture doc's plugin API remains unshipped.
   Every credible Dart test framework (flutter_test's `testWidgets`, glados, kiri_check,
   ribs_check) registers plain `test()` calls. `test()`'s full signature (test_core 0.6.19):
   `(Object? description, FutureOr Function() body, {testOn, timeout, skip, tags, onPlatform,
   retry, TestLocation? location, solo})`. `location` lets a wrapper report the *user's* call
   site to IDEs and the JSON reporter. Wrappers carry `@isTest` (package:meta) so IDE run
   gutters work; description must be the first parameter.
2. **`package:test_api/hooks.dart` is the official in-test seam**: `TestHandle.current.name`
   (the full name including group prefixes), `TestFailure`, `formatStackTrace`, and
   `OutstandingWork`. This is how the runner gets a stable database key without macros.
3. **Async error attribution is zone-based.** The Invoker runs each test body in a zone whose
   `handleUncaughtError` routes stray async errors to the *current test*; `print` is captured
   per test via `ZoneSpecification`; `printOnFailure(message)` buffers text and emits it only
   if the test fails; `registerException(error, stackTrace)` reports an error to the current
   test through the zone without throwing. The default 30s timeout is **inactivity-based**
   (reset by a heartbeat on async activity), so a long property that awaits between cases does
   not trip it, and fully synchronous FFI stretches suppress the timer entirely — the engine's
   own TooSlow health check (30s per case) is the complementary guard.
4. **Dynamically registering tests in loops is idiomatic and supported**; the only restriction
   is declaring tests after the run begins (`StateError`). Suites (files) run in separate
   isolates, concurrently — which composes with the per-isolate `Libhegel` session for free.
5. **Language constraints.** Macros: cancelled (dart.dev announcement, Jan 2025); augmentations:
   experiment-flagged in 3.13; `dart:mirrors`: JIT-only, absent from AOT/`dart compile exe`;
   parameter destructuring of records: does not exist (dart-lang/language#3001 open). Records,
   patterns, sealed/final class modifiers, and extension types are all stable. Consequence: the
   imperative `tc.draw(...)` style is not just family-consistent, it is the *only* shape that
   avoids Dart's multi-arity callback problem outright (glados caps at `Glados3`; kiri_check
   pushes arity into `combine2..8` + destructure-in-body; ribs_check generates arity-22
   extensions).
6. **Existing Dart PBT.** glados (41k downloads/30d, dormant ~2 years, fixed `Random(42)` —
   deterministic but no seed reporting or replay); kiri_check (Hypothesis-inspired, maintained,
   `property('...', () { forAll(arb, (v) {...}); })`, value-level shrinking, stateful
   `Behavior/Action` API, statistics via `collect()`); ribs_check (record-of-generators
   `forAll`, prints an actionable `RIBS_CHECK_SEED=... dart test --plain-name "..."` repro
   line); several smaller ports. None has engine-grade shrinking, a failure database, or
   choice-sequence replay — that is this package's differentiation, and ribs_check's repro-line
   UX is the local bar to beat.
7. **Flutter.** Build hooks ("native assets") are stable since Dart 3.10 / Flutter 3.38
   (flutter/flutter#129757 closed: "Build hooks and code assets support in Flutter is available
   in stable"), and `flutter test` builds hooks for the host — so this package's engine
   acquisition works under `flutter test` today. `testWidgets` bodies run inside a **FakeAsync
   zone** (verified from flutter_test source): synchronous FFI calls are fine there, but a
   future completed by another OS thread or real I/O deadlocks unless wrapped in
   `tester.runAsync`. Since every hegel draw is a synchronous FFI call, the property loop itself
   is FakeAsync-compatible by construction. flutter_test **pins `test_api` exactly** (0.7.12 on
   current stable), so this package's `test` dependency must stay wide enough to include the
   one `test` release compatible with each Flutter stable (today: 1.31.1).

---

## 5. Design overview

The load-bearing decisions, then the API in §6:

1. **Imperative draws, one entry point.** `property(description, (tc) async { ... })` registers
   exactly one `package:test` test. The body draws values through `tc.draw`, any number, any
   dependency structure, sync or async. No `Glados2`-style arity ladder, no
   record-destructuring workarounds, no separate async variant.
2. **The runner is a pull loop; only the body awaits.** hegel-typescript's factoring is adopted
   directly: a synchronous engine-pump loop yields test cases; the driver awaits the user body
   between pumps; draws are synchronous FFI throughout. This is what makes async properties
   trivial and FakeAsync-safe.
3. **Closed generator algebra, spans by construction.** `Generator<T>` is `abstract final`; all
   combinators live in the package and each opens its reserved span per §2's canonical shapes.
   `composite()` is the escape hatch (span label minted above the reserved range, since 0.33
   reserves no COMPOSITE label). User-defined generator *classes* are impossible; user-defined
   generator *values* are a one-liner.
4. **Engine defaults are never overridden silently.** The L2 `Settings` omission model is
   promoted to the public API unchanged: what the user does not set, the engine decides —
   including its CI behavior. The property layer adds only what the engine cannot know: the
   database key (derived from test identity), env overrides, and replay plumbing.
5. **Failures are the engine's, errors are the engine's, but the *report* is Dart's.** The
   minimal counterexample is replayed through the user's own body; the original error object is
   rethrown with its original stack; draws, notes, engine chatter, seed and reproduce hints are
   emitted via `printOnFailure` so passing properties are silent.
6. **Stateful testing is a library call inside a property** (`runStateful(tc, machine)`), one
   API from sequential to concurrent, with concurrency realized as interleaved async tasks in
   one isolate — each worker driving its own `TestCase` clone stream exactly as the ABI
   prescribes for threads. This ships the engine capability no sibling frontend has, in the
   concurrency model Dart programs actually use.
7. **Everything not engine-backed is cut or deferred**: no value-level shrinking, no schema IR
   (a TS-historical artifact of the 0.23 CBOR ABI), no weighted `frequency` (no sibling has
   it), no statistics/`collect` in v1, no codegen derive. §12 lists each with its revisit
   trigger.

What using it looks like (the target, end-state):

```dart
import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

void main() {
  property('round-trip: decode inverts encode', (tc) {
    final message = tc.draw(lists(integers(min: 0, max: 255)), name: 'message');
    expect(decode(encode(message)), equals(message));
  });

  property('index survives concurrent writers', (tc) async {
    await runStateful(tc, IndexMachine(), maxConcurrency: 4);
  });
}
```

And a failure, as rendered by `dart test` (draws and hints emitted via `printOnFailure`):

```
00:03 +12 -1: round-trip: decode inverts encode [E]

  message = [0, 128]

  Expected: [0, 128]
    Actual: [0, 0]
  package:matcher            expect
  test/codec_test.dart 7:5   main.<fn>

  Counterexample stored in .hegel/examples; rerunning replays it first.
  To reproduce anywhere: property(..., reproduce: 'AAECAwQF...')
```

---

## 6. Public API design

### 6.1 Entry points

```dart
@isTest
void property(
  Object? description,
  FutureOr<void> Function(TestCase) body, {
  Settings settings = const Settings(),
  String? reproduce,            // a reproduce blob: replay exactly this case, no run loop
  bool? printBlob,              // null = auto: print when the database is off (CI)
  // pass-through to test(), same names, same semantics:
  String? testOn,
  Timeout? timeout,
  Object? skip,
  Object? tags,
  Map<String, dynamic>? onPlatform,
  int? retry,
});
```

- Registers exactly one `test()` whose `location:` is the caller's frame (parsed from
  `StackTrace.current` via `package:stack_trace`), so IDEs and the JSON reporter point at the
  user's `property(` line, not inside the package. `solo` is not forwarded (it is
  `@doNotSubmit`; users who need it can wrap in `test`+`runProperty`).
- The description composes with `group()` nesting like any test; `dart test -N`/`--name`
  filtering works unchanged.
- Inside the registered body, the runner derives the **database key** as
  `'<suite path>:<full test name>'` — the path from the registration-time caller frame, the
  name from `TestHandle.current.name` (includes group prefixes; hooks.dart is the official
  seam, §4.2). Stable across runs and machines, per-property unique, no user input — the same
  property Go solves with `t.Name()` and Rust with `module_path!()`.
- `reproduce:` switches the property to single-replay mode: `TestCase.fromBlob` + one body
  execution + report (§6.6). This is Rust's `#[hegel::reproduce_failure]` in Dart clothes.

```dart
Future<void> runProperty(
  FutureOr<void> Function(TestCase) body, {
  Settings settings = const Settings(),
  String? databaseKey,
  String? reproduce,
  void Function(String line)? onDiagnostic,   // where draws/notes/engine lines go; default: printOnFailure when in a test, stderr otherwise
});
```

The programmatic runner: no `package:test` required, throws on failure, returns normally on
pass. `property()` is a thin shell over it. It exists for the same reasons hegel-go has
`hegel.Run`: composition into other harnesses, a future workload/soak runner, and — immediately
— this package's own tests, which can drive the full runner without spawning subprocesses.

**Dependency change:** `test` moves from dev-dependency to a regular dependency, constrained
`^1.31.0` (needs `location:` and `TestLocation`; 1.31.1 is the release compatible with current
Flutter stable's `test_api 0.7.12` pin — §4.7). glados sets the precedent for a PBT library
depending on `test` directly. `stack_trace` and `meta` become direct dependencies (both already
transitively present; house rule: nothing relied on transitively).

### 6.2 The `TestCase` handle

The public `TestCase` is a new class in the property layer wrapping the binding-layer test case
(which stays unexported; internally the property layer imports it as `engine.TestCase`). All
frontends name this type `TestCase` and the parameter `tc` — kept.

```dart
final class TestCase {
  /// Draws a value. [name] labels it in the failure report.
  T draw<T>(Generator<T> generator, {String? name});

  /// Rejects this test case if [condition] is false (the case becomes invalid
  /// and does not count against the budget).
  void assume(bool condition);

  /// Records [message] for the failure report. Silent unless this case is the
  /// final replay of a counterexample (or the run is nondeterministic, §6.6).
  void note(Object? message);

  /// Records an observation for targeted generation; higher is more
  /// interesting. No-op unless the target phase is enabled.
  void target(double value, {String label = 'target'});
}
```

- `draw` counts span depth; only depth-0 draws are recorded (value + optional name) into the
  per-case draw log. On the final replay the log renders as `name = <value>;` lines
  (`draw_1 = ...` unnamed), Java-style. Values render via a small `repr()` helper (strings
  quoted, `Uint8List` as hex, collections recursively) rather than raw `toString`, matching
  Java's escaping discipline.
- `assume(false)` throws the existing `AssumptionFailed` — deliberately the *same* type the
  engine's own rejections map to, so the catch ladder and the stateful driver treat user and
  engine rejection uniformly (with one latch-aware distinction, §6.8).
- `target` maps to `hegel_target`; the default label serves the common single-objective case
  (Rust auto-labels from source text, which Dart cannot do; Go requires a label; a default is
  the ergonomic middle).
- Not exposed: `isFinalReplay`, span methods, the engine handle. Generators reach those through
  a package-internal interface, keeping the algebra closed (§6.3).

### 6.3 `Generator<T>` and the combinator algebra

```dart
abstract final class Generator<T> {
  Generator<R> map<R>(R Function(T) transform);          // MAPPED span
  Generator<R> flatMap<R>(Generator<R> Function(T) bind); // FLAT_MAP span
  Generator<T> where(bool Function(T) predicate);         // FILTER span, 3 retries → assume
}
```

- `abstract final` + all combinators implemented in one library (with parts) = a closed
  algebra: the only way to introduce custom generation is `composite()`, which is a function
  value, not a subclass. This is Go's sealed-interface decision, and it is what guarantees the
  span discipline (§2) can't be bypassed.
- `.where` rather than `.filter`: `Iterable.where` is the strongest naming anchor in Dart, and
  Effective Dart's "prefer consistency with core libraries" outranks family vocabulary when the
  two conflict; dartdoc cross-references "filter" for Hegel users. `.map`/`.flatMap` agree with
  both worlds.
- `map` opens a MAPPED span around the source draw (matching Rust/Go; the TS fused path skips
  it only as a schema-era optimization — parity with the current-ABI frontends wins, and the
  pinned shrink-quality suite in §8 is the arbiter if this proves to matter).
- Draw-time plumbing: generators receive an internal draw context (the engine test case +
  session + span helpers). A `DrawContext` seam interface — the analogue of TS's 7-method
  `DataSource` — keeps every combinator unit-testable against a scripted fake without the
  engine, which the fake-tier of the test strategy (§8) uses for unreachable branches only.

Escape hatch and recursion:

```dart
Generator<T> composite<T>(T Function(TestCase) build);   // minted label ≥ SpanLabel.firstAvailable

// Declared inside the algebra library, so it can subtype the final Generator.
final class DeferredGenerator<T> extends Generator<T> {   // returned by deferred()
  void define(Generator<T> generator);   // exactly once; drawing before define throws
}
DeferredGenerator<T> deferred<T>();
```

`composite` receives the *public* `TestCase`, so a custom generator is written exactly like a
property body (family-uniform; the hegel-go docs frame imperative generation as the feature it
is). Its span label is one minted constant above the reserved range — Dart has no compile-time
source hashing (Rust) and no per-instance stable hash worth inventing; Go's single
`LABEL_COMPOSITE` precedent is fine. `deferred()` is the Java/Rust recursion helper Go's users
visibly miss (manual closure + depth counter); the engine's size control keeps recursive
structures finite.

### 6.4 The generator catalog

Top-level factory functions (Effective Dart: prefer top-level functions over static-only
namespace classes), exported from `package:hegel/hegel.dart` and alone from
`package:hegel/generators.dart` for users who want `import ... as gs;` sibling-style. Naming
rule, applied consistently: **when Dart core has an anchor, follow Dart; otherwise follow the
Hegel family.** Concretely: `min`/`max` (L2 precedent, kiri_check precedent),
`minLength`/`maxLength` for every sized thing (`List.length`, `String.length`, `Set.length`
are the anchors; family uses "size" — noted in dartdoc).

| Function | Returns | Engine path | Notes |
|---|---|---|---|
| `integers({int? min, int? max})` | `int` | `drawInteger` | null bounds = full int64 range (Rust type-range convention) |
| `bigIntegers({BigInt? min, BigInt? max})` | `BigInt` | `drawBigInteger` | null bounds = ±2^127 (TS convention: wide-finite ≈ unbounded distribution) |
| `doubles({double min = double.negativeInfinity, double max = double.infinity, bool? allowNan, bool? allowInfinity, bool excludeMin = false, bool excludeMax = false})` | `double` | `drawFloat` width 64 | Hypothesis defaults: NaN allowed iff fully unbounded, infinity iff the side is open; 32-bit width deferred |
| `booleans({double probability = 0.5})` | `bool` | `drawBoolean` | probability replaces a separate weighted variant |
| `text({int minLength = 0, int? maxLength, String? codec, int? minCodepoint, int? maxCodepoint, List<String>? categories, List<String>? excludeCategories, String? includeCharacters, String? excludeCharacters})` | `String` | `drawString` over `StringGenerator.text` | returns concrete `TextGenerator` (usable as `fromRegex` alphabet); null maxLength = engine-unbounded |
| `characters(...)` | `String` | text with min=max=1 | Dart has no char type; same filters as `text` |
| `fromRegex(String pattern, {bool fullMatch = true, TextGenerator? alphabet})` | `String` | `StringGenerator.regex` | Python `re` syntax, per engine |
| `emails()` / `urls()` / `domains({int maxLength = 255})` | `String` | the respective `StringGenerator` | draw can self-reject → engine `AssumptionFailed`, handled like any assume |
| `bytes({int minLength = 0, int? maxLength})` | `Uint8List` | `drawBytes` | family says "binary"; `BytesBuilder`/`utf8.encode` anchor "bytes" in Dart |
| `dates({DateTime? min, DateTime? max})` | `DateTime` (UTC, midnight) | `drawDate` | engine default range year 1–9999 fits `DateTime`; shrinks toward 2000-01-01 |
| `times({Duration? min, Duration? max})` | `Duration` since midnight | `drawTime` | Dart core has no time-of-day type; Flutter's `TimeOfDay` belongs to the follow-on package |
| `dateTimes({DateTime? min, DateTime? max})` | `DateTime` (UTC, naive) | `drawDateTime` | microsecond precision matches both sides |
| `durations({Duration? min, Duration? max})` | `Duration` | `drawInteger` over microseconds | Rust/Java precedent |
| `uuids({int? version})` | `String` (8-4-4-4-12) | `drawUuid` | no SDK UUID type; canonical text form |
| `ipAddresses({InternetAddressType? type})` | `InternetAddress` | `drawIpv4/6` | dart:io is fine — the package is VM-only by nature; unset type = ONE_OF of v4/v6 |
| `just<T>(T value)` | `T` | no draw | family name |
| `sampledFrom<T>(List<T> values)` | `T` | index `drawInteger` in SAMPLED_FROM span | throws on empty list at construction |
| `oneOf<T>(List<Generator<T>> options)` | `T` | §2 ONE_OF shape | uniform; weighted variant deferred |
| `optional<T>(Generator<T> inner)` | `T?` | ONE_OF-of-null shape under OPTIONAL span | Dart nullability makes this the one frontend where the natural return type is exact |
| `lists<T>(Generator<T> elements, {int minLength = 0, int? maxLength, bool unique = false})` | `List<T>` | §2 list shape | `unique` by `==`/`hashCode` (Dart's own equality; a Set tracks seen) |
| `sets<T>(Generator<T> elements, {int minLength = 0, int? maxLength})` | `Set<T>` | SET/SET_ELEMENT + reject duplicates | |
| `maps<K, V>(Generator<K> keys, Generator<V> values, {int minLength = 0, int? maxLength})` | `Map<K, V>` | §2 map shape | duplicate keys rejected |
| `tuple2<A,B>(Generator<A>, Generator<B>)` … `tuple4` | `(A, B)` … | TUPLE span | records; beyond 4, `composite` reads better than a longer ladder |

Implementation notes carried from §2 and the bindings:

- Every argument the engine would reject is validated Dart-side first where L2 already does
  (negative sizes, inverted bounds); catalog functions validate at *construction* what they can
  (empty `sampledFrom`, bad codec strings pass through to the engine's own construction-time
  validation in `StringGenerator`).
- String-family generators build their native `StringGenerator` lazily on first draw, cache it
  **by specification** for the process lifetime, and never free it — the TS bounded-leak
  policy, adopted because construction is expensive (regex compilation, Unicode tables) and the
  free rule ("only after every draw using it has completed") has no good deterministic point in
  a value-semantics API. The leak-diagnostics layer gets one exemption hook for these, so the
  assert-mode tracker stays meaningful for everything else.

  *Corrected during commit 11's review.* This said "per generator instance", which is the wrong
  key and was measured to be: the natural way to write a property puts the generator in the
  body (`tc.draw(text())`), which is a fresh instance per test case, so a hundred cases built
  and kept a hundred compiled alphabets — invisibly, since the exemption above is exactly the
  diagnostic that would have reported them. Keyed by specification the same property builds
  one, and the cost is what this bullet always claimed: bounded by the number of distinct
  string generators a program *describes*, a property of the source rather than of how long a
  run goes on. The keys are length-prefixed rather than delimiter-joined, because every
  free-form field in a specification — a pattern, an alphabet, a category name — can contain
  whatever a delimiter would have been.
- `unique:` uses Dart `==` — unlike TS, which needed a structural `valueKey()` because JS
  `Set` identity is wrong for its values; Dart's story is the language's own, documented (a
  list of lists won't dedupe structurally unless the element type implements `==`).

### 6.5 Configuration

The binding layer's `Settings` (and `Phase`, `HealthCheck`, `Mode`, `Backend`, `Verbosity`,
`Database`) are promoted to the public API and re-exported from the barrel — they are already
value-typed, const-constructible, omission-aware, and shaped 1:1 with the engine, and their
"null = engine decides" contract is exactly the frontend-settings philosophy hegel-go
demonstrates. Their dartdoc gets a user-facing pass (same content, less binding jargon). No
parallel property-layer settings type: one settings vocabulary from the ABI to the test file.

Resolution order (first hit wins), per knob:

1. `reproduce:` parameter (forces `Mode.singleTestCase` semantics via the blob path),
2. environment: `HEGEL_TEST_CASES`, `HEGEL_DATABASE` (path, or empty string = disabled) — the
   two overrides hegel-rust honors, read via `Platform.environment`,
3. the `settings:` argument,
4. engine defaults (including CI detection — the engine flips database off and derandomize on
   by itself; the property layer never re-implements CI sniffing).

The property layer supplies `databaseKey` automatically (§6.1) whenever the user hasn't set one
— which also satisfies the binding layer's refusal of an enabled database without a key. A
user-set `settings.databaseKey` wins (shared-key scenarios).

Engine output (`Run.start(onOutput: ...)`): routed line-by-line into the diagnostic sink —
`printOnFailure` by default, so summary lines, health-check text, and the engine's
nondeterminism notice appear exactly when a property fails and never otherwise. At
`Verbosity.verbose` and up the sink switches to live `print`, since asking for verbosity means
wanting it now. The engine's default verbosity is left untouched (normal) — its output is
buffered, not suppressed, so the failure report always includes what the engine said.

### 6.6 Failure reporting and replay

The runner's shape follows hegel-typescript's `runSteps` generator (sync pump, driver awaits
the body), with the engine loop from the bindings:

1. `Run.start` → loop `nextTestCase()`; for each case: run the body (§6.7), map the outcome
   through the catch ladder — `AssumptionFailed` → `invalid`, `StopTest` → `overrun`,
   anything else → `interesting` with origin — `markComplete`, dispose. Per-case bookkeeping:
   the draw log, notes, and engine output lines (buffered; needed for the final report and,
   on nondeterministic runs, captured for *every* case because there will be no replay).
2. `result()`:
   - `passed` → return.
   - `error` → throw `PropertyError` (new, `implements Exception`) carrying the engine's
     run-level message (health checks, nondeterminism mismatch, engine invariants). Not a
     `TestFailure`: the run reached **no verdict on the property**, and package:test renders
     non-TestFailure throws as errors — the correct severity, mirroring Java's
     `HealthCheckFailure extends HegelException` distinction.
   - `failed` → for each distinct failure: read `origin` and `reproductionBlob`; replay the
     blob via `TestCase.fromBlob` as a **final** case (draw log renders, notes render, the
     body's own error is captured with its stack). A replay that *passes* is reported as
     stale/flaky rather than silently dropped (the header's contract: the caller decides).
     Then: first failure's error is rethrown via `Error.throwWithStackTrace` — the original
     `TestFailure`/exception object, Java's "friendlier to debuggers" call, so `expect()`
     mismatch output renders natively; each additional distinct failure is surfaced through
     `registerException`, package:test's sanctioned multi-error channel (§4.3). A trailing
     diagnostic line lists all origins.
   - `failedNondeterministic` → no blobs exist; the report is assembled from the discovering
     case's captured log (which the runner kept because `isNondeterministic` was stamped on
     the case up front — the header documents exactly this pattern), then the captured error
     is rethrown the same way.
3. Diagnostics rendered on failure (via `printOnFailure`): the draw lines, notes, buffered
   engine output, and the reproduce ladder — a database line when persistence is on
   ("Counterexample stored in …; rerunning replays it first"), the blob hint when `printBlob`
   resolves true (explicitly: when the database is disabled, i.e. CI, where the blob is the
   only artifact — improving on Rust's always-opt-in default), and the seed when one was set.

**Origins.** Derived from the failure's stack: the first frame not in `package:hegel`,
`package:test*`, `package:matcher`, `package:stack_trace`, or `dart:*` (parsed with
`package:stack_trace`), formatted `'<errorType> at <uri>:<line>'` — Java's format, Go's
automation. Stable across cases by construction (same assertion site → same string), and two
different assertion sites in one body are two distinct bugs, which is the engine's grouping
contract. Fallback when no user frame exists: the error's `runtimeType`.

**`reproduce:`.** Replays exactly one case from the blob: `TestCase.fromBlob`, body once,
draws/notes render unconditionally, error (if any) rethrown. Stale blobs surface the engine's
own diagnostics: invalid blob → `PropertyError` with the engine message; generator-mismatch →
the overrun path with a "this blob no longer matches the generators" explanation. This is the
CI-failure → local-repro bridge; the database covers the local loop without any parameter.

### 6.7 Async properties and zones

The body type is `FutureOr<void> Function(TestCase)`. Per case, the runner executes the body
inside `runZonedGuarded`:

- Synchronous throws and errors flowing through the awaited future hit the catch ladder
  directly.
- **Out-of-band async errors** (a fire-and-forget future failing mid-case) land in the zone
  guard, which records the *first* error as the case's outcome; without this fork they would
  bypass the ladder entirely and hit package:test's Invoker as a whole-test failure mid-run,
  wedging the engine loop. The guarded zone is a child of the test's zone, so `print` capture
  and `TestHandle.current` continue to work.
- An error arriving *after* the case completed (leaked async work) is forwarded to
  `registerException` with a "leaked async work escaped its test case" prefix — attributed,
  loud, but not corrupting a later case's status.
- Explicitly documented as unsupported inside property bodies: `expectAsync*`/`neverCalled`
  (they register *test*-level outstanding callbacks that cannot be scoped to a case) and
  anything relying on the test's own zone for completion. `expectLater` works (it returns a
  future the body can await).

The draw primitives stay synchronous — an `await` between draws suspends the case with the
engine handle idle, which the ABI is fine with (the run advances only on `nextTestCase`).
`StopTest`/`AssumptionFailed` raised by a draw after the body has gone async still unwind
through the body's future into the ladder; the binding layer's family abort latch already
guarantees a late/leaked draw on an aborted case re-raises the same signal instead of
corrupting the engine.

### 6.8 Stateful testing

One API, sequential to concurrent — hegel-go's unification, with Rust's model-in-the-machine
ergonomics:

```dart
final class Rule {
  Rule(String name, FutureOr<void> Function(TestCase) body,
      {bool Function()? precondition, String? group});
}

final class Invariant {
  Invariant(String name, FutureOr<void> Function(TestCase) body);
}

abstract base class StateMachine {
  List<Rule> get rules;                       // required, non-empty
  List<Invariant> get invariants => const []; // run at every join point, and once initially
}

Future<void> runStateful(
  TestCase tc,
  StateMachine machine, {
  int minConcurrency = 1,
  int maxConcurrency = 1,
});
```

Usage — the model state lives in the machine instance, constructed fresh per test case because
`runStateful` is called from the property body:

```dart
final class CounterMachine extends StateMachine {
  int model = 0;
  final counter = CounterUnderTest();

  @override
  List<Rule> get rules => [
        Rule('increment', (tc) async {
          final by = tc.draw(integers(min: 1, max: 10), name: 'by');
          await counter.add(by);
          model += by;
        }),
        Rule('reset', (tc) async {
          await counter.reset();
          model = 0;
        }),
      ];

  @override
  List<Invariant> get invariants =>
      [Invariant('matches model', (tc) async => expect(await counter.value, model))];
}

property('counter matches its model', (tc) async {
  await runStateful(tc, CounterMachine());
});
```

**Driver protocol** (the part no other frontend has shipped against 0.33's grouped, concurrent
ABI — the bindings' two-worker test already proved the primitives):

- Registration: rule names, `group:` strings mapped to distinct group ids (ungrouped rules
  share one), invariant names, concurrency bounds → `newStateMachine`; the engine draws the
  concurrency level.
- Round loop on the root case: `nextGroup()` until null; per round, each of `concurrency`
  workers pulls `nextRule(workerCase, workerIndex)` until its round is done; invariants run at
  every join point (and once before the first round), on the root case's stream.
- Each rule invocation is wrapped in a `SpanLabel.statefulRule` span (the header assigns this
  label to the frontend driver) and logged as a note (`Step 3: increment`), so failures read as
  a step script.
- **Preconditions.** Two forms, both engine-integrated: the declarative `precondition:` closure
  is checked before the rule body runs (rejecting via `ruleRejected` without wasting draws —
  the preferred form), and a user-level `tc.assume(...)` inside the rule body is caught by the
  driver and converted to `ruleRejected` + retry, Rust's pattern, for preconditions that
  depend on drawn parameters. The one distinction that matters: an **engine-originated**
  rejection (empty pool draw, self-rejecting string draw) has already latched the case abort
  in the binding layer and cannot be converted to a rule rejection — the driver detects the
  latch and lets the case end invalid, which mirrors Rust/Go ("drawing from an empty pool
  rejects the case"). Guard with `precondition:` instead; the dartdoc says exactly this.
- **Typed pools**, the model-variable mechanism (Rust `Pool<T>`, Go `Pool[T]`):

  ```dart
  final class Pool<T> {
    Pool(TestCase tc);                    // engine pool created on the case's family
    void add(TestCase tc, T value);       // fresh engine id ↔ value, mapping kept here
    Generator<T> get reusable;            // engine picks which existing variable
    Generator<T> get consumed;            // …and removes it
    int get length;
  }
  ```

  The public `Pool<T>` shadows the binding layer's raw-id pool (which stays unexported); the
  engine still owns *which* variable a draw picks and how it shrinks.
- **Concurrency = interleaved async tasks.** With `maxConcurrency > 1`, the driver clones the
  root case once per worker (each clone is an independent choice stream — the ABI's own recipe
  for threads), runs one async task per worker, and `Future.wait`s them at each join point.
  Within a worker, rules run strictly sequentially; *across* workers, execution interleaves at
  every await point in the rule bodies — which is precisely the concurrency real Dart programs
  have, and enough to catch lost-update/interleaving bugs in async SUTs (the same KV-store
  race both Rust's and Go's example suites plant and find). Rules in different groups never
  overlap, per the engine's rounds. What a worker notes *and draws* is buffered and tagged
  `[worker N]`, flushed round-by-round (Go's presentation), with steps numbered per worker
  rather than per case -- a shared counter cannot be wound back when a rule declines without
  handing a number out twice, and the worker-at-a-time flush means a case-wide number would
  be read out of order regardless; simultaneous worker outcomes resolve by the Go
  precedence (control signals > overrun > invalid > failures, lowest index first, dropped
  failures noted).
- The first `maxConcurrency > 1` creation on a run is refused by the engine with
  `AssumptionFailed` (the documented handshake, already pinned by the bindings' tests); the
  driver reports the case invalid and the run is nondeterministic from the next case on —
  which flips the runner into capture-everything reporting mode (§6.6) automatically, because
  every later case is stamped `isNondeterministic` up front.
- Truly parallel workers (isolates) are deferred: Dart model state cannot be shared across
  isolates, so the meaningful version needs either a message-passing model protocol or a
  models-free (SUT-only, FFI/shared-memory) design — a follow-on with its own plan, enabled by
  the borrow-token machinery the bindings already ship.

`Settings.statefulStepCount` governs the engine's step budget (default 50), unchanged.

### 6.9 Flutter posture (this plan ships facts, the follow-on ships code)

What already works, verified (§4.7): `flutter test` runs build hooks for the host since
Flutter 3.38 / Dart 3.10 stable, so the engine binary arrives in Flutter projects through the
existing hook; pure-Dart `property()` tests run under `flutter test` unchanged. The package's
platform declaration (linux/macos/windows) matches where the engine exists; `-p chrome` and
mobile targets are correctly excluded by it.

What the FakeAsync findings mean, recorded here because they shaped §5's sync-pump decision:
`testWidgets` bodies run entirely inside a FakeAsync zone; synchronous FFI is safe there, but
futures completed by real external events deadlock without `tester.runAsync`. Because every
hegel draw is synchronous and the run loop only awaits the user body, a future
`propertyWidgets('...', (tc, tester) async { ... })` is buildable on the documented
constraints: per-iteration `binding.takeException()` (the error slot is one-deep and a leaked
exception poisons every later case), remount (`pumpWidget(Container(key: UniqueKey()))`) and
`binding.reset()` between cases, and golden matchers not nested inside a held `runAsync`. That
package (`hegel_flutter`) also inherits flutter_test's exact `test_api` pin — one more reason
it must be a separate package with its own constraint dance rather than a Flutter dependency
inside `hegel`. Out of scope for this plan's commits; in scope for its README ("works with
Flutter today for pure-Dart properties; widget-level PBT is coming as hegel_flutter").

---

## 7. Architecture and layout

The property layer sits strictly above the binding layer's safe API (L2) and below nothing —
it is the public surface. Generators and the runner call L2 wrappers only; no `dart:ffi` import
appears above `src/libhegel/`. The L2 `TestCase` never escapes: the property layer's `TestCase`
wraps it, and files that need both import the bindings `as engine`.

```
lib/
├── hegel.dart                      # public barrel: everything below
├── generators.dart                 # catalog-only export, for `as gs` prefix imports
└── src/
    ├── libhegel/                   # existing bindings (unchanged; Settings & enums get
    │                               #   user-facing dartdoc and become publicly re-exported)
    └── property/
        ├── test_case.dart          # public TestCase; draw log; span-depth accounting
        ├── generator.dart          # Generator<T>, combinators, composite, deferred (one
        │                           #   library with parts — the closed algebra)
        ├── catalog.dart            # the §6.4 factory functions
        ├── runner.dart             # runProperty: pump loop, catch ladder, zone guard,
        │                           #   blob replay, outcome mapping
        ├── property.dart           # property(): test() registration, location, DB key,
        │                           #   env/settings resolution, printOnFailure wiring
        ├── reporting.dart          # repr(), draw-log rendering, origin derivation,
        │                           #   diagnostic sink, reproduce hints
        ├── stateful.dart           # Rule, Invariant, StateMachine, runStateful, Pool<T>
        └── config.dart             # env overrides, database-key derivation
```

Public exports from `hegel.dart`: `property`, `runProperty`, `TestCase`, `Generator`,
`DeferredGenerator`, `TextGenerator`, the catalog, `composite`, `deferred`, `Rule`,
`Invariant`, `StateMachine`, `runStateful`, `Pool`, `PropertyError`, and from the binding
layer: `Settings`, `Database`, `Phase`, `HealthCheck`, `Mode`, `Backend`, `Verbosity`,
`AssumptionFailed` (users may catch it; they never throw it directly — `tc.assume` does).
`StopTest`, `HegelException`, and everything else in `src/libhegel/` remain internal.

---

## 8. Testing and verification strategy

House rules carry over: **the engine is never mocked; integration against the real engine is
the default; fakes exist only for branches the engine cannot produce; 100% line+branch
coverage, gated in CI, maintained by every commit.** The property layer adds tiers of its own,
because a test framework's correctness claims are about what *users* see:

1. **Pure unit tests** (no engine): `repr()` rendering; origin extraction from synthetic stack
   traces (user frame, no user frame, package-only); database-key derivation; env-override
   resolution order; catalog argument validation (empty `sampledFrom`, inverted bounds);
   draw-log/naming accounting via a scripted `DrawContext` fake.
2. **Generator integration** (real engine, driven through `runProperty`): every catalog entry
   draws values satisfying its own contract — bounds respected, lengths within limits, `unique`
   lists duplicate-free, `optional` produces both null and non-null across a run, `oneOf`
   covers every branch across a derandomized run, `deferred` recursion terminates. These are
   **self-hosted properties** — the framework testing itself is the first real user.
3. **Shrink-quality pins** — the regression net for span placement, which nothing else can
   see. Derandomized, seeded properties with known minimal counterexamples, asserting the
   exact reported values: `integers(0..1000)` failing above a threshold shrinks to
   `threshold+1`; `lists(integers())` failing on `length >= 2` shrinks to `[0, 0]` (the
   canonical sort example every sibling README uses); a failing `oneOf` shrinks into its first
   failing branch; `where` never surfaces a filtered value; a `tuple2` shrinks each component.
   Measured while landing P2, by deleting each span and re-running: **the pins move only
   where the value has parts that can be deleted.** Every fixed-arity pin — mapped, filter,
   `tuple2`, `oneOf`, `optional`, composite — still passes with its span removed, because the
   engine reaches the same minimum unaided on a value of fixed shape. The recursive-tree pin
   stops finishing at all (minutes against milliseconds). So the pins are the net for
   *structural* shrinking — recursion, and the collections in P4 — and **each compound
   generator also gets a scripted-`DrawContext` test pinning its exact call sequence,
   including each `discard`**, which is what catches a misplaced span on a flat shape. Pinned
   values are engine-version-dependent by nature; the update tool's engine-bump workflow
   re-runs them, and a bump commit may re-pin with the diff as review evidence.
4. **Runner semantics** (real engine): catch-ladder mapping for all four outcomes;
   `assume`-heavy properties end invalid without burning budget; `StopTest` under a
   deliberately over-drawing body ends overrun; distinct assertion sites yield distinct
   origins and `reportMultipleFailures: true` surfaces both (one rethrown, one registered);
   run-level `error` (an unsuppressed health check driven the way the bindings' health-check
   suite already does) throws `PropertyError`, not `TestFailure`; async bodies — awaited
   failure, fire-and-forget failure captured by the zone guard, post-completion error routed
   to `registerException`; the replay-passes (stale blob) path reports flakiness.
5. **Replay and database lifecycle at the property layer**: a failing property with
   `Database.at(tempDir)` persists; a second `runProperty` with the same derived key replays
   first (observable as the bindings' database suite already observes it: first draw equals
   the stored counterexample, one test case in a replay-only phase set); fixing the property
   cleans the entry; `reproduce:` with a printed blob reproduces the same draws; a stale blob
   (changed generators) reports the mismatch message. `HEGEL_TEST_CASES`/`HEGEL_DATABASE`
   proven effective through a spawned `Process` with the environment set.
6. **Subprocess end-to-end** — what the user actually sees. Fixture test files under
   `test/fixture/` (excluded from the normal suite via tags), executed with
   `Process.run('dart', ['test', ...])` from a driver test: exit codes; failure output contains
   the named draw line, the original `expect` mismatch, the database/blob hint; passing
   properties print nothing; `dart test -N` selects a property by name; `location:` appears in
   the JSON reporter. Substring assertions, not goldens — the predecessor plan's lesson about
   matching runner output loosely applies (`fb4de40` fixed exactly that class of brittleness).
7. **Stateful**: sequential machine with a planted model/SUT divergence found and shrunk to a
   short step script; `precondition:` rejections un-counted (observable via engine budget:
   rejected rules don't consume steps); assume-inside-rule converts to rejection; the
   empty-pool case ends invalid with the documented guidance; invariants run initially and at
   join points (order pinned via notes); the concurrent lost-update machine (the Rust/Go KV
   example, built on an async SUT with an await between read and write) fails under
   `maxConcurrency: 4`, reports from the discovering case with no blob, with `[worker N]`
   tagging — and passes at concurrency 1, proving the interleaving is what finds it. Groups:
   rules in different groups never observed overlapping (the bindings' concurrency-group test
   pattern lifted to the public API).
8. **Fake-driven branches** only where the engine can't go: `DrawContext` failures mid-span,
   the leak-tracker exemption for cached string generators, engine-output callback errors
   surfaced through the property runner.
9. **The audit, extended**: the existing header-derived L1 exercise audit gains a property-layer
   companion asserting every draw primitive and every reserved frontend span label is
   exercised through the *public* API (catalog + combinators + stateful driver) — the check
   that the catalog table in §6.4 stays true as the engine grows.

   The draw half landed with commit 12 (`test/property/catalog_audit_test.dart`) and is green:
   twelve draws, all reached from the catalog, read off the binding layer rather than listed.
   The span half is what remains for commit 22, and it needs a decision rather than a test:
   **two reserved frontend labels have no generator in §6.4 and are not going to get one.**
   FIXED_DICT is what a named-field record generator would open, and tuples cover that ground
   under TUPLE; ENUM_VARIANT is what a Dart `enum` generator would open, and `sampledFrom`
   covers that ground under SAMPLED_FROM — both being an index draw, neither shrinks better
   for having its own label. So the span audit asserts the labels the catalog *claims*
   (LIST, LIST_ELEMENT, SET, SET_ELEMENT, MAP, MAP_ENTRY, TUPLE, ONE_OF, OPTIONAL, FLAT_MAP,
   FILTER, MAPPED, SAMPLED_FROM, STATEFUL_RULE, and the minted composite label), and names the
   two it does not, so that a later generator for either is a deliberate addition rather than
   a gap nobody noticed.

Meta-verification: `example/echo.dart` is rewritten against the public API (and a stateful
example added), so the examples are compile-checked documentation; `dart doc` stays gated.

---

## 9. CI

No new jobs; the property layer rides the existing matrix, coverage, drift, AOT-smoke,
no-network, docs, and packaging jobs. Two adjustments:

- The subprocess E2E fixtures are tagged (`e2e`) and run in CI on all platforms; locally
  `just test` includes them (they are seconds, not the 30-second `slow` class).
- The AOT smoke gains a `runProperty` call, proving the property layer (not just
  `hegel_version`) survives `dart build cli` — the seam a future workload runner depends on.

---

## 10. Milestones

| # | Milestone | Commits | Exit criterion |
|---|---|---|---|
| **P0** | Plan | 1 | this document reviewed and merged |
| **P1** | Vertical slice | 2–6 | a failing `property()` in a real test file prints a named minimal counterexample, rethrows the original `expect` error, persists to the database, and replays on rerun; passing properties are silent |
| **P2** | Combinator algebra | 7–9 | map/where/flatMap/oneOf/optional/sampledFrom/just/tuples/composite/deferred all green with span shapes pinned by shrink-quality tests |
| **P3** | Full catalog | 10–12 | every draw primitive reachable through a public generator; audit extension green |
| **P4** | Collections | 13–14 | lists/sets/maps with uniqueness and bounds, shrink pins green |
| **P5** | Failure UX & config hardening | 15–17 | multiple failures, run-error mapping, reproduce blobs, env overrides, targeting — all proven end-to-end |
| **P6** | Stateful | 18–20 | sequential and concurrent machines find their planted bugs on the full platform matrix |
| **P7** | DX & release | 21–23 | examples, README, docs, packaging check; `0.1.0` publishable |

P1 carries the design risk (zone guard, replay flow, reporting seams); P2's span pins protect
everything after it; P3–P4 are wide but mechanical; P6 is the novel capability and gets the
matrix time it needs.

## 11. Commit plan

Ground rules unchanged from the bindings plan: every commit is green (format, analyze
`--fatal-infos`, full suite, coverage gate) locally and in CI; feature commits carry their
tests; generated artifacts regenerate with their inputs.

**P0**

1. `docs: property-testing layer implementation plan` — this document.

**P1 — vertical slice**

2. `feat: generator core and the integer generator` — `Generator<T>` closed algebra skeleton,
   `DrawContext` seam over the engine test case, public `TestCase` with `draw`/`assume`/`note`
   and span-depth draw logging, `integers()`. Green: integration draws through a raw L2 loop;
   unit tests for the log and depth accounting.
3. `feat: runProperty and the catch ladder` — the pump loop, per-case `runZonedGuarded`
   execution, outcome mapping, origin derivation, blob replay of failures as final cases,
   original-error rethrow, `PropertyError` for run errors. Green: pass/fail/invalid/overrun
   integration; origin stability; stale-replay reporting; async-body error paths.
4. `feat: property() package:test entry point` — registration with pass-through parameters,
   `@isTest`, caller `location:`, database-key derivation via `TestHandle`, `printOnFailure`
   diagnostic sink, engine-output buffering. Green: first subprocess E2E fixtures (failing and
   passing properties; `-N` selection).
5. `feat: named draws and failure rendering` — `name:` on draw, `repr()`, the draw-line and
   note rendering, reproduce/database hint lines. Green: E2E output assertions.
6. `feat: settings resolution, env overrides, reproduce parameter` — public re-export of
   `Settings` + enums with user-facing dartdoc, `HEGEL_TEST_CASES`/`HEGEL_DATABASE`,
   `reproduce:` single-replay mode, auto `printBlob`. Green: resolution-order unit tests;
   database lifecycle and blob-reproduce integration (§8.5).

**P2 — combinators**

7. `feat: map, where, flatMap` — spans per §2, `where` with 3 discard-retries then assume.
   Green: shrink pins for filter and mapped shapes; latch interaction tests.
8. `feat: just, sampledFrom, oneOf, optional, tuples` — the ONE_OF/SAMPLED_FROM/OPTIONAL/TUPLE
   shapes; `tuple2..tuple4` over records. Green: branch-coverage property, shrink pins
   (first-branch, component-wise).
9. `feat: composite and deferred` — minted span label above the reserved range; one-shot
   `define` with clear misuse errors. Green: recursive tree generator terminates and shrinks;
   composite-in-composite nesting.

**P3 — catalog**

10. `feat: booleans, doubles, bigIntegers, durations` — Hypothesis float defaults, big-bound
    defaults. Green: bounds properties; NaN/infinity gating; int64/BigInt split already proven
    at L2, re-proven through the public surface.
11. `feat: text, characters, fromRegex, emails, urls, domains` — per-instance native generator
    cache with the leak-tracker exemption; `TextGenerator` as `fromRegex` alphabet. Green:
    alphabet constraints hold; self-rejecting draws surface as assumption rejections;
    cache-reuse proven (one native construction across a run).
12. `feat: bytes, dates, times, dateTimes, uuids, ipAddresses` — type mappings per §6.4,
    plus `package:hegel/generators.dart` (§6.4), which lands here because this is the commit
    that makes a catalog worth importing on its own. Green: range properties; UUID version
    nibble; v4/v6 branch coverage; audit extension now green for the whole primitive surface
    (the draw half of §8.9; the span half waits for the labels P4 and P6 bring).

**P4 — collections**

13. `feat: lists with uniqueness` — the §2 list shape; `unique` via `==` with documented
    semantics. Green: the canonical `[0, 0]` shrink pin; unbounded lists; rejection loops
    don't count against length.
14. `feat: sets and maps` — SET/MAP shapes, duplicate rejection. Green: key-uniqueness
    property; shrink pins; bounds.

**P5 — failure UX & config hardening**

15. `feat: multiple distinct failures` — `reportMultipleFailures` through
    rethrow-plus-`registerException`, origin list rendering. Green: two-bug fixture E2E
    showing both errors.
16. `feat: run-error surfacing` — health-check and nondeterminism-mismatch texts through
    `PropertyError`; verbose-mode live output routing. Green: driven health check (the
    bindings' suite pattern) surfaces as a test *error* with the engine's message.
17. `feat: target()` — public targeting with the phase interplay documented. Green: targeting
    smoke with the phase on and off (mirrors the L2 test at the public layer).

**P6 — stateful**

18. `feat: sequential state machines` — `Rule`/`Invariant`/`StateMachine`/`runStateful`,
    STATEFUL_RULE spans, step notes, both precondition forms, latch-aware rejection handling.
    Green: planted-bug counter machine found and shrunk; rejection accounting; invariant
    ordering.
19. `feat: typed pools` — `Pool<T>` over the engine pool with reusable/consumed generators.
    Green: lifecycle model (create/use/destroy of named resources); empty-pool guidance path.
20. `feat: concurrent state machines` — clone-per-worker async tasks, groups, join points,
    buffered `[worker N]` output, outcome precedence, nondeterministic-run reporting. Green:
    the async lost-update machine fails at concurrency 4 and passes at 1, on the full matrix;
    no-blob reporting path; first-creation handshake through the public API.

**P7 — DX & release**

21. `docs: examples and README` — `example/echo.dart` rewritten on the public API plus a
    stateful example; README quick start (including Flutter posture per §6.9 and the
    hegeltest/naming note); dartdoc pass over the public surface.
22. `test: property-layer audit and AOT smoke extension` — the span half of the §8.9 audit
    (the draw half landed with commit 12); `runProperty` in the AOT smoke.
23. `chore: 0.1.0 release preparation` — CHANGELOG, pubspec description update, packaging
    dry-run re-verified, version to `0.1.0`.

## 12. Deferred, with revisit triggers

- **`hegel_flutter` (`propertyWidgets`)** — after 0.1.0; the constraints are documented in
  §6.9 and the flutter_test pin makes it structurally a separate package.
- **Codegen derive (`hegel_generator`)** for user classes — revisit if/when augmentations ship
  or user demand shows `composite()` fatigue; mocktail-vs-mockito is the ecosystem precedent
  that zero-codegen explicitness is a feature, not a gap.
- **Isolate-parallel stateful workers** — needs a model-sharing design; the bindings' borrow
  tokens keep it reachable.
- **Workload/soak runner** (hegel-go `Workload`, Antithesis) — `runProperty` +
  `Mode.singleTestCase` + `Backend.urandom` are the ingredients; build when a consumer exists.
- **Statistics/`collect`** — frontend-only counting (kiri_check precedent) gated on verbose
  output; small, but not v1.
- **Weighted `oneOf`/`frequency`** — no sibling ships it; adding it would fork the family's
  generator vocabulary. Revisit if upstream adds engine support.
- **Explicit examples** (Rust `explicit_test_case`; engine phase reserved, "none today") —
  requires named-draw binding to pinned values; revisit when the engine's EXPLICIT phase gains
  semantics.
- **32-bit float draws, Go-style source-statement echo, `tc.repeat`** — noted in §6 where each
  arose; all additive.

## 13. Risks

- **A parallel community frontend (`hegeltest`) is publishing first.** Mitigation: the `hegel`
  name is held (pubspec) and free on pub.dev (verified); this plan's differentiators (stateful
  incl. concurrency, failure UX depth, verification rigor) are the response; publishing 0.1.0
  at P7 rather than polishing indefinitely.
- **Engine ABI churn pre-1.0** — the frontends span three ABI generations already; the pinned
  header, drift job, and update tool localize a bump, and the shrink pins plus the §8.9 audit
  are the property-layer's bump detectors. Shrink-pin values may legitimately change on engine
  bumps; the bump workflow re-pins them consciously.
- **Zone interplay with package:test internals** — the guard-per-case design touches
  under-documented Invoker behavior; mitigated by the dedicated async suite (§8.4), by using
  only `hooks.dart`-sanctioned APIs (`TestHandle`, `registerException`, `printOnFailure`), and
  by the subprocess E2E tier catching regressions in real runner output across `test` package
  upgrades.
- **The `test` regular dependency vs Flutter's exact `test_api` pins** — constraint chosen to
  include the compatible release (§6.1); a Flutter-stable bump can force a constraint-widening
  patch release; the risk is a pubspec edit, not a design change.
- **Latch semantics vs stateful rule rejection** — the one place engine semantics and driver
  ergonomics genuinely tension (§6.8); resolved by the precondition-first API and pinned by
  §8.7 tests; if user reports show assume-in-rule confusion anyway, the dartdoc and a lint-like
  runtime hint are the lever, not a semantic fork.
- **Shrink-quality pins flaking across platforms** — derandomize + fixed seeds make draws
  platform-independent (the engine's determinism is already proven by the bindings' suite);
  any platform divergence found is an upstream bug worth filing, and the pin failure is the
  detector.

---

## Appendix A — engine capability → public API map

| Engine surface | Public surface |
|---|---|
| `hegel_generate_boolean/integer/integer_big/float/bytes` | `booleans`, `integers`, `bigIntegers`, `doubles`, `bytes` |
| `hegel_string_generator_text/regex/email/url/domain` + `hegel_generate_string` | `text`, `characters`, `fromRegex`, `emails`, `urls`, `domains` |
| `hegel_generate_date/time/datetime/uuid/ipv4/ipv6` | `dates`, `times`, `dateTimes`, `uuids`, `ipAddresses` (+ `durations` over integer draws) |
| spans + reserved labels | combinator internals (`map`/`where`/`flatMap`/`oneOf`/`optional`/`sampledFrom`/tuples/collections), `composite` minted label, STATEFUL_RULE in the driver |
| `hegel_new_collection` / `more` / `reject` | `lists`, `sets`, `maps` (incl. `unique`) |
| `hegel_new_pool` / `add` / `generate` | `Pool<T>` |
| `hegel_new_state_machine` / `next_group` / `next_rule` / `rule_rejected` / clone | `StateMachine`, `Rule(group:)`, `Invariant`, `runStateful(min/maxConcurrency:)` |
| `hegel_target` | `tc.target` |
| `hegel_mark_complete` statuses + origins | the catch ladder + automatic origin derivation |
| run lifecycle + `hegel_run_result_*` + failures | `runProperty` / `property()` outcome mapping |
| `hegel_failure_reproduction_blob` + `hegel_test_case_from_blob` | final-replay reporting, `reproduce:`, printed blob hints |
| settings ABI (13 setters) | public `Settings` (unchanged from L2) + env overrides + derived `databaseKey` |
| example database + CI defaults | automatic persistence/replay; hint lines; engine-owned CI behavior |
| output callback | buffered diagnostics via `printOnFailure`; live at verbose |
| `hegel_test_case_is_nondeterministic` + `FAILED_NONDETERMINISTIC` | capture-mode reporting; concurrent stateful UX |
| `Mode.singleTestCase`, backends, phases, health checks | exposed via `Settings`; `reproduce:`; `PropertyError` for health-check aborts |

## Appendix B — sibling frontend comparison (the design inputs)

| | hegel-rust | hegel-go | hegel-typescript | hegel-java | **hegel (this plan)** |
|---|---|---|---|---|---|
| entry | `#[hegel::test] fn(tc)` | `hegel.Test(t, func(ht))` | `test('…', () => hegel.test(tc => …))` | `@HegelTest void t(TestCase tc)` | `property('…', (tc) async …)` |
| draw | `tc.draw(g)` (macro-named) | `hegel.Draw(ht, g)` | `tc.draw(g)` | `tc.draw(g, "name")` | `tc.draw(g, name: '…')` |
| async | via outer `#[tokio::test]` | goroutines + clones | separate `testAsync` | none | one `FutureOr` entry point |
| custom types | composite macro, derive, deferred | `Composite` fn | `composite`, `record` | `composite`, reflection `forType`, `deferred` | `composite`, `deferred`; codegen deferred |
| filter | 3 retries → assume | 3 retries → assume | 3 retries → assume | 3 retries → assume | same, as `.where` |
| origin | panic location | first non-hegel frame | first non-node_modules frame | `Type at File:Line` | `Type at uri:line`, first non-framework frame |
| DB key | `module_path::fn` | `t.Name()` | `testFn.toString()` | method name | suite path + `TestHandle.current.name` |
| blob UX | `reproduce_failure` attribute + `print_blob` | internal only | internal only | n/a (0.14 ABI) | `reproduce:` param; auto-printed when DB off |
| multiple failures | grouped report opt-in | aggregate error | wrapped message | rethrow original / opt-in aggregate | rethrow first + `registerException` rest |
| stateful | two APIs (seq/concurrent macros) | one API, reflection discovery | none | none | one API, declarative rules, async workers |
| concurrency substrate | OS threads | goroutines | — | — | interleaved async tasks (isolates deferred) |
