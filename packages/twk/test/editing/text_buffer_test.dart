// A text in pieces edited as a String is, its lines found by piece, what
// changed since the texts it was edited from; where a caret stops found
// from a window around the offset as in the whole text, across scripts,
// emoji, flags, conjuncts and runs that leave no certain bound for long.
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/src/editing/text_buffer.dart';
import 'package:twk_core/twk_core.dart' show ClusterScan, TextSegmenter;

/// Pieces of text that make characters of their own and with their
/// neighbours: letters of several scripts, blanks, controls, marks, CJK,
/// Hangul jamo, emoji with skin tones and ZWJ, flags, Indic conjuncts,
/// Prepend, lone surrogates.
const _pieces = [
  'a', 'b', 'Z', '1', '_', '.', ',', '-', ' ', ' ', '\t', '\n', '\r', //
  '\r\n', '\x00', 'é', 'e\u0301', '\u0301', 'я', 'ж', 'α', 'ש', //
  'ب', '\u064B', '日', '本', 'あ', 'カ', '한', '\u1100', '\u1161', //
  '\u11A8', '👋', '🏽', '👨‍👩‍👧', '\u200D', '🇺', //
  '🇦', '🇺🇦', 'क', '\u094D', 'ष', '\u093F', '\u0600', //
  '\u00AD', '©', '\uFE0F', '\uD800', '\uDC00', '😀', //
];

/// Runs that leave no bound certain from its neighbours for a while.
const _runs = [
  '\u0301',
  '🇺',
  'क\u094D',
  '\u200D👋',
  'ب\u064B',
];

String randomText(Random r, int length) {
  final out = StringBuffer();
  while (out.length < length) {
    if (r.nextInt(40) == 0) {
      out.write(_runs[r.nextInt(_runs.length)] * (20 + r.nextInt(100)));
    } else {
      out.write(_pieces[r.nextInt(_pieces.length)]);
    }
  }
  return out.toString();
}

/// Where a caret stops in a whole String, worked out from all of its
/// characters: what the stops found from a window must agree with.
final class WholeStops {
  WholeStops(this.text) {
    final segmenter = TextSegmenter();
    final scan = ClusterScan();
    final bounds = <int>[0];
    for (var i = 0; i < text.length; i = scan.end) {
      segmenter.scan(text, i, scan);
      bounds.add(scan.end);
    }
    b = Int32List.fromList(bounds);
  }

  final String text;
  late final Int32List b;

