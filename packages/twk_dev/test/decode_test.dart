// `twk decode`: a recording and the files TWK_TRACE_INPUT and
// TWK_TRACE_OUTPUT write, named row by row, framed, filtered; what it says
// of a file it cannot read.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/decode.dart' show printable;
import 'package:twk_dev/twk_dev.dart';

import 'twk.dart';

const esc = '\x1b';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_decode'));
  tearDown(() => dir.deleteSync(recursive: true));

  String cast(List<(double, String, String)> events) {
    final path = p.join(dir.path, 'a.cast');
    File(path).writeAsStringSync(
      [
        jsonEncode({'version': 2, 'width': 80, 'height': 24}),
        for (final (t, code, data) in events) jsonEncode([t, code, data]),
      ].join('\n'),
    );
    return path;
  }

  /// A trace file: its header, then a record of each of [reads].
  String trace(String name, String direction, List<(int, String)> reads) {
    final path = p.join(dir.path, name);
    File(path).writeAsBytesSync([
      ...ascii.encode('twk-trace 1 $direction 100x30\n'),
      for (final (micros, text) in reads) ...[
        ...ascii.encode('$micros ${utf8.encode(text).length}\n'),
        ...utf8.encode(text),
        0x0a,
      ],
    ]);
    return path;
  }

  List<String> rows(ProcessResult r) =>
      const LineSplitter().convert(r.stdout as String);

  /// A row's columns: time, direction, name and bytes (if it has them).
  List<String> columns(String row) => row.trim().split(RegExp(r'\s{2,}'));

  test(
    'names what a recording holds, with times, notes and both ways',
    () async {
      final file = cast([
        (0.5, 'o', 'hi$esc[3;5H'),
        (1.25, 'i', '$esc[A'),
        (2.0, 'r', '100x30'),
        (2.5, 'm', 'done'),
      ]);

      final r = await twkHere(['decode', file]);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(rows(r).map(columns), [
        ['0.000', '--', 'recording 80x24'],
        ['0.500', 'out', 'text "hi"', 'hi'],
        ['0.500', 'out', 'CUP cursor to row 3, column 5', 'ESC [3;5H'],
        ['1.250', 'in', 'key Up', 'ESC [A'],
        ['2.000', '--', 'resized to 100x30'],
        ['2.500', '--', 'marker done'],
      ]);
    },
  );

  test('a synchronized update is opened, or one row with --frames', () async {
    final file = cast([
      (1.0, 'o', '$esc[?2026h$esc[H$esc[31mx$esc[?2026l'),
    ]);

    final opened = rows(await twkHere(['decode', file]));
    final framed = rows(await twkHere(['decode', '--frames', file]));

    expect(framed.map(columns), [
      ['0.000', '--', 'recording 80x24'],
      [
        '1.000',
        'out',
        'frame 1: 1 DECSET, 1 CUP, 1 SGR, 1 text, 1 DECRST',
        '25 bytes',
      ],
    ]);
    expect(opened.first, framed.first);
    expect(opened[1], framed[1]);
    // the frame's five rows are below it, further in
    expect(opened.skip(2).map(columns), [
      ['1.000', 'out', 'DECSET 2026 synchronized output', 'ESC [?2026h'],
      ['1.000', 'out', 'CUP cursor to row 1, column 1', 'ESC [H'],
      ['1.000', 'out', 'SGR fg red', 'ESC [31m'],
      ['1.000', 'out', 'text "x"', 'x'],
      ['1.000', 'out', 'DECRST 2026 synchronized output', 'ESC [?2026l'],
    ]);
    expect(opened[2], startsWith('    1.000  out    DECSET'));
  });

  test('--only and --grep choose rows; a frame stays for a row of its own '
      'that matches', () async {
    final file = cast([
      (0.1, 'o', '$esc[2J'),
      (0.2, 'i', 'q'),
      (0.3, 'o', '$esc[?2026h$esc[Hab$esc[?2026l'),
    ]);

    final input = rows(await twkHere(['decode', '--only=input', file]));
    final grep = rows(await twkHere(['decode', '--grep=^CUP', file]));
    final framed = rows(
      await twkHere(['decode', '--frames', '--grep=CUP', file]),
    );
    final none = rows(
      await twkHere(['decode', '--grep=nothing like it', file]),
    );

    expect(columns(input.single), ['0.200', 'in', 'key q', 'q']);
    expect(grep.map((r) => columns(r).take(3).toList()), [
      ['0.300', 'out', startsWith('frame 1')],
      ['0.300', 'out', 'CUP cursor to row 1, column 1'],
    ]);
    expect(framed.map((r) => columns(r)[2]), [startsWith('frame 1')]);
    expect(none, isEmpty);
  });

  test('traces: the input and the output of one run merged by time', () async {
    final output = trace('o.trace', 'output', [
      (1000, '$esc[6n'),
      (3000, 'ok'),
    ]);
    final input = trace('i.trace', 'input', [(2000, '$esc[5;7R')]);

    final r = await twkHere(['decode', output, input]);

    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(rows(r).map((row) => columns(row).take(3).toList()), [
      ['0.000', '--', 'output trace 100x30'],
      ['0.000', '--', 'input trace 100x30'],
      ['0.001', 'out', 'DSR query: the cursor position'],
      ['0.002', 'in', 'CPR answer: the cursor at row 5, column 7'],
      ['0.003', 'out', 'text "ok"'],
    ]);
  });

  test('a file that cannot be read, or is neither, exits with 1; '
      'nothing to read with 64', () async {
    final missing = await twkHere(['decode', p.join(dir.path, 'nowhere.cast')]);
    expect(missing.exitCode, 1);
    expect(missing.stderr, contains('twk decode: cannot read '));

    final other = File(p.join(dir.path, 'x.txt'))
      ..writeAsStringSync('not json');
    final odd = await twkHere(['decode', other.path]);
    expect(odd.exitCode, 1);
    expect(odd.stderr, startsWith('twk decode: ${other.path}: '));

    final bare = await twkHere(['decode']);
    expect(bare.exitCode, usageExitCode);

    final bad = await twkHere(['decode', '--grep=(', other.path]);
    expect(bad.exitCode, usageExitCode);
    expect(bad.stderr, contains('--grep: not a regular expression'));
  });

  test(
    'no byte a file holds reaches the terminal as a control: names made '
    'of a title, a notification or a C1 character are shown escaped',
    () async {
      final file = cast([
        // a title that holds a screen clear and a clipboard write
        (0.1, 'o', '$esc]0;$esc[2J$esc]52;c;aGk=\x07'),
        (0.2, 'o', 'a\u009b2Jb\u0085'),
        (0.3, 'o', '$esc]777;notify;t;$esc[31mred\x07'),
        (0.4, 'i', '$esc\r'),
        (0.5, 'm', 'mark$esc[2J'),
      ]);

      final r = await twkHere(['decode', file]);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      final out = r.stdout as String;
      final bad = out.runes.where(
        (c) => c != 0x0a && (c < 0x20 || c == 0x7f || (c >= 0x80 && c <= 0x9f)),
      );
      expect(bad, isEmpty, reason: 'control characters in: $out');
      expect(out, contains('^[[2J'));
      expect(out, contains(r'\x9b'));
      expect(out, contains('key Alt+Enter'));
    },
  );

  test(
    'printable shows C0, DEL, C1 and bidi controls, and leaves the rest',
    () {
      expect(printable('plain é 日本'), 'plain é 日本');
      expect(printable('a\x1b[2J\x07\x7f'), 'a^[[2J^G^?');
      expect(printable('\u009b\u009d\u0085'), r'\x9b\x9d\x85');
      expect(printable('a${String.fromCharCode(0x202e)}b'), r'a\u{202e}b');
    },
  );

  test('every row is shown: no cap of the live viewer', () async {
    final file = cast([for (var i = 0; i < 20500; i++) (i / 1000, 'o', 'x')]);

    final r = await twkHere(['decode', file]);

    expect(rows(r), hasLength(20501));
  });

  test('a synchronized update and a string left open at the end are shown, '
      'saying so', () async {
    final file = cast([
      (1.0, 'o', '$esc[?2026h$esc[H'),
      (2.0, 'o', '$esc]0;hi'),
    ]);

    final r = await twkHere(['decode', '--frames', file]);

    expect(rows(r).map(columns), [
      ['0.000', '--', 'recording 80x24'],
      [
        '1.000',
        'out',
        'frame 1: 1 DECSET, 1 CUP, 1000 ms, not closed',
        '11 bytes',
      ],
      ['2.000', '--', 'output cut short: ESC ]0;hi'],
    ]);
  });
}
