// A line broken into rows from each row's start, as far as asked for, as
// a reference breaks it from the measure of the whole line; the rows kept
// across edits, of the line edited and of the others, as worked out anew;
// a wide character that does not fit after a word carried over goes to
// the next row.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk/src/editing/caret.dart' show measureClusters;
import 'package:twk/src/editing/text_buffer.dart';
import 'package:twk/src/editing/text_rows.dart';
import 'package:twk_core/twk_core.dart'
    show ClusterScan, TextMode, TextSegmenter;

/// Pieces of lines: words, blanks and tabs, wide characters, marks with
/// and without a base (spacing marks among them), emoji, controls.
const _pieces = [
  'a', 'bc', 'word', 'longerword', ' ', ' ', '  ', '\t', '日', '本語', //
  '한', 'é', 'e\u0301', '\u0301', '👋🏽', '👨‍👩‍👧', //
  '🇺🇦', '\x01', ',', 'ж', '\u200B', '\u1100\u1161', '\u093F', '\u0903', //
];

/// Runs longer than a row is wide: blanks that hang past its end, marks
/// and controls of no width.
const _runs = [' ', '\u0301', '\x01'];

String randomLine(Random r, int length) {
  final out = StringBuffer();
  while (out.length < length) {
    if (r.nextInt(30) == 0) {
      out.write(_runs[r.nextInt(_runs.length)] * (50 + r.nextInt(200)));
    } else {
      out.write(_pieces[r.nextInt(_pieces.length)]);
    }
  }
  return out.toString();
}

bool _isBlank(String text, int offset) {
  final c = text.codeUnitAt(offset);
  return c == 0x20 || c == 0x09;
}

/// The rows of a line at a width as the area breaks them, each from its
/// start, measured with the columns of the whole line.
final class Reference {
  Reference(this.line, this.width, TextSegmenter segmenter) {
    measureClusters(line, segmenter, offsets, columns, ClusterScan());
    final n = offsets.length - 1;
    var s = 0;
    outer:
    while (true) {
      var column = 0;
      var brk = -1;
      for (var k = s; k <= n; k++) {
        final end = k == n;
        final w = end ? 1 : columns[k + 1] - columns[k];
        final blank = !end && _isBlank(line, offsets[k]);
        if (k > s && !blank) {
          final wPrev = columns[k] - columns[k - 1];
          if (_isBlank(line, offsets[k - 1]) || w == 2 && wPrev == 2) {
            brk = k;
          }
        }
        if (!blank && column + w > width && k > s) {
          s = brk > s ? brk : k;
          rows.add(s);
          continue outer;
        }
        column += w;
      }
      break;
    }
  }

  final String line;
  final int width;

  // the offset of each cluster and the line's end, the column of each in
  // the line, the cluster each row starts at
  final offsets = <int>[];
  final columns = <int>[];
  final rows = <int>[0];

  List<int> get starts => [for (final k in rows) offsets[k]];

  int _cluster(int offset) => offsets.lastIndexWhere((o) => o <= offset);

  int _row(int k) => rows.lastIndexWhere((s) => s <= k);

  int _column(int k) => columns[k] - columns[rows[_row(k)]];

  int columnOf(int offset) => _column(_cluster(offset));

  (int, int) place(int offset) {
    final k = _cluster(offset);
    final r = _row(k);
    final c = _column(k);
    return c >= width && r + 1 < rows.length ? (r + 1, 0) : (r, c);
  }

  int offsetAt(int row, int column) {
    final from = rows[row];
    final to = row + 1 < rows.length ? rows[row + 1] - 1 : offsets.length - 1;
    var best = from;
    for (var k = from + 1; k <= to; k++) {
      if (_column(k) > column) {
        break;
      }
      best = k;
    }
    return offsets[best];
  }
}

/// Every row start of [rows], all of them worked out.
List<int> startsOf(LineRows rows) => [
  for (var r = 0; r < rows.rowCount; r++) rows.rowStart(r),
];

