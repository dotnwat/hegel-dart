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

  // The package root is often reached through a symlink -- on macOS the
  // temporary directory always is -- and a path that does not exist yet
  // cannot be resolved directly. Both together once let lib/nested past every
  // check.
  group('through a symlinked root', () {
    late Directory real;
    late Directory viaLink;

    setUp(() {
      real = Directory.systemTemp.createTempSync('hegel_doc_real_');
      Directory('${real.path}${Platform.pathSeparator}lib').createSync();
      final linkPath = '${real.path}_link';
      Link(linkPath).createSync(real.path);
      viaLink = Directory(linkPath);
    });

    tearDown(() {
      final link = Link('${real.path}_link');
      if (link.existsSync()) link.deleteSync();
      if (real.existsSync()) real.deleteSync(recursive: true);
    });

    test('still refuses a source directory', () {
      expect(
        () => checkSafeToEmpty(viaLink, resolveOutputDirectory(viaLink, 'lib')),
        throwsArgumentError,
      );
    });

    test('still refuses a path inside one that does not exist yet', () {
      expect(
        () => checkSafeToEmpty(
          viaLink,
          resolveOutputDirectory(viaLink, 'lib/nested'),
        ),
        throwsArgumentError,
      );
    });

    test('still refuses the package itself', () {
      expect(
        () => checkSafeToEmpty(viaLink, resolveOutputDirectory(viaLink, '.')),
        throwsArgumentError,
      );
    });
  }, skip: Platform.isWindows ? 'symlinks need privileges on Windows' : null);

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
    test('a directory this tool wrote before', () {
      final previous = Directory('${root.path}/build/doc')
        ..createSync(recursive: true);
      File('${previous.path}/.hegel-doc-output').writeAsStringSync('ours');
      File('${previous.path}/index.json').writeAsStringSync('[]');
      File('${previous.path}/stale-page.html').writeAsStringSync('<html>');
      expect(() => check('build/doc'), returnsNormally);
    });
  });

  group('refusing directories that only look like documentation', () {
    // index.json used to be the proof of ownership, which meant anything that
    // happened to contain one -- a web root, a data dump -- was fair game to
    // delete recursively. Looking like our output is not being our output.
    test('a foreign directory carrying an index.json', () {
      final web = Directory('${root.path}/web')..createSync(recursive: true);
      File('${web.path}/index.json').writeAsStringSync('{"routes":[]}');
      File('${web.path}/app.js').writeAsStringSync('// someone\'s work');
      expect(
        () => check('web'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('this tool did not write it'),
          ),
        ),
      );
      expect(File('${web.path}/app.js').existsSync(), isTrue);
    });
  });

  group('through dot segments in a path that does not exist yet', () {
    // The suffix is only normalised by the operating system, so every
    // character-level comparison against "lib" missed and the tool would
    // delete the source tree. Same shape as the symlink hole above: a form of
    // the path that the checks never saw.
    for (final value in <String>['missing/../lib', 'a/b/../../lib', './lib']) {
      test('refuses --output $value', () {
        expect(
          () => check(value),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.message.toString(),
              'message',
              contains('is inside lib'),
            ),
          ),
          reason: '$value names the source tree once resolved',
        );
        // check() only inspects, so asserting the source survived it would
        // hold no matter what. This instead pins the premise: that the value
        // really does name lib once resolved, which is what makes refusing it
        // the right answer.
        expect(
          lexicalPath(resolve(value).path),
          lexicalPath('${root.path}${Platform.pathSeparator}lib'),
        );
      });
    }

    test('refuses a dotted path landing deeper inside a protected name', () {
      expect(
        () => check('build/../lib/src'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('is inside lib'),
          ),
        ),
      );
    });

    test('refuses a dotted path that climbs out to the package itself', () {
      expect(() => check('build/doc/../..'), throwsA(isA<ArgumentError>()));
    });
  });
}
