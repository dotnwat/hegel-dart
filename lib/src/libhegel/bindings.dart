// GENERATED FILE. DO NOT EDIT.
//
// Generated from bindings.g.dart by tool/generate_bindings_interface.dart.
// Regenerate with `just regen`.
//
// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars

/// The seam between the safe layer and the raw FFI bindings.
///
/// Everything above this calls libhegel through [Bindings], never through the
/// generated functions directly. That buys two things: tests can inject a fake
/// to reach result codes the real engine cannot be driven to produce, and
/// [NativeBindings.verifySymbols] resolves every symbol up front so an
/// ABI-skewed engine fails when a session opens rather than mid-test.
library;

import 'dart:ffi' as ffi;

import 'bindings.g.dart' as raw;

/// Every function libhegel exports, one-to-one with the C ABI.
///
/// Names are the C names so this surface diffs cleanly against the header when
/// the ABI moves. No parameter is defaulted or absorbed here; convenience
/// belongs in the safe layer, where it stays visible.
abstract interface class Bindings {
  /// Resolves every symbol, throwing if any is missing.
  ///
  /// Part of the interface rather than only the native implementation so a
  /// session opens the same way whichever bindings it was handed.
  void verifySymbols();

  ffi.Pointer<raw.hegel_context_t> hegel_context_new();
  int hegel_context_free(ffi.Pointer<raw.hegel_context_t> ctx);
  ffi.Pointer<ffi.Char> hegel_context_last_error(
    ffi.Pointer<raw.hegel_context_t> ctx,
  );
  int hegel_settings_new(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Pointer<raw.hegel_settings_t>> out_settings,
  );
  int hegel_settings_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
  );
  int hegel_settings_set_mode(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int mode,
  );
  int hegel_settings_set_backend(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int backend,
  );
  int hegel_settings_set_test_cases(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int n,
  );
  int hegel_settings_set_stateful_step_count(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int n,
  );
  int hegel_settings_set_verbosity(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int v,
  );
  int hegel_settings_set_seed(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int seed,
    bool has_seed,
  );
  int hegel_settings_set_derandomize(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    bool derandomize,
  );
  int hegel_settings_set_report_multiple_failures(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    bool yes,
  );
  int hegel_settings_set_database(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    ffi.Pointer<ffi.Char> database,
  );
  int hegel_settings_set_database_key(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    ffi.Pointer<ffi.Char> key,
  );
  int hegel_settings_set_phases(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int phases,
  );
  int hegel_settings_set_suppress_health_check(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int checks,
  );
  int hegel_run_start(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> settings,
    raw.hegel_output_callback_t callback,
    ffi.Pointer<ffi.Void> user_data,
    ffi.Pointer<ffi.Pointer<raw.hegel_run_t>> out_run,
  );
  int hegel_next_test_case(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_t> run,
    ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>> out_test_case,
  );
  int hegel_run_result(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_t> run,
    ffi.Pointer<ffi.Pointer<raw.hegel_run_result_t>> out_result,
  );
  int hegel_run_result_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
  );
  int hegel_run_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_t> run,
  );
  int hegel_test_case_from_blob(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    ffi.Pointer<ffi.Char> blob,
    raw.hegel_output_callback_t callback,
    ffi.Pointer<ffi.Void> user_data,
    ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>> out_test_case,
  );
  int hegel_test_case_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
  );
  int hegel_test_case_is_nondeterministic(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Bool> out_is_nondeterministic,
  );
  int hegel_test_case_clone(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>> out_test_case,
  );
  int hegel_start_span(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int label,
  );
  int hegel_stop_span(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    bool discard,
  );
  int hegel_new_collection(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int min_size,
    int max_size,
    ffi.Pointer<ffi.Pointer<raw.hegel_collection_t>> out_collection,
  );
  int hegel_collection_more(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_collection_t> collection,
    ffi.Pointer<ffi.Bool> out_more,
  );
  int hegel_collection_reject(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_collection_t> collection,
    ffi.Pointer<ffi.Char> why,
  );
  int hegel_collection_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_collection_t> collection,
  );
  int hegel_new_pool(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Pointer<raw.hegel_pool_t>> out_pool,
  );
  int hegel_pool_add(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_pool_t> pool,
    ffi.Pointer<ffi.Int64> out_variable_id,
  );
  int hegel_pool_generate(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_pool_t> pool,
    bool consume,
    ffi.Pointer<ffi.Int64> out_variable_id,
  );
  int hegel_pool_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_pool_t> pool,
  );
  int hegel_new_state_machine(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Pointer<ffi.Char>> rule_names,
    ffi.Pointer<ffi.Int64> rule_groups,
    int num_rules,
    ffi.Pointer<ffi.Pointer<ffi.Char>> invariant_names,
    int num_invariants,
    int min_concurrency,
    int max_concurrency,
    ffi.Pointer<ffi.Pointer<raw.hegel_state_machine_t>> out_state_machine,
    ffi.Pointer<ffi.Int64> out_concurrency,
  );
  int hegel_state_machine_next_group(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_state_machine_t> state_machine,
    ffi.Pointer<ffi.Int64> out_group_id,
  );
  int hegel_state_machine_next_rule(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_state_machine_t> state_machine,
    int worker_index,
    ffi.Pointer<ffi.Int64> out_rule_index,
  );
  int hegel_state_machine_rule_rejected(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_state_machine_t> state_machine,
    int worker_index,
  );
  int hegel_state_machine_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_state_machine_t> state_machine,
  );
  int hegel_generate_boolean(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    double p,
    bool forced,
    bool has_forced,
    ffi.Pointer<ffi.Bool> out_value,
  );
  int hegel_generate_integer(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int min_value,
    int max_value,
    ffi.Pointer<ffi.Int64> out_value,
  );
  int hegel_generate_integer_big(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Uint8> min_value,
    int min_value_len,
    ffi.Pointer<ffi.Uint8> max_value,
    int max_value_len,
    ffi.Pointer<ffi.Uint8> out_value,
    int out_value_cap,
    ffi.Pointer<ffi.Size> out_value_len,
  );
  int hegel_generate_float(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int width,
    double min_value,
    double max_value,
    bool allow_nan,
    bool allow_infinity,
    bool exclude_min,
    bool exclude_max,
    double smallest_nonzero_magnitude,
    ffi.Pointer<ffi.Double> out_value,
  );
  int hegel_generate_bytes(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int min_size,
    int max_size,
    ffi.Pointer<raw.hegel_generate_bytes_result_t> out_result,
  );
  int hegel_generate_bytes_result_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_generate_bytes_result_t> result,
  );
  int hegel_string_generator_text(
    ffi.Pointer<raw.hegel_context_t> ctx,
    int min_size,
    int max_size,
    ffi.Pointer<ffi.Char> codec,
    int min_codepoint,
    int max_codepoint,
    ffi.Pointer<ffi.Pointer<ffi.Char>> categories,
    int categories_len,
    ffi.Pointer<ffi.Pointer<ffi.Char>> exclude_categories,
    int exclude_categories_len,
    ffi.Pointer<ffi.Uint8> include_characters,
    int include_characters_len,
    ffi.Pointer<ffi.Uint8> exclude_characters,
    int exclude_characters_len,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  );
  int hegel_string_generator_regex(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Char> pattern,
    bool fullmatch,
    ffi.Pointer<raw.hegel_string_generator_t> alphabet,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  );
  int hegel_string_generator_email(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  );
  int hegel_string_generator_url(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  );
  int hegel_string_generator_domain(
    ffi.Pointer<raw.hegel_context_t> ctx,
    int max_length,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  );
  int hegel_string_generator_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_string_generator_t> generator,
  );
  int hegel_generate_string(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_string_generator_t> generator,
    ffi.Pointer<raw.hegel_generate_string_result_t> out_result,
  );
  int hegel_generate_string_result_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_generate_string_result_t> result,
  );
  int hegel_generate_date(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    raw.hegel_date_t min_value,
    raw.hegel_date_t max_value,
    ffi.Pointer<raw.hegel_date_t> out_value,
  );
  int hegel_generate_time(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    raw.hegel_time_t min_value,
    raw.hegel_time_t max_value,
    ffi.Pointer<raw.hegel_time_t> out_value,
  );
  int hegel_generate_datetime(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    raw.hegel_datetime_t min_value,
    raw.hegel_datetime_t max_value,
    ffi.Pointer<raw.hegel_datetime_t> out_value,
  );
  int hegel_generate_uuid(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int version,
    bool has_version,
    ffi.Pointer<ffi.Uint8> out_bytes,
  );
  int hegel_generate_ipv4(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Uint8> out_bytes,
  );
  int hegel_generate_ipv6(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Uint8> out_bytes,
  );
  int hegel_target(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    double value,
    ffi.Pointer<ffi.Char> label,
  );
  int hegel_mark_complete(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int status,
    ffi.Pointer<ffi.Char> origin,
  );
  int hegel_run_result_status(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
    ffi.Pointer<ffi.UnsignedInt> out_status,
  );
  int hegel_run_result_error(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out_error,
  );
  int hegel_run_result_failure_count(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
    ffi.Pointer<ffi.Size> out_count,
  );
  int hegel_run_result_failure(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
    int index,
    ffi.Pointer<ffi.Pointer<raw.hegel_failure_t>> out_failure,
  );
  int hegel_failure_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_failure_t> f,
  );
  int hegel_failure_origin(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_failure_t> f,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out_origin,
  );
  int hegel_failure_reproduction_blob(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_failure_t> f,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out_blob,
  );
  int hegel_version(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out_version,
  );
}

