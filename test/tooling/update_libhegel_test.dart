@TestOn('vm')
library;

import 'dart:io';

import 'package:hegel/src/libhegel/version.g.dart';
import 'package:hegel/src/tooling/acquire.dart';
import 'package:test/test.dart';

import '../../tool/update_libhegel.dart';

const String _asset = 'libhegel-linux-amd64.so';
const String _digest =
    '9a14df0a6259ce83426e4015ce02d376b938323f7c210bab90b86bfbca970406';

void main() {
  group('parseSha256Sidecar', () {
    test('reads the sha256sum format upstream publishes', () {
      expect(
        parseSha256Sidecar('$_digest  $_asset\n', assetName: _asset),
        _digest,
      );
    });

    test('accepts binary-mode and path-qualified names', () {
      expect(
        parseSha256Sidecar('$_digest *$_asset', assetName: _asset),
        _digest,
      );
      expect(
        parseSha256Sidecar('$_digest  ./dist/$_asset', assetName: _asset),
        _digest,
      );
    });

    test('normalizes an uppercase digest', () {
      expect(
        parseSha256Sidecar(
          '${_digest.toUpperCase()}  $_asset',
          assetName: _asset,
        ),
        _digest,
      );
    });

    test('rejects a sidecar that names a different file', () {
      expect(
        () => parseSha256Sidecar(
          '$_digest  libhegel-linux-arm64.so',
          assetName: _asset,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a truncated digest', () {
      expect(
        () => parseSha256Sidecar('abc123  $_asset', assetName: _asset),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty or garbage text', () {
      expect(
        () => parseSha256Sidecar('', assetName: _asset),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseSha256Sidecar('404: Not Found', assetName: _asset),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('missingAssetNames', () {
    test('accepts a release carrying every binary and sidecar', () {
      expect(missingAssetNames(requiredAssetNames()), isEmpty);
    });

    test('reports a missing binary', () {
      final published = requiredAssetNames()..remove(_asset);
      expect(missingAssetNames(published), <String>[_asset]);
    });

    // The sidecar is what a recomputed digest gets checked against, so a
    // release without one cannot be verified and must not be pinned.
    test('reports a missing sidecar', () {
      final published = requiredAssetNames()..remove(sidecarNameFor(_asset));
      expect(missingAssetNames(published), <String>[sidecarNameFor(_asset)]);
    });

    test('reports everything when the release publishes nothing', () {
      expect(
        missingAssetNames(const <String>[]),
        hasLength(supportedEngineTargets.length * 2),
      );
    });
  });

  group('renderVersionFile', () {
    test('sorts entries so an unchanged pin renders identically', () {
      const scrambled = EnginePin(
        version: '1.2.3',
        sha256ByAsset: <String, String>{'b.so': 'bb', 'a.so': 'aa'},
      );
      const ordered = EnginePin(
        version: '1.2.3',
        sha256ByAsset: <String, String>{'a.so': 'aa', 'b.so': 'bb'},
      );
      expect(renderVersionFile(scrambled), renderVersionFile(ordered));
      expect(
        renderVersionFile(scrambled).indexOf("'a.so'"),
        lessThan(renderVersionFile(scrambled).indexOf("'b.so'")),
      );
    });

    test('lowercases digests', () {
      const shouty = EnginePin(
        version: '1.2.3',
        sha256ByAsset: <String, String>{'a.so': 'AABB'},
      );
      expect(renderVersionFile(shouty), contains("'aabb'"));
      expect(renderVersionFile(shouty), isNot(contains("'AABB'")));
    });
  });

  group('the checked-in pin', () {
    // Catches a hand-edited version.g.dart without needing the network: the
    // file on disk has to be exactly what the tool would write for the pin it
    // itself declares.
    test('is byte-identical to what the tool renders', () {
      final onDisk = File('lib/src/libhegel/version.g.dart').readAsStringSync();
      expect(renderVersionFile(libhegelPin), onDisk);
    });

    test('agrees with the standalone version constant', () {
      expect(libhegelPin.version, libhegelVersion);
    });

    test('carries a digest for every supported target', () {
      for (final target in supportedEngineTargets) {
        expect(
          libhegelPin.digestFor(target),
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: 'no usable digest pinned for ${target.assetName}',
        );
      }
    });
  });
}
