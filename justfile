# Local convenience wrapper. CI runs the same dart commands directly, so a
# green `just` here means a green CI job.

# Everything CI checks.
default: lint test

# Formatting and static analysis.
lint:
    dart format --output=none --set-exit-if-changed .
    dart analyze --fatal-infos

# The test suite.
test:
    dart test

# Regenerate the raw FFI bindings from the vendored header. Needs libclang;
# CI re-runs this and fails if the checked-in output differs.
regen:
    dart run ffigen --config ffigen.yaml
