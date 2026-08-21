/// Locating, verifying, and staging the prebuilt libhegel engine.
///
/// Pure Dart: no `dart:ffi` and no build-hook protocol, so `hook/build.dart`
/// can use it without pulling in the bindings and `tool/update_libhegel.dart`
/// can reuse the same asset table and verification when it moves the pin.
///
/// See `docs/libhegel-bindings-plan.md` section 5.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart' show Architecture, OS;
import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

/// Where hegel-rust publishes engine binaries.
///
/// These are public release-download URLs: no GitHub API call, no token. A
/// build hook must never need a secret, because hook inputs are materialized
/// on disk.
const String releaseDownloadBase =
    'https://github.com/hegeldev/hegel-rust/releases/download';

/// One `(os, architecture)` pair that hegel-rust publishes an engine for.
@immutable
final class EngineTarget {
  const EngineTarget._(this.os, this.architecture, this.assetName);

  /// The operating system this engine runs on.
  final OS os;

  /// The instruction set this engine is built for.
  final Architecture architecture;

  /// The release asset's file name, such as `libhegel-linux-amd64.so`.
  ///
  /// Upstream names assets Go-style — `darwin` rather than `macos`, `amd64`
  /// rather than `x64` — which is why this is a table rather than something
  /// formatted from [os] and [architecture].
  final String assetName;

  @override
  String toString() => '${os.name}/${architecture.name}';
}

/// Every target hegel-rust ships a prebuilt engine for.
///
/// Intel macOS is deliberately absent: upstream does not publish it. Mobile
/// targets are absent for the same reason, which is why this package is
/// desktop-only until upstream builds change.
const List<EngineTarget> supportedEngineTargets = <EngineTarget>[
  EngineTarget._(OS.linux, Architecture.x64, 'libhegel-linux-amd64.so'),
  EngineTarget._(OS.linux, Architecture.arm64, 'libhegel-linux-arm64.so'),
  EngineTarget._(OS.macOS, Architecture.arm64, 'libhegel-darwin-arm64.dylib'),
  EngineTarget._(OS.windows, Architecture.x64, 'libhegel-windows-amd64.dll'),
  EngineTarget._(OS.windows, Architecture.arm64, 'libhegel-windows-arm64.dll'),
];

/// The published target for [os] and [architecture], or null when there is
/// none.
EngineTarget? engineTargetFor(OS os, Architecture architecture) {
  for (final target in supportedEngineTargets) {
    if (target.os == os && target.architecture == architecture) return target;
  }
  return null;
}

/// The exact engine release this package is built against.
///
/// `tool/update_libhegel.dart` generates one of these into `version.g.dart`;
/// nothing else may construct a pin from data fetched at build time, since the
/// whole point is that the digests were reviewed in a commit.
@immutable
final class EnginePin {
  /// Creates a pin for [version] with a digest per asset.
  const EnginePin({required this.version, required this.sha256ByAsset});

  /// The hegel-rust release version without its `v` prefix, e.g. `0.33.0`.
  final String version;

  /// Lowercase hex SHA-256 of each asset, keyed by [EngineTarget.assetName].
  final Map<String, String> sha256ByAsset;

  /// The public download URL for [target] at this pin.
  Uri downloadUrl(EngineTarget target) =>
      Uri.parse('$releaseDownloadBase/v$version/${target.assetName}');

  /// The pinned digest for [target].
  ///
  /// Throws [EngineAcquisitionException] when the pin has no entry, which
  /// means the generated pin and [supportedEngineTargets] have drifted apart.
  String digestFor(EngineTarget target) {
    final digest = sha256ByAsset[target.assetName];
    if (digest == null) {
      throw EngineAcquisitionException(
        'the pinned engine $version has no SHA-256 recorded for '
        '${target.assetName}. Re-run tool/update_libhegel.dart to regenerate '
        'the pin.',
      );
    }
    return digest.toLowerCase();
  }
}

/// Raised when the engine cannot be located, verified, or staged.
final class EngineAcquisitionException implements Exception {
  /// Creates an exception describing why acquisition failed.
  EngineAcquisitionException(this.message);

  /// What went wrong, phrased for whoever is running the build.
  final String message;

  @override
  String toString() => 'EngineAcquisitionException: $message';
}

/// Downloads [url] and returns its bytes.
///
/// Injected so tests never reach the network.
typedef EngineFetch = Future<Uint8List> Function(Uri url);

