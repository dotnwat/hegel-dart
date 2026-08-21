@TestOn('vm')
library;

// The barrel exports nothing yet, so importing it is the whole point of this
// test: it proves the package resolves and its library compiles. Drop the
// ignore once the public API lands.
// ignore: unused_import
import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

void main() {
  test('the package barrel resolves and compiles', () {
    // Reaching this point means `package:hegel/hegel.dart` was resolved and
    // compiled by the test runner.
    expect(true, isTrue);
  });
}
