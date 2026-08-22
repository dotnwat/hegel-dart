// A fixture rather than a test file, which is why its name does not end in
// `_test.dart`: this one is meant to fail, and a file the runner picked up by
// itself would fail the suite. test/property/e2e_test.dart runs it as a
// subprocess and reads what came out.
@TestOn('vm')
library;

import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

/// No database, so a counterexample from one run cannot change the next, and
/// a fixed seed, so what the engine tries is the same every time.
const Settings fixtureSettings = Settings(
  testCases: 100,
  seed: 1,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
);

void main() {
  property('every drawn value is an integer', (TestCase tc) {
    expect(tc.draw(integers(min: 0, max: 100)), isA<int>());
  }, settings: fixtureSettings);

  property('every drawn value is below fifty', (TestCase tc) {
    expect(tc.draw(integers(min: 0, max: 1000)), lessThan(50));
  }, settings: fixtureSettings);
}
