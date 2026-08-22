/// A draw context that answers from a script instead of from the engine.
library;

import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/property/test_case.dart';

/// A [DrawContext] that answers from a script and records what it was asked.
///
/// The engine cannot be asked to hand back a particular value at a particular
/// point, which is exactly what pinning the bookkeeping around a draw needs:
/// the third retry of a filter, the branch a choice landed on, the draw that
/// comes after a span was discarded.
final class ScriptedContext implements DrawContext {
  /// Answers draws with [integers], in order.
  ScriptedContext(this.integers);

  /// The values [drawInteger] returns, in order.
  final List<int> integers;

  /// Every call made, as text, so a test can pin the order as well as the
  /// count -- a span closed before its body ran would otherwise look right.
  final List<String> calls = <String>[];

  int _next = 0;

  @override
  int drawInteger({required int min, required int max}) {
    calls.add('draw $min..$max');
    return integers[_next++];
  }

  @override
  void startSpan(SpanLabel label) => calls.add('start ${label.value}');

  @override
  void stopSpan({bool discard = false}) =>
      calls.add(discard ? 'discard' : 'stop');
}
