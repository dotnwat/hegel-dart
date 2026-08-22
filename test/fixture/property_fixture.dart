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

/// The same run, asked to narrate.
///
/// Fewer cases because every one of them prints a line, and this exists to
/// show that the lines arrive rather than to produce a lot of them.
const Settings verboseSettings = Settings(
  testCases: 5,
  seed: 1,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.verbose,
);

void main() {
  property('every drawn value is an integer', (TestCase tc) {
    expect(tc.draw(integers(min: 0, max: 100)), isA<int>());
  }, settings: fixtureSettings);

  property('every drawn value is below fifty', (TestCase tc) {
    final value = tc.draw(integers(min: 0, max: 1000), name: 'value');
    tc.note('about to check $value');
    expect(value, lessThan(50));
  }, settings: fixtureSettings);

  // Two bugs in one property, not one bug reached two ways: the engine groups
  // failures by where they came from, so two assertion sites are two things
  // to shrink and two things to report. Which is the point -- a run that
  // showed only the first would leave the second to be found on the next run,
  // after the first was fixed.
  property('small values stay small, whichever kind they are', (TestCase tc) {
    final value = tc.draw(integers(min: 0, max: 1000), name: 'value');
    if (value.isEven) {
      expect(value, lessThan(100), reason: 'an even value went large');
    } else {
      expect(value, lessThan(200), reason: 'an odd value went large');
    }
  }, settings: fixtureSettings);

  // Verbose and passing, which is the combination that has somewhere to go
  // wrong: the engine's per-case output is meant to be watched while a run
  // happens, and a sink that buffered until failure would throw all of it
  // away on exactly the run somebody was watching.
  property('a verbose property narrates its own run', (TestCase tc) {
    tc.draw(integers(min: 0, max: 100), name: 'value');
  }, settings: verboseSettings);
}
