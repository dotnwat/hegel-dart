// A fixture rather than a test file; see property_fixture.dart. This one is
// run by test/property/e2e_test.dart with HEGEL_TEST_CASES set, and checks
// itself, so the driver only has to look at the exit code -- how many cases a
// run actually got is not something the output says.
@TestOn('vm')
library;

import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

/// The number of cases this property is written to run.
///
/// Deliberately not the number the driver sets in the environment: which of
/// the two wins is the whole question.
const int casesWritten = 7;

/// The number the environment asks for instead.
const int casesFromEnvironment = 3;

int bodies = 0;

void main() {
  property(
    'counts the cases it is given',
    (TestCase tc) {
      bodies++;
      tc.draw(integers(min: 0, max: 10));
    },
    settings: const Settings(
      testCases: casesWritten,
      seed: 1,
      derandomize: true,
      database: Database.disabled,
      verbosity: Verbosity.quiet,
    ),
  );

  test('ran as many cases as the environment asked for', () {
    expect(bodies, casesFromEnvironment);
  });
}
