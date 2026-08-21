// GENERATED FILE. DO NOT EDIT.
//
// Regenerate with:
//
//     dart run tool/update_libhegel.dart --version 0.33.0
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
const String libhegelVersion = '0.33.0';

/// The pinned engine release, with a SHA-256 for each published platform.
const EnginePin libhegelPin = EnginePin(
  version: libhegelVersion,
  sha256ByAsset: <String, String>{
    'libhegel-darwin-arm64.dylib':
        '86042e449e74020340001f31bf99f9abb0f06a33aff170d9ad6c7e03b2cbf64e',
    'libhegel-linux-amd64.so':
        '9a14df0a6259ce83426e4015ce02d376b938323f7c210bab90b86bfbca970406',
    'libhegel-linux-arm64.so':
        '0ed646c4dc560ba8755006c274ec4a5c10e9cc6919b731c2918906a78c246841',
    'libhegel-windows-amd64.dll':
        'a08f48a0953f68bc2095f735ae3b521d530817eb2b91ab5d1ea215a6c6a0355d',
    'libhegel-windows-arm64.dll':
        'ccb39178181c3bdf5b2cc549ab3b766b22c9b47fc2d4993ae165f7c94206e677',
  },
);
