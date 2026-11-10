// What a recording keeps of the input and which of it is the person's:
// the terminal's answers to the program's queries are told from keys by
// their shape (and, for the cursor position, by the query in the output).
import 'package:test/test.dart';
import 'package:twk_dev/src/replay.dart';
import 'package:twk_dev/twk_dev.dart';

String _keys(String typed, {String output = ''}) {
  final s = InputSplitter()..sawOutput(output);
  return [
    for (final p in [...s.add(typed), ...s.flush()])
      if (!p.isAnswer) p.text,
  ].join();
}

void main() {
  group('InputSplitter', () {
    test('takes the answers of a terminal out of the keys', () {
      const answers = [
        '\x1b[?2026;2\$y', // a mode report
        '\x1b[?62;4c', // device attributes
        '\x1b[>0;276;0c',
        '\x1b[?0u', // kitty flags
        '\x1b[?12;40R', // an extended cursor position
        '\x1b]11;rgb:1e1e/1e1e/2e2e\x1b\\', // a colour, ST
        '\x1b]10;rgb:ffff/ffff/ffff\x07', // a colour, BEL
        '\x1bP>|xterm(388)\x1b\\', // XTVERSION
        '\x1b_Gi=1;OK\x1b\\', // a kitty graphics reply
        '\x1b[8;24;80t', // a size
        '\x1b[0n', // a status
        '\x1b[?997;1n', // a colour scheme
      ];
      for (final a in answers) {
        expect(
          _keys('a${a}b'),
          'ab',
          reason: InputPiece(a, isAnswer: false).toString(),
        );
      }
    });

    test('keeps the keys, the mouse, focus and a paste', () {
      const keys = [
        'abc é',
        '\r',
        '\x1b', // a lone Escape
        '\x1b[A',
        '\x1b[1;5C',
        '\x1b[3~',
        '\x1b[97;5u', // a kitty key
        '\x1b[97;5:3u', // a kitty release
        '\x1bOP',
        '\x1b[I',
        '\x1b[<0;10;5M',
        '\x1bx', // Alt+x
        '\x1b[1;2R', // F3 with Shift, no position asked
      ];
      for (final k in keys) {
        expect(_keys('<$k>'), '<$k>');
      }
      const paste = '\x1b[200~\x1b[?62;4c and \x1b]0;x\x07\x1b[201~';
      expect(_keys('x${paste}y'), 'x${paste}y');
    });

    test('takes a position for an answer once it was asked, once', () {
      expect(_keys('\x1b[1;5R'), '\x1b[1;5R');
      expect(_keys('\x1b[12;40R', output: 'a\x1b[6nb'), '');
      expect(_keys('\x1b[12;40R\x1b[12;40R', output: '\x1b[6n'), '\x1b[12;40R');
    });

    test('an unanswered query is given up at the next key', () {
      final s = InputSplitter()..sawOutput('\x1b[6n');
      expect([for (final p in s.add('q')) p.text], ['q']);
      expect(
        [for (final p in s.add('\x1b[1;5R')) (p.isAnswer, p.text)],
        [(false, '\x1b[1;5R')],
      );
    });

    test('a query cut between two writes is found', () {
      final s = InputSplitter()
        ..sawOutput('a\x1b[')
        ..sawOutput('6nb');
      expect([for (final p in s.add('\x1b[12;40R')) p.isAnswer], [true]);
      final t = InputSplitter()
        ..sawOutput('\x1b')
        ..sawOutput('[?6')
        ..sawOutput('n');
      expect([for (final p in t.add('\x1b[12;40R')) p.isAnswer], [true]);
    });

    test('waits for the rest of a sequence and keys the end', () {
      final s = InputSplitter();
      expect(s.add('a\x1b[?20'), hasLength(1));
      expect(s.pending, '\x1b[?20');
      final rest = s.add(r'26;2$yz');
      expect(
        [for (final p in rest) (p.isAnswer, p.text)],
        [
          (true, '\x1b[?2026;2\$y'),
          (false, 'z'),
        ],
      );
      expect(s.add('\x1b]11;rgb'), isEmpty);
      expect(
        [for (final p in s.flush()) (p.isAnswer, p.text)],
        [
          (false, '\x1b]11;rgb'),
        ],
      );
    });
  });

  test('replaySteps are the keys of a recording at their times', () {
    final cast = Cast(const CastHeader(width: 80, height: 24), const [
      CastEvent(0.1, 'o', 'x\x1b[6n\x1b[?2026\$p'),
      CastEvent(0.11, 'i', '\x1b[?2026;2\$y\x1b[3;1R'),
      CastEvent(0.5, 'i', '+'),
      CastEvent(0.6, 'r', '60x20'),
      CastEvent(0.9, 'i', '\x1b[?62;4cq'),
    ]);
    expect(
      [for (final s in replaySteps(cast)) (s.time, s.keys)],
      [
        (0.5, '+'),
        (0.9, 'q'),
      ],
    );
  });

  test('replaySteps say which keys the program reacted to', () {
    final cast = Cast(const CastHeader(width: 80, height: 24), const [
      CastEvent(0.1, 'o', 'x'),
      CastEvent(0.5, 'i', '+'),
      CastEvent(0.6, 'o', 'y'),
      CastEvent(0.9, 'i', 'a'),
      CastEvent(1, 'i', 'b'),
      CastEvent(1.5, 'o', 'z'),
      CastEvent(2, 'i', 'q'),
    ]);
    expect(
      [for (final s in replaySteps(cast)) (s.keys, s.reacts)],
      [('+', true), ('a', false), ('b', true), ('q', false)],
    );
  });

  test('reacts goes by the order of events when times are equal', () {
    final cast = Cast(const CastHeader(width: 80, height: 24), const [
      CastEvent(0.5, 'i', 'a'),
      CastEvent(0.5, 'o', 'echo of a'),
      CastEvent(0.9, 'o', 'before b'),
      CastEvent(0.9, 'i', 'b'),
      CastEvent(0.9, 'o', 'echo of b'),
      CastEvent(1, 'i', 'c'),
      CastEvent(1.2, 'i', 'q'),
    ]);
    expect(
      [for (final s in replaySteps(cast)) (s.keys, s.reacts)],
      [('a', true), ('b', true), ('c', false), ('q', false)],
    );
  });
}
