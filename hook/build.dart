/// Provides the pinned libhegel engine to Dart as a code asset.
///
/// `@Native` declarations in this package bind to the asset id
/// `package:hegel/libhegel`, and this hook is what fulfills it: it resolves an
/// engine — a local override, one already staged, the cross-project cache, or
/// the pinned download — verifies it against the checked-in digests, and
/// stages a copy for the SDK to bundle.
///
/// Configuration comes from pub user-defines, never from the environment. A
/// build hook runs in a filtered environment (on Linux the process sees only
/// `HOME` and `PATH`), so an environment variable cannot reach it, and would
/// not be a declared hook input even if it could — changing one would reuse a
/// stale cached hook result. Consumers configure it in their own
/// `pubspec.yaml`:
///
/// ```yaml
/// hooks:
///   user_defines:
///     hegel:
///       libhegel_path: ../hegel-rust/target/release/libhegel_c.so
///       cache_dir: /shared/engine-cache
/// ```
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hegel/src/libhegel/version.g.dart';
import 'package:hegel/src/tooling/acquire.dart';
import 'package:hooks/hooks.dart';

/// The user-define naming a locally built engine to use instead of the pin.
const String libhegelPathDefine = 'libhegel_path';

/// The user-define naming a cross-project cache root for downloaded engines.
const String cacheDirDefine = 'cache_dir';

/// The asset name. With the package name this forms the asset id
/// `package:hegel/libhegel`.
const String libhegelAssetName = 'libhegel';

Future<void> main(List<String> arguments) async {
  await build(arguments, buildLibhegelAsset);
}

/// Resolves, verifies, stages, and publishes the engine for one build.
///
/// [pin], [fetch], and [environment] are injectable so hook tests can drive
/// this exact body with synthetic bytes, without reaching the network or the
/// developer's own cache. Production always takes the defaults.
Future<void> buildLibhegelAsset(
  BuildInput input,
  BuildOutputBuilder output, {
  EnginePin pin = libhegelPin,
  EngineFetch fetch = httpEngineFetch,
  Map<String, String>? environment,
}) async {
  final overridePath = input.userDefines.path(libhegelPathDefine);
  final cacheDirPath = input.userDefines.path(cacheDirDefine);

  final acquired = await acquireEngine(
    pin: pin,
    os: input.config.code.targetOS,
    architecture: input.config.code.targetArchitecture,
    // Only ever the hook's own managed directory: emitting a path inside a
    // user-level cache would let cache cleanup break a later build without
    // this hook re-running.
    stagingDirectory: Directory.fromUri(input.outputDirectoryShared),
    overrideFile: overridePath == null ? null : File.fromUri(overridePath),
    cacheRoot: cacheDirPath != null
        ? Directory.fromUri(cacheDirPath)
        : defaultCacheRoot(
            environment: environment ?? Platform.environment,
            isWindows: Platform.isWindows,
          ),
    fetch: fetch,
  );

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: libhegelAssetName,
      linkMode: DynamicLoadingBundled(),
      file: acquired.file.uri,
    ),
  );

  // An override is not covered by the pin, so the hook has to re-run whenever
  // that file changes. Without this, rebuilding the engine locally would leave
  // the previous copy staged and silently in use.
  for (final dependency in acquired.dependencies) {
    output.dependencies.add(dependency.uri);
  }
}
