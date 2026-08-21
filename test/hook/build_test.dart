@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:hegel/src/tooling/acquire.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../../hook/build.dart';

/// Stand-in engine payloads. The hook never loads what it stages, so these
/// only have to hash consistently.
final Uint8List engineBytes = utf8.encode('fake libhegel engine, hook tests');
final Uint8List staleBytes = utf8.encode('an engine from an older pin');

const String linuxAsset = 'libhegel-linux-amd64.so';

/// A pin over the fake payload, so the whole resolution path can be driven
/// without the network and without the real 2.5 MB engine.
final EnginePin testPin = EnginePin(
  version: '9.9.9',
  sha256ByAsset: <String, String>{linuxAsset: sha256HexOf(engineBytes)},
);

Future<Uint8List> neverFetch(Uri url) async =>
    fail('the hook reached the network for $url');

/// What a hook run produced, read while the harness's output still exists.
typedef HookRun = ({
  List<CodeAsset> assets,
  List<Uri> dependencies,
  Uint8List bytes,
  String path,
});

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hegel_hook_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory subdirectory(String name) =>
      Directory.fromUri(root.uri.resolve('$name/'))
        ..createSync(recursive: true);

  /// Runs the real hook body through the hooks test harness.
  ///
  /// The harness deletes its output directory as soon as its check callback
  /// returns, so the staged file is read inside that callback and handed back.
  Future<HookRun> runHook({
    Map<String, Object?> defines = const <String, Object?>{},
    EngineFetch fetch = neverFetch,
    Map<String, String> environment = const <String, String>{},
    OS os = OS.linux,
    Architecture architecture = Architecture.x64,
  }) async {
    late HookRun captured;
    await testCodeBuildHook(
      targetOS: os,
      targetArchitecture: architecture,
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: defines,
          basePath: root.uri,
        ),
      ),
      mainMethod: (List<String> arguments) => build(
        arguments,
        (BuildInput input, BuildOutputBuilder output) => buildLibhegelAsset(
          input,
          output,
          pin: testPin,
          fetch: fetch,
          environment: environment,
        ),
      ),
      check: (BuildInput input, BuildOutput output) {
        final assets = output.assets.code;
        expect(assets, hasLength(1));
        final staged = File.fromUri(assets.single.file!);
        captured = (
          assets: assets,
          dependencies: output.dependencies,
          bytes: staged.readAsBytesSync(),
          path: staged.path,
        );
      },
    );
    return captured;
  }

  group('the published asset', () {
    test('has the id @Native declarations bind to', () async {
      final run = await runHook(
        fetch: (Uri url) async => engineBytes,
        defines: <String, Object?>{cacheDirDefine: subdirectory('cache').path},
      );
      expect(run.assets.single.id, 'package:hegel/libhegel');
      expect(run.assets.single.linkMode, isA<DynamicLoadingBundled>());
    });

    test('is the staged copy, never the cache entry', () async {
      final cache = subdirectory('cache');
      final run = await runHook(
        fetch: (Uri url) async => engineBytes,
        defines: <String, Object?>{cacheDirDefine: cache.path},
      );
      expect(run.bytes, engineBytes);
      // Emitting the cache path would let cache cleanup break a later build
      // without this hook re-running.
      expect(run.path, isNot(startsWith(cache.path)));
    });
  });

  group('resolution', () {
    test('downloads and fills the cache named by the user-define', () async {
      final cache = subdirectory('cache');
      await runHook(
        fetch: (Uri url) async => engineBytes,
        defines: <String, Object?>{cacheDirDefine: cache.path},
      );
      final cached = File.fromUri(
        engineCacheDirectory(cache, testPin).uri.resolve(linuxAsset),
      );
      expect(cached.readAsBytesSync(), engineBytes);
    });

    test('serves a verified cache hit without fetching', () async {
      final cache = subdirectory('cache');
      publishFile(
        engineBytes,
        engineCacheDirectory(cache, testPin),
        linuxAsset,
        replaceExisting: true,
      );
      final run = await runHook(
        defines: <String, Object?>{cacheDirDefine: cache.path},
      );
      expect(run.bytes, engineBytes);
    });

    test('replaces a corrupt cache entry rather than serving it', () async {
      final cache = subdirectory('cache');
      publishFile(
        staleBytes,
        engineCacheDirectory(cache, testPin),
        linuxAsset,
        replaceExisting: true,
      );
      final run = await runHook(
        fetch: (Uri url) async => engineBytes,
        defines: <String, Object?>{cacheDirDefine: cache.path},
      );
      expect(run.bytes, engineBytes);
      final cached = File.fromUri(
        engineCacheDirectory(cache, testPin).uri.resolve(linuxAsset),
      );
      expect(cached.readAsBytesSync(), engineBytes);
    });

    test(
      'derives a cache root from the environment when unconfigured',
      () async {
        final home = subdirectory('home');
        // The hook hands defaultCacheRoot the *host* platform, so inject
        // whichever variable that host's branch reads. Injecting only HOME
        // leaves a Windows runner with no cache root at all, and nothing to
        // find below.
        final environment = Platform.isWindows
            ? <String, String>{'LOCALAPPDATA': home.path}
            : <String, String>{'HOME': home.path};

        await runHook(
          fetch: (Uri url) async => engineBytes,
          environment: environment,
        );

        // Which directory that maps to is acquire_test's subject. All this
        // test asks is that the hook consulted the environment and cached
        // where that says.
        final cacheRoot = defaultCacheRoot(
          environment: environment,
          isWindows: Platform.isWindows,
        )!;
        final cached = File.fromUri(
          engineCacheDirectory(cacheRoot, testPin).uri.resolve(linuxAsset),
        );
        expect(cached.existsSync(), isTrue);
      },
    );

    test('works with no cache root discoverable at all', () async {
      final run = await runHook(fetch: (Uri url) async => engineBytes);
      expect(run.bytes, engineBytes);
    });
  });

  group('the libhegel_path override', () {
    test('is staged and registered so a rebuild re-runs the hook', () async {
      final local = File.fromUri(root.uri.resolve('local-build.so'))
        ..writeAsBytesSync(staleBytes);
      final run = await runHook(
        defines: <String, Object?>{libhegelPathDefine: local.path},
      );

      // Deliberately not checked against the pin: a local build is whatever
      // the developer just compiled.
      expect(run.bytes, staleBytes);
      expect(run.dependencies, contains(local.uri));
    });

    test('resolves a relative path against the defining pubspec', () async {
      File.fromUri(root.uri.resolve('relative-build.so'))
          .writeAsBytesSync(staleBytes);
      final run = await runHook(
        defines: <String, Object?>{libhegelPathDefine: 'relative-build.so'},
      );
      expect(run.bytes, staleBytes);
    });
  });

  group('refusals', () {
    test('a download that does not match the pin', () async {
      await expectLater(
        runHook(
          fetch: (Uri url) async => staleBytes,
          defines: <String, Object?>{cacheDirDefine: subdirectory('c').path},
        ),
        throwsA(isA<EngineAcquisitionException>()),
      );
    });

    test('an override path that does not exist', () async {
      await expectLater(
        runHook(
          defines: <String, Object?>{
            libhegelPathDefine: root.uri.resolve('absent.so').toFilePath(),
          },
        ),
        throwsA(isA<EngineAcquisitionException>()),
      );
    });

    test('a target upstream publishes no engine for', () async {
      await expectLater(
        runHook(os: OS.android, architecture: Architecture.arm64),
        throwsA(isA<EngineAcquisitionException>()),
      );
    });
  });
}
