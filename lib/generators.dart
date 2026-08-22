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
/// `Pool` comes with them, which is the one name here that is not itself a
/// generator. It is where two of them come from, and a pool separated from
/// `gen.reusable` by an import would be a seam across one idea.
library;

export 'src/property/generator.dart';
