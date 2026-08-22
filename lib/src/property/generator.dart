/// The generator algebra: what a property draws from.
library;

import 'package:meta/meta.dart';

import 'test_case.dart';

part 'catalog.dart';

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
/// generation has its own door, `composite`, which is a function rather than
/// a subclass.
abstract final class Generator<T> {
  /// For the generators in this library.
  const Generator();

  /// Produces one value, drawing whatever it needs from [testCase].
  ///
  /// Called by [TestCase.draw]; a property body never calls it directly.
  @internal
  T generate(TestCase testCase);
}
