// A document fed to MarkdownView(data) piece by piece: the view shows what
// a view made fresh for the same text shows, whatever was appended,
// edited, cut or given again; told what was appended, it compares that
// much of the text and not the whole.
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/src/markdown/appended.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

/// Pieces of Markdown the documents are made of: every kind of block,
/// references before and after their definitions, lazy lines and loose
/// lists, so that an append can change blocks before it.
const _parts = [
  '# A heading\n\n',
  'Some *em*, **strong**, `code` and a [link](https://a.dev).\n',
  'a lazy line\nof a paragraph\n\n',
  '- one\n- two\n  - deeper\n\n- loose\n',
  '1. first\n2. second\n\n',
  '> quoted\n> more\nlazy\n\n',
  '```dart\nvoid main() {\n  print(1);\n}\n```\n',
  '| a | b |\n|---|:-:|\n| 1 | 2 |\n| 3 | 4 |\n\n',
  'See [ref] and [other].\n\n',
  '[ref]: https://ref.dev\n',
  '---\n',
  'Setext\n===\n',
  '    indented code\n\n',
  '- [ ] a task\n- [x] done\n',
  'Wide 你好 and é and 🙂 text.\n\n',
  '\r\nline\r\n',
];

const _width = 30;
const _height = 120;

/// The live view of [data] beside a view made fresh for it ([fresh] its
/// key), each in a column [_width] wide.
Widget _pair(String data, String? appended, int fresh) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(
      child: SingleChildScrollView(
        child: MarkdownView(data, appended: appended),
      ),
    ),
    Expanded(
      child: SingleChildScrollView(
        child: MarkdownView(data, key: ValueKey(fresh)),
      ),
    ),
  ],
);

/// Row [y] of the column at [x0], each cell as a snapshot with styles marks
/// it, with its link.
String _row(TwkTester t, int x0, int y) {
  final row = StringBuffer();
  for (var x = x0; x < x0 + _width; x++) {
    final cell = t.cell(x, y);
    // a blank is drawn in any pen it looks the same in
    final blank = cell.text == ' ' && cell.attrs & Attr.visibleOnBlank == 0;
    row.write(blank ? '[bg ${cell.bg}] ' : '$cell');
    if (cell.link != null) {
      row.write('<${cell.link}>');
    }
  }
  return '$row';
}

/// Fails where the live view shows other than the fresh one.
void _expectSame(TwkTester t, String what) {
  for (var y = 0; y < _height; y++) {
    final live = _row(t, 0, y);
    final fresh = _row(t, _width, y);
    if (live != fresh) {
      fail('row $y after $what:\n  live:  $live\n  fresh: $fresh');
    }
  }
}

void main() {
  group('appendedTo', () {
    test('is what data has after the last text, null where it does not '
        'begin with it', () {
      expect(appendedTo('abc', 'abcde', null), 'de');
      expect(appendedTo('abc', 'abcde', 'de'), 'de');
      expect(appendedTo('abc', 'abc', null), '');
      expect(appendedTo('abc', 'abc', ''), '');
      expect(appendedTo('abc', 'aXcde', null), isNull);
      expect(appendedTo('abc', 'ab', null), isNull);
      expect(appendedTo('abc', 'ab', 'de'), isNull);
    });

    test('appended not of the length, or not at the end, is not taken: the '
        'whole text is compared', () {
      // two pieces arrived, the last one named
      expect(appendedTo('abc', 'abcdefg', 'fg'), 'defg');
      // the same text again, the piece before named
      expect(appendedTo('abcde', 'abcde', 'de'), '');
      // as long, but other text at the end
      expect(appendedTo('abc', 'abcxy', 'de'), 'xy');
      expect(appendedTo('abc', 'aXcxy', 'de'), isNull);
    });

    test('appended of the length at the end, the text before it edited, '
        'fails an assert', () {
      expect(
        () => appendedTo('abc', 'aXcde', 'de'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  for (final seed in [1, 2, 3, 4, 5, 6]) {
    testTwk('random appends, edits, cuts and rebuilds show what a fresh '
        'view does (seed $seed)', (t) async {
      final random = math.Random(seed);
      var text = '';
      for (var step = 0; step < 160; step++) {
        String? appended;
        final String what;
        final op = random.nextInt(20);
        if (op < 13 || text.isEmpty) {
          // a piece of a part, told or not
          final part = _parts[random.nextInt(_parts.length)];
          final from = random.nextInt(part.length);
          final to = math.min(part.length, from + 1 + random.nextInt(12));
          final piece = part.substring(from, to);
          text = '$text$piece';
          appended = random.nextInt(4) == 0 ? null : piece;
          what =
              'appending ${_quote(piece)}${appended == null ? '' : ', told'}';
        } else if (op < 16) {
          // an edit in the middle; where it cut, so that the length is
          // not that of an append, the text put in named or not
          final at = random.nextInt(text.length);
          final cut = random.nextInt(math.min(4, text.length - at) + 1);
          final put = _parts[random.nextInt(_parts.length)].substring(0, 2);
          text = text.replaceRange(at, at + cut, put);
          appended = cut > 0 && random.nextBool() ? put : null;
          what = 'replacing $cut at $at with ${_quote(put)}';
        } else if (op < 18) {
          // the end cut off
          text = text.substring(0, random.nextInt(text.length));
          what = 'cutting to ${text.length}';
        } else {
          // the same text again, a new string, with a stale piece
          text = String.fromCharCodes(text.codeUnits);
          appended = random.nextBool() && text.isNotEmpty
              ? text.substring(text.length - 1)
              : null;
          what = 'the same text again${appended == null ? '' : ', told'}';
        }
        await t.pumpWidget(
          _pair(text, appended, step),
          size: (2 * _width, _height),
        );
        _expectSame(t, '$what (step $step)');
      }
    });
  }

  testTwk("a piece told costs its own length, not the document's", (
    t,
  ) async {
    final doc = StringBuffer();
    for (var i = 0; doc.length < 20000; i++) {
      doc.write(_parts[i % _parts.length]);
    }
    final answer = '$doc';
    const size = 6;
    await t.pumpWidget(
      const SingleChildScrollView(child: MarkdownView('')),
      size: (40, 10),
    );
    final before = comparedUnits;
    for (var at = 0; at < answer.length; at += size) {
      final end = math.min(at + size, answer.length);
      final piece = answer.substring(at, end);
      final text = answer.substring(0, end);
      await t.pumpWidget(
        SingleChildScrollView(child: MarkdownView(text, appended: piece)),
        size: (40, 10),
      );
    }
    final compared = comparedUnits - before;
    printOnFailure(
      '$compared code units compared for ${answer.length} streamed; the '
      'whole text each piece is ${answer.length * answer.length ~/ 12}',
    );
    expect(compared, answer.length);
  });
}

String _quote(String s) => '"${s.replaceAll('\n', r'\n')}"';
