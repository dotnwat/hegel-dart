/// The libhegel bindings: the engine, wrapped.
///
/// This is the internal layer the property-testing API will be built on, not
/// the API itself. It mirrors the C ABI closely -- handles are disposed by
/// hand, draws are primitives rather than generators -- because its job is to
/// make the engine reachable and safe, not pleasant.
library;

export 'collection.dart';
export 'errors.dart';
export 'pool.dart';
export 'run.dart';
export 'run_result.dart';
export 'session.dart';
export 'settings.dart';
export 'span.dart';
export 'state_machine.dart' show HandleToken, StateMachine;
export 'string_generator.dart';
export 'test_case.dart';
export 'version.g.dart' show libhegelVersion;
