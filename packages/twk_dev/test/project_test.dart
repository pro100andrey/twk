// The project a command works for: the nearest directory up with a
// pubspec.yaml, of a directory made absolute and normalised.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/project.dart';

void main() {
  test('the project of a directory is the nearest one up with a pubspec, '
      'by its absolute path without . or ..', () {
    final root = Directory.systemTemp.createTempSync('twk_project');
    addTearDown(() => root.deleteSync(recursive: true));
    final dir = p.normalize(root.absolute.path);
    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('name: app\n');
    Directory(p.join(dir, 'lib', 'src')).createSync(recursive: true);
    Directory(p.join(dir, 'inner')).createSync();
    File(p.join(dir, 'inner', 'pubspec.yaml')).writeAsStringSync('name: i\n');

    expect(projectOf(p.join(dir, 'lib', 'src')), dir);
    expect(projectOf(p.join(dir, 'inner')), p.join(dir, 'inner'));
    expect(projectOf(p.join(dir, 'inner', '..', '.', 'lib')), dir);
    expect(
      projectOf(p.relative(p.join(dir, 'lib'))),
      dir,
      reason: 'a relative directory is from the current one',
    );
  });

  test('without a directory, the project of the current one', () {
    expect(projectOf(null), projectOf(Directory.current.path));
  });

  test('the path dependencies of a package are those of its package '
      'configuration outside the pub cache, with a lib/', () {
    final root = Directory.systemTemp.createTempSync('twk_deps');
    addTearDown(() => root.deleteSync(recursive: true));
    final dir = p.normalize(root.absolute.path);
    for (final lib in [
      'app/lib',
      'ws/b/lib',
      'far/lib',
      'cache/hosted/h/lib',
    ]) {
      Directory(p.join(dir, lib)).createSync(recursive: true);
    }
    Directory(p.join(dir, 'nolib')).createSync();
    Directory(p.join(dir, 'app', '.dart_tool')).createSync();
    Map<String, String> entry(String name, String root) => {
      'name': name,
      'rootUri': root,
      'packageUri': 'lib/',
    };
    File(p.join(dir, 'app', '.dart_tool', 'package_config.json'))
        .writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': [
              entry('app', '../'),
              entry('b', '../../ws/b'),
              entry('far', Uri.directory(p.join(dir, 'far')).toString()),
              entry('nolib', '../../nolib'),
              entry(
                'h',
                Uri.directory(p.join(dir, 'cache', 'hosted', 'h')).toString(),
              ),
              entry('web', 'https://example.com/web'),
            ],
          }),
        );

    expect(
      pathDependencyLibs(p.join(dir, 'app'), pubCache: p.join(dir, 'cache')),
      {'b': p.join(dir, 'ws', 'b', 'lib'), 'far': p.join(dir, 'far', 'lib')},
    );
    expect(pathDependencyLibs(p.join(dir, 'ws')), isEmpty);
  });

  test('a package entry without a packageUri is the package root, as the '
      'package configuration says', () {
    final root = Directory.systemTemp.createTempSync('twk_deps');
    addTearDown(() => root.deleteSync(recursive: true));
    final dir = p.normalize(root.absolute.path);
    Directory(p.join(dir, 'app', '.dart_tool')).createSync(recursive: true);
    Directory(p.join(dir, 'b', 'lib')).createSync(recursive: true);
    File(p.join(dir, 'app', '.dart_tool', 'package_config.json'))
        .writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': [
              {'name': 'b', 'rootUri': '../../b'},
            ],
          }),
        );
    expect(pathDependencyLibs(p.join(dir, 'app'), pubCache: '/none'), {
      'b': p.join(dir, 'b'),
    });
  });

  test('where no pub cache is known, only packages under a .pub-cache are '
      'left out as hosted', () {
    final root = Directory.systemTemp.createTempSync('twk_deps');
    addTearDown(() => root.deleteSync(recursive: true));
    final dir = p.normalize(root.absolute.path);
    Directory(p.join(dir, 'app', '.dart_tool')).createSync(recursive: true);
    for (final lib in ['b/lib', '.pub-cache/hosted/h/lib']) {
      Directory(p.join(dir, lib)).createSync(recursive: true);
    }
    File(p.join(dir, 'app', '.dart_tool', 'package_config.json'))
        .writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': [
              {'name': 'b', 'rootUri': '../../b', 'packageUri': 'lib/'},
              {
                'name': 'h',
                'rootUri': '../../.pub-cache/hosted/h',
                'packageUri': 'lib/',
              },
            ],
          }),
        );
    expect(pathDependencyLibs(p.join(dir, 'app'), environment: {}), {
      'b': p.join(dir, 'b', 'lib'),
    });
  });
}
