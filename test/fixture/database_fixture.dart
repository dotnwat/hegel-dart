// A fixture rather than a test file; see property_fixture.dart. This one is
// run twice by test/property/e2e_test.dart against one example database, and
// prints the first value each run drew: replay is only visible from outside
// as "this run started where the last one ended".
@TestOn('vm')
library;

import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

/// The first value the property drew, whenever that was.
final List<int> firstDrawn = <int>[];

void main() {
  property(
    'every drawn value is below fifty',
    (TestCase tc) {
      final value = tc.draw(integers(min: 0, max: 1000), name: 'value');
      if (firstDrawn.isEmpty) firstDrawn.add(value);
      expect(value, lessThan(50));
    },
    settings: const Settings(
      testCases: 200,
      seed: 4,
      derandomize: true,
      verbosity: Verbosity.quiet,
    ),
  );

  // Printed rather than asserted: which value it is depends on whether
  // anything was stored, which is the driver's question rather than this
  // file's.
  test('says what it drew first', () {
    print('FIRST=${firstDrawn.single}');
  });
}
