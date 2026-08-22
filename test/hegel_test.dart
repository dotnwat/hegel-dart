@TestOn('vm')
library;

import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

void main() {
  test('the barrel exposes the public API', () {
    // What is being checked is the export graph, not the generator: a type
    // that has to be imported from `src/` to be named is not public, however
    // public its declaration looks.
    expect(integers(min: 0, max: 1), isA<Generator<int>>());
  });
}
