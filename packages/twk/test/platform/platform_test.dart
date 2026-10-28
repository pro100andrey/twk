// What packages/twk asks of the process: on the VM, platform.dart gives
// what dart:io does; web.dart, the web's stand-ins, imported here on the VM
// as they import nothing of either.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/src/platform/platform.dart';
import 'package:twk/src/platform/web.dart' as web;

void main() {
  group('on the VM', () {
    late String root;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('twk_platform_');
      addTearDown(() => dir.deleteSync(recursive: true));
      root = dir.path;
    });

    test('the process is the one dart:io gives', () {
      expect(environment, Platform.environment);
      expect(isWindows, Platform.isWindows);
      expect(pathSeparator, Platform.pathSeparator);
      expect(processId, pid);
      expect(currentDirectory, Directory.current.path);
      expect(
        tempFile('a.log'),
        '${Directory.systemTemp.path}${Platform.pathSeparator}a.log',
      );
    });

    test('kindOf follows links, and is none where nothing is', () {
      Directory('$root/d').createSync();
      File('$root/f').writeAsStringSync('');
      Link('$root/to_d').createSync('$root/d');
      Link('$root/to_f').createSync('$root/f');
      expect(kindOf('$root/d'), FileKind.directory);
      expect(kindOf('$root/to_d'), FileKind.directory);
      expect(kindOf('$root/f'), FileKind.file);
      expect(kindOf('$root/to_f'), FileKind.file);
      expect(kindOf('$root/none'), FileKind.none);
    });

    test('listDirectory gives each entry, a link to a directory one', () async {
      Directory('$root/d').createSync();
      File('$root/f').writeAsStringSync('');
      Link('$root/to_d').createSync('$root/d');
      final entries = await listDirectory(root).toList();
      expect(
        {for (final e in entries) e.path: e.isDirectory},
        {'$root/d': true, '$root/f': false, '$root/to_d': true},
      );
    });

    test('listDirectory fails with the system error, described by its '
        'message', () async {
      final error = await listDirectory(
        '$root/none',
      ).first.then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<FileSystemException>());
      expect(
        describeFileError(error!),
        (error as FileSystemException).osError!.message,
      );
      expect(describeFileError(StateError('x')), 'Bad state: x');
    });

    test('writeFile replaces what the file held', () async {
      final file = File('$root/f')..writeAsStringSync('old and longer');
      await writeFile(file.path, 'new');
      expect(file.readAsStringSync(), 'new');
    });

    test('sourcePath is the file of a file: URI or of a package the program '
        'resolves, null for another', () {
      expect(sourcePath(Uri.file('$root/a.dart')), '$root/a.dart');
      expect(
        sourcePath(Uri.parse('package:twk/twk.dart')),
        '${Directory.current.path}/lib/twk.dart',
      );
      expect(sourcePath(Uri.parse('package:no_such_package/a.dart')), isNull);
      expect(sourcePath(Uri.parse('dart:core/errors.dart')), isNull);
    });

    test('readLines gives the lines of a UTF-8 file, null for none or '
        'another', () {
      File('$root/f').writeAsStringSync('a\nb · c\n');
      File('$root/latin1').writeAsBytesSync([0x61, 0xE9, 0x0A]);
      expect(readLines('$root/f'), ['a', 'b · c']);
      expect(readLines('$root/none'), isNull);
      expect(readLines('$root/latin1'), isNull);
    });
  });

  group('on the web', () {
    test('there is no environment, the root is the working directory', () {
      expect(web.environment, isEmpty);
      expect(web.isWindows, isFalse);
      expect(web.pathSeparator, '/');
      expect(web.processId, 0);
      expect(web.currentDirectory, '/');
      expect(web.tempFile('a.log'), 'a.log');
    });

    test('nothing is at any path, and no directory is listed', () async {
      expect(web.kindOf('/'), web.FileKind.none);
      final error = await web
          .listDirectory('/')
          .first
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<UnsupportedError>());
      expect(web.describeFileError(error!), 'no file system on the web');
    });

    test('no file is written', () {
      expect(web.writeFile('a.log', 'a'), throwsUnsupportedError);
    });

    test('no source is read', () {
      expect(web.sourcePath(Uri.parse('package:twk/twk.dart')), isNull);
      expect(web.readLines('/a.dart'), isNull);
    });
  });
}