/// [Bindings] backed by the real engine.
final class NativeBindings implements Bindings {
  /// Creates a binding onto the loaded engine.
  const NativeBindings();

  /// Resolves every symbol, throwing if any is missing.
  ///
  /// `@Native` resolution is lazy, so without this an engine missing a symbol
  /// would surface at the first call that needs it — somewhere deep in a test
  /// run — instead of at the moment the session opens.
  @override
  void verifySymbols() {
    ffi.Native.addressOf<
      ffi.NativeFunction<ffi.Pointer<raw.hegel_context_t> Function()>
    >(raw.hegel_context_new);
    ffi.Native.addressOf<
      ffi.NativeFunction<ffi.Int Function(ffi.Pointer<raw.hegel_context_t>)>
    >(raw.hegel_context_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Pointer<ffi.Char> Function(ffi.Pointer<raw.hegel_context_t>)
      >
    >(raw.hegel_context_last_error);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<ffi.Pointer<raw.hegel_settings_t>>,
        )
      >
    >(raw.hegel_settings_new);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
        )
      >
    >(raw.hegel_settings_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Uint32,
        )
      >
    >(raw.hegel_settings_set_mode);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Uint32,
        )
      >
    >(raw.hegel_settings_set_backend);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Uint64,
        )
      >
    >(raw.hegel_settings_set_test_cases);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Int64,
        )
      >
    >(raw.hegel_settings_set_stateful_step_count);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Uint32,
        )
      >
    >(raw.hegel_settings_set_verbosity);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Uint64,
          ffi.Bool,
        )
      >
    >(raw.hegel_settings_set_seed);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Bool,
        )
      >
    >(raw.hegel_settings_set_derandomize);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Bool,
        )
      >
    >(raw.hegel_settings_set_report_multiple_failures);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Pointer<ffi.Char>,
        )
      >
    >(raw.hegel_settings_set_database);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Pointer<ffi.Char>,
        )
      >
    >(raw.hegel_settings_set_database_key);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Uint32,
        )
      >
    >(raw.hegel_settings_set_phases);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Uint32,
        )
      >
    >(raw.hegel_settings_set_suppress_health_check);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          raw.hegel_output_callback_t,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Pointer<raw.hegel_run_t>>,
        )
      >
    >(raw.hegel_run_start);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_run_t>,
          ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>>,
        )
      >
    >(raw.hegel_next_test_case);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_run_t>,
          ffi.Pointer<ffi.Pointer<raw.hegel_run_result_t>>,
        )
      >
    >(raw.hegel_run_result);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_run_result_t>,
        )
      >
    >(raw.hegel_run_result_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_run_t>,
        )
      >
    >(raw.hegel_run_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_settings_t>,
          ffi.Pointer<ffi.Char>,
          raw.hegel_output_callback_t,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>>,
        )
      >
    >(raw.hegel_test_case_from_blob);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
        )
      >
    >(raw.hegel_test_case_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<ffi.Bool>,
        )
      >
    >(raw.hegel_test_case_is_nondeterministic);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>>,
        )
      >
    >(raw.hegel_test_case_clone);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Uint64,
        )
      >
    >(raw.hegel_start_span);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Bool,
        )
      >
    >(raw.hegel_stop_span);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Uint64,
          ffi.Uint64,
          ffi.Pointer<ffi.Pointer<raw.hegel_collection_t>>,
        )
      >
    >(raw.hegel_new_collection);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<raw.hegel_collection_t>,
          ffi.Pointer<ffi.Bool>,
        )
      >
    >(raw.hegel_collection_more);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<raw.hegel_collection_t>,
          ffi.Pointer<ffi.Char>,
        )
      >
    >(raw.hegel_collection_reject);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_collection_t>,
        )
      >
    >(raw.hegel_collection_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<ffi.Pointer<raw.hegel_pool_t>>,
        )
      >
    >(raw.hegel_new_pool);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<raw.hegel_pool_t>,
          ffi.Pointer<ffi.Int64>,
        )
      >
    >(raw.hegel_pool_add);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<raw.hegel_pool_t>,
          ffi.Bool,
          ffi.Pointer<ffi.Int64>,
        )
      >
    >(raw.hegel_pool_generate);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_pool_t>,
        )
      >
    >(raw.hegel_pool_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
          ffi.Pointer<ffi.Int64>,
          ffi.Size,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
          ffi.Size,
          ffi.Int64,
          ffi.Int64,
          ffi.Pointer<ffi.Pointer<raw.hegel_state_machine_t>>,
          ffi.Pointer<ffi.Int64>,
        )
      >
    >(raw.hegel_new_state_machine);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<raw.hegel_state_machine_t>,
          ffi.Pointer<ffi.Int64>,
        )
      >
    >(raw.hegel_state_machine_next_group);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<raw.hegel_state_machine_t>,
          ffi.Int64,
          ffi.Pointer<ffi.Int64>,
        )
      >
    >(raw.hegel_state_machine_next_rule);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<raw.hegel_state_machine_t>,
          ffi.Int64,
        )
      >
    >(raw.hegel_state_machine_rule_rejected);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_state_machine_t>,
        )
      >
    >(raw.hegel_state_machine_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Double,
          ffi.Bool,
          ffi.Bool,
          ffi.Pointer<ffi.Bool>,
        )
      >
    >(raw.hegel_generate_boolean);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Int64,
          ffi.Int64,
          ffi.Pointer<ffi.Int64>,
        )
      >
    >(raw.hegel_generate_integer);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<ffi.Uint8>,
          ffi.Size,
          ffi.Pointer<ffi.Uint8>,
          ffi.Size,
          ffi.Pointer<ffi.Uint8>,
          ffi.Size,
          ffi.Pointer<ffi.Size>,
        )
      >
    >(raw.hegel_generate_integer_big);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Uint32,
          ffi.Double,
          ffi.Double,
          ffi.Bool,
          ffi.Bool,
          ffi.Bool,
          ffi.Bool,
          ffi.Double,
          ffi.Pointer<ffi.Double>,
        )
      >
    >(raw.hegel_generate_float);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Uint64,
          ffi.Uint64,
          ffi.Pointer<raw.hegel_generate_bytes_result_t>,
        )
      >
    >(raw.hegel_generate_bytes);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_generate_bytes_result_t>,
        )
      >
    >(raw.hegel_generate_bytes_result_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Uint64,
          ffi.Uint64,
          ffi.Pointer<ffi.Char>,
          ffi.Uint32,
          ffi.Uint32,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
          ffi.Size,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
          ffi.Size,
          ffi.Pointer<ffi.Uint8>,
          ffi.Size,
          ffi.Pointer<ffi.Uint8>,
          ffi.Size,
          ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>>,
        )
      >
    >(raw.hegel_string_generator_text);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<ffi.Char>,
          ffi.Bool,
          ffi.Pointer<raw.hegel_string_generator_t>,
          ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>>,
        )
      >
    >(raw.hegel_string_generator_regex);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>>,
        )
      >
    >(raw.hegel_string_generator_email);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>>,
        )
      >
    >(raw.hegel_string_generator_url);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Uint64,
          ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>>,
        )
      >
    >(raw.hegel_string_generator_domain);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_string_generator_t>,
        )
      >
    >(raw.hegel_string_generator_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<raw.hegel_string_generator_t>,
          ffi.Pointer<raw.hegel_generate_string_result_t>,
        )
      >
    >(raw.hegel_generate_string);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_generate_string_result_t>,
        )
      >
    >(raw.hegel_generate_string_result_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          raw.hegel_date_t,
          raw.hegel_date_t,
          ffi.Pointer<raw.hegel_date_t>,
        )
      >
    >(raw.hegel_generate_date);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          raw.hegel_time_t,
          raw.hegel_time_t,
          ffi.Pointer<raw.hegel_time_t>,
        )
      >
    >(raw.hegel_generate_time);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          raw.hegel_datetime_t,
          raw.hegel_datetime_t,
          ffi.Pointer<raw.hegel_datetime_t>,
        )
      >
    >(raw.hegel_generate_datetime);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Uint8,
          ffi.Bool,
          ffi.Pointer<ffi.Uint8>,
        )
      >
    >(raw.hegel_generate_uuid);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<ffi.Uint8>,
        )
      >
    >(raw.hegel_generate_ipv4);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Pointer<ffi.Uint8>,
        )
      >
    >(raw.hegel_generate_ipv6);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Double,
          ffi.Pointer<ffi.Char>,
        )
      >
    >(raw.hegel_target);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_test_case_t>,
          ffi.Uint32,
          ffi.Pointer<ffi.Char>,
        )
      >
    >(raw.hegel_mark_complete);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_run_result_t>,
          ffi.Pointer<ffi.UnsignedInt>,
        )
      >
    >(raw.hegel_run_result_status);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_run_result_t>,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
        )
      >
    >(raw.hegel_run_result_error);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_run_result_t>,
          ffi.Pointer<ffi.Size>,
        )
      >
    >(raw.hegel_run_result_failure_count);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_run_result_t>,
          ffi.Size,
          ffi.Pointer<ffi.Pointer<raw.hegel_failure_t>>,
        )
      >
    >(raw.hegel_run_result_failure);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_failure_t>,
        )
      >
    >(raw.hegel_failure_free);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_failure_t>,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
        )
      >
    >(raw.hegel_failure_origin);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<raw.hegel_failure_t>,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
        )
      >
    >(raw.hegel_failure_reproduction_blob);
    ffi.Native.addressOf<
      ffi.NativeFunction<
        ffi.Int Function(
          ffi.Pointer<raw.hegel_context_t>,
          ffi.Pointer<ffi.Pointer<ffi.Char>>,
        )
      >
    >(raw.hegel_version);
  }

  @override
  ffi.Pointer<raw.hegel_context_t> hegel_context_new() =>
      raw.hegel_context_new();

  @override
  int hegel_context_free(ffi.Pointer<raw.hegel_context_t> ctx) =>
      raw.hegel_context_free(ctx);

  @override
  ffi.Pointer<ffi.Char> hegel_context_last_error(
    ffi.Pointer<raw.hegel_context_t> ctx,
  ) => raw.hegel_context_last_error(ctx);

  @override
  int hegel_settings_new(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Pointer<raw.hegel_settings_t>> out_settings,
  ) => raw.hegel_settings_new(ctx, out_settings);

  @override
  int hegel_settings_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
  ) => raw.hegel_settings_free(ctx, s);

  @override
  int hegel_settings_set_mode(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int mode,
  ) => raw.hegel_settings_set_mode(ctx, s, mode);

  @override
  int hegel_settings_set_backend(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int backend,
  ) => raw.hegel_settings_set_backend(ctx, s, backend);

  @override
  int hegel_settings_set_test_cases(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int n,
  ) => raw.hegel_settings_set_test_cases(ctx, s, n);

  @override
  int hegel_settings_set_stateful_step_count(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int n,
  ) => raw.hegel_settings_set_stateful_step_count(ctx, s, n);

  @override
  int hegel_settings_set_verbosity(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int v,
  ) => raw.hegel_settings_set_verbosity(ctx, s, v);

  @override
  int hegel_settings_set_seed(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int seed,
    bool has_seed,
  ) => raw.hegel_settings_set_seed(ctx, s, seed, has_seed);

  @override
  int hegel_settings_set_derandomize(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    bool derandomize,
  ) => raw.hegel_settings_set_derandomize(ctx, s, derandomize);

  @override
  int hegel_settings_set_report_multiple_failures(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    bool yes,
  ) => raw.hegel_settings_set_report_multiple_failures(ctx, s, yes);

  @override
  int hegel_settings_set_database(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    ffi.Pointer<ffi.Char> database,
  ) => raw.hegel_settings_set_database(ctx, s, database);

  @override
  int hegel_settings_set_database_key(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    ffi.Pointer<ffi.Char> key,
  ) => raw.hegel_settings_set_database_key(ctx, s, key);

  @override
  int hegel_settings_set_phases(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int phases,
  ) => raw.hegel_settings_set_phases(ctx, s, phases);

  @override
  int hegel_settings_set_suppress_health_check(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    int checks,
  ) => raw.hegel_settings_set_suppress_health_check(ctx, s, checks);

  @override
  int hegel_run_start(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> settings,
    raw.hegel_output_callback_t callback,
    ffi.Pointer<ffi.Void> user_data,
    ffi.Pointer<ffi.Pointer<raw.hegel_run_t>> out_run,
  ) => raw.hegel_run_start(ctx, settings, callback, user_data, out_run);

  @override
  int hegel_next_test_case(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_t> run,
    ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>> out_test_case,
  ) => raw.hegel_next_test_case(ctx, run, out_test_case);

  @override
  int hegel_run_result(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_t> run,
    ffi.Pointer<ffi.Pointer<raw.hegel_run_result_t>> out_result,
  ) => raw.hegel_run_result(ctx, run, out_result);

  @override
  int hegel_run_result_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
  ) => raw.hegel_run_result_free(ctx, r);

  @override
  int hegel_run_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_t> run,
  ) => raw.hegel_run_free(ctx, run);

  @override
  int hegel_test_case_from_blob(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_settings_t> s,
    ffi.Pointer<ffi.Char> blob,
    raw.hegel_output_callback_t callback,
    ffi.Pointer<ffi.Void> user_data,
    ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>> out_test_case,
  ) => raw.hegel_test_case_from_blob(
    ctx,
    s,
    blob,
    callback,
    user_data,
    out_test_case,
  );

  @override
  int hegel_test_case_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
  ) => raw.hegel_test_case_free(ctx, tc);

  @override
  int hegel_test_case_is_nondeterministic(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Bool> out_is_nondeterministic,
  ) =>
      raw.hegel_test_case_is_nondeterministic(ctx, tc, out_is_nondeterministic);

  @override
  int hegel_test_case_clone(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Pointer<raw.hegel_test_case_t>> out_test_case,
  ) => raw.hegel_test_case_clone(ctx, tc, out_test_case);

  @override
  int hegel_start_span(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int label,
  ) => raw.hegel_start_span(ctx, tc, label);

  @override
  int hegel_stop_span(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    bool discard,
  ) => raw.hegel_stop_span(ctx, tc, discard);

  @override
  int hegel_new_collection(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int min_size,
    int max_size,
    ffi.Pointer<ffi.Pointer<raw.hegel_collection_t>> out_collection,
  ) => raw.hegel_new_collection(ctx, tc, min_size, max_size, out_collection);

  @override
  int hegel_collection_more(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_collection_t> collection,
    ffi.Pointer<ffi.Bool> out_more,
  ) => raw.hegel_collection_more(ctx, tc, collection, out_more);

  @override
  int hegel_collection_reject(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_collection_t> collection,
    ffi.Pointer<ffi.Char> why,
  ) => raw.hegel_collection_reject(ctx, tc, collection, why);

  @override
  int hegel_collection_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_collection_t> collection,
  ) => raw.hegel_collection_free(ctx, collection);

  @override
  int hegel_new_pool(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Pointer<raw.hegel_pool_t>> out_pool,
  ) => raw.hegel_new_pool(ctx, tc, out_pool);

  @override
  int hegel_pool_add(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_pool_t> pool,
    ffi.Pointer<ffi.Int64> out_variable_id,
  ) => raw.hegel_pool_add(ctx, tc, pool, out_variable_id);

  @override
  int hegel_pool_generate(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_pool_t> pool,
    bool consume,
    ffi.Pointer<ffi.Int64> out_variable_id,
  ) => raw.hegel_pool_generate(ctx, tc, pool, consume, out_variable_id);

  @override
  int hegel_pool_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_pool_t> pool,
  ) => raw.hegel_pool_free(ctx, pool);

  @override
  int hegel_new_state_machine(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Pointer<ffi.Char>> rule_names,
    ffi.Pointer<ffi.Int64> rule_groups,
    int num_rules,
    ffi.Pointer<ffi.Pointer<ffi.Char>> invariant_names,
    int num_invariants,
    int min_concurrency,
    int max_concurrency,
    ffi.Pointer<ffi.Pointer<raw.hegel_state_machine_t>> out_state_machine,
    ffi.Pointer<ffi.Int64> out_concurrency,
  ) => raw.hegel_new_state_machine(
    ctx,
    tc,
    rule_names,
    rule_groups,
    num_rules,
    invariant_names,
    num_invariants,
    min_concurrency,
    max_concurrency,
    out_state_machine,
    out_concurrency,
  );

  @override
  int hegel_state_machine_next_group(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_state_machine_t> state_machine,
    ffi.Pointer<ffi.Int64> out_group_id,
  ) => raw.hegel_state_machine_next_group(ctx, tc, state_machine, out_group_id);

  @override
  int hegel_state_machine_next_rule(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_state_machine_t> state_machine,
    int worker_index,
    ffi.Pointer<ffi.Int64> out_rule_index,
  ) => raw.hegel_state_machine_next_rule(
    ctx,
    tc,
    state_machine,
    worker_index,
    out_rule_index,
  );

  @override
  int hegel_state_machine_rule_rejected(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_state_machine_t> state_machine,
    int worker_index,
  ) => raw.hegel_state_machine_rule_rejected(
    ctx,
    tc,
    state_machine,
    worker_index,
  );

  @override
  int hegel_state_machine_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_state_machine_t> state_machine,
  ) => raw.hegel_state_machine_free(ctx, state_machine);

  @override
  int hegel_generate_boolean(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    double p,
    bool forced,
    bool has_forced,
    ffi.Pointer<ffi.Bool> out_value,
  ) => raw.hegel_generate_boolean(ctx, tc, p, forced, has_forced, out_value);

  @override
  int hegel_generate_integer(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int min_value,
    int max_value,
    ffi.Pointer<ffi.Int64> out_value,
  ) => raw.hegel_generate_integer(ctx, tc, min_value, max_value, out_value);

  @override
  int hegel_generate_integer_big(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Uint8> min_value,
    int min_value_len,
    ffi.Pointer<ffi.Uint8> max_value,
    int max_value_len,
    ffi.Pointer<ffi.Uint8> out_value,
    int out_value_cap,
    ffi.Pointer<ffi.Size> out_value_len,
  ) => raw.hegel_generate_integer_big(
    ctx,
    tc,
    min_value,
    min_value_len,
    max_value,
    max_value_len,
    out_value,
    out_value_cap,
    out_value_len,
  );

  @override
  int hegel_generate_float(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int width,
    double min_value,
    double max_value,
    bool allow_nan,
    bool allow_infinity,
    bool exclude_min,
    bool exclude_max,
    double smallest_nonzero_magnitude,
    ffi.Pointer<ffi.Double> out_value,
  ) => raw.hegel_generate_float(
    ctx,
    tc,
    width,
    min_value,
    max_value,
    allow_nan,
    allow_infinity,
    exclude_min,
    exclude_max,
    smallest_nonzero_magnitude,
    out_value,
  );

  @override
  int hegel_generate_bytes(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int min_size,
    int max_size,
    ffi.Pointer<raw.hegel_generate_bytes_result_t> out_result,
  ) => raw.hegel_generate_bytes(ctx, tc, min_size, max_size, out_result);

  @override
  int hegel_generate_bytes_result_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_generate_bytes_result_t> result,
  ) => raw.hegel_generate_bytes_result_free(ctx, result);

  @override
  int hegel_string_generator_text(
    ffi.Pointer<raw.hegel_context_t> ctx,
    int min_size,
    int max_size,
    ffi.Pointer<ffi.Char> codec,
    int min_codepoint,
    int max_codepoint,
    ffi.Pointer<ffi.Pointer<ffi.Char>> categories,
    int categories_len,
    ffi.Pointer<ffi.Pointer<ffi.Char>> exclude_categories,
    int exclude_categories_len,
    ffi.Pointer<ffi.Uint8> include_characters,
    int include_characters_len,
    ffi.Pointer<ffi.Uint8> exclude_characters,
    int exclude_characters_len,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  ) => raw.hegel_string_generator_text(
    ctx,
    min_size,
    max_size,
    codec,
    min_codepoint,
    max_codepoint,
    categories,
    categories_len,
    exclude_categories,
    exclude_categories_len,
    include_characters,
    include_characters_len,
    exclude_characters,
    exclude_characters_len,
    out_generator,
  );

  @override
  int hegel_string_generator_regex(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Char> pattern,
    bool fullmatch,
    ffi.Pointer<raw.hegel_string_generator_t> alphabet,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  ) => raw.hegel_string_generator_regex(
    ctx,
    pattern,
    fullmatch,
    alphabet,
    out_generator,
  );

  @override
  int hegel_string_generator_email(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  ) => raw.hegel_string_generator_email(ctx, out_generator);

  @override
  int hegel_string_generator_url(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  ) => raw.hegel_string_generator_url(ctx, out_generator);

  @override
  int hegel_string_generator_domain(
    ffi.Pointer<raw.hegel_context_t> ctx,
    int max_length,
    ffi.Pointer<ffi.Pointer<raw.hegel_string_generator_t>> out_generator,
  ) => raw.hegel_string_generator_domain(ctx, max_length, out_generator);

  @override
  int hegel_string_generator_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_string_generator_t> generator,
  ) => raw.hegel_string_generator_free(ctx, generator);

  @override
  int hegel_generate_string(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<raw.hegel_string_generator_t> generator,
    ffi.Pointer<raw.hegel_generate_string_result_t> out_result,
  ) => raw.hegel_generate_string(ctx, tc, generator, out_result);

  @override
  int hegel_generate_string_result_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_generate_string_result_t> result,
  ) => raw.hegel_generate_string_result_free(ctx, result);

  @override
  int hegel_generate_date(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    raw.hegel_date_t min_value,
    raw.hegel_date_t max_value,
    ffi.Pointer<raw.hegel_date_t> out_value,
  ) => raw.hegel_generate_date(ctx, tc, min_value, max_value, out_value);

  @override
  int hegel_generate_time(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    raw.hegel_time_t min_value,
    raw.hegel_time_t max_value,
    ffi.Pointer<raw.hegel_time_t> out_value,
  ) => raw.hegel_generate_time(ctx, tc, min_value, max_value, out_value);

  @override
  int hegel_generate_datetime(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    raw.hegel_datetime_t min_value,
    raw.hegel_datetime_t max_value,
    ffi.Pointer<raw.hegel_datetime_t> out_value,
  ) => raw.hegel_generate_datetime(ctx, tc, min_value, max_value, out_value);

  @override
  int hegel_generate_uuid(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int version,
    bool has_version,
    ffi.Pointer<ffi.Uint8> out_bytes,
  ) => raw.hegel_generate_uuid(ctx, tc, version, has_version, out_bytes);

  @override
  int hegel_generate_ipv4(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Uint8> out_bytes,
  ) => raw.hegel_generate_ipv4(ctx, tc, out_bytes);

  @override
  int hegel_generate_ipv6(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    ffi.Pointer<ffi.Uint8> out_bytes,
  ) => raw.hegel_generate_ipv6(ctx, tc, out_bytes);

  @override
  int hegel_target(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    double value,
    ffi.Pointer<ffi.Char> label,
  ) => raw.hegel_target(ctx, tc, value, label);

  @override
  int hegel_mark_complete(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_test_case_t> tc,
    int status,
    ffi.Pointer<ffi.Char> origin,
  ) => raw.hegel_mark_complete(ctx, tc, status, origin);

  @override
  int hegel_run_result_status(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
    ffi.Pointer<ffi.UnsignedInt> out_status,
  ) => raw.hegel_run_result_status(ctx, r, out_status);

  @override
  int hegel_run_result_error(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out_error,
  ) => raw.hegel_run_result_error(ctx, r, out_error);

  @override
  int hegel_run_result_failure_count(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
    ffi.Pointer<ffi.Size> out_count,
  ) => raw.hegel_run_result_failure_count(ctx, r, out_count);

  @override
  int hegel_run_result_failure(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_run_result_t> r,
    int index,
    ffi.Pointer<ffi.Pointer<raw.hegel_failure_t>> out_failure,
  ) => raw.hegel_run_result_failure(ctx, r, index, out_failure);

  @override
  int hegel_failure_free(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_failure_t> f,
  ) => raw.hegel_failure_free(ctx, f);

  @override
  int hegel_failure_origin(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_failure_t> f,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out_origin,
  ) => raw.hegel_failure_origin(ctx, f, out_origin);

  @override
  int hegel_failure_reproduction_blob(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<raw.hegel_failure_t> f,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out_blob,
  ) => raw.hegel_failure_reproduction_blob(ctx, f, out_blob);

  @override
  int hegel_version(
    ffi.Pointer<raw.hegel_context_t> ctx,
    ffi.Pointer<ffi.Pointer<ffi.Char>> out_version,
  ) => raw.hegel_version(ctx, out_version);
}
