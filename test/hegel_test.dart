@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:hegel/generators.dart' as gen;
import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

void main() {
  test('the barrel exposes the public API', () {
    // What is being checked is the export graph, not the generator: a type
    // that has to be imported from `src/` to be named is not public, however
    // public its declaration looks.
    expect(integers(min: 0, max: 1), isA<Generator<int>>());
  });

  test('the barrel exposes every generator in the catalog', () {
    // One line per catalog entry, which is the point: a generator that
    // exists but is not exported is one nobody can use, and nothing else in
    // the suite would notice, since every other test reaches into `src/`.
    expect(booleans(), isA<Generator<bool>>());
    expect(doubles(), isA<Generator<double>>());
    expect(bigIntegers(), isA<Generator<BigInt>>());
    expect(durations(), isA<Generator<Duration>>());
    expect(text(), isA<TextGenerator>());
    expect(characters(), isA<TextGenerator>());
    expect(fromRegex('a'), isA<Generator<String>>());
    expect(emails(), isA<Generator<String>>());
    expect(urls(), isA<Generator<String>>());
    expect(domains(), isA<Generator<String>>());
    expect(bytes(), isA<Generator<Uint8List>>());
    expect(dates(), isA<Generator<DateTime>>());
    expect(times(), isA<Generator<Duration>>());
    expect(dateTimes(), isA<Generator<DateTime>>());
    expect(uuids(), isA<Generator<String>>());
    expect(ipAddresses(), isA<Generator<InternetAddress>>());
    expect(just(1), isA<Generator<int>>());
    expect(sampledFrom(<int>[1]), isA<Generator<int>>());
    expect(oneOf(<Generator<int>>[just(1)]), isA<Generator<int>>());
    expect(optional(just(1)), isA<Generator<int?>>());
    expect(tuple2(just(1), just(2)), isA<Generator<(int, int)>>());
    expect(
      tuple3(just(1), just(2), just(3)),
      isA<Generator<(int, int, int)>>(),
    );
    expect(
      tuple4(just(1), just(2), just(3), just(4)),
      isA<Generator<(int, int, int, int)>>(),
    );
    expect(composite((TestCase tc) => 1), isA<Generator<int>>());
    expect(deferred<int>(), isA<Generator<int>>());
  });

  test('the generators library exposes them on their own', () {
    // The sibling-style import, for anyone who would rather prefix the
    // catalog than take forty names into their file.
    expect(gen.integers(), isA<gen.Generator<int>>());
    expect(gen.text(), isA<gen.Generator<String>>());
    expect(gen.integers().map((int n) => '$n'), isA<gen.Generator<String>>());
  });
}
