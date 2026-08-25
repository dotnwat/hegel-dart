/// The arithmetic, with no Flutter in it.
///
/// Everything Abacus knows about numbers lives here: a tokeniser, a parser
/// with the precedence people expect, and the formatting that turns a double
/// back into something to put on a screen. It is ordinary Dart, it is pure,
/// and `test/arithmetic_test.dart` holds properties over all of it.
///
/// That matters for what this example is about. When the calculator shows the
/// wrong answer, this is not where the mistake is.
library;

/// The multiplication sign the keypad shows, and the one expressions carry.
const String timesSign = '×';

/// The division sign the keypad shows.
const String divideSign = '÷';

/// The minusSign sign the keypad shows.
const String minusSign = '−';

/// The operators, in the spelling an expression uses.
const String operators = '+$minusSign$timesSign$divideSign';

/// The value of [expression], or null if it is not one.
///
/// Null covers everything that is not a number waiting to be read: an empty
/// expression, one that ends in an operator because the next number has not
/// been typed yet, a number with two decimal points in it, and a division by
/// zero. A calculator has one of these on screen most of the time -- it is
/// what a half-typed sum looks like -- so it is a normal answer rather than
/// an error.
double? evaluate(String expression) {
  final tokens = _tokenise(expression);
  if (tokens == null || tokens.isEmpty) return null;
  final parser = _Parser(tokens);
  final value = parser.sum();
  if (value == null || !parser.done) return null;
  return value.isFinite ? value : null;
}

/// [value] as a calculator would show it.
///
/// Whole numbers lose their decimal point, and everything else is cut to ten
/// significant digits with the trailing zeros taken off, because a display
/// that reads `0.30000000000000004` is telling the truth and helping nobody.
String formatAnswer(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  final text = value.toStringAsPrecision(10);
  if (!text.contains('.') || text.contains('e')) return text;
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// The answer [expression] should be showing, or the empty string.
///
/// The one function this whole example is about: the calculator's job is to
/// put this, and nothing else, under the expression on screen.
String answerFor(String expression) {
  final value = evaluate(expression);
  return value == null ? '' : formatAnswer(value);
}

/// [expression] as numbers and operators, or null if it is neither.
List<Object>? _tokenise(String expression) {
  final tokens = <Object>[];
  var index = 0;
  while (index < expression.length) {
    final character = expression[index];
    if (operators.contains(character)) {
      tokens.add(character);
      index++;
      continue;
    }
    final start = index;
    var points = 0;
    while (index < expression.length) {
      final digit = expression[index];
      if (digit == '.') {
        points++;
      } else if (digit.codeUnitAt(0) < 0x30 || digit.codeUnitAt(0) > 0x39) {
        break;
      }
      index++;
    }
    if (index == start || points > 1) return null;
    final number = double.tryParse(expression.substring(start, index));
    if (number == null) return null;
    tokens.add(number);
  }
  return tokens;
}

/// Sums of products, left to right within each.
final class _Parser {
  _Parser(this._tokens);

  final List<Object> _tokens;
  int _at = 0;

  bool get done => _at == _tokens.length;

  double? sum() {
    var value = product();
    if (value == null) return null;
    while (_at < _tokens.length) {
      final token = _tokens[_at];
      if (token != '+' && token != minusSign) break;
      _at++;
      final right = product();
      if (right == null) return null;
      value = token == '+' ? value! + right : value! - right;
    }
    return value;
  }

  double? product() {
    var value = number();
    if (value == null) return null;
    while (_at < _tokens.length) {
      final token = _tokens[_at];
      if (token != timesSign && token != divideSign) break;
      _at++;
      final right = number();
      if (right == null) return null;
      if (token == divideSign && right == 0) return null;
      value = token == timesSign ? value! * right : value! / right;
    }
    return value;
  }

  double? number() {
    if (_at >= _tokens.length) return null;
    final token = _tokens[_at];
    if (token is! double) return null;
    _at++;
    return token;
  }
}
