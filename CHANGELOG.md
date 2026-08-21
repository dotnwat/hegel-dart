# Changelog

## 0.1.0-dev

Unreleased. The libhegel FFI bindings, built from the bottom up.

- Engine distribution through a build hook: the pinned release is downloaded,
  verified against a checked-in SHA-256, staged, and published as a code asset,
  with a local-engine override via pub user-defines.
- Generated raw bindings for the whole C ABI, checked in and drift-checked
  against the vendored header.
- A safe layer over the engine: sessions, settings, runs, test cases, every
  draw primitive, spans, collections, pools, state machines, targeting,
  failures, and blob replay.
- Concurrent stateful testing across isolates, with handle borrowing that keeps
  ownership in the coordinator.
- Engine output delivered to Dart through a callback.

No public API yet: everything lives under `lib/src/`, and the barrel
`lib/hegel.dart` is deliberately empty until the property-testing layer exists.
