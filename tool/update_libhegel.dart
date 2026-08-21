/// Moves the pinned libhegel engine to a published hegel-rust release.
///
///     dart run tool/update_libhegel.dart [--version 0.33.0]
///
/// Downloads every published platform asset, recomputes each digest and checks
/// it against the release's own `.sha256` sidecar, and then writes the
/// generated pin and vendors `hegel.h` and the upstream licence at the same
/// tag. A release that is missing any supported platform is refused outright:
/// a partial pin would leave some platform unable to build.
///
/// Unlike the build hook, this runs in a normal environment, so it may use the
/// GitHub API and `GITHUB_TOKEN` to look up release metadata. The engine
/// downloads themselves stay on public URLs that need no token.
library;

import 'dart:convert';
import 'dart:io';

import 'package:hegel/src/libhegel/version.g.dart';
import 'package:hegel/src/tooling/acquire.dart';

const String repository = 'hegeldev/hegel-rust';
const String _apiBase = 'https://api.github.com/repos/$repository';
const String _rawBase = 'https://raw.githubusercontent.com/$repository';

const String _versionFilePath = 'lib/src/libhegel/version.g.dart';
const String _headerPath = 'third_party/libhegel/hegel.h';
const String _licensePath = 'third_party/libhegel/LICENSE';

const String _upstreamHeaderPath = 'hegel-c/include/hegel.h';
const String _upstreamLicensePath = 'LICENSE';

/// The sidecar published next to [assetName].
String sidecarNameFor(String assetName) => '$assetName.sha256';

/// Every asset a release must publish before it can be pinned.
///
/// Both the binary and its sidecar: the sidecar is what the recomputed digest
/// is checked against, so a release without one cannot be verified.
List<String> requiredAssetNames() => <String>[
  for (final target in supportedEngineTargets) ...<String>[
    target.assetName,
    sidecarNameFor(target.assetName),
  ],
];

/// Required assets that [published] does not contain, in a stable order.
List<String> missingAssetNames(Iterable<String> published) {
  final have = published.toSet();
  return <String>[
    for (final name in requiredAssetNames())
      if (!have.contains(name)) name,
  ];
}

/// The digest a `sha256sum`-style sidecar records for [assetName].
///
/// Throws [FormatException] when the sidecar is malformed or names a
/// different file, either of which means the release is not what it claims.
String parseSha256Sidecar(String text, {required String assetName}) {
  final line = text.trim();
  final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(\S+)$').firstMatch(line);
  if (match == null) {
    throw FormatException('malformed sha256 sidecar for $assetName', line);
  }
  final named = match.group(2)!.split('/').last;
  if (named != assetName) {
    throw FormatException(
      'sidecar for $assetName names a different file: $named',
      line,
    );
  }
  return match.group(1)!.toLowerCase();
}

/// Renders the generated pin file for [pin].
///
/// Entries are sorted so that regenerating an unchanged pin produces no diff.
String renderVersionFile(EnginePin pin) {
  final names = pin.sha256ByAsset.keys.toList()..sort();
  final entries = <String>[
    for (final name in names)
      "    '$name':\n"
          "        '${pin.sha256ByAsset[name]!.toLowerCase()}',",
  ];
  return '''
// GENERATED FILE. DO NOT EDIT.
//
// Regenerate with:
//
//     dart run tool/update_libhegel.dart --version ${pin.version}
//
// The digests below are this package's supply-chain anchor: the build hook
// verifies every engine it downloads or reads from a cache against them, so
// they are reviewed in a commit rather than fetched at build time.

import '../tooling/acquire.dart';

/// The libhegel release this package is built against.
///
/// The runtime version check compares the loaded engine's `major.minor`
/// against this, since libhegel is pre-1.0 and its ABI can change between
/// minor releases.
const String libhegelVersion = '${pin.version}';

/// The pinned engine release, with a SHA-256 for each published platform.
const EnginePin libhegelPin = EnginePin(
  version: libhegelVersion,
  sha256ByAsset: <String, String>{
${entries.join('\n')}
  },
);
''';
}

/// Writes the pin, the vendored header, and the vendored licence for [tag].
///
/// Every artifact is fetched and decoded before the first one is written. A
/// failure partway through would otherwise leave the pin naming one release
/// while the header stayed vendored from another — precisely the drift these
/// three files are pinned together to prevent.
Future<void> writePinnedArtifacts({
  required Directory root,
  required String tag,
  required EnginePin pin,
  EngineFetch fetch = httpEngineFetch,
}) async {
  final pinSource = renderVersionFile(pin);
  final header = utf8.decode(await fetch(_rawUrl(tag, _upstreamHeaderPath)));
  final licence = utf8.decode(await fetch(_rawUrl(tag, _upstreamLicensePath)));

  _write(root, _versionFilePath, pinSource);
  _write(root, _headerPath, header);
  _write(root, _licensePath, licence);
}

Future<void> main(List<String> arguments) async {
  try {
    await _run(arguments);
  } on _UpdateFailure catch (failure) {
    stderr.writeln('update_libhegel: ${failure.message}');
    exitCode = 1;
  }
}

