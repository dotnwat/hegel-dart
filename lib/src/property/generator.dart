/// The generator algebra: what a property draws from.
library;

import 'package:meta/meta.dart';

import '../libhegel/errors.dart';
import '../libhegel/leaks.dart';
import '../libhegel/session.dart';
import '../libhegel/span.dart';
import '../libhegel/string_generator.dart' as engine;
import 'test_case.dart';

part 'catalog.dart';
part 'combinators.dart';
part 'composite.dart';

/// A recipe for values of type [T].
///
/// Generators are values: cheap to make, free of state, and safe to share
/// between properties and between cases.
///
/// The algebra is closed. [Generator] is `final`, so the only generators that
/// exist are the ones this library defines, and every compound one wraps its
/// parts in the span the engine expects. That is what the shrinker works
/// from -- delete this element, simplify that component -- so a generator
/// built outside the algebra would not shrink so much as fall apart. Custom
/// generation has its own door, [composite], which is a function rather than
/// a subclass.
abstract final class Generator<T> {
  /// For the generators in this library.
  const Generator();

  /// Produces one value, drawing whatever it needs from [testCase].
  ///
  /// Called by [TestCase.draw]; a property body never calls it directly.
  @internal
  T generate(TestCase testCase);

  /// This generator's values, each put through [transform].
  ///
  /// The way to generate anything the catalog does not: draw the shape the
  /// engine knows how to make and shrink, then build the value the property
  /// is about out of it. A user id from an integer, a sorted list from a
  /// list, a command from a name and its arguments -- the engine goes on
  /// shrinking the integer, and the id follows it down.
  ///
  /// [transform] runs on every case, including the ones that pass, so it is
  /// not the place for anything expensive or anything with an effect.
  Generator<R> map<R>(R Function(T value) transform) =>
      _MappedGenerator<T, R>(this, transform);

  /// This generator's values that satisfy [predicate], and no others.
  ///
  /// Named for `Iterable.where`; the rest of the Hegel family calls this one
  /// `filter`.
  ///
  /// Filtering is the second choice and worth avoiding where the value can be
  /// built instead: a generator that redraws until it lands on an even number
  /// wastes most of what it draws, where `integers().map((n) => n * 2)`
  /// wastes none of it and shrinks better. What filtering costs is bounded --
  /// three attempts, then the case is rejected as though the body had called
  /// [TestCase.assume] -- so a predicate that rarely holds does not hang; it
  /// rejects case after case until the engine's FilterTooMuch health check
  /// says so.
  Generator<T> where(bool Function(T value) predicate) =>
      _FilteredGenerator<T>(this, predicate);

  /// The values of whichever generator [choose] picks for each of this one's.
  ///
  /// For values whose shape depends on a value: a list and an index into it,
  /// a length and a string of that length, a tagged union whose payload the
  /// tag decides. [map] cannot do it, because the second half needs to draw.
  ///
  /// [choose] is called once per draw and must return a generator that
  /// depends on nothing but its argument. One that consults the clock or a
  /// counter makes a case that cannot be replayed: the engine hands back the
  /// same choices, and a different generator reads them as different values.
  Generator<R> flatMap<R>(Generator<R> Function(T value) choose) =>
      _FlatMapGenerator<T, R>(this, choose);
}
