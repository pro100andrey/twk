// fileIdentity on macOS and Linux, where tailFile tells a replaced file by
// it: the same file through a write, another one moved onto the name, none
// where nothing is there.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/src/platform/file_identity.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('twk_identity');
    path = '${dir.path}/app.log';
  });
  tearDown(() => dir.delete(recursive: true));

  test('files are told apart here', () {
    expect(knowsFileIdentity, isTrue);
  });

  test('a file written to is the same file', () {
    File(path).writeAsStringSync('old\n');
    final before = fileIdentity(path);
    File(path).writeAsStringSync('new\n', mode: FileMode.append);
    expect(before, isNotNull);
    expect(fileIdentity(path), before);
  });

  test('a file moved onto the name is another one', () {
    File(path).writeAsStringSync('old\n');
    final before = fileIdentity(path);
    File('${dir.path}/next.log')
      ..writeAsStringSync('old\n')
      ..renameSync(path);
    expect(fileIdentity(path), isNot(before));
  });

  test('no file, no identity', () {
    expect(fileIdentity(path), isNull);
  });
}