Future<void> _run(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/update_libhegel.dart [--version <x.y.z>]\n'
      '       dart run tool/update_libhegel.dart --artifacts-only\n'
      '\n'
      'Pins the libhegel engine to a hegel-rust release, defaulting to the\n'
      'latest one. Writes $_versionFilePath, $_headerPath, and\n'
      '$_licensePath.\n'
      '\n'
      '--artifacts-only re-fetches the vendored header and licence at the\n'
      'version already pinned, without downloading any engine. CI runs this\n'
      'and then diffs, to prove the vendored files still match their tag.',
    );
    return;
  }

  if (arguments.contains('--artifacts-only')) {
    await writePinnedArtifacts(
      root: _packageRoot(),
      tag: 'v$libhegelVersion',
      pin: libhegelPin,
    );
    stdout.writeln('refreshed the vendored artifacts for v$libhegelVersion');
    return;
  }

  final token = Platform.environment['GITHUB_TOKEN'];
  final requested = _argumentValue(arguments, '--version');
  final version = requested ?? await _latestReleaseVersion(token);
  final tag = 'v$version';
  stdout.writeln('pinning $repository $tag');

  final published = await _releaseAssetNames(tag, token);
  final missing = missingAssetNames(published);
  if (missing.isNotEmpty) {
    throw _UpdateFailure(
      'release $tag does not publish ${missing.join(', ')}. Refusing to pin a '
      'release that cannot build on every supported platform.',
    );
  }

  final digests = <String, String>{};
  for (final target in supportedEngineTargets) {
    final assetName = target.assetName;
    final sidecar = parseSha256Sidecar(
      utf8.decode(
        await httpEngineFetch(_downloadUrl(tag, sidecarNameFor(assetName))),
      ),
      assetName: assetName,
    );
    // Recompute rather than transcribe: a sidecar is only evidence about the
    // bytes if the bytes are actually hashed and compared.
    final actual = sha256HexOf(
      await httpEngineFetch(_downloadUrl(tag, assetName)),
    );
    if (actual != sidecar) {
      throw _UpdateFailure(
        '$assetName does not match its published sidecar (sidecar $sidecar, '
        'downloaded $actual). Refusing to pin it.',
      );
    }
    digests[assetName] = actual;
    stdout.writeln('  verified $assetName  $actual');
  }

  final root = _packageRoot();
  final pin = EnginePin(version: version, sha256ByAsset: digests);
  await writePinnedArtifacts(root: root, tag: tag, pin: pin);

  stdout.writeln(
    'wrote $_versionFilePath, $_headerPath, and $_licensePath.\n'
    'Next: re-run ffigen and the test suite before committing.',
  );
}

String? _argumentValue(List<String> arguments, String name) {
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == name) {
      if (i + 1 >= arguments.length) {
        throw _UpdateFailure('$name needs a value');
      }
      return arguments[i + 1];
    }
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1);
    }
  }
  return null;
}

Uri _downloadUrl(String tag, String assetName) =>
    Uri.parse('$releaseDownloadBase/$tag/$assetName');

Uri _rawUrl(String tag, String path) => Uri.parse('$_rawBase/$tag/$path');

Future<String> _latestReleaseVersion(String? token) async {
  final release = await _getJson(Uri.parse('$_apiBase/releases/latest'), token);
  final tag = release['tag_name'];
  if (tag is! String || !tag.startsWith('v')) {
    throw _UpdateFailure('unexpected latest release tag: $tag');
  }
  return tag.substring(1);
}

Future<List<String>> _releaseAssetNames(String tag, String? token) async {
  final release = await _getJson(
    Uri.parse('$_apiBase/releases/tags/$tag'),
    token,
  );
  final assets = release['assets'];
  if (assets is! List) {
    throw _UpdateFailure('release $tag has no asset list');
  }
  return <String>[
    for (final asset in assets)
      if (asset is Map && asset['name'] is String) asset['name'] as String,
  ];
}

Future<Map<String, Object?>> _getJson(Uri url, String? token) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'hegel-dart-update-tool');
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw _UpdateFailure(
        'GET $url failed with HTTP ${response.statusCode}. '
        '${response.statusCode == HttpStatus.forbidden ? 'Set GITHUB_TOKEN to '
                  'raise the API rate limit. ' : ''}$body',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw _UpdateFailure('GET $url did not return a JSON object');
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

Directory _packageRoot() {
  final fromScript = Directory.fromUri(Platform.script.resolve('../'));
  if (File.fromUri(fromScript.uri.resolve('pubspec.yaml')).existsSync()) {
    return fromScript;
  }
  final cwd = Directory.current;
  if (File.fromUri(cwd.uri.resolve('pubspec.yaml')).existsSync()) return cwd;
  throw _UpdateFailure('run this from the hegel package root');
}

void _write(Directory root, String relativePath, String contents) {
  final file = File.fromUri(root.uri.resolve(relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

final class _UpdateFailure implements Exception {
  _UpdateFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
