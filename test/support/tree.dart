/// A recursive value, and the generator that builds one.
///
/// The shape recursion is always demonstrated on, and the one that shows what
/// spans are for: a tree is made of trees, so shrinking it means deleting
/// whole subtrees rather than picking at the numbers in the leaves.
library;

import 'package:hegel/src/property/generator.dart';

/// A binary tree of integers.
sealed class Tree {
  /// How many leaves are under this node, counting itself if it is one.
  int get leaves;
}

/// A tree that is one value.
final class Leaf extends Tree {
  /// A leaf holding [value].
  Leaf(this.value);

  /// What this leaf holds.
  final int value;

  @override
  int get leaves => 1;

  @override
  String toString() => 'Leaf($value)';
}

/// A tree that is two trees.
final class Branch extends Tree {
  /// A branch over [left] and [right].
  Branch(this.left, this.right);

  /// The subtree on the left.
  final Tree left;

  /// The subtree on the right.
  final Tree right;

  @override
  int get leaves => left.leaves + right.leaves;

  @override
  String toString() => 'Branch($left, $right)';
}

/// Generates trees, leaves first.
///
/// The leaf option comes first so that the smallest choice ends the
/// recursion: as a case runs out of choice budget the engine pushes draws
/// toward their smallest value, and a recursion whose first option recurses
/// would have nothing to bottom out into.
Generator<Tree> trees({int maxLeafValue = 100}) {
  final tree = deferred<Tree>();
  tree.define(
    oneOf(<Generator<Tree>>[
      integers(min: 0, max: maxLeafValue).map<Tree>(Leaf.new),
      tuple2(
        tree,
        tree,
      ).map<Tree>(((Tree, Tree) pair) => Branch(pair.$1, pair.$2)),
    ]),
  );
  return tree;
}
