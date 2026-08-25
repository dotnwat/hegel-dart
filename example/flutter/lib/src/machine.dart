/// Stateful testing whose steps go through the interface.
library;

import 'package:hegel/hegel.dart';

import 'actions.dart';
import 'checks.dart';
import 'surface.dart';
import 'text.dart';

/// A state machine that drives an app through its interface.
///
/// The same bargain [StateMachine] makes, with the system under test on the
/// far side of a screen: rules tap and type, the model says what the screen
/// should be showing, and an invariant compares them. What the engine shrinks
/// is the sequence, so a counterexample is the shortest script of taps that
/// still drives the app and its model apart.
///
/// Subclasses hold the surface and whatever model they are comparing against:
///
/// ```dart
/// final class CartMachine extends UiMachine {
///   CartMachine(super.ui);
///
///   int expectedItems = 0;
///
///   @override
///   List<Rule> get rules => <Rule>[
///     Rule('add an item', (TestCase testCase) async {
///       await ui.tap(find.byKey(const Key('add')));
///       expectedItems++;
///     }),
///   ];
/// }
/// ```
///
/// [checks] are held between steps on top of whatever [invariants] the
/// subclass adds, and default to the one that says the frame rendered at all.
abstract base class UiMachine extends StateMachine {
  /// A machine driving [ui].
  UiMachine(this.ui);

  /// The interface this machine acts on.
  final UiSurface ui;

  /// Interface invariants held between steps.
  List<UiCheck> get checks => const <UiCheck>[noFlutterErrors];

  @override
  List<Invariant> get invariants => <Invariant>[
    for (final check in checks)
      Invariant(check.name, (TestCase testCase) => check.check(ui)),
  ];
}

/// A machine that does whatever the app currently offers, and knows nothing
/// about what any of it means.
///
/// The cheapest user-interface property there is: no model, no rules written
/// by hand, and an oracle that only says the app must not break. What it
/// finds is what a monkey test finds -- an unguarded index, a null after a
/// delete, a screen that cannot render what the last screen put in it -- and
/// what it adds over a monkey test is that the engine shrinks the walk. Forty
/// taps that crash become the three that had to happen.
///
/// Point it at an app and give it a policy:
///
/// ```dart
/// widgetProperty('the app survives being used', (testCase, tester) async {
///   final ui = await UiSurface.open(tester, const MyApp());
///   await runStateful(testCase, MonkeyMachine(ui));
/// });
/// ```
///
/// [checks] decides what "break" means. The default is that every frame
/// renders; adding [accessibilityChecks] turns the same walk into an audit of
/// every state the app can reach.
final class MonkeyMachine extends UiMachine {
  /// A monkey on [ui].
  MonkeyMachine(
    super.ui, {
    this.policy = const ActionPolicy(),
    List<UiCheck>? checks,
    Generator<String>? text,
  }) : _checks = checks ?? const <UiCheck>[noFlutterErrors],
       _text = text ?? hostileText();

  /// What this monkey is allowed to do.
  final ActionPolicy policy;

  final List<UiCheck> _checks;
  final Generator<String> _text;

  /// What was on offer when the tree was last looked at.
  ///
  /// Every rule's precondition asks what is available and then its body asks
  /// again, so a step that does not cache walks the semantics tree four
  /// times. The tree cannot change between those questions -- nothing has
  /// happened yet -- so the answer is kept until something does.
  List<UiAction>? _offering;

  @override
  List<UiCheck> get checks => _checks;

  @override
  List<Rule> get rules => <Rule>[
    Rule('tap', (TestCase testCase) async {
      final actions = _offered(UiActionKind.tap);
      // Drawn as a name rather than an index, so the report reads as a
      // script -- `step 2 target = Add` -- instead of as a list of numbers
      // that mean nothing without the screen in front of you.
      final chosen = testCase.draw(
        sampledFrom(actions.map((UiAction action) => action.id).toList()),
        name: 'target',
      );
      await _act(_named(actions, chosen));
    }, precondition: () => _offered(UiActionKind.tap).isNotEmpty),
    Rule('type', (TestCase testCase) async {
      final fields = _offered(UiActionKind.type);
      final chosen = testCase.draw(
        sampledFrom(fields.map((UiAction action) => action.id).toList()),
        name: 'field',
      );
      final value = testCase.draw(_text, name: 'text');
      await _act(_named(fields, chosen), text: value);
    }, precondition: () => _offered(UiActionKind.type).isNotEmpty),
  ];

  List<UiAction> _offered(UiActionKind kind) => (_offering ??= discoverActions(
    ui,
    policy: policy,
  )).where((UiAction action) => action.kind == kind).toList();

  Future<void> _act(UiAction action, {String text = ''}) async {
    await perform(ui, action, text: text);
    _offering = null;
  }

  UiAction _named(List<UiAction> actions, String id) =>
      actions.firstWhere((UiAction action) => action.id == id);
}