/// The default [EngineFetch]: an HTTPS GET that follows redirects.
///
/// Release-download URLs redirect to a storage host, which [HttpClient]
/// follows on its own.
Future<Uint8List> httpEngineFetch(Uri url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw EngineAcquisitionException(
        'downloading $url failed with HTTP ${response.statusCode}.',
      );
    }
    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    return Uint8List.fromList(<int>[for (final chunk in chunks) ...chunk]);
  } finally {
    client.close(force: true);
  }
}

/// Where an acquired engine came from.
enum EngineSource {
  /// A locally built engine named by the `libhegel_path` user-define.
  override,

  /// Already present in the hook's own output directory from a previous run.
  staged,

  /// The cross-project cache, re-verified against the pin before use.
  cache,

  /// Freshly downloaded from the pinned release.
  download,
}

/// The outcome of [acquireEngine].
@immutable
final class AcquiredEngine {
  /// Creates a result naming the staged [file] and where it came from.
  const AcquiredEngine({
    required this.file,
    required this.source,
    this.dependencies = const <File>[],
  });

  /// The engine to publish as a code asset.
  ///
  /// Always inside the staging directory: emitting a path in a user-level
  /// cache would let cache cleanup break a later build without re-running the
  /// hook.
  final File file;

  /// Where [file]'s contents came from.
  final EngineSource source;

  /// Files the caller should register as additional hook inputs.
  ///
  /// Only a local override lands here — it is not covered by the pin, so the
  /// hook has to re-run whenever it changes.
  final List<File> dependencies;
}