  int _indexOf(int offset) {
    var lo = 0;
    var hi = b.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (b[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static final _blankRe = RegExp(r'\s', unicode: true);
  static const _wordClass =
      r'[\p{L}\p{N}\p{M}\p{Pc}\p{Extended_Pictographic}\p{Regional_Indicator}]';
  static final _wordRe = RegExp(_wordClass, unicode: true);

  int _classAt(int offset) {
    if (_blankRe.matchAsPrefix(text, offset) != null) {
      return 0;
    }
    return _wordRe.matchAsPrefix(text, offset) != null ? 1 : 2;
  }

  bool _same(int kind, int first, bool blankDelimited) =>
      blankDelimited ? kind != 0 : kind == first;

  int characterStartBefore(int offset) {
    final k = _indexOf(offset);
    return b[b[k] < offset || k == 0 ? k : k - 1];
  }

  int characterEndAfter(int offset) {
    final k = _indexOf(offset);
    return b[k + 1 < b.length ? k + 1 : k];
  }

  int wordStartBefore(int offset, bool blankDelimited) {
    var k = _indexOf(offset);
    while (k > 0 && _classAt(b[k - 1]) == 0) {
      k--;
    }
    if (k == 0) {
      return 0;
    }
    final kind = _classAt(b[k - 1]);
    while (k > 0 && _same(_classAt(b[k - 1]), kind, blankDelimited)) {
      k--;
    }
    return b[k];
  }

  int wordEndAfter(int offset, bool blankDelimited) {
    final last = b.length - 1;
    var k = _indexOf(offset);
    while (k < last && _classAt(b[k]) == 0) {
      k++;
    }
    if (k == last) {
      return text.length;
    }
    final kind = _classAt(b[k]);
    while (k < last && _same(_classAt(b[k]), kind, blankDelimited)) {
      k++;
    }
    return b[k];
  }
}

void main() {
  group('TextBuffer', () {
    test('edited at random across many blocks of pieces, it reads as the '
        'String edited alike, and stays in few blocks', () {
      final r = Random(11);
      for (var round = 0; round < 4; round++) {
        // a few hundred pieces: several blocks of them
        var s = randomText(r, 200000 + r.nextInt(200000));
        var b = TextBuffer(s);
        expect(b.blockCount, greaterThan(2));
        for (var i = 0; i < 400; i++) {
          final start = r.nextInt(s.length + 1);
          final reach = switch (r.nextInt(20)) {
            // now and then a cut across blocks, or most of the text
            0 => 150000,
            1 => s.length,
            _ => 40,
          };
          final end = start + r.nextInt(min(s.length - start, reach) + 1);
          final inserted = r.nextInt(15) == 0
              ? randomText(r, r.nextInt(120000))
              : randomText(r, r.nextInt(4));
          s = s.replaceRange(start, end, inserted);
          b = b.replace(start, end, inserted);
          expect(b.length, s.length);
          final a = r.nextInt(s.length + 1);
          final z = a + r.nextInt(min(s.length - a, 5000) + 1);
          expect(b.substring(a, z), s.substring(a, z));
          if (i % 40 == 0) {
            final lines = s.split('\n');
            expect(b.lineCount, lines.length);
            for (var l = 0; l < lines.length; l += 1 + l ~/ 7) {
              final at = _startOfLine(s, l);
              expect(b.lineStart(l), at, reason: 'line $l');
              expect(b.lineOf(at), l);
            }
          }
          // pieces of 512 to 2048 code units, blocks of 32 to 64 of them
          // but where the text has fewer
          expect(
            b.blockCount,
            lessThanOrEqualTo(b.pieceCount ~/ 32 + 2),
            reason: '${b.pieceCount} pieces',
          );
        }
        expect(b.text, s);
        expect(b.sameText(s), isTrue);
        expect(b.sameText(TextBuffer(s)), isTrue);
        // all of it deleted, then written again
        final none = b.replace(0, b.length, '');
        expect(none.length, 0);
        expect(none.text, '');
        expect(none.lineCount, 1);
        final again = none.replace(0, 0, s);
        expect(again.text, s);
        expect(again.lineCount, s.split('\n').length);
      }
    });

    test('a part across pieces read again is the same String, and a part '
        'read after another is that part', () {
      final s = List.generate(4000, (i) => 'line $i').join('\n');
      // an edit splits the text's pieces: a part across them is joined
      final b = TextBuffer(s).replace(9000, 9000, 'x');
      final t = s.replaceRange(9000, 9000, 'x');
      expect(b.pieceCount, greaterThan(1));
      final first = b.substring(8000, 10500);
      expect(first, t.substring(8000, 10500));
      expect(identical(b.substring(8000, 10500), first), isTrue);
      expect(b.substring(8000, 10501), t.substring(8000, 10501));
      expect(b.substring(7999, 10500), t.substring(7999, 10500));
      expect(b.substring(8000, 10500), first);
      // the text edited from it joins its own
      final c = b.replace(8500, 8501, 'yz');
      expect(
        c.substring(8000, 10500),
        t.replaceRange(8500, 8501, 'yz').substring(8000, 10500),
      );
    });

    test('edited at random, it reads as the String edited alike: its '
        'length, parts, lines and line breaks', () {
      final r = Random(7);
      for (var round = 0; round < 20; round++) {
        var s = randomText(r, r.nextInt(6000));
        var b = TextBuffer(s);
        for (var i = 0; i < 300; i++) {
          final start = r.nextInt(s.length + 1);
          final end = start + r.nextInt(min(s.length - start, 3000) + 1);
          final inserted = r.nextInt(10) == 0
              ? randomText(r, r.nextInt(5000))
              : randomText(r, r.nextInt(3));
          s = s.replaceRange(start, end, inserted);
          b = b.replace(start, end, inserted);
          expect(b.length, s.length);
          final a = r.nextInt(s.length + 1);
          final z = a + r.nextInt(s.length - a + 1);
          expect(b.substring(a, z), s.substring(a, z));
        }
        expect(b.text, s);
        final lines = s.split('\n');
        expect(b.lineCount, lines.length);
        var at = 0;
        for (var l = 0; l < lines.length; l++) {
          expect(b.lineStart(l), at, reason: 'line $l');
          expect(b.lineEnd(l), at + lines[l].length);
          expect(b.lineOf(at), l);
          expect(b.lineOf(at + lines[l].length), l, reason: 'its break');
          at += lines[l].length + 1;
        }
        expect(b.sameText(s), isTrue);
        expect(b.sameText(TextBuffer(s)), isTrue);
        expect(b.sameText('${s}x'), isFalse);
        if (s.isNotEmpty) {
          final other = b.replace(0, 1, s[0] == 'q' ? 'r' : 'q');
          expect(b.sameText(other), isFalse);
          expect(b.sameText(other.text), isFalse);
        }
      }
    });

    test('is compared piece by piece before it is put together', () {
      final s = 'line of text\n' * 1000;
      final a = TextBuffer(s).replace(5, 5, 'x');
      final b = TextBuffer(s).replace(5, 5, 'x');
      final c = TextBuffer(s).replace(5, 5, 'y');
      final joins = TextBuffer.joins;
      final edited = s.replaceRange(5, 5, 'x');
      expect(a.sameText(edited), isTrue);
      expect(a.sameText(s.replaceRange(5, 5, 'y')), isFalse);
      expect(a.sameText(b), isTrue);
      expect(a.sameText(c), isFalse);
      expect(TextBuffer.joins, joins);
      expect('$a', 'TextBuffer(${s.length + 1}, ${a.pieceCount} pieces)');
    });

    test('an edit leaves the text edited as it was, and a String asked '
        'for is put together once', () {
      final s = 'line of text\n' * 10000;
      final b = TextBuffer(s);
      final edited = b.replace(5, 5, 'x');
      expect(b.text, same(s));
      expect(edited.substring(0, 8), 'line xof');
      final joins = TextBuffer.joins;
      final text = edited.text;
      expect(edited.text, same(text));
      expect(TextBuffer.joins, joins + 1);
      // one piece is its own String
      expect(TextBuffer('short').replace(0, 0, 'a ').text, 'a short');
      expect(TextBuffer.joins, joins + 1);
    });

    test('a piece left short by an edit goes with the one next to it, '
        'so that a text keeps to a piece for each half a kilobyte', () {
      var b = TextBuffer('word ' * 20000);
      for (var i = 0; i < 90000; i++) {
        b = b.replace(i % 9000, i % 9000 + 1, '');
      }
      expect(b.length, 10000);
      expect(b.pieceCount, lessThanOrEqualTo(10000 ~/ 512 + 1));
    });

    test('tells what changed since each of the last texts it was edited '
        'from, and nothing for others', () {
      final r = Random(3);
      var s = randomText(r, 5000);
      final texts = [TextBuffer(s)];
      final strings = [s];
      for (var i = 0; i < 40; i++) {
        final start = r.nextInt(s.length + 1);
        final end = start + r.nextInt(min(s.length - start, 50) + 1);
        final inserted = randomText(r, r.nextInt(30));
        s = s.replaceRange(start, end, inserted);
        texts.add(texts.last.replace(start, end, inserted));
        strings.add(s);
      }
      final now = texts.last;
      for (var back = 0; back < texts.length; back++) {
        final i = texts.length - 1 - back;
        final change = now.changeSince(texts[i]);
        if (back > 16) {
          expect(change, isNull, reason: '$back back');
          continue;
        }
        final (:start, :oldEnd, :newEnd) = change!;
        final old = strings[i];
        expect(
          old.replaceRange(start, oldEnd, s.substring(start, newEnd)),
          s,
          reason: '$back back',
        );
        expect(old.substring(0, start), s.substring(0, start));
        expect(old.substring(oldEnd), s.substring(newEnd));
      }
      expect(now.changeSince(TextBuffer(s)), isNull);
    });
  });

  group('TextStops', () {
    test('finds from a window the stops the whole text has, in any part '
        'of it', () {
      final r = Random(11);
      for (var round = 0; round < 60; round++) {
        // windows as narrow as a code unit, and as wide as they are
        final stops = TextStops(margin: round.isEven ? 1 + round % 4 : 64);
        final text = randomText(r, 200 + r.nextInt(1500));
        final lo = r.nextBool() ? 0 : r.nextInt(text.length ~/ 3);
        final hi = r.nextBool()
            ? text.length
            : text.length - r.nextInt(text.length ~/ 3);
        final whole = WholeStops(text.substring(lo, hi));
        for (var o = lo - 1; o <= hi + 1; o++) {
          final local = o - lo;
          final reason = 'offset $o in $lo..$hi of round $round';
          expect(
            stops.characterStartBefore(text.substring, lo, hi, o),
            lo + whole.characterStartBefore(local),
            reason: reason,
          );
          expect(
            stops.characterEndAfter(text.substring, lo, hi, o),
            lo + whole.characterEndAfter(local),
            reason: reason,
          );
          for (final blankDelimited in [false, true]) {
            expect(
              stops.wordStartBefore(
                text.substring,
                lo,
                hi,
                o,
                blankDelimited: blankDelimited,
              ),
              lo + whole.wordStartBefore(local, blankDelimited),
              reason: reason,
            );
            expect(
              stops.wordEndAfter(
                text.substring,
                lo,
                hi,
                o,
                blankDelimited: blankDelimited,
              ),
              lo + whole.wordEndAfter(local, blankDelimited),
              reason: reason,
            );
          }
        }
      }
    });

    test('in a long word, the stops are its ends however far they are', () {
      final word = 'x' * 100000;
      final text = 'a $word b';
      final b = TextBuffer(text);
      expect(b.wordStartBefore(50000), 2);
      expect(b.wordEndAfter(50000), 100002);
      expect(b.characterEndAfter(50000), 50001);
      expect(b.wordStartBefore(50000, from: 1000, to: 60000), 1000);
    });

    test('a character that goes on past a window is found whole: an emoji '
        'sequence joined by ZWJs, a conjunct of linkers and marks, a mark '
        'in the next plane', () {
      for (final run in [
        '👋\u200D©\u200D' * 100,
        'क\u094D\u0301' * 100,
      ]) {
        final b = TextBuffer('a $run b');
        expect(b.characterEndAfter(2), 2 + run.length);
        expect(b.characterStartBefore(2 + run.length), 2);
      }
      final marked = '${'a🏽' * 300}b';
      final whole = WholeStops(marked);
      for (var margin = 1; margin <= 4; margin++) {
        final stops = TextStops(margin: margin);
        for (var o = 0; o <= marked.length; o++) {
          expect(
            stops.characterEndAfter(marked.substring, 0, marked.length, o),
            whole.characterEndAfter(o),
          );
          expect(
            stops.characterStartBefore(marked.substring, 0, marked.length, o),
            whole.characterStartBefore(o),
          );
        }
      }
    });
  });
}

/// The offset line [line] of [s] starts at.
int _startOfLine(String s, int line) {
  var at = 0;
  for (var l = 0; l < line; l++) {
    at = s.indexOf('\n', at) + 1;
  }
  return at;
}
