// A script rather than a test file: the point of this one is that there is no
// package:test around it. `runProperty` is documented as drivable by any
// harness, and a property that fails in more than one way has more failures
// than a future can carry -- so what happens to the rest is a promise that
// only a run outside a test can check.
//
// test/property/standalone_test.dart runs it as a subprocess and reads what
// came out.
library;

import 'package:hegel/hegel.dart';

const Settings fixtureSettings = Settings(
  testCases: 100,
  seed: 1,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
);

Future<void> main() async {
  print('BEFORE');
  try {
    await runProperty((TestCase tc) {
      final value = tc.draw(integers(min: 0, max: 1000), name: 'value');
      if (value.isEven) {
        if (value >= 100) throw StateError('an even value went large: $value');
      } else {
        if (value >= 200) throw StateError('an odd value went large: $value');
      }
    }, settings: fixtureSettings);
  } on Object catch (error) {
    print('CAUGHT $error');
  }
  print('AFTER');
}
