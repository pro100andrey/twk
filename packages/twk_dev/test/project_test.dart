// The project a command works for: the nearest directory up with a
// pubspec.yaml, of a directory made absolute and normalised.
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
}
