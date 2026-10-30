// screenFrames: a program's writes to a terminal played through the test
// emulator, a screen a write.
import 'package:test/test.dart';
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
}
