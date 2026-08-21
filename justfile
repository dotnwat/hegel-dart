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
