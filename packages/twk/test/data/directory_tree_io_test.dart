// PickerFileSystem.local on a real temporary directory, as a
// DirectoryTree reads it: a directory's watch telling of a file made in
// it, the text and the size of a file; and a DirectoryTree of it, which
// says why a directory without the right to read it does not list and
// shows a file made in it.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('directory_tree_io_test');
  });

  tearDown(() {
    // a directory left unreadable by a failed test is made readable first
    Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
    dir.deleteSync(recursive: true);
  });

  const files = PickerFileSystem.local;

  test(
    'the watch of a directory tells of a file made in it',
    () async {
      final changed = Completer<void>();
      final watch = files.watch(dir.path).listen((_) {
        if (!changed.isCompleted) {
          changed.complete();
        }
      });
      addTearDown(watch.cancel);
      // the watch is set up as the stream is listened to, which nothing
      // tells: the file is written again until it tells of it
      final file = File('${dir.path}/new.txt');
      await waitUntil(
        () => changed.isCompleted,
        'the watch to tell of new.txt',
        timeout: const Duration(seconds: 5),
        between: () => file.writeAsStringSync('hi'),
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
    skip: Platform.isLinux || Platform.isMacOS || Platform.isWindows
        ? false
        : 'no directory watch here',
  );

  test('a file reads as its text, and has its size in bytes', () async {
    final path = '${dir.path}/a.txt';
    File(path).writeAsStringSync('héllo');
    expect(await files.read(path), 'héllo');
    expect(await files.sizeOf(path), 6);
    expect(await files.sizeOf('${dir.path}/none'), isNull);
  });

  testTwk(
    'a tree of it lists it, says why a directory without the right to '
    'read it does not list, and shows a file made in it',
    (t) async {
      final root = '${dir.path}/r';
      Directory('$root/secret').createSync(recursive: true);
      Process.runSync('chmod', ['000', '$root/secret']);
      File('$root/a.txt').writeAsStringSync('a');
      final controller = DirectoryTreeController()..expand('$root/secret');
      await t.pumpWidget(
        DirectoryTree(root: root, controller: controller),
        size: (30, 5),
      );
      const listed = [
        '▾ r/',
        '  ▾ secret/',
        '      (permission denied)',
        '    a.txt',
        '',
      ];
      await until(t, listed);
      File('$root/b.txt').writeAsStringSync('b');
      await until(t, [...listed.sublist(0, 4), '    b.txt']);
    },
    timeout: const Timeout(Duration(seconds: 20)),
    skip: Platform.isLinux || Platform.isMacOS
        ? (Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
              ? 'root reads every directory'
              : false)
        : 'chmod is POSIX',
  );
}

/// Pumps 100 ms at a time, and waits on the real clock in between, until
/// [t] shows [lines]: the disk is read and watched in real time. A failure
/// showing the screen if it has not after 10 s.
Future<void> until(TwkTester t, List<String> lines) {
  String shown() => t.lines.join('\n');
  final want = lines.join('\n');
  return waitUntil(
    () => shown() == want,
    'the tree to show\n$want',
    between: () => t.pump(const Duration(milliseconds: 100)),
  ).onError<TestFailure>((e, _) => fail('${e.message}; it shows\n${shown()}'));
}
