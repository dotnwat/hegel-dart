@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart' show Architecture, OS;
import 'package:hegel/src/tooling/acquire.dart';
import 'package:test/test.dart';

/// Stand-in engine payloads. Nothing here is a real shared library; the
/// acquisition layer only ever moves bytes around and hashes them.
final Uint8List engineBytes = utf8.encode('fake libhegel engine');
final Uint8List otherBytes = utf8.encode('a different engine build');

final String engineDigest = sha256HexOf(engineBytes);

final EnginePin pin = EnginePin(
  version: '0.33.0',
  sha256ByAsset: <String, String>{'libhegel-linux-amd64.so': engineDigest},
);

const String assetName = 'libhegel-linux-amd64.so';

/// A fetch that hands back [bytes] and records every URL it was asked for.
EngineFetch fetchReturning(Uint8List bytes, {List<Uri>? log}) =>
    (Uri url) async {
      log?.add(url);
      return bytes;
    };

/// A fetch that fails the test if it is called at all.
Future<Uint8List> neverFetch(Uri url) async =>
    fail('the network was used, but $url should have been served locally');

/// True when the process can write anywhere regardless of mode bits, which
/// makes "unwritable directory" tests meaningless.
bool get runningAsRoot =>
    !Platform.isWindows &&
    Process.runSync('id', <String>['-u']).stdout.toString().trim() == '0';

