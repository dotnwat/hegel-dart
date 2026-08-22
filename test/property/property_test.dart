@TestOn('vm')
library;

import 'package:hegel/hegel.dart';
import 'package:test/test.dart';
import 'package:test_api/hooks.dart';

/// A short, seeded run: these properties are here to show the registration
/// works, not to search hard for a counterexample.
const Settings fastAndQuiet = Settings(
  testCases: 25,
  seed: 3,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
);

void main() {
  property('registers as an ordinary test that passes', (TestCase tc) {
    expect(tc.draw(integers(min: 0, max: 10)), inInclusiveRange(0, 10));
  }, settings: fastAndQuiet);

  property('awaits a body that is asynchronous', (TestCase tc) async {
    final value = tc.draw(integers(min: 0, max: 10));
    await Future<void>.delayed(Duration.zero);
    expect(value, inInclusiveRange(0, 10));
  }, settings: fastAndQuiet);

  property('is skipped when it says it is', (TestCase tc) {
    fail('the body of a skipped property must not run');
  }, skip: 'proving that skip: reaches the test it registers');

  property(
    'takes the platform it runs on',
    (TestCase tc) {
      expect(tc.draw(integers(min: 0, max: 10)), isA<int>());
    },
    settings: fastAndQuiet,
    testOn: 'vm',
  );

  group('inside a group', () {
    property('is named for the group it is in', (TestCase tc) {
      // The name is half of the key its counterexamples are filed under, so
      // what package:test considers this test to be called is load-bearing:
      // two properties with the same name in different groups must not share
      // a database entry.
      expect(
        TestHandle.current.name,
        'inside a group is named for the group it is in',
      );
      tc.draw(integers(min: 0, max: 3));
    }, settings: fastAndQuiet);
  });
}
