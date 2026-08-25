# Abacus

A calculator, and the app the hegel user-interface demonstration is recorded
against.

```console
$ flutter run -d linux      # the app
$ flutter test              # its own tests
```

Two screens, a keypad, an expression with a live answer under it, and a
history you can recall a calculation from. It is a toy, but it is not one
widget: the bug it has is in the wiring between the screens, which is the part
no test of a pure function can reach.

- `lib/arithmetic.dart` is the sums, and has no Flutter in it.
  `test/arithmetic_test.dart` holds properties over it with plain hegel, and
  they pass. When the calculator shows a wrong answer, the arithmetic is not
  where the mistake is.
- `lib/calculator_page.dart` is the screen, the state, and the wiring.
- `test/` is ordinary example-based tests: enough to know the app works.
- `demo/reference_property_test.dart` is a property over the interface, kept
  out of `test/` so that `flutter test` does not run it. It is the reference
  for the demonstration: known to find the bug and to shrink it.