/// Lowercase hex SHA-256 of [bytes].
String sha256HexOf(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// Whether [file] exists and hashes to [expectedHex].
@visibleForTesting
bool fileMatchesDigest(File file, String expectedHex) {
  if (!file.existsSync()) return false;
  return sha256HexOf(file.readAsBytesSync()) == expectedHex.toLowerCase();
}

/// The directory holding cached engines for [pin] under a cache [root].
///
/// The version is part of the path, so moving the pin misses the cache
/// instead of needing invalidation.
Directory engineCacheDirectory(Directory root, EnginePin pin) =>
    Directory.fromUri(root.uri.resolve('hegel-dart/natives/v${pin.version}/'));

/// A cache root derived from [environment], or null when none is discoverable.
///
/// Build hooks run in a filtered environment — on Linux the hook process sees
/// only `HOME` and `PATH` — so this deliberately depends on nothing else, and
/// returning null simply means the cross-project cache is skipped and the
/// hook's own output directory does all the work.
Directory? defaultCacheRoot({
  required Map<String, String> environment,
  required bool isWindows,
}) {
  String? nonEmpty(String name) {
    final value = environment[name];
    return (value == null || value.isEmpty) ? null : value;
  }

  final explicit = nonEmpty('XDG_CACHE_HOME');
  if (explicit != null) return Directory(explicit);
  if (isWindows) {
    final localAppData = nonEmpty('LOCALAPPDATA');
    if (localAppData != null) return Directory(localAppData);
    final profile = nonEmpty('USERPROFILE');
    if (profile != null) {
      return Directory.fromUri(Directory(profile).uri.resolve('.cache'));
    }
    return null;
  }
  final home = nonEmpty('HOME');
  if (home == null) return null;
  return Directory.fromUri(Directory(home).uri.resolve('.cache'));
}

/// Resolves, verifies, and stages the engine for [os] and [architecture].
///
/// Resolution stops at the first hit: [overrideFile], then an engine already
/// staged in [stagingDirectory], then [cacheRoot], then the pinned download.
/// Every candidate except an override is checked against [pin] before it is
/// used, including cache hits — an unverified cache would defeat the point of
/// pinning digests at all.
///
/// The returned file is always inside [stagingDirectory].
Future<AcquiredEngine> acquireEngine({
  required EnginePin pin,
  required OS os,
  required Architecture architecture,
  required Directory stagingDirectory,
  File? overrideFile,
  Directory? cacheRoot,
  EngineFetch fetch = httpEngineFetch,
}) async {
  final target = engineTargetFor(os, architecture);
  if (target == null) {
    throw EngineAcquisitionException(
      'hegel has no prebuilt libhegel engine for ${os.name}/'
      '${architecture.name}. Upstream publishes '
      '${supportedEngineTargets.join(', ')}. Build the engine yourself and '
      'name it with the hegel.libhegel_path user-define to use another '
      'target.',
    );
  }

  if (overrideFile != null) {
    if (!overrideFile.existsSync()) {
      throw EngineAcquisitionException(
        'the hegel.libhegel_path user-define names ${overrideFile.path}, '
        'which does not exist. Correct the path or remove the user-define to '
        'use the pinned engine.',
      );
    }
    // A local build has nothing to verify against, so it is restaged every
    // time rather than trusted to still match: the hook re-runs whenever the
    // file changes, and a stale copy would outlive the build it came from.
    final staged = _publish(
      overrideFile.readAsBytesSync(),
      stagingDirectory,
      target.assetName,
      replaceExisting: true,
    );
    return AcquiredEngine(
      file: staged,
      source: EngineSource.override,
      dependencies: <File>[overrideFile],
    );
  }

  final digest = pin.digestFor(target);

  final stagedFile = _child(stagingDirectory, target.assetName);
  if (fileMatchesDigest(stagedFile, digest)) {
    return AcquiredEngine(file: stagedFile, source: EngineSource.staged);
  }

  final cacheFile = cacheRoot == null
      ? null
      : _child(engineCacheDirectory(cacheRoot, pin), target.assetName);
  if (cacheFile != null) {
    if (fileMatchesDigest(cacheFile, digest)) {
      final staged = _publish(
        cacheFile.readAsBytesSync(),
        stagingDirectory,
        target.assetName,
        replaceExisting: true,
      );
      return AcquiredEngine(file: staged, source: EngineSource.cache);
    }
    if (cacheFile.existsSync()) {
      // Corrupt or truncated. Drop it so the download below can replace it.
      _deleteQuietly(cacheFile);
    }
  }

  final url = pin.downloadUrl(target);
  final bytes = await fetch(url);
  final actual = sha256HexOf(bytes);
  if (actual != digest) {
    throw EngineAcquisitionException(
      'the engine downloaded from $url does not match its pinned SHA-256 '
      '(expected $digest, got $actual). Nothing was installed.',
    );
  }

  if (cacheFile != null) {
    // Best effort. A read-only or unwritable cache is an inconvenience, not a
    // build failure: the staged copy below is what the build actually uses.
    try {
      _publish(
        bytes,
        cacheFile.parent,
        target.assetName,
        replaceExisting: false,
      );
    } on FileSystemException {
      // Leave the cache alone and carry on.
    }
  }

  final staged = _publish(
    bytes,
    stagingDirectory,
    target.assetName,
    replaceExisting: true,
  );
  return AcquiredEngine(file: staged, source: EngineSource.download);
}

/// Writes [bytes] into [directory] as [name] without ever exposing a partial
/// file.
///
/// The bytes go to a uniquely named temporary file in the destination's own
/// directory — so the rename stays on one filesystem — which is then renamed
/// into place. When another process wins the race, [replaceExisting] decides
/// the outcome: false keeps the winner's file, which is what the cache wants
/// since any correct copy is as good as this one, and true overwrites, which
/// is what restaging needs.
@visibleForTesting
File publishFile(
  Uint8List bytes,
  Directory directory,
  String name, {
  required bool replaceExisting,
}) => _publish(bytes, directory, name, replaceExisting: replaceExisting);

int _temporarySequence = 0;

File _child(Directory directory, String name) =>
    File.fromUri(directory.uri.resolve(name));

File _publish(
  Uint8List bytes,
  Directory directory,
  String name, {
  required bool replaceExisting,
}) {
  directory.createSync(recursive: true);
  final destination = _child(directory, name);
  if (!replaceExisting && destination.existsSync()) return destination;

  final temporary = _child(directory, '$name.tmp-$pid-${_temporarySequence++}');
  try {
    temporary.writeAsBytesSync(bytes, flush: true);
    try {
      temporary.renameSync(destination.path);
    } on FileSystemException {
      // Windows refuses to rename onto an existing file, and a concurrent
      // installer can create one between the check above and this rename.
      if (!destination.existsSync()) rethrow;
      if (!replaceExisting) return destination;
      destination.deleteSync();
      temporary.renameSync(destination.path);
    }
  } finally {
    _deleteQuietly(temporary);
  }
  return destination;
}

void _deleteQuietly(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // Nothing useful to do; the caller's own error is the interesting one.
  }
}
