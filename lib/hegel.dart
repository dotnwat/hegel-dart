/// Property-based testing for Dart, powered by the Hegel engine.
///
/// A property is a claim about every input, checked against inputs the engine
/// generates. When one fails, the engine shrinks the failing case to the
/// smallest one that still fails and remembers it, so the property keeps
/// failing until the bug is fixed.
library;

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
export 'src/property/test_case.dart' show TestCase;
