/// Property-based testing for Dart, powered by the Hegel engine.
///
/// A property is a claim about every input, checked against inputs the engine
/// generates. When one fails, the engine shrinks the failing case to the
/// smallest one that still fails and remembers it, so the property keeps
/// failing until the bug is fixed.
library;

// This signal and no other. `tc.assume` throws it in plain Dart, so the
// engine never sees it and only this layer's report says the case was
// rejected: a body that swallows one turns fifty rejected cases into fifty
// valid ones, and a run that should have complained about filtering into a
// run that held. So it has to be nameable. StopTest is the engine's own --
// it accounts for the exhausted budget itself and overrides whatever status
// is reported for such a case -- so swallowing one changes nothing and
// naming it would buy nothing. Both were checked before deciding.
export 'src/libhegel/errors.dart' show AssumptionFailed;
export 'src/libhegel/settings.dart'
    show
        Backend,
        Database,
        HealthCheck,
        Mode,
        Phase,
        Settings,
        Verbosity,
        everyHealthCheck,
        everyPhase;
export 'src/property/generator.dart';
export 'src/property/property.dart' show property;
export 'src/property/runner.dart' show PropertyError, runProperty;
export 'src/property/stateful.dart'
    show Invariant, Rule, StateMachine, runStateful;
export 'src/property/test_case.dart' show TestCase;