void main() {
  late Directory root;
  late Directory staging;
  late Directory cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hegel_acquire_');
    staging = Directory.fromUri(root.uri.resolve('staging/'))
      ..createSync(recursive: true);
    cache = Directory.fromUri(root.uri.resolve('cache/'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File stagedFile() => File.fromUri(staging.uri.resolve(assetName));
  File cachedFile() =>
      File.fromUri(engineCacheDirectory(cache, pin).uri.resolve(assetName));

  group('sha256HexOf', () {
    // Ground the primitive on published vectors rather than on itself.
    test('matches the known digest of the empty input', () {
      expect(
        sha256HexOf(<int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('matches the known digest of "abc"', () {
      expect(
        sha256HexOf(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('target table', () {
    test('maps every published target to its Go-style asset name', () {
      expect(
        <String?>[
          engineTargetFor(OS.linux, Architecture.x64)?.assetName,
          engineTargetFor(OS.linux, Architecture.arm64)?.assetName,
          engineTargetFor(OS.macOS, Architecture.arm64)?.assetName,
          engineTargetFor(OS.windows, Architecture.x64)?.assetName,
          engineTargetFor(OS.windows, Architecture.arm64)?.assetName,
        ],
        <String>[
          'libhegel-linux-amd64.so',
          'libhegel-linux-arm64.so',
          'libhegel-darwin-arm64.dylib',
          'libhegel-windows-amd64.dll',
          'libhegel-windows-arm64.dll',
        ],
      );
    });

    test('has no entry for Intel macOS, which upstream does not publish', () {
      expect(engineTargetFor(OS.macOS, Architecture.x64), isNull);
    });

    test('has no entry for mobile targets', () {
      expect(engineTargetFor(OS.android, Architecture.arm64), isNull);
      expect(engineTargetFor(OS.iOS, Architecture.arm64), isNull);
    });

    test('covers exactly the five published targets', () {
      expect(supportedEngineTargets, hasLength(5));
    });
  });

  group('EnginePin', () {
    test('builds the public release-download URL', () {
      final target = engineTargetFor(OS.linux, Architecture.x64)!;
      expect(
        pin.downloadUrl(target).toString(),
        'https://github.com/hegeldev/hegel-rust/releases/download/'
        'v0.33.0/libhegel-linux-amd64.so',
      );
    });

    test('reports a target the pin has no digest for', () {
      final target = engineTargetFor(OS.windows, Architecture.arm64)!;
      expect(
        () => pin.digestFor(target),
        throwsA(
          isA<EngineAcquisitionException>().having(
            (EngineAcquisitionException e) => e.message,
            'message',
            allOf(contains('libhegel-windows-arm64.dll'), contains('0.33.0')),
          ),
        ),
      );
    });

    test('normalizes an uppercase digest', () {
      final target = engineTargetFor(OS.linux, Architecture.x64)!;
      final shouty = EnginePin(
        version: '0.33.0',
        sha256ByAsset: <String, String>{assetName: engineDigest.toUpperCase()},
      );
      expect(shouty.digestFor(target), engineDigest);
    });
  });

  group('defaultCacheRoot', () {
    test('prefers XDG_CACHE_HOME when it is set', () {
      final resolved = defaultCacheRoot(
        environment: <String, String>{'XDG_CACHE_HOME': '/xdg', 'HOME': '/h'},
        isWindows: false,
      );
      expect(resolved?.path, '/xdg');
    });

    test('falls back to HOME/.cache on POSIX', () {
      final resolved = defaultCacheRoot(
        environment: <String, String>{'HOME': '/home/someone'},
        isWindows: false,
      );
      // Derived rather than passed through, so this goes through a URI
      // round-trip that renders as \home\someone\.cache on Windows. The URI
      // path is the platform-neutral view of the same value.
      expect(resolved?.uri.path, '/home/someone/.cache/');
    });

    test('uses LOCALAPPDATA on Windows', () {
      final resolved = defaultCacheRoot(
        environment: <String, String>{'LOCALAPPDATA': r'C:\Users\me\AppData'},
        isWindows: true,
      );
      expect(resolved?.path, r'C:\Users\me\AppData');
    });

    test('falls back to USERPROFILE on Windows', () {
      final resolved = defaultCacheRoot(
        environment: <String, String>{'USERPROFILE': '/users/me'},
        isWindows: true,
      );
      expect(resolved?.uri.path, '/users/me/.cache/');
    });

    // A hook that cannot find a cache root still has to work: it just leans
    // on its own output directory instead.
    test('returns null when nothing usable is in the environment', () {
      expect(
        defaultCacheRoot(
          environment: <String, String>{'PATH': '/usr/bin', 'HOME': ''},
          isWindows: false,
        ),
        isNull,
      );
    });
  });

  group('readVerified', () {
    test('returns the very bytes it hashed', () {
      final file = File.fromUri(root.uri.resolve('engine'))
        ..writeAsBytesSync(engineBytes);
      // The caller stages what this returns, so returning the buffer that was
      // hashed is what makes a shared cache safe: re-reading the file would
      // leave room for a concurrent writer to swap it after verification.
      expect(readVerified(file, engineDigest), engineBytes);
    });

    test('returns null when the digest does not match', () {
      final file = File.fromUri(root.uri.resolve('engine'))
        ..writeAsBytesSync(otherBytes);
      expect(readVerified(file, engineDigest), isNull);
    });

    test('returns null for a file that is not there', () {
      expect(
        readVerified(File.fromUri(root.uri.resolve('absent')), engineDigest),
        isNull,
      );
    });

    test(
      'treats an unreadable file as a miss rather than an error',
      () {
        final file = File.fromUri(root.uri.resolve('locked-engine'))
          ..writeAsBytesSync(engineBytes);
        Process.runSync('chmod', <String>['a-r', file.path]);
        addTearDown(() => Process.runSync('chmod', <String>['u+r', file.path]));
        expect(readVerified(file, engineDigest), isNull);
      },
      skip: Platform.isWindows || runningAsRoot
          ? 'needs POSIX mode bits and a non-root user'
          : null,
    );
  });

  group('publishFile', () {
    test('writes the bytes and leaves no temporary behind', () {
      final written = publishFile(
        engineBytes,
        staging,
        assetName,
        replaceExisting: true,
      );
      expect(written.readAsBytesSync(), engineBytes);
      expect(
        staging.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last),
        <String>[assetName],
      );
    });

    test('keeps the existing file when told not to replace it', () {
      publishFile(otherBytes, staging, assetName, replaceExisting: false);
      publishFile(engineBytes, staging, assetName, replaceExisting: false);
      expect(stagedFile().readAsBytesSync(), otherBytes);
    });

    test('overwrites when told to replace', () {
      publishFile(otherBytes, staging, assetName, replaceExisting: true);
      publishFile(engineBytes, staging, assetName, replaceExisting: true);
      expect(stagedFile().readAsBytesSync(), engineBytes);
    });

    test('creates missing parent directories', () {
      final nested = Directory.fromUri(root.uri.resolve('a/b/c/'));
      publishFile(engineBytes, nested, assetName, replaceExisting: true);
      expect(File.fromUri(nested.uri.resolve(assetName)).existsSync(), isTrue);
    });
  });

  // The real fetch: every other test injects a fake one, so without this the
  // function that actually downloads engines would ship unexercised.
  group('httpEngineFetch', () {
    late HttpServer server;
    late Uri base;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://${server.address.address}:${server.port}');
    });

    tearDown(() => server.close(force: true));

    test('returns the body it was served', () async {
      server.listen((HttpRequest request) {
        request.response
          ..add(engineBytes)
          ..close();
      });
      expect(await httpEngineFetch(base.resolve('/engine')), engineBytes);
    });

    // Release downloads redirect to a storage host, so following them is not
    // optional.
    test('follows a redirect', () async {
      server.listen((HttpRequest request) {
        if (request.uri.path == '/engine') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/elsewhere')
            ..close();
          return;
        }
        request.response
          ..add(engineBytes)
          ..close();
      });
      expect(await httpEngineFetch(base.resolve('/engine')), engineBytes);
    });

    test(
      'reports a non-OK status rather than returning the error body',
      () async {
        server.listen((HttpRequest request) {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('nope')
            ..close();
        });
        await expectLater(
          httpEngineFetch(base.resolve('/missing')),
          throwsA(
            isA<EngineAcquisitionException>().having(
              (EngineAcquisitionException e) => e.message,
              'message',
              contains('404'),
            ),
          ),
        );
      },
    );

    test('handles a body arriving in several chunks', () async {
      server.listen((HttpRequest request) async {
        request.response.add(engineBytes.sublist(0, 4));
        await request.response.flush();
        request.response.add(engineBytes.sublist(4));
        await request.response.close();
      });
      expect(await httpEngineFetch(base.resolve('/chunked')), engineBytes);
    });
  });

  group('EngineAcquisitionException', () {
    test('names itself in its message', () {
      expect(
        EngineAcquisitionException('the cache melted').toString(),
        'EngineAcquisitionException: the cache melted',
      );
    });
  });

  group('acquireEngine', () {
    test('downloads, verifies, stages, and fills the cache', () async {
      final log = <Uri>[];
      final result = await acquireEngine(
        pin: pin,
        os: OS.linux,
        architecture: Architecture.x64,
        stagingDirectory: staging,
        cacheRoot: cache,
        fetch: fetchReturning(engineBytes, log: log),
      );

      expect(result.source, EngineSource.download);
      expect(result.file.readAsBytesSync(), engineBytes);
      expect(result.file.path, stagedFile().path);
      expect(result.dependencies, isEmpty);
      expect(cachedFile().readAsBytesSync(), engineBytes);
      expect(log.single.toString(), endsWith('/v0.33.0/$assetName'));
    });

    test('reuses an already staged engine without fetching', () async {
      publishFile(engineBytes, staging, assetName, replaceExisting: true);
      final result = await acquireEngine(
        pin: pin,
        os: OS.linux,
        architecture: Architecture.x64,
        stagingDirectory: staging,
        cacheRoot: cache,
        fetch: neverFetch,
      );
      expect(result.source, EngineSource.staged);
    });

    test('restages from the cache without fetching', () async {
      publishFile(
        engineBytes,
        engineCacheDirectory(cache, pin),
        assetName,
        replaceExisting: true,
      );
      final result = await acquireEngine(
        pin: pin,
        os: OS.linux,
        architecture: Architecture.x64,
        stagingDirectory: staging,
        cacheRoot: cache,
        fetch: neverFetch,
      );
      expect(result.source, EngineSource.cache);
      expect(stagedFile().readAsBytesSync(), engineBytes);
    });

    // The pin is worthless if a cache hit skips verification, so a corrupt
    // entry has to be discarded rather than served.
    test('discards a corrupt cache entry and refetches', () async {
      publishFile(
        otherBytes,
        engineCacheDirectory(cache, pin),
        assetName,
        replaceExisting: true,
      );
      final result = await acquireEngine(
        pin: pin,
        os: OS.linux,
        architecture: Architecture.x64,
        stagingDirectory: staging,
        cacheRoot: cache,
        fetch: fetchReturning(engineBytes),
      );
      expect(result.source, EngineSource.download);
      expect(stagedFile().readAsBytesSync(), engineBytes);
      expect(cachedFile().readAsBytesSync(), engineBytes);
    });

    test(
      'ignores a stale staged file that no longer matches the pin',
      () async {
        publishFile(otherBytes, staging, assetName, replaceExisting: true);
        final result = await acquireEngine(
          pin: pin,
          os: OS.linux,
          architecture: Architecture.x64,
          stagingDirectory: staging,
          cacheRoot: cache,
          fetch: fetchReturning(engineBytes),
        );
        expect(result.source, EngineSource.download);
        expect(stagedFile().readAsBytesSync(), engineBytes);
      },
    );

    test('refuses a download that does not match the pin', () async {
      await expectLater(
        acquireEngine(
          pin: pin,
          os: OS.linux,
          architecture: Architecture.x64,
          stagingDirectory: staging,
          cacheRoot: cache,
          fetch: fetchReturning(otherBytes),
        ),
        throwsA(
          isA<EngineAcquisitionException>().having(
            (EngineAcquisitionException e) => e.message,
            'message',
            contains('does not match its pinned SHA-256'),
          ),
        ),
      );
      expect(stagedFile().existsSync(), isFalse);
      expect(cachedFile().existsSync(), isFalse);
    });

    test('works without any cache root', () async {
      final result = await acquireEngine(
        pin: pin,
        os: OS.linux,
        architecture: Architecture.x64,
        stagingDirectory: staging,
        fetch: fetchReturning(engineBytes),
      );
      expect(result.source, EngineSource.download);
      expect(stagedFile().readAsBytesSync(), engineBytes);
    });

    test('names the supported targets when one is unsupported', () async {
      await expectLater(
        acquireEngine(
          pin: pin,
          os: OS.macOS,
          architecture: Architecture.x64,
          stagingDirectory: staging,
          fetch: neverFetch,
        ),
        throwsA(
          isA<EngineAcquisitionException>().having(
            (EngineAcquisitionException e) => e.message,
            'message',
            allOf(
              contains('macos/x64'),
              contains('linux/x64'),
              contains('libhegel_path'),
            ),
          ),
        ),
      );
    });

    test(
      'falls back to downloading when a cache entry cannot be read',
      () async {
        final cached = publishFile(
          engineBytes,
          engineCacheDirectory(cache, pin),
          assetName,
          replaceExisting: true,
        );
        Process.runSync('chmod', <String>['a-r', cached.path]);
        addTearDown(
          () => Process.runSync('chmod', <String>['u+r', cached.path]),
        );

        final result = await acquireEngine(
          pin: pin,
          os: OS.linux,
          architecture: Architecture.x64,
          stagingDirectory: staging,
          cacheRoot: cache,
          fetch: fetchReturning(engineBytes),
        );

        // An optional cache going unreadable must not fail the build.
        expect(result.source, EngineSource.download);
        expect(result.file.readAsBytesSync(), engineBytes);
      },
      skip: Platform.isWindows || runningAsRoot
          ? 'needs POSIX mode bits and a non-root user'
          : null,
    );

    group('local override', () {
      test('stages the named file and reports it as a dependency', () async {
        final local = File.fromUri(root.uri.resolve('local-build.so'))
          ..writeAsBytesSync(otherBytes);
        final result = await acquireEngine(
          pin: pin,
          os: OS.linux,
          architecture: Architecture.x64,
          stagingDirectory: staging,
          cacheRoot: cache,
          overrideFile: local,
          fetch: neverFetch,
        );

        expect(result.source, EngineSource.override);
        // Deliberately not checked against the pin: a local build is whatever
        // the developer just compiled.
        expect(result.file.readAsBytesSync(), otherBytes);
        expect(result.dependencies.single.path, local.path);
        expect(cachedFile().existsSync(), isFalse);
      });

      test('restages over a previously staged engine', () async {
        publishFile(engineBytes, staging, assetName, replaceExisting: true);
        final local = File.fromUri(root.uri.resolve('local-build.so'))
          ..writeAsBytesSync(otherBytes);
        await acquireEngine(
          pin: pin,
          os: OS.linux,
          architecture: Architecture.x64,
          stagingDirectory: staging,
          overrideFile: local,
          fetch: neverFetch,
        );
        expect(stagedFile().readAsBytesSync(), otherBytes);
      });

      // The unsupported-target error tells the user to build the engine and
      // name it here, so the override has to work on exactly those targets.
      test('works on a target upstream publishes no engine for', () async {
        final local = File.fromUri(root.uri.resolve('intel-mac-build.dylib'))
          ..writeAsBytesSync(otherBytes);
        final result = await acquireEngine(
          pin: pin,
          os: OS.macOS,
          architecture: Architecture.x64,
          stagingDirectory: staging,
          overrideFile: local,
          fetch: neverFetch,
        );

        expect(result.source, EngineSource.override);
        expect(result.file.readAsBytesSync(), otherBytes);
        // With no published asset there is no canonical name to stage under,
        // so the local build keeps its own.
        expect(result.file.uri.pathSegments.last, 'intel-mac-build.dylib');
      });

      test('fails loudly instead of falling back to the pin', () async {
        await expectLater(
          acquireEngine(
            pin: pin,
            os: OS.linux,
            architecture: Architecture.x64,
            stagingDirectory: staging,
            overrideFile: File.fromUri(root.uri.resolve('missing.so')),
            fetch: neverFetch,
          ),
          throwsA(
            isA<EngineAcquisitionException>().having(
              (EngineAcquisitionException e) => e.message,
              'message',
              allOf(contains('does not exist'), contains('libhegel_path')),
            ),
          ),
        );
      });
    });

    test(
      'survives an unwritable cache',
      () async {
        final locked = Directory.fromUri(root.uri.resolve('locked/'))
          ..createSync(recursive: true);
        Process.runSync('chmod', <String>['a-w', locked.path]);
        addTearDown(
          () => Process.runSync('chmod', <String>['u+w', locked.path]),
        );

        final result = await acquireEngine(
          pin: pin,
          os: OS.linux,
          architecture: Architecture.x64,
          stagingDirectory: staging,
          cacheRoot: locked,
          fetch: fetchReturning(engineBytes),
        );

        expect(result.source, EngineSource.download);
        expect(result.file.readAsBytesSync(), engineBytes);
      },
      skip: Platform.isWindows || runningAsRoot
          ? 'needs POSIX mode bits and a non-root user'
          : null,
    );
  });
}
