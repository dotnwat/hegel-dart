/// The generator catalog, on its own.
///
/// Everything `package:hegel/hegel.dart` exports about *making values*, for
/// anyone who would rather prefix them than import forty names:
///
/// ```dart
/// import 'package:hegel/hegel.dart';
/// import 'package:hegel/generators.dart' as gen;
///
/// final names = gen.text(minLength: 1);
///
/// property('a greeting keeps the name it was given', (tc) {
///   final name = tc.draw(names, name: 'name');
///   expect(greet(name), contains(name));
/// });
/// ```
///
/// The same generators either way; this is a spelling, not a second API.
///
/// `Pool` comes with them, which is not itself a generator: it is where
/// `pool.reusable` and `pool.consumed` come from, and putting a pool on the
/// far side of an import from the generators it hands out would be a seam
/// across one idea.
library;

// The counter is `@visibleForTesting`, which is a lint and not an export
// filter, so it would otherwise be part of this library's public surface --
// and it is not a generator, which is the one thing this library claims
// everything here is. The tests that read it import the source directly.
export 'src/property/generator.dart' hide nativeStringGeneratorCount;
