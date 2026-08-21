@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/doc.dart';

/// The documentation tool empties its output directory before writing, which
/// makes the value of `--output` a destructive argument. These pin the checks
/// that stand between a typo and a deleted checkout.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hegel_doc_')
      ..createSync(recursive: true);
    for (final name in <String>['lib', 'test', 'tool', 'hook', '.git']) {
      Directory('${root.path}${Platform.pathSeparator}$name').createSync();
    }
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory resolve(String value) => resolveOutputDirectory(root, value);
  void check(String value) => checkSafeToEmpty(root, resolve(value));

  group('resolving', () {
    test('places a relative path inside the package', () {
      expect(resolve('build/doc').path, startsWith(root.path));
    });

    test('leaves an absolute path alone', () {
      final absolute = Directory.systemTemp.path;
      expect(resolve(absolute).path, absolute);
    });

    // Uri.resolve reads C:\docs as a URI with scheme "c" and a UNC path as a
    // host, so a valid Windows destination used to throw before dartdoc ran.
    test('treats a Windows path as a path, not a URI', () {
      expect(() => resolve(r'C:\temp\docs'), returnsNormally);
      expect(() => resolve(r'\\server\share\docs'), returnsNormally);
    });

    test('refuses an empty value', () {
      expect(() => resolve(''), throwsArgumentError);
      expect(() => resolve('   '), throwsArgumentError);
    });
  });

  group('refusing to empty', () {
    test('the package itself', () {
      expect(() => check('.'), throwsArgumentError);
    });

    // The worst of them: this used to resolve to the directory holding every
    // sibling checkout.
    test('anything containing the package', () {
      expect(() => check('..'), throwsArgumentError);
      expect(() => check('../..'), throwsArgumentError);
    });

    test('source directories', () {
      for (final protected in <String>['lib', 'test', 'tool', 'hook', '.git']) {
        expect(
          () => check(protected),
          throwsArgumentError,
          reason: '$protected should be protected',
        );
        expect(() => check('$protected/nested'), throwsArgumentError);
      }
    });

    test('a non-empty directory dartdoc did not write', () {
      final stranger = Directory('${root.path}/somewhere')..createSync();
      File('${stranger.path}/important.txt').writeAsStringSync('keep me');
      expect(() => check('somewhere'), throwsArgumentError);
    });
  });

  group('allowing', () {
    test('a directory that does not exist yet', () {
      expect(() => check('build/doc'), returnsNormally);
    });

    test('an empty directory', () {
      Directory('${root.path}/empty').createSync();
      expect(() => check('empty'), returnsNormally);
    });

    // Recognised by the index dartdoc always writes, so regeneration keeps
    // working without any special case.
    test('a directory dartdoc wrote before', () {
      final previous = Directory('${root.path}/build/doc')
        ..createSync(recursive: true);
      File('${previous.path}/index.json').writeAsStringSync('[]');
      File('${previous.path}/stale-page.html').writeAsStringSync('<html>');
      expect(() => check('build/doc'), returnsNormally);
    });
  });
}
