# hegel

Property-based testing for Dart, powered by the [Hegel](https://hegel.dev)
engine.

> **Status: the bindings, not the API.** This package currently contains the
> FFI bindings to libhegel — the engine that does generation, shrinking, and
> replay. The property-testing API those bindings exist to support has not been
> written yet, so there is nothing here a test author would want to use
> directly. See `docs/libhegel-bindings-plan.md` for the plan and where this
> sits in it.

## What works today

The engine is fully reachable from Dart: configure a run, pull test cases, draw
values, report outcomes, read results, shrink failures, and replay them from a
reproduce blob. Every function the C ABI exposes is bound and exercised.

`example/echo.dart` drives a complete run through the bindings:

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
