// asciicast v2 read and written, its pauses cut; what an output leaves
// turned on in a terminal and what turns it off; a recording played
// through the test emulator, a screen a frame.
import 'package:test/test.dart';
import 'package:twk_dev/cast_frames.dart';
import 'package:twk_dev/src/cast.dart' show CastWriter;
import 'package:twk_dev/src/modes.dart';

/// A recording of a [width] by [height] terminal with [events].
Cast _cast(int width, int height, List<(double, String, String)> events) =>
    Cast(CastHeader(width: width, height: height), [
      for (final (time, code, data) in events) CastEvent(time, code, data),
    ]);

void main() {
  group('Cast', () {
    test('reads the header and an event a line, blank lines aside', () {
      final cast = Cast.parse(
        '{"version": 2, "width": 80, "height": 24, "timestamp": 1700000000, '
        '"idle_time_limit": 1.5, "command": "sh", "title": "a shell", '
        '"env": {"TERM": "xterm-256color", "SHELL": "/bin/sh"}}\n'
        '[0.5, "o", "\\u001b[1mhi\\r\\n"]\n'
        '\n'
        '[1, "i", "q"]\n'
        '[2.25, "r", "100x30"]\n',
      );

      final header = cast.header;
      expect((header.width, header.height), (80, 24));
      expect(header.timestamp, 1700000000);
      expect(header.idleTimeLimit, 1.5);
      expect(header.command, 'sh');
      expect(header.title, 'a shell');
      expect(header.env, {'TERM': 'xterm-256color', 'SHELL': '/bin/sh'});
      expect(
        [for (final e in cast.events) (e.time, e.code, e.data)],
        [(0.5, 'o', '\x1b[1mhi\r\n'), (1.0, 'i', 'q'), (2.25, 'r', '100x30')],
      );
      expect(cast.events.last.size, (100, 30));
      expect(cast.events.first.size, isNull);
      expect(cast.duration, 2.25);
    });

    test('takes no other version, and says which line is not an event', () {
      expect(
        () => Cast.parse('{"version": 1, "width": 80, "height": 24}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'asciicast version 1; this reads version 2',
          ),
        ),
      );
      expect(
        () => Cast.parse('{"version": 2, "width": 80}'),
        throwsFormatException,
      );
      expect(
        () => Cast.parse(
          '{"version": 2, "width": 80, "height": 24}\n'
          '[0.5, "o", "a"]\n'
          '[0.5, "o"]\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'line 3: no [time, code, data] event',
          ),
        ),
      );
    });
  });

  group('CastWriter', () {
    test('writes the header, then each event with its time, every pause '
        'longer than the idle limit cut to it', () {
      final out = StringBuffer();
      final writer =
          CastWriter(
              out.write,
              const CastHeader(
                width: 40,
                height: 10,
                idleTimeLimit: 2,
                env: {'TERM': 'xterm'},
              ),
              idleLimit: const Duration(seconds: 2),
            )
            ..output(const Duration(milliseconds: 500), 'a\x1b[0m'.codeUnits)
            ..input(const Duration(seconds: 10), 'q'.codeUnits)
            ..resize(const Duration(milliseconds: 10250), 50, 12);

      expect(out.toString(), r'''
{"version":2,"width":40,"height":10,"idle_time_limit":2.0,"env":{"TERM":"xterm"}}
[0.500000, "o", "a\u001b[0m"]
[2.500000, "i", "q"]
[2.750000, "r", "50x12"]
''');
      expect(writer.count, 3);
      expect(writer.time, 2.75);
      expect(Cast.parse(out.toString()).events.last.size, (50, 12));
    });

    test('keeps each pause without an idle limit', () {
      final out = StringBuffer();
      CastWriter(
        out.write,
        const CastHeader(width: 40, height: 10),
      ).output(const Duration(seconds: 30), 'a'.codeUnits);

      expect(Cast.parse(out.toString()).events.single.time, 30);
    });

    test('puts a character split between two writes together, and writes '
        'what is left of one cut off at the end', () {
      final out = StringBuffer();
      const second = Duration(seconds: 1);
      final writer = CastWriter(
        out.write,
        const CastHeader(width: 9, height: 9),
      );
      // ■ is E2 96 A0
      final first = writer.output(second, [0x61, 0xE2, 0x96]);
      final rest = writer.output(second * 2, [0xA0, 0x62]);
      writer
        ..output(second * 3, [0xE2])
        ..close(second * 4);

      expect((first, rest), ('a', '■b'));
      expect(
        [for (final e in Cast.parse(out.toString()).events) (e.time, e.data)],
        [(1.0, 'a'), (2.0, '■b'), (4.0, '�')],
      );
    });
  });

  group('ModeTracker', () {
    test('turns off what the output left on, the alternate screen last; '
        'nothing when it left nothing on', () {
      final modes = ModeTracker()
        ..add(
          '\x1b[?1049h\x1b[?1000;1006h\x1b[?2004h\x1b[?25l\x1b[?7l'
          '\x1b[>1u\x1b[>5u\x1b[<u\x1b[5 q',
        );
      expect(
        modes.off,
        [
          '\x1b[0m\x1b[?1000l\x1b[?1006l\x1b[?2004l\x1b[<1u\x1b[0 q',
          '\x1b[?7h\x1b[?25h\x1b[?1049l',
        ].join(),
      );

      modes.add(
        [
          '\x1b[?1000;1006l\x1b[?2004l\x1b[?25h\x1b[?7h\x1b[<u\x1b[0 q',
          '\x1b[?1049l',
        ].join(),
      );
      expect(modes.off, '');
    });

    test('puts a sequence split between two pieces together', () {
      final modes = ModeTracker()
        ..add('\x1b[?1049h\x1b[?10')
        ..add('00h')
        ..add('\x1b')
        ..add('[?1049l');

      expect(modes.off, '\x1b[0m\x1b[?1000l');
    });
  });

  group('castFrames', () {
    test('a frame after each output event that leaves no synchronized '
        'update open, at the size the resizes give', () {
      final frames = castFrames(
        _cast(6, 2, [
          (0.1, 'o', 'one'),
          (0.2, 'o', '\x1b[?2026h\x1b[H\x1b[2Jtw'),
          (0.3, 'o', 'o\x1b[?2026l'),
          (0.4, 'i', 'x'),
          (0.5, 'r', '8x3'),
          (0.6, 'o', '\x1b[3;1Hthree\x1b[?25l'),
        ]),
      );

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
      final frames = castFrames(
        _cast(6, 2, [(0.1, 'o', 'a'), (0.2, 'o', '\x07b'), (0.3, 'o', 'c')]),
      );

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
