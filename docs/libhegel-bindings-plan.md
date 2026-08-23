# libhegel bindings for Dart — implementation plan

**Status:** accepted, revised after review · **Updated:** 2026-08-20 · **Scope:** the FFI binding layer only

This plan covers the first step of hegel-dart: binding the [libhegel](https://hegel.dev/reference/libhegel)
C ABI from Dart. The property-testing API (generators, runner, `test` integration) comes later and is
out of scope here, but the binding layer is designed with that consumer in mind. The bindings are not
published separately — they live as an internal library inside the hegel-dart package. The plan's only
external dependency is **hegel-rust**, which supplies the engine we bind to.

This revision incorporates `libhegel-bindings-plan-review.md` (all blocking, high-priority, and
maintainability findings). Deviations from the review's prescriptions are listed in §14.

---

## 1. Context and goals

libhegel is the core property-testing engine (generation, shrinking, example database, run
sequencing), shipped as a C-ABI shared library built from `hegel-rust/hegel-c`. Language frontends
drive it through a run loop: start a run, pull test cases, draw values, report each case's outcome,
read the result, replay failures from reproduce blobs.

**Goals**

- Bind the complete current C API (~60 functions, `hegel-c` 0.33.x generation) with full fidelity:
  run lifecycle, all value generation, spans, collections, pools, state machines (including the
  concurrency-aware API), targeting, run results, failures, and blob replay.
- Idiomatic Dart throughout: build hooks for native-library distribution, ffigen-generated raw
  bindings, a hand-written safe layer with typed handles and exceptions, `package:ffi` arenas for
  marshalling.
- Deterministic, explicit resource management (the engine's ownership rules are strict).
- Integration-tested against the real engine on every supported platform — including one real
  two-worker concurrent state-machine test, since the bindings claim to enable that.

**Non-goals (deferred to the property-testing layer)**

- Generator combinators, the data-source seam, runner/`package:test` integration, user-facing API.
- Full multi-isolate orchestration of concurrent state machines. The bindings ship the enabling
  primitives and prove them with one minimal two-worker test (§7.5, commit 31); the general
  worker-pool runner is a later phase.
- Publishing the bindings as a standalone pub package.
- Flutter **mobile**. The upstream release assets cover desktop Linux/macOS/Windows only, so this
  design is Flutter-desktop-compatible at most; Android/iOS need upstream engine builds that do
  not exist today and are a separate project.

## 2. Ground truth: the C ABI we bind

- **Canonical definition:** `hegel-rust/hegel-c/include/hegel.h` (cbindgen-generated, checked in
  upstream). The website reference lags the header — the 0.33.0 header adds concurrency-aware
  state machines (`rule_groups`, `min/max_concurrency`, `worker_index`,
  `hegel_state_machine_next_group`), `HEGEL_RUN_STATUS_FAILED_NONDETERMINISTIC`, and
  `hegel_test_case_is_nondeterministic`. **The header at the pinned tag is authoritative**, fetched
  from `https://raw.githubusercontent.com/hegeldev/hegel-rust/v<VERSION>/hegel-c/include/hegel.h`.
- **Calling convention:** every function takes `hegel_context_t*` first and returns `hegel_result_t`
  (0 = OK, negative = error), except `hegel_context_new` and `hegel_context_last_error`. Outputs via
  trailing `out_*` parameters. NULL context is allowed (opts out of error messages).
- **Ownership:** input pointers are caller-owned and copied during the call — the caller may free
  them as soon as the call returns. Every returned handle has exactly one matching `*_free`
  (including `hegel_context_free`); everything else returned is a borrowed string with a documented
  validity window.
- **Text is strict UTF-8, both directions.** Verified in the pinned implementation: inbound
  length-delimited character buffers are validated with `core::str::from_utf8` and rejected with
  `HEGEL_E_INVALID_ARG` when invalid; engine-side strings are Rust `String`s, which structurally
  cannot contain unpaired surrogates, so output is always valid UTF-8. There is no WTF-8 anywhere
  in this ABI (see §7.3 for what that means for Dart's UTF-16 strings).
- **Environment awareness:** `hegel_settings_new` itself detects CI environments and flips the
  defaults (database off, derandomize on) — the binding adds no environment detection of its own,
  and must not accidentally override those defaults (§7.2, Settings).
- **Prebuilt binaries:** each hegel-rust release publishes `libhegel-<goos>-<goarch>.<ext>` plus a
  `.sha256` sidecar for `linux/amd64`, `linux/arm64`, `darwin/arm64`, `windows/amd64`,
  `windows/arm64`. Intel macOS is not published. This is the intended consumption path for
  non-Rust languages (per hegel-c's README). Assets are served from public release-download URLs
  that require no API access or token.
- **Version pin:** we pin one exact libhegel version — the latest release at implementation start
  (0.33.x today). libhegel is pre-1.0/zerover: the ABI may change between minors, so the runtime
  check compares `major.minor`.

Useful upstream references: `hegel-c/examples/*.c` (echo, failing, spans_collections, pool,
state_machine, custom_output, invalid_argument) are effectively a conformance checklist — §9 ports
them as integration tests.

## 3. Toolchain decisions (verified against this machine)

Facts verified locally on Dart SDK **3.13.0 stable**:

1. **Build hooks are stable and on by default.** A probe package with `hook/build.dart` had its
   hook executed by plain `dart run` *and* `dart test` (no flags; the old
   `--enable-experiment=native-assets` flag is gone). `package:hooks` 2.x and
   `package:code_assets` 2.x resolve from pub. `dart build cli` exists for AOT bundling.
2. **Build hooks run in a filtered environment.** Verified empirically: the hook process sees
   exactly two variables, `HOME` and `PATH`. Custom variables (and `XDG_CACHE_HOME`,
   `GITHUB_TOKEN`, …) are stripped. All hook configuration must therefore flow through
   **pub user-defines** (`hooks:` → `user_defines:` in the root package's `pubspec.yaml`, read via
   `input.userDefines`), which are declared hook inputs and correctly invalidate the hook cache.
   An environment variable can never configure the hook.
3. **ffigen** supports `ffi-native` output with `asset-id`, generating `@Native` external
   functions bound to a code asset — the intended pairing with build hooks. The usable version is
   **20.1.1**, not the current 21.x: ffigen 21 depends on `code_assets ^1.1.0`, which cannot
   resolve alongside the `^2.0.0` that `hooks` 2.2.0 and the `testCodeBuildHook` harness require.
   ffigen 20.1.1 declares no `code_assets` constraint at all — the `../code_assets` and `../hooks`
   entries in its pubspec are `dependency_overrides`, which pub ignores for a non-root package.
4. `package:code_assets` 2.0 API: hooks call
   `output.assets.code.add(CodeAsset(package:, name:, linkMode: DynamicLoadingBundled(), file:))`,
   reading `input.config.code.targetOS/targetArchitecture` and staging files under
   `input.outputDirectoryShared`; `output.addDependency(uri)` registers extra hook inputs; the
   package exports a `testCodeBuildHook` harness for testing hooks for real.
5. **Dart's `utf8.encode` silently replaces an unpaired surrogate with U+FFFD** (verified:
   `String.fromCharCode(0xD800)` encodes to `EF BF BD`). Inbound strings must be validated before
   encoding or the engine receives silently corrupted text (§7.3).

**Decisions**

- **Distribution:** `hook/build.dart` provides libhegel as a code asset
  (`package:hegel/libhegel`). Consumers run `dart test` and the engine is fetched, verified, and
  bundled automatically — no install scripts, no manual library management.
- **Raw bindings:** ffigen in `ffi-native` mode against a vendored copy of the pinned `hegel.h`.
  Generated code is **checked in** (reviewable diffs; libclang needed only to regenerate), with a
  CI drift check. The ffigen version is pinned exactly (20.1.1) so drift diffs represent
  intentional generator upgrades; a bump must be checked against the `code_assets` constraint
  above, which is what rules out 21.x today.
- **Package name:** `hegel`, repo `hegel-dart`.
- **Coverage:** 100% line + branch, enforced in CI once the core vertical slice exists (commit 19
  in §12) and maintained by every later commit. Measured over `lib/` **excluding**
  `bindings.g.dart` (generated `@Native` externals have no Dart bodies to cover) and excluding the
  non-gating GC-delivery smoke test (§7.1).
- **Dependencies:** runtime — `ffi`, `crypto` (SHA-256; the SDK has none), `meta`
  (`@visibleForTesting`/`@internal`); hook-only — `hooks`, `code_assets`; dev — `ffigen`, `test`,
  `lints`, coverage tooling. All declared directly; nothing relied on transitively.

## 4. Architecture and repo layout

Three strictly one-way layers:

```
generated raw bindings (bindings.g.dart, @Native externals, C shapes)
        ▲
Bindings interface + NativeBindings impl (bindings.dart, 1:1 with C, injectable)
        ▲
safe layer (typed handles, exceptions, marshalling — the deliverable API)
        ▲
[future: data-source seam → generators → runner → public hegel API]
```

- **L0 `bindings.g.dart`** — ffigen output: `@Native` functions, structs, constants. Never edited
  by hand; regenerated by `tool/update_libhegel.dart`.
- **L1 `bindings.dart`** — `abstract interface class Bindings` listing every C function in raw
  shape (`Pointer` args, `int` results), plus `final class NativeBindings implements Bindings`
  forwarding one-to-one to L0. Purpose: (a) tests inject an in-memory fake to reach error branches
  the real engine can't produce (`E_BACKEND`, `E_INTERNAL`, `E_CONCURRENT_USE`); (b) its
  constructor eagerly touches `Native.addressOf` for each symbol so an ABI-skewed library fails at
  load instead of lazily at first call (`@Native` resolution is lazy) — this eager pass is what
  proves whole-surface linkage; (c) it is the single diffable inventory of the bound surface for
  ABI-bump audits, cross-checked against the header by a generated inventory (§9). Mechanical,
  type-checked against L0, and deliberately without absorbed defaults: every parameter the C
  function takes appears in the interface so the surface diffs cleanly against the header —
  defaulting and convenience live in L2 only.
- **L2 safe layer** — the API the rest of hegel-dart consumes. Wrapper classes own handles and
  lifecycles; all marshalling and error mapping happens here.

A per-isolate, **disposable** session object ties them together (Dart statics are per-isolate,
which makes the per-isolate part automatic):

```dart
final class Libhegel {
  static Libhegel get instance => _instance ??= Libhegel._open(NativeBindings());
  final Bindings bindings;
  final Pointer<hegel_context_t> _context;  // freed by dispose(); never shared across isolates
  final String engineVersion;                // checked against pinned major.minor at open
  void dispose();                            // frees the context; session unusable afterward
  @visibleForTesting static void overrideForTesting(Bindings b);  // disposes any prior session
}
```

Session lifecycle rules (these close the "leak one context per isolate" hole, which matters once
worker isolates are spawned and torn down repeatedly):

- Every wrapper **captures its owning session** at construction and calls through it — never
  through the replaceable global getter — so overriding or disposing a session cannot silently
  redirect live wrappers.
- The session must outlive every wrapper created from it; disposing the session while wrappers
  are live is a documented usage error (checked in debug mode).
- Worker-isolate entry points dispose their wrappers and then their session in `finally`. The main
  isolate may hold its session for the program's lifetime, but `dispose` is available and correct.
- If the version check fails during `_open`, the freshly created context is freed before the
  exception propagates. `overrideForTesting` disposes the session it replaces.

Layout inside the repo:

```
hegel-dart/
├── pubspec.yaml               # name: hegel, sdk ^3.13.0
├── analysis_options.yaml      # package:lints/recommended + stricter additions
├── justfile                   # local convenience: lint, test, regen, update-libhegel
├── ffigen.yaml
├── hook/build.dart            # code-asset acquisition (§5)
├── third_party/libhegel/
│   ├── hegel.h                # vendored header at the pinned version
│   └── LICENSE                # upstream license + attribution, vendored with the pin
├── lib/
│   ├── hegel.dart             # public barrel — empty for now (property API comes later)
│   └── src/
│       ├── tooling/
│       │   └── acquire.dart   # pure-Dart acquisition logic shared by hook and tools (no dart:ffi)
│       └── libhegel/
│           ├── libhegel.dart      # library entry, exports the safe layer
│           ├── bindings.g.dart    # L0 (generated, checked in; excluded from coverage)
│           ├── bindings.dart      # L1 Bindings + NativeBindings
│           ├── version.g.dart     # pinned version + per-platform sha256 map (generated by tool)
│           ├── session.dart       # Libhegel per-isolate disposable session, version check
│           ├── errors.dart        # result codes, exception taxonomy, the check funnel
│           ├── marshal.dart       # arena string/buffer helpers, scalar validation, sentinels
│           ├── settings.dart
│           ├── run.dart
│           ├── test_case.dart     # draws, spans, target, markComplete, clone, family state
│           ├── string_generator.dart
│           ├── collection.dart
│           ├── pool.dart
│           ├── state_machine.dart
│           ├── run_result.dart    # RunResult + Failure
│           └── codec/
│               └── bigint.dart    # BigInt ⇄ two's-complement little-endian
├── tool/
│   ├── update_libhegel.dart   # bump pin: fetch assets+header+license, verify, write hashes, regen, test
│   └── fetch_libhegel.dart    # manual fetch for development
├── test/                      # §9
├── example/echo.dart          # port of hegel-c/examples/echo.c
└── .github/workflows/ci.yml
```

The acquisition logic lives in a pure-Dart library (no `dart:ffi` import) so `hook/build.dart` can
import it without dragging in the bindings themselves. CI invokes `dart` commands directly; the
`justfile` is a local convenience mirroring them.

## 5. Native library acquisition

Build hooks cannot see custom environment variables (§3, verified), so **all acquisition
configuration flows through pub user-defines** declared in the root package's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    hegel:
      libhegel_path: ../hegel-rust/target/release/libhegel_c.so   # optional local-engine override
      cache_dir: /some/shared/cache                                # optional cross-project cache
```

`hook/build.dart` resolves the engine in this order (first hit wins):

1. **`libhegel_path` user-define** — explicit override for engine development (build libhegel in a
   sibling `hegel-rust` checkout with `cargo build -p hegeltest-c --release`, then point the
   user-define at it; the `justfile` automates this workflow). The file is registered via
   `output.addDependency`, so rebuilding the engine re-runs the hook instead of reusing a stale
   cached result. A set-but-invalid path is a hard failure with no fall-through. Skips checksum
   verification (it's a local build) but remains subject to the runtime version check. Error
   messages name the user-define; the `HEGEL_LIBHEGEL_PATH` environment variable used by other
   Hegel frontends does **not** work for Dart hooks and is mentioned in docs only to redirect
   people who try it.
2. **The hook's managed shared output** — `input.outputDirectoryShared` is the normal cache. A hit
   here was placed by a previous verified run.
3. **Optional cross-project cache** — the `cache_dir` user-define if set, else a conservative
   default derived from `HOME`/`USERPROFILE` (the only variables hooks can see):
   `~/.cache/hegel-dart/natives/v<version>/<asset>`. **Every cache hit is re-verified against the
   pinned hash before use** — an unverified hit would defeat the checked-in hash anchor; corrupt or
   truncated entries are deleted and re-downloaded.
4. **Download** — `https://github.com/hegeldev/hegel-rust/releases/download/v<version>/<asset>`,
   where `<asset>` comes from a single source-of-truth map from
   `(targetOS, targetArchitecture)` → Go-style asset name (`linux/x64 → libhegel-linux-amd64.so`).
   Verified against **checked-in sha256 pins** in `version.g.dart`. No token or GitHub API is
   involved: these are public direct-download URLs, and secrets must not pass through user-defines
   (hook inputs are materialized on disk).

Whatever the source, the verified file is **copied (or hard-linked) into
`outputDirectoryShared`**, and only that managed file is emitted as
`CodeAsset(package: 'hegel', name: 'libhegel', linkMode: DynamicLoadingBundled(), file: ...)` —
emitting a path inside an external cache would let cache cleanup break later builds without
re-running the hook. Installation into either cache is race-safe: unique temp file + atomic
rename, with a loser path that re-verifies and uses the existing destination (Windows
rename-onto-existing included). Unsupported target (e.g. `darwin/amd64`, all mobile) ⇒ fail with a
message naming the supported platforms and the `libhegel_path` user-define.

**Version pinning** (three anchors, one source of truth):

- `tool/update_libhegel.dart` (which runs in a normal environment and *may* use the GitHub API and
  a token for release enumeration) downloads every platform asset, **recomputes each digest and
  compares it against the published `.sha256` sidecar** — it never merely transcribes sidecar
  text — then writes `version.g.dart` (`libhegelVersion = '0.33.0'` + sha256 map) and refetches
  `third_party/libhegel/hegel.h` and the upstream `LICENSE` at the same tag. It refuses to pin a
  release that is missing any supported platform asset.
- The hook downloads exactly that version and verifies the pinned hashes (downloads *and* cache
  hits).
- At first use per isolate, the session calls `hegel_version` and **throws** on a `major.minor`
  mismatch, naming both versions and the `libhegel_path` user-define as the likely cause. With
  hook-bundled binaries a mismatch is always either a stale override or a real bug, so a hard
  failure is right; L1's eager symbol check backstops this at load time.

## 6. Generated bindings (ffigen)

`ffigen.yaml` decisions:

- Input: `third_party/libhegel/hegel.h`. Output: `lib/src/libhegel/bindings.g.dart`.
- `ffi-native: asset-id: 'package:hegel/libhegel'` — `@Native` externals, no `DynamicLibrary`
  handling anywhere in the package.
- Keep C names verbatim (`hegel_generate_integer`, `hegel_settings_t`) — the raw layer should diff
  cleanly against the header during ABI bumps; Dart naming happens in L2.
- Emit C enums as integer constants, not Dart enums — the ABI deliberately takes `uint32_t` (an
  out-of-range value must be an engine-side error, not UB), and semantic Dart enums live in L2.
- Structs (`hegel_date_t`, `hegel_time_t`, `hegel_datetime_t`, `hegel_generate_bytes_result_t`,
  `hegel_generate_string_result_t`) generate as `Struct` subclasses with explicit field widths;
  dart:ffi passes them by value natively.
- The callback typedef generates as
  `Pointer<NativeFunction<Void Function(Pointer<Void>, Pointer<Char>, Size)>>`.

**Drift control:** CI re-downloads the pinned header, diffs it against the vendored copy, reruns
ffigen (exact-pinned version), and fails on `git diff` — so neither the header nor the generated
code can silently drift from the pin. The first generation commit doubles as a spike validating
that ffigen's `ffi-native` mode handles every construct in the header (by-value struct params, the
function-pointer parameter, `uint64_t`/`size_t`, `const char *const *` arrays). **The fallback for
any unsupported construct stays `@Native`-shaped**: hand-written `@Native` declarations (or a
small generated shim) against the same asset id. A classic `DynamicLibrary.open` fallback is not
viable — a bundled code asset is resolved by asset id and has no stable runtime filesystem path
across JIT, AOT, and Flutter bundles.

## 7. Safe layer design

### 7.1 Handles and lifecycle

Each opaque handle gets a wrapper class implementing `ffi.Finalizable` (keeps the wrapper alive for
the duration of any call using its pointer). Every wrapper captures its owning `Libhegel` session
(§4) at construction.

| C handle | Dart class | Freed by |
|---|---|---|
| `hegel_settings_t` | `Settings` | `dispose()` |
| `hegel_run_t` | `Run` | `dispose()` |
| `hegel_test_case_t` | `TestCase` | `dispose()` (per handle; clones are separate handles) |
| `hegel_string_generator_t` | `StringGenerator` | `dispose()` |
| `hegel_collection_t` | `Collection` | `dispose()` |
| `hegel_pool_t` | `Pool` | `dispose()` |
| `hegel_state_machine_t` | `StateMachine` | `dispose()` |
| `hegel_run_result_t` | `RunResult` | `dispose()` |
| `hegel_failure_t` | `Failure` | `dispose()` |
| `hegel_context_t` | inside `Libhegel` session | `Libhegel.dispose()` (§4) |

Policy: **explicit, deterministic disposal is the mechanism; GC is never the mechanism.**
The engine's rules are ordering-sensitive (a run-owned test case must be `mark_complete`d before
the run can advance; every handle freed exactly once, and double-free is UB), so freeing must
happen at lexically predictable points — `try`/`finally` discipline — never at GC's discretion.
Concretely:

- `dispose()` is idempotent (guarded by a `_disposed` flag); any other use after dispose throws
  `StateError`. The flag also protects the engine's free-exactly-once rule.
- The pointer getter asserts not-disposed, so a stale handle can't reach native code.
- Constructor failures clean up partially created native state before rethrowing (nothing leaks
  when `run_start` or a generator constructor fails).
- **Leak diagnostics are best-effort, never a gate.** Dart's `Finalizer` makes no delivery
  promise, so GC-dependent reporting cannot back a deterministic test or a coverage bar. The
  registration/reporting logic is extracted behind a sink so it is unit-testable deterministically;
  actual GC delivery gets one non-gating VM smoke test. The report callback never throws, and it
  only ever *reports* — freeing from GC would trade a leak for nondeterministic UB. Active in
  assert mode only; detached on dispose.
- `NativeFinalizer` is not usable here anyway: the `*_free` functions take `(ctx, handle)`, not
  the single `Pointer<Void>` a `NativeFinalizerFunction` receives.

Byte/string draw results (`hegel_generate_bytes_result_t`, `hegel_generate_string_result_t`) never
surface as handles: the wrapper zero-initializes the out-struct in a per-call `Arena`, copies the
payload into a Dart `Uint8List`/`String` immediately, calls the paired `*_result_free` (only when
the call succeeded and the struct is owned), and returns the plain Dart value. Same for borrowed
strings (`origin`, `reproduction_blob`, `last_error`, `version`): copied to Dart `String` before
the validity window can close.

**Lifecycle contract: prevention, not surfacing.** L2 is guard-first — it tracks `_disposed`,
`_completed` (family-wide, §7.2), and run-state (`idle` / `caseInFlight` / `finished` /
`disposed`) and throws `StateError` *before* crossing FFI for misuse it can see (double
`markComplete`, `nextTestCase` with a case in flight, `result()` before completion). The engine's
`E_ALREADY_COMPLETE`/`E_NOT_COMPLETE` therefore indicate binding bugs when they appear via L2;
integration tests that exercise those engine errors do so **through L1 directly**, where the raw
protocol is visible. This resolves the earlier ambiguity of claiming structural prevention while
testing surfacing through the same layer.

### 7.2 Errors: one funnel, small taxonomy

All fallible calls route through one funnel:

```dart
Never _throwFor(int rc, String op) {
  if (rc == HEGEL_E_STOP_TEST) throw const StopTest();
  if (rc == HEGEL_E_ASSUME) throw const AssumptionFailed();
  throw HegelException(op, rc, _lastError());   // keeps the raw code verbatim
}
void check(int rc, String op) { if (rc != HEGEL_OK) _throwFor(rc, op); }
```

- `StopTest` and `AssumptionFailed` are **control flow, not errors**: `const` classes implementing
  `Exception`, no payload. The future runner translates them to `overrun` / `invalid`; the
  engine-originated `E_ASSUME` and a future user-facing `assume()` throw the same type, so
  engine-side and user-side rejection unify in one catch.
- `HegelException` carries the operation name, the **raw** result code, a derived
  `HegelResultCode` enum with an `unknown` member (an unrecognized code from a local engine build
  must produce an intelligible ABI-skew diagnostic, not a secondary lookup error), and the
  `hegel_context_last_error` message read immediately (the next context call invalidates it). No
  per-code subclasses: under the guard-first contract (§7.1) the lifecycle codes indicate binding
  bugs, so no caller has a reason to catch them individually.
- Argument validation that Dart can do better than the engine — Unicode scalar-value validation
  (§7.3), interior NUL in a string bound for a NUL-terminated `const char*`, inverted bounds where
  cheap — throws `ArgumentError`/`RangeError` before crossing the boundary.
- **Family-wide abort latch.** Root and clones created in this isolate share one family-state
  object. When any family member's operation raises `StopTest` or `AssumptionFailed`, the latch
  records **which kind**; from then on, *every* test-case-associated operation — draws, collection
  `more`/`reject`, pool ops, state-machine ops, span open — re-throws **the original kind**
  without touching native (re-throwing `StopTest` unconditionally would let a `finally`-block draw
  convert an `AssumptionFailed` case into a spurious `overrun`). `stopSpan` becomes a no-op under
  the latch so unwinding `finally` blocks can't poke a torn-down case; handle `dispose()` calls
  remain real native frees (they are independent of case state); `markComplete` remains callable
  (it's how the abort is reported). The latch is per-isolate Dart state: for clones sent to worker
  isolates, cancellation is an explicit runner-level message — a Dart field cannot be family-wide
  across isolates, and the plan documents that limit rather than pretending otherwise.

**Settings must not override the engine's defaults.** `hegel_settings_new` applies CI-aware
defaults (§2). The `Settings` constructor therefore models "not specified" as omission: every
parameter is nullable (or a sentinel-free optional), and **a setter is called only for explicitly
supplied values** — implementing an omitted `derandomize` as `set_derandomize(false)` would
silently defeat the engine's CI behavior. The database option is a sealed type layered on
nullability: `Database?` where `null` = don't call the setter (keep the engine default),
`Database.standard` = call with NULL (force the default path), `Database.disabled` = call with
`""`, `Database.path(p)` = call with the path. A fake-driven test asserts the exact L1 call
sequence for each combination.

### 7.3 Marshalling

- **Unicode scalar-value validation on every inbound string.** Dart `String`s are UTF-16 and can
  contain unpaired surrogates; the engine accepts only strict UTF-8 (§2), and Dart's `utf8.encode`
  would silently replace a lone surrogate with U+FFFD (§3) — corrupting the caller's data instead
  of failing. Every inbound string path — NUL-terminated strings *and* length-delimited character
  buffers — validates that the code units form Unicode scalar values (paired surrogates fine, lone
  surrogates ⇒ `ArgumentError`) before encoding. U+0000 is permitted only in length-delimited
  buffers; NUL-terminated destinations additionally reject interior NULs. Outbound
  length-delimited strings are read as bytes (`uint8_t*`, never a C string, so interior NULs can't
  truncate), copied, freed, and decoded as **strict UTF-8** — the engine cannot emit unpaired
  surrogates, so no WTF-8 machinery exists in this design.
- **Absent versus empty for every pointer/length pair.** For `hegel_string_generator_text`,
  `categories == NULL` means "no restriction" while non-NULL with length 0 means "deliberately
  empty alphabet" — and a naïve arena allocation of zero bytes may yield a null pointer, silently
  flipping the meaning. Public API: `List<String>? categories` — `null` ⇒ `nullptr`; a present
  empty list ⇒ a guaranteed non-null dummy allocation with length 0. Every pointer/length pair in
  the ABI is audited for the same distinction, with tests pinning the three cases
  (`null`, `[]` with `maxSize == 0`, `[]` with `maxSize > 0`) to their distinct outcomes.
- **BigInt** (`hegel_generate_integer_big`): minimal two's-complement little-endian codec,
  including the sign-byte edge (non-negative with high bit set gains `0x00`; negative with high
  bit clear gains `0xff`). Bounds that fit `int64` route to `hegel_generate_integer` instead.
  Out-buffer allocated at `max(minLen, maxLen)` — always sufficient since the draw is within
  bounds — and decoded at full width, ignoring `out_value_len`: the header guarantees the engine
  sign-fills the whole buffer, so fixed-width decoding is correct and simpler.
- **Fixed-size outputs**: UUID → `Uint8List(16)`, IPv4/IPv6 → `Uint8List(4|16)`, arena-allocated
  scratch, copied out. Interpretation (Dart `DateTime`, `InternetAddress`…) belongs to the
  generator layer.
- **Date/time structs**: passed and returned by value as generated `Struct`s at L0/L1; L2 exposes
  Dart records — `typedef HegelDate = ({int year, int month, int day})` etc. — because the engine's
  domain (years ±999999) exceeds `DateTime`'s range and conversion policy is a generator-layer
  concern.
- **Flags and enums**: L2 defines Dart enums (`TestCaseStatus`, `RunStatus`, `Mode`, `Backend`,
  `Verbosity`, `HegelResultCode` incl. `unknown`) and const-constructible extension types for
  bitmasks and labels: `extension type const Phases(int bits)` with `|`, `Phases.all`; same for
  `HealthChecks`; `extension type const SpanLabel(int value)` with the 34 reserved constants — an
  extension type rather than an enum because libraries may mint their own labels above the
  reserved range.
- **Unsigned 64-bit values.** Dart's native `int` is *signed* 64-bit: `0xFFFFFFFFFFFFFFFF`
  evaluates to `-1`, so there is no positive Dart `int` for `UINT64_MAX`. Sentinels therefore stay
  **internal**: the public API takes `int? maxSize` (null = unbounded), validates the supplied
  bound is non-negative, and marshals `null` as the `-1` bit pattern; `nextRule` returns `int?`
  with `null` replacing the `HEGEL_STATE_MACHINE_DONE` sentinel. Full-width unsigned inputs
  (seeds, user-defined span labels) are documented as **signed-bit-pattern APIs**: any Dart `int`
  is accepted and its 64 bits are passed through verbatim. Raw fake-driven tests assert the exact
  marshalled bit patterns; a real unbounded-collection integration test covers the sentinel path.

### 7.4 The output callback

`NativeCallable.isolateLocal` matches the header's contract — the callback fires synchronously on
the thread calling `hegel_next_test_case` / `hegel_test_case_from_blob`, inside our own FFI call
(`.listener` would be wrong: asynchronous delivery breaks the "emitted during the call"
semantics). The surrounding policy is transactional, because an exception in the user's `onOutput`
must not leak handles or wedge the run:

- `Run.start(settings, {void Function(String line)? onOutput})`: null ⇒ pass `nullptr` and engine
  output goes to stderr (the default). Non-null ⇒ create an `isolateLocal` callable whose
  trampoline decodes `(line, len)` as UTF-8 and invokes the closure inside a catch-all that
  captures the first `(error, stackTrace)` pair — exceptions never cross the C boundary.
- **After the native call returns**, if the trampoline captured an error: free any test-case
  handle the call returned (otherwise it leaks and the run wedges at `E_NOT_COMPLETE`), dispose
  the run (a callback failure poisons it; `hegel_run_free` cleanly abandons the in-flight case),
  close the callable, and rethrow the original error via `Error.throwWithStackTrace` so the
  user's stack survives. Blob replay frees its returned handle the same way before rethrowing.
- **Re-entrancy is guarded unconditionally**, not by a debug assert: re-entering the same run is
  UB in release too. The `Run` keeps an `_inEngineCall` flag; every L2 entry point on the same run
  checks it and throws `StateError` before any FFI call, making the guard mode-independent by
  construction.
- Callable lifetime brackets the native lifetime: a callable created for a `run_start` that fails
  is closed before the error propagates; on normal disposal `hegel_run_free` runs **before** the
  callable is closed (teardown may still emit output); `testCaseFromBlob` closes its callable when
  the call returns (the header says it need not outlive the call).
- Fake-driven ownership-count tests cover: callback throws with no case returned, with a case
  returned, and at run completion; plus a test proving the re-entrancy guard rejects before any
  second native call occurs.

### 7.5 Threading model → isolate model

The engine's per-handle thread contracts map onto isolates cleanly:

- One `Libhegel` session (context + bindings) per isolate, automatically via per-isolate statics;
  disposable per §4. Contexts are never shared, satisfying "context must not be used
  concurrently".
- A `Run` and the test cases it yields are confined to their creating isolate (single mutator
  thread ⇒ "run used from one thread at a time" holds by construction). Confinement asserted in
  debug mode by capturing the creating isolate's identity.
- Synchronous FFI calls block the isolate while the engine generates/shrinks inside
  `hegel_next_test_case`. Correct and acceptable for a test framework; the future runner can move
  whole runs onto worker isolates if needed.
- **Explicit draw streams.** The C operations for collections, pools, and state machines take both
  the object handle and a `hegel_test_case_t*`, and the draw lands in *whichever handle makes the
  call* — for concurrent machines, each worker must draw through its own long-lived clone. The L2
  API keeps that stream explicit rather than capturing the creating handle:
  `collection.more(tc)`, `pool.add(tc)`, `pool.draw(tc, consume: …)`,
  `machine.nextGroup(rootTc)`, `machine.nextRule(workerTc, workerIndex)`,
  `machine.ruleRejected(workerTc, workerIndex)`.
- **Concurrent state machines** (`max_concurrency > 1`) with defined ownership. Ownership of every
  native handle stays with the **coordinator**: it creates one clone per worker and keeps the
  owning `TestCase` wrappers, and it owns the machine/pool wrappers. Workers receive **non-owning,
  sendable address tokens** for each handle they need (clone + machine + any pools) and
  reconstruct borrowed views (`TestCase.adoptBorrowed(token)` etc.) that have no `dispose`.
  Keeping borrowed views valid is the coordinator's responsibility to sequence: it frees the
  underlying handles only after all workers have joined. This is a deliberate
  borrow protocol, not ownership transfer — an isolate that dies without running `finally` must
  not take a handle's free obligation with it. Orchestration is restricted to `Isolate.spawn`
  within the same isolate group, and ordinary Dart heap state is *not* shared between workers —
  concurrent stateful tests over shared model state need a message or native-shared-state design,
  which is the future runner's problem. In scope now: the primitives above plus **one real
  two-worker integration test** (commit 31) covering the first-creation `HEGEL_E_ASSUME` flip,
  worker indices > 0, group join points, clone streams driven from worker isolates,
  `isNondeterministic`, `FAILED_NONDETERMINISTIC`, and the absence of a reproduction blob. A
  sequential test alone cannot back the claim that the bindings enable concurrency.

### 7.6 API sketch (representative)

```dart
final settings = Settings(testCases: 50, seed: 42, database: Database.disabled);
final run = Run.start(settings, onOutput: buffer.writeln);
try {
  while (true) {
    final tc = run.nextTestCase();          // TestCase? — null ⇒ run finished
    if (tc == null) break;
    try {
      final n = tc.drawInteger(min: 0, max: 100);
      if (n < 0 || n > 100) {
        tc.markComplete(TestCaseStatus.interesting, origin: 'echo.dart:42');
      } else {
        tc.markComplete(TestCaseStatus.valid);
      }
    } on StopTest {
      tc.markComplete(TestCaseStatus.overrun);
    } on AssumptionFailed {
      tc.markComplete(TestCaseStatus.invalid);
    } finally {
      tc.dispose();
    }
  }
  final result = run.result();              // RunResult, independent of the run
  try {
    switch (result.status) { /* passed / failed / error / failedNondeterministic */ }
    for (var i = 0; i < result.failureCount; i++) {
      final f = result.failure(i);          // origin, reproductionBlob (String?)
      try { /* … */ } finally { f.dispose(); }
    }
  } finally {
    result.dispose();
  }
} finally {
  run.dispose();
  settings.dispose();
}
```

Draw surface on `TestCase` (all synchronous, all throw `StopTest`/`AssumptionFailed` as control
flow): `drawBoolean({double probability = 0.5, bool? forced})`, `drawInteger({required int min,
required int max})`, `drawBigInteger({required BigInt min, required BigInt max})`,
`drawFloat({int width = 64, double min, double max, bool allowNan, bool allowInfinity, bool
excludeMin, bool excludeMax, double? smallestNonzeroMagnitude})`, `drawBytes({required int
minLength, required int maxLength})`, `drawString(StringGenerator g)`, `drawDate/Time/DateTime`,
`drawUuid({int? version})`, `drawIpv4()`, `drawIpv6()`; plus `startSpan(SpanLabel)`,
`stopSpan({bool discard = false})`, `startCollection({required int minSize, int? maxSize})`
(then `collection.more(tc)` / `collection.reject(tc, {why})`), `newPool()` (then `pool.add(tc)` /
`pool.draw(tc, consume: …)`), `newStateMachine(...)` (then the explicit-stream machine calls of
§7.5), `target(double value, {required String label})`, `clone()`, `isNondeterministic`.
`StringGenerator.text/regex/email/url/domain(...)` constructors mirror the C constructors with
Dart-typed parameters. Blob replay: `TestCase.fromBlob(settings, blob, {onOutput})`.

## 8. Designed-for (but not built): the property layer

Decisions above that exist specifically so the next phase composes cleanly, without building any of
it now:

- The draw surface is shaped so a data-source seam can sit directly on `TestCase` — generators
  will never import the FFI layer.
- Control-flow exceptions match the runner's eventual catch-ladder (`valid` / `AssumptionFailed →
  invalid` / `StopTest → overrun` / anything else → `interesting` + origin).
- `SpanLabel` is open-ended for library-defined compound generators; reserved constants exported.
- Stable-origin strings are the caller's job by ABI design; the runner will derive them from
  `StackTrace` frames, filtering out package frames so the origin points at the user's assertion.
- The borrow-token protocol and explicit draw streams (§7.5) keep concurrent stateful testing
  reachable, and the two-worker test proves it against the real engine.
- The disposable per-isolate session means a future runner can spawn and tear down worker isolates
  freely, with no accumulating native state.

## 9. Testing strategy

Three tiers. **Integration against the real engine is the default; the engine is never mocked;
fakes exist only for branches the engine cannot be driven to produce.** One operational caveat: the
tiers describe *execution* dependencies, not network independence — after commit 6, `dart test`
runs the package's build hook before any test, whatever the test imports. For offline work and
no-network CI, the `libhegel_path` user-define points the hook at a local fixture engine; a
dedicated no-network CI job proves that path stays honest.

1. **Pure unit tests** (no native calls): BigInt codec round-trips incl. sign-byte edges and int64
   boundary split; Unicode scalar validation (paired surrogates pass, lone surrogates throw,
   U+0000 policy per destination); null-vs-empty pointer/length marshalling; flag/extension-type
   algebra; the `check` funnel's mapping incl. unknown raw codes; acquisition logic
   (platform→asset map, hash verification, install/race logic) with injected fs/HTTP.
2. **Fake-`Bindings` tests**: unreachable codes (`E_BACKEND`, `E_INTERNAL`, `E_CONCURRENT_USE`),
   callback ownership accounting (§7.4), exact `Settings` setter-call sequences (§7.2), sentinel
   bit patterns (§7.3), post-error cleanup, version-mismatch throw, leak-sink reporting. The fake
   is a scriptable in-memory `Bindings` with per-function return-code overrides and sentinel
   pointers.
3. **Hook tests**: `testCodeBuildHook`-harness tests running the real hook logic — user-define
   override, verified cache hit, corrupt/truncated cache recovery, unwritable cache fallback,
   concurrent-installer race (best-effort), destination-already-exists, external cache deleted
   after a successful hook run, unsupported platform. Unit tests of an injected environment cannot
   detect the hook runner's environment filtering or cache-input behavior — these can.
4. **Integration tests** (real engine via the hook — the identical path users take):
   - Ports of every `hegel-c/examples/*.c`: echo (passing run), failing (failure → shrink →
     origin/blob → `fromBlob` replay reproduces), spans_collections, pool, state_machine
     (sequential), custom_output (callback capture), invalid_argument (error paths — engine
     lifecycle codes like `E_NOT_COMPLETE`/`E_ALREADY_COMPLETE` exercised **through L1**, since L2
     guards them off; L2 misuse tests assert `StateError` before FFI instead).
   - The **two-worker concurrent state-machine test** (§7.5).
   - Determinism: fixed seed ⇒ identical draw sequences across two full runs.
   - String edge cases: astral-plane characters round-trip; U+0000 draw via `include_characters`;
     lone-surrogate inputs rejected with `ArgumentError`; `categories: null` vs `[]` outcomes;
     empty-alphabet `E_INVALID_ARG`; regex/email/url/domain smoke.
   - BigInt draws with bounds outside int64; date/time/datetime at extreme bounds; UUID version
     nibble; unbounded collection; targeting smoke; `reportMultipleFailures` with two distinct
     origins.
   - Abort-latch behavior for **both** kinds through draws, collections, pools, and machines,
     including an operation performed by a `finally` block.
   - Session lifecycle: dispose frees the context; version-check failure frees the fresh context;
     wrappers outliving a disposed session are caught in debug mode.
5. **L1 exercise audit**: a suite asserting every `Bindings` method is exercised by the
   integration suites, with the expected inventory **generated from the pinned header** so a
   manually maintained list can't omit a new function on both sides. (Eager `Native.addressOf` in
   the `NativeBindings` constructor already proves *linkage*; this audit proves *behavioral*
   exercise through L2.)

Coverage bar: 100% line + branch, gated in CI from commit 19 (§12), measured per the exclusions in
§3 (generated externals, the GC-delivery smoke). As built, the gate enforces ratcheted floors
sitting just under the measured ceiling rather than a literal 100% — `tool/check_coverage.dart`
says why: Windows-only and POSIX-permission branches are unreachable on the one platform coverage
runs on, and the floors only ever move up.

## 10. CI

GitHub Actions (invoking `dart` commands directly; the `justfile` mirrors them for local use):

- **lint**: `dart format --output=none --set-exit-if-changed .`, `dart analyze --fatal-infos`.
- **test matrix**: `ubuntu-latest` (linux/amd64), `ubuntu-24.04-arm` (linux/arm64), `macos-14`
  (darwin/arm64), `windows-2025` (windows/amd64), and `windows-11-arm` (windows/arm64) if the
  hosted runner is available to the org. Each job is `dart pub get && dart test` — the hook
  fetches the pinned engine, so CI exercises exactly the path users take. No token is needed
  (public direct-download URLs); the cross-project engine cache is primed via the actions cache.
- **no-network job**: primes a fixture engine, then runs the suite with downloads blocked and the
  `libhegel_path` user-define set — keeping the offline path honest.
- **AOT smoke**: `dart build cli` on a tiny CLI that calls `hegel_version`, proving the code asset
  survives AOT bundling (from commit 9, not deferred to the end).
- **coverage**: the 100% gate (from commit 19), with the §3 exclusions.
- **drift**: re-fetch pinned `hegel.h` and upstream `LICENSE`, `git diff --exit-code third_party/`;
  rerun exact-pinned ffigen (this job installs libclang),
  `git diff --exit-code lib/src/libhegel/bindings.g.dart`.
- **packaging**: `dart pub publish --dry-run` (archive-content check) so the hook, vendored
  header/license, and generated files actually ship when hegel-dart is eventually published.
- Later (post-bindings): automation that opens a PR per new hegel-rust release, runs
  `tool/update_libhegel.dart`, and includes an alignment audit diffing the new header against the
  L1 `Bindings` inventory.

## 11. Milestones

Each milestone is a contiguous range of the commits in §12 and lands green before the next starts.

| # | Milestone | Commits | Exit criterion |
|---|---|---|---|
| **M0** | Scaffold | 1–3 | empty package lints, tests, and runs in CI |
| **M1** | Engine acquisition | 4–6 | fresh checkout: `dart test` downloads, verifies, and calls into the real engine on all supported platforms; user-define override and cache recovery proven by hook tests |
| **M2** | Generated bindings | 7–10 | full raw surface generated from the vendored header; drift-checked; matrix + AOT smoke green |
| **M3** | Safe core | 11–19 | echo- and failing-equivalent runs pass end to end; guard-first misuse contract tested; coverage gate on |
| **M4** | Full value surface | 20–26 | every draw primitive bound, codecs proven, string/temporal/UUID/IP/targeting suites green |
| **M5** | Structure & stateful | 27–32 | spans, collections, pools, state machines (sequential **and** two-worker concurrent), callback — all example ports green |
| **M6** | Hardening & DX | 33–35 | leak diagnostics, L1 exercise audit, docs, example, packaging check |

M1–M3 carry the risk (hook ecosystem, ffigen mode, lifecycle design); M4–M5 are wide but
mechanical once the M3 patterns exist.

## 12. Commit plan

Ground rules:

- **Every commit builds and passes tests**: format check, `dart analyze --fatal-infos`, and
  `dart test` are green at every commit, locally and in CI. Sole exemption: commit 1 is docs-only
  and predates the package — there is nothing to build until commit 2.
- From commit 6 onward, `dart test` includes real-engine integration tests; the build hook fetches
  the pinned engine automatically, so any commit is testable from a fresh checkout given network
  access (or the `libhegel_path` user-define).
- Generated artifacts (`bindings.g.dart`, `version.g.dart`, the vendored header and license) are
  regenerated in the same commit as their inputs; the drift job enforces this from commit 10.
- From commit 19 onward, every commit maintains the coverage gate (with the §3 exclusions) —
  feature commits carry their own fake-driven tests for branches the engine can't produce.
- Each feature commit includes its tests; test-only commits exist only where the suite itself is
  the deliverable.

**M0 — scaffold**

1. `docs: libhegel bindings implementation plan` — this document (docs-only; exempt, see above).
2. `chore: scaffold the hegel package` — `pubspec.yaml` (name `hegel`, sdk `^3.13.0`, direct deps
   incl. `crypto` and `meta`), `analysis_options.yaml`, `.gitignore`, empty `lib/hegel.dart`
   barrel, a smoke test that imports it, `justfile` with `lint`/`test` recipes. Green: analyze +
   smoke test.
3. `ci: lint and linux test jobs` — format/analyze/test on `ubuntu-latest`, invoking `dart`
   directly. Green: CI mirrors the local recipes.

**M1 — engine acquisition**

4. `feat: engine acquisition library` — `lib/src/tooling/acquire.dart`: platform→asset map for the
   five released targets, release-URL construction, sha256 verification (`package:crypto`),
   race-safe atomic install with a destination-exists loser path, verified-cache-hit logic, and a
   configuration model fed by user-defines (not environment variables). Pure Dart. Green: unit
   tests with injected fs/HTTP; no network.
5. `feat: update tool and pinned engine version` — `tool/update_libhegel.dart`: resolve the pinned
   hegel-rust release (normal environment; may use the GitHub API/token), download every platform
   asset, **recompute digests and compare against the `.sha256` sidecars**, write the pins, vendor
   `hegel.h` and upstream `LICENSE` at the tag; refuse a release missing any platform. Run once:
   this commit checks in `version.g.dart` and `third_party/libhegel/`. Green: unit tests for the
   tool's pure parts (metadata parsing, digest comparison, pin-file rendering).
6. `feat: build hook providing the libhegel code asset` — `hook/build.dart`: `libhegel_path`
   user-define override (registered via `output.addDependency`), managed `outputDirectoryShared`
   staging, optional HOME-derived / `cache_dir` cross-project cache with verify-on-hit, race-safe
   install; every emitted asset comes from the managed directory. Includes
   `testCodeBuildHook`-harness tests (override, corrupt cache recovery, unwritable cache,
   unsupported platform, external-cache deletion) and one hand-written `@Native` declaration for
   `hegel_version` in an integration smoke test asserting the pinned version — proving the entire
   acquisition pipeline end to end before any generated code exists. CI gains engine-cache
   priming. Green: first real-engine test + hook harness tests.

**M2 — generated bindings**

7. `feat: ffigen config and generated raw bindings` — `ffigen.yaml` (exact-pinned ffigen),
   checked-in `bindings.g.dart` for the full header, `just regen` recipe; the smoke test switches
   to the generated `hegel_version`. This commit is the `ffi-native` spike: any unsupported
   construct gets a hand-written `@Native` shim against the same asset id (no
   `DynamicLibrary.open` fallback — §6). Green: smoke via generated code.
8. `ci: full platform test matrix` — add linux/arm64, darwin/arm64, windows/amd64 (and
   windows/arm64 when available). Early cross-platform signal while the surface is one function.
   Green: smoke on every platform.
9. `ci: AOT bundling smoke` — a minimal CLI target built with `dart build cli` that calls
   `hegel_version`, run in CI. Proves the code asset survives AOT bundling now rather than at the
   end. Green: AOT smoke passes on the matrix's primary platforms.
10. `ci: header and bindings drift check` — refetch pinned header + license, rerun ffigen,
    `git diff --exit-code`. Green: drift job passes on a clean tree.

**M3 — safe core**

11. `feat: result codes and error funnel` — `errors.dart`: `HegelResultCode` (with `unknown`),
    `HegelException` retaining the raw code, const `StopTest`/`AssumptionFailed`, the `check`
    funnel. Green: pure unit tests over every code, including unrecognized ones.
12. `feat: Bindings interface and NativeBindings` — L1 covering the full C surface 1:1, eager
    `Native.addressOf` verification in the constructor; scriptable `FakeBindings` test helper.
    Green: integration test constructing `NativeBindings` (whole-surface linkage against the
    pinned engine); unit tests that fake return codes flow through.
13. `feat: disposable per-isolate session with version check` — `session.dart` per §4:
    `Libhegel.instance`, context ownership, `dispose()`, `major.minor` check that frees the fresh
    context on failure, `overrideForTesting` disposing its predecessor. Green: integration
    (engineVersion matches pin; dispose frees); fake-driven mismatch and cleanup-on-failure tests.
14. `feat: string marshalling and scalar validation` — `marshal.dart`: arena string/buffer
    helpers, Unicode scalar-value validation, NUL policy per destination kind, null-vs-empty
    pointer/length helper, internal sentinel constants. Green: pure unit tests (paired/lone
    surrogates, U+0000 both destinations, empty-list non-null allocation, bit patterns).
15. `feat: Settings` — `settings.dart`: nullable omission-aware parameters calling setters only
    when supplied, `Database?` semantics per §7.2, `Phases`/`HealthChecks` extension types,
    `Mode`/`Backend`/`Verbosity` enums. Green: fake test asserting exact setter-call sequences
    (incl. "omitted ⇒ no call"); integration (construct, set everything, dispose; idempotent
    double-dispose; use-after-dispose throws); unit (flag algebra).
16. `feat: Run, TestCase, RunResult lifecycle` — start/nextTestCase/result/dispose,
    `markComplete`, statuses, and the guard-first state machine of §7.1 (`StateError` before FFI
    for misuse L2 can see). Green: integration — a zero-draw run finishes `passed`; L2 misuse
    throws `StateError` without native calls (fake-verified); engine lifecycle codes
    (`E_NOT_COMPLETE`, `E_ALREADY_COMPLETE`) exercised through L1.
17. `feat: scalar draws with family abort latch` — `drawBoolean`/`drawInteger`/`drawFloat`; the
    family-state latch of §7.2 recording and re-throwing the **original** abort kind across all
    family members. Green: echo.c port; determinism test; latch tests for both kinds including a
    draw from a `finally` block; inverted-bounds `ArgumentError`.
18. `feat: failures and blob replay` — `Failure`, `RunResult.failureCount/failure`,
    `TestCase.fromBlob`. Green: failing.c port — failure surfaces origin + blob and the replay
    reproduces the same drawn value; invalid blob throws; `reportMultipleFailures` yields two
    distinct origins.
19. `ci: enforce the coverage gate` — coverage tooling + CI gate per §3's exclusions; backfill
    fake-driven tests for branches unreachable so far (`E_BACKEND`/`E_INTERNAL`/
    `E_CONCURRENT_USE` mappings, error-path cleanup). Green: gate passes; stays on for every later
    commit.

**M4 — full value surface**

20. `feat: BigInt two's-complement codec` — `codec/bigint.dart`. Green: exhaustive unit tests
    (sign-byte edges, int64 boundaries, round-trips both directions).
21. `feat: drawBigInteger` — int64-fit split; big path wiring with full-width sign-filled decode.
    Green: integration with bounds beyond int64 in both signs; equal-bounds; seed determinism.
22. `feat: drawBytes` — zero-initialized out-struct marshalling, immediate copy, free only owned
    results. Green: integration incl. zero-length draws and buffer independence after free.
23. `feat: string generators and drawString` — `StringGenerator.text/regex/email/url/domain`,
    `drawString` with strict UTF-8 decode. Green: integration — each constructor draws;
    astral-plane round-trip; U+0000 via `include_characters`; lone-surrogate input rejected;
    `categories: null` vs `[]` distinct outcomes; empty-alphabet `E_INVALID_ARG`; generator
    self-rejection surfaces as `AssumptionFailed`.
24. `feat: temporal draws` — date/time/datetime records, by-value struct marshalling. Green:
    integration at full-range and extreme bounds.
25. `feat: drawUuid, drawIpv4, drawIpv6` — fixed-size buffers. Green: integration — version
    nibble forcing, output lengths, non-nil UUID.
26. `feat: target` — targeting observations. Green: integration smoke with the TARGET phase on
    and off; non-finite value rejected client-side.

**M5 — structure & stateful**

27. `feat: spans` — `startSpan`/`stopSpan`, `SpanLabel` constants. Green: integration — nested
    spans and the discard path (first half of the spans_collections.c port).
28. `feat: collections` — explicit-stream `Collection.more(tc)`/`reject(tc)`; `int? maxSize`
    marshalling the internal unbounded sentinel. Green: spans_collections.c port complete;
    size-bounds tests; real unbounded-collection test; fake assertion of the `-1` bit pattern;
    latch coverage through collection ops.
29. `feat: pools` — explicit-stream `Pool.add(tc)`/`draw(tc, consume:)`. Green: pool.c port;
    empty pool ⇒ `AssumptionFailed`; consume semantics; latch coverage through pool ops.
30. `feat: state machines` — full constructor (rules, groups, invariants, concurrency bounds),
    explicit-stream `nextGroup`/`nextRule`/`ruleRejected`, `clone`, `isNondeterministic`,
    non-owning borrow tokens (`@internal`). Green: state_machine.c port (sequential,
    `min == max == 1`); rejected-rule retry; `DONE` sentinel mapped to null; latch coverage
    through machine ops.
31. `test: two-worker concurrent state machine` — coordinator + two `Isolate.spawn` workers using
    borrow tokens per §7.5: first-creation `E_ASSUME` flip, worker index > 0, group join points,
    clone streams in workers, `isNondeterministic`, `FAILED_NONDETERMINISTIC`, no reproduction
    blob, coordinator-owned frees after join. Green: the test itself, on the full matrix.
32. `feat: output callback` — `NativeCallable.isolateLocal` with the transactional error policy
    and unconditional re-entrancy guard of §7.4; ordered teardown. Green: custom_output.c port
    capturing engine lines; fake-driven ownership-count tests (throw before a case / with a case /
    at completion); guard test proving no second native call; null default leaves output on
    stderr.

**M6 — hardening & DX**

33. `feat: best-effort leak diagnostics` — assert-mode `Finalizer` reporting through an extracted,
    deterministic sink; detached on dispose; callback never throws. Green: sink logic
    unit-tested deterministically; one non-gating VM smoke for actual GC delivery (excluded from
    the coverage gate).
34. `test: L1 exercise audit` — inventory generated from the pinned header, asserting every
    `Bindings` method is exercised by the integration suites (behavioral coverage; linkage is
    already proven eagerly by commit 12). Green: the audit itself.
35. `docs: API docs, example, README, packaging check` — dartdoc on the L2 surface,
    `example/echo.dart`, README quick-start incl. the `libhegel_path` local-engine workflow and
    the note that env vars cannot configure hooks; `dart pub publish --dry-run` archive check in
    CI. Green: `dart doc` builds; full suite green on the full matrix.

## 13. Risks

- **Hooks ecosystem churn** — `hooks`/`code_assets` are 2.x with recent majors, and user-defines
  are a young mechanism. Mitigation: pin tightly, keep all hook logic behind our own acquisition
  library, real hook-harness tests, CI on the real path.
- **ffigen ffi-native coverage** — validated by the commit-7 spike; the fallback is
  `@Native`-shaped shims, so acquisition and asset design are unaffected either way.
- **AOT bundling** — proven early by the commit-9 `dart build cli` smoke rather than assumed.
- **Flutter** — desktop-only at most (upstream ships no mobile engines); package platform
  metadata will say so. Mobile is a separate upstream + design project.
- **ABI bump cadence** — upstream changed the state-machine signature within the last few minor
  releases; more bumps will come. Mitigation: exact pin, the L1 inventory + eager verification,
  the header-derived exercise audit, and the update tool making bumps a one-command workflow.
- **Two-worker test flakiness** — it exercises real concurrency, so it is kept small (two workers,
  bounded steps, fixed concurrency bounds) and asserts protocol outcomes, not timing.

## 14. Review disposition

All findings from `libhegel-bindings-plan-review.md` (B1–B4, H1–H7, M1–M9) are incorporated.
Verified during triage: the hook environment contains only `HOME` and `PATH` (B2); the engine
strictly validates UTF-8 with `core::str::from_utf8` and cannot emit unpaired surrogates (B1);
Dart's `utf8.encode` replaces a lone surrogate with U+FFFD. Deviations from the review's exact
prescriptions:

- **B3:** of the two offered options, the plan adopts the stronger one — a real two-worker
  integration test (commit 31) — rather than dropping the concurrency-enablement claim.
- **B4:** the "release-mode re-entry test" is replaced by making the re-entrancy guard an
  unconditional runtime check plus a fake-driven test proving no second native call — the property
  the review wanted, made independent of build mode by construction.
- **H1/M8:** inherently nondeterministic race tests (concurrent installers) are written as
  best-effort and are not flake-gates, consistent with the review's own M3 reasoning about
  GC-dependent tests.
- **B2:** `GITHUB_TOKEN` is removed from the hook path as required, but retained as an *optional*
  input to `tool/update_libhegel.dart`, which runs in a normal environment and may use the GitHub
  API for release enumeration.

---

## Appendix A — C API → Dart surface map

| C functions | Dart surface (L2) |
|---|---|
| `hegel_context_new/free/last_error`, `hegel_version` | `Libhegel` session (per isolate, disposable): context owned internally and freed by `dispose()`, `engineVersion`, error messages folded into `HegelException` |
| `hegel_settings_new/free`, 13 `hegel_settings_set_*` | `Settings` ctor with omission-aware named params (`testCases`, `statefulStepCount`, `mode`, `backend`, `seed`, `derandomize`, `database` (`Database?`), `databaseKey`, `phases`, `suppressHealthChecks`, `reportMultipleFailures`, `verbosity`) — setters called only for supplied values — + `dispose` |
| `hegel_run_start/next_test_case/result/free` | `Run.start(settings, {onOutput})`, `nextTestCase() → TestCase?`, `result() → RunResult`, `dispose`; guard-first run-state machine, unconditional re-entrancy guard |
| `hegel_test_case_free/clone/is_nondeterministic`, `hegel_mark_complete`, `hegel_test_case_from_blob` | `TestCase`: `dispose`, `clone`, `isNondeterministic`, `markComplete(status, {origin})`, static `fromBlob`; family-wide abort latch; `@internal` non-owning borrow tokens |
| `hegel_generate_boolean/integer/integer_big/float/bytes(+free)` | `drawBoolean/drawInteger/drawBigInteger/drawFloat/drawBytes` returning plain Dart values |
| `hegel_string_generator_text/regex/email/url/domain/free`, `hegel_generate_string(+free)` | `StringGenerator.text/regex/email/url/domain` (null-vs-empty list semantics preserved) + `dispose`; `drawString → String` (strict UTF-8) |
| `hegel_generate_date/time/datetime/uuid/ipv4/ipv6` | `drawDate/drawTime/drawDateTime` (records), `drawUuid/drawIpv4/drawIpv6` (`Uint8List`) |
| `hegel_start_span/stop_span` | `startSpan(SpanLabel)`, `stopSpan({discard})` (no-op under the abort latch) |
| `hegel_new_collection`, `collection_more/reject/free` | `tc.startCollection({minSize, int? maxSize})`; `Collection.more(tc) → bool`, `reject(tc, {why})`, `dispose` |
| `hegel_new_pool`, `pool_add/generate/free` | `tc.newPool()`; `Pool.add(tc) → int`, `draw(tc, {consume}) → int`, `dispose` |
| `hegel_new_state_machine`, `state_machine_next_group/next_rule/rule_rejected/free` | `tc.newStateMachine(...)` (concurrency drawn at creation); `StateMachine.nextGroup(rootTc) → int?`, `nextRule(workerTc, workerIndex) → int?` (null = done), `ruleRejected(workerTc, workerIndex)`, `dispose` |
| `hegel_target` | `target(value, {label})` |
| `hegel_run_result_status/error/failure_count/failure/free` | `RunResult`: `status` (enum incl. `failedNondeterministic`), `error`, `failureCount`, `failure(i)`, `dispose` |
| `hegel_failure_origin/reproduction_blob/free` | `Failure`: `origin`, `reproductionBlob` (`String?`), `dispose` |
