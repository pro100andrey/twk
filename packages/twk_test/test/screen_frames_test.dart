// screenFrames: a program's writes to a terminal played through the test
// emulator, a screen a write.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/src/screen_file.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  group('screenFrames', () {
    test('a frame after each output that leaves no synchronized update '
        'open, at the size the resizes give', () {
      final frames = screenFrames(6, 2, [
        (time: 0.1, output: 'one', size: null),
        (time: 0.2, output: '\x1b[?2026h\x1b[H\x1b[2Jtw', size: null),
        (time: 0.3, output: 'o\x1b[?2026l', size: null),
        (time: 0.4, output: null, size: null),
        (time: 0.5, output: null, size: (8, 3)),
        (time: 0.6, output: '\x1b[3;1Hthree\x1b[?25l', size: null),
      ]);

      expect(
        [
          for (final f in frames) [f.number, f.time, f.lines],
        ],
        [
          [
            1,
            0.1,
            ['one', ''],
          ],
          [
            2,
            0.3,
            ['two', ''],
          ],
          [
            3,
            0.6,
            ['two', '', 'three'],
          ],
        ],
      );
      final last = frames.last;
      expect((last.width, last.height), (8, 3));
      expect((last.cursorX, last.cursorY, last.cursorVisible), (5, 2, false));
      expect(last.errors, isEmpty);
      expect(last.toString(), '''
frame 3 at 0.600 s, 8×3:
  0 │two
  1 │
  2 │three''');
    });

    test("each frame has what the emulator couldn't take up to it", () {
      final frames = screenFrames(6, 2, [
        (time: 0.1, output: 'a', size: null),
        (time: 0.2, output: '\x07b', size: null),
        (time: 0.3, output: 'c', size: null),
      ]);

      expect(
        [for (final f in frames) f.errors],
        [
          isEmpty,
          ['raw control byte 0x7'],
          ['raw control byte 0x7'],
        ],
      );
      expect(frames.last.lines.first, 'abc');
    });
  });

  group('a frame held to a screen file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('frames_'));
    tearDown(() {
      updateScreenFilesOverride = null;
      dir.deleteSync(recursive: true);
    });

    final writes = <TerminalWrite>[
      (time: 0.1, output: 'a\tb', size: null),
      (time: 0.2, output: '\x1b[1mhi\x1b[0m\x1b[?25l', size: null),
      (time: 0.3, output: '\r\nsecond', size: null),
    ];

    test('keeps a screen only for the frames asked', () {
      final frames = screenFrames(12, 3, writes, screens: {2});
      expect(
        [for (final f in frames) f.screenFile != null],
        [false, true, false],
      );
    });

    test('is written while updating and matches it, a tab as the emulator '
        'draws it', () {
      final path = '${dir.path}/g/two.txt';
      final frames = screenFrames(12, 3, writes, screens: {2, 3});
      updateScreenFilesOverride = true;
      expect(frames[1], matchesScreenFile(path));
      updateScreenFilesOverride = false;
      expect(frames[1], matchesScreenFile(path));
      final text = File(path).readAsStringSync();
      expect(
        text,
        startsWith('screen 12×3, cursor hidden\ntext\n│abhi'),
      );
      expect(text, contains('a bold'));
      expect(frames[2], isNot(matchesScreenFile(path)));
    });

    test('fails on an edited file, leaving the screen beside it, and keeps '
        "the file's characters for the styles", () {
      final path = '${dir.path}/two.txt';
      final frames = screenFrames(12, 3, writes, screens: {2});
      updateScreenFilesOverride = true;
      expect(frames[1], matchesScreenFile(path));
      updateScreenFilesOverride = false;
      File(path).writeAsStringSync(
        File(path).readAsStringSync().replaceFirst('│abhi', '│xbhi'),
      );
      Object? message;
      try {
        expect(frames[1], matchesScreenFile(path));
      } on TestFailure catch (e) {
        message = e.message;
      }
      expect(message, contains('differs from $path'));
      expect(message, contains('+ 0│abhi'));
      expect(File('$path.actual').existsSync(), isTrue);
      updateScreenFilesOverride = true;
      expect(frames[1], matchesScreenFile(path));
      expect(File('$path.actual').existsSync(), isFalse);
    });

    test('a styled screen written again takes the characters the file had', () {
      final path = '${dir.path}/styled.txt';
      File(path).writeAsStringSync('''
screen 12×3, cursor hidden
text
│abhi  │
│             │
│             │
styles
│            │
│            │
│            │
legend
q bold
''');
      final frames = screenFrames(12, 3, writes, screens: {2});
      updateScreenFilesOverride = true;
      expect(frames[1], matchesScreenFile(path));
      expect(File(path).readAsStringSync(), contains('\nq bold\n'));
    });

    test('a frame whose screen was not kept fails, saying so', () {
      final frames = screenFrames(12, 3, writes);
      Object? message;
      try {
        expect(frames[0], matchesScreenFile('${dir.path}/x.txt'));
      } on TestFailure catch (e) {
        message = e.message;
      }
      expect(message, contains('screen of frame 1 was not kept'));
    });
  });
}