void main() {
  for (final mode in TextMode.values) {
    test('breaks a line into rows as the reference does, as far as asked '
        'for, the columns in each row too (${mode.name})', () {
      final r = Random(mode.index + 5);
      final segmenter = TextSegmenter(mode: mode);
      final scan = ClusterScan();
      for (var round = 0; round < 300; round++) {
        final line = randomLine(r, r.nextInt(400));
        final width = 1 + r.nextInt(20);
        final ref = Reference(line, width, segmenter);
        final text = TextBuffer('x\n$line\ny');
        final rows = LineRows(text, 2, line.length, width, segmenter, scan);
        final reason = 'width $width: ${line.replaceAll('\t', r'\t')}';
        // a row in the middle asked for first: the rows before it only
        final mid = ref.rows.length ~/ 2;
        expect(rows.hasRow(mid), isTrue, reason: reason);
        expect(rows.rowStart(mid), ref.starts[mid], reason: reason);
        expect(startsOf(rows), ref.starts, reason: reason);
        for (var o = 0; o <= line.length; o++) {
          expect(rows.place(o), ref.place(o), reason: '$reason at $o');
          expect(rows.columnOf(o), ref.columnOf(o), reason: '$reason at $o');
        }
        for (var row = 0; row < ref.rows.length; row++) {
          for (var column = 0; column < width + 2; column++) {
            expect(
              rows.offsetAt(row, column),
              ref.offsetAt(row, column),
              reason: '$reason row $row column $column',
            );
          }
        }
      }
    });
  }

  test('keeps the rows of the lines an edit does not reach, and of the '
      'line it is in those before it, as worked out anew', () {
    final r = Random(9);
    final segmenter = TextSegmenter();
    for (var round = 0; round < 40; round++) {
      final width = 3 + r.nextInt(30);
      var text = TextBuffer(
        [
          for (var l = 0; l < 1 + r.nextInt(8); l++)
            randomLine(r, r.nextBool() ? r.nextInt(30) : r.nextInt(3000)),
        ].join('\n'),
      );
      final kept = TextRows()..update(text, width, segmenter);
      for (var step = 0; step < 30; step++) {
        // some rows asked for, of some lines
        for (var i = 0; i < 3; i++) {
          final line = r.nextInt(text.lineCount);
          final rows = kept.of(line);
          if (r.nextBool()) {
            rows.place(r.nextInt(rows.length + 1));
          } else {
            rows.hasRow(r.nextInt(50));
          }
        }
        // an edit or a few, a line break in some
        for (var e = r.nextInt(r.nextInt(10) == 0 ? 20 : 3); e >= 0; e--) {
          final start = r.nextInt(text.length + 1);
          final end = start + r.nextInt(min(text.length - start, 40) + 1);
          final inserted = r.nextInt(5) == 0
              ? '${randomLine(r, 5)}\n${randomLine(r, 5)}'
              : randomLine(r, r.nextInt(4));
          text = text.replace(start, end, inserted);
        }
        kept.update(text, width, segmenter);
        final fresh = TextRows()
          ..update(TextBuffer(text.text), width, segmenter);
        for (var line = 0; line < text.lineCount; line++) {
          final a = kept.of(line);
          final b = fresh.of(line);
          final reason = 'round $round step $step line $line';
          expect(a.start, b.start, reason: reason);
          expect(a.length, b.length, reason: reason);
          expect(startsOf(a), startsOf(b), reason: reason);
          for (var o = 0; o <= a.length; o += 1 + a.length ~/ 50) {
            expect(a.place(o), b.place(o), reason: '$reason at $o');
          }
        }
        if (r.nextInt(4) == 0) {
          kept.sweep();
        }
      }
    }
  });

  test('a wide character that does not fit after a word carried to a row '
      'goes on to the next', () {
    final segmenter = TextSegmenter();
    // the word carried over takes 9 of 10 columns, the ideograph two
    const line = ' bbbbbbbbb日';
    final rows = LineRows(
      TextBuffer(line),
      0,
      line.length,
      10,
      segmenter,
      ClusterScan(),
    );
    expect(startsOf(rows), [0, 1, 10]);
    expect(rows.place(10), (2, 0));
  });

  test('in visual order, the caret after a blank hanging past a row of a '
      'right-to-left line shows at the start of the next row as drawn', () {
    const line = 'אבגד  הו';
    final rows = LineRows(
      TextBuffer(line),
      0,
      line.length,
      4,
      TextSegmenter(),
      ClusterScan(),
      visual: true,
    );
    expect(startsOf(rows), [0, 6]);
    expect(rows.place(4), (0, 0));
    expect(rows.place(5), rows.place(6));
    expect(rows.place(5).$1, 1);
  });

  test('the ints a row is measured in are read and written within their '
      'length only, an assert says so in debug; grown, they read 0', () {
    final ints = GrowingInts()..addAll([1, 2, 3]);
    expect(ints[2], 3);
    ints[1] = 7;
    expect(ints, [1, 7, 3]);
    ints.length = 0;
    // what the last measure left past the length
    expect(() => ints[0], throwsA(isA<AssertionError>()));
    expect(() => ints[0] = 4, throwsA(isA<AssertionError>()));
    ints.length = 2;
    expect(ints, [0, 0]);
    expect(() => ints[2], throwsA(isA<AssertionError>()));
    ints.add(5);
    expect(ints, [0, 0, 5]);
    for (var i = 0; i < 100; i++) {
      ints.add(i);
    }
    expect(ints.length, 103);
    expect(ints.copy(), [0, 0, 5, for (var i = 0; i < 100; i++) i]);
  });
}
