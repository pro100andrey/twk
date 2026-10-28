/// The Unicode Bidirectional Algorithm (UAX #9): the embedding levels of a
/// text's paragraphs and, line by line, the order its runs are drawn in
/// from left to right.
///
/// Rules P1 to L2 are implemented, and L4 by [bidiMirror]. For L3 a
/// right-to-left run is reversed by grapheme cluster rather than by code
/// point, as [BidiText.visual] does, so marks stay after their bases.
library;

import 'dart:typed_data';

import 'bidi_data.g.dart';
import 'unicode.dart';

/// The Bidi_Class of a character (UAX #9, table 4).
enum BidiClass {
  /// Left-to-right.
  l,

  /// Right-to-left.
  r,

  /// Right-to-left Arabic.
  al,

  /// European number.
  en,

  /// European number separator.
  es,

  /// European number terminator.
  et,

  /// Arabic number.
  an,

  /// Common number separator.
  cs,

  /// Nonspacing mark.
  nsm,

  /// Boundary neutral.
  bn,

  /// Paragraph separator.
  b,

  /// Segment separator.
  s,

  /// Whitespace.
  ws,

  /// Other neutral.
  on,

  /// Left-to-right embedding.
  lre,

  /// Left-to-right override.
  lro,

  /// Right-to-left embedding.
  rle,

  /// Right-to-left override.
  rlo,

  /// Pop directional format.
  pdf,

  /// Left-to-right isolate.
  lri,

  /// Right-to-left isolate.
  rli,

  /// First strong isolate.
  fsi,

  /// Pop directional isolate.
  pdi,
}

/// The direction text runs in.
enum TextDirection {
  /// Left to right.
  ltr,

  /// Right to left.
  rtl,
}

// Bidi_Class codes: the indices of BidiClass, as the generated table has
// them.
const _l = 0;
const _r = 1;
const _al = 2;
const _en = 3;
const _es = 4;
const _et = 5;
const _an = 6;
const _cs = 7;
const _nsm = 8;
const _bn = 9;
const _b = 10;
const _s = 11;
const _ws = 12;
const _on = 13;
const _lre = 14;
const _lro = 15;
const _rle = 16;
const _rlo = 17;
const _pdf = 18;
const _lri = 19;
const _rli = 20;
const _fsi = 21;
const _pdi = 22;

/// The classes rule X9 removes.
const int _removed =
    1 << _lre | 1 << _rle | 1 << _lro | 1 << _rlo | 1 << _pdf | 1 << _bn;

const int _isolateInitiators = 1 << _lri | 1 << _rli | 1 << _fsi;

/// Neutral and isolate formatting classes (NI, rules N1 and N2).
const int _neutrals =
    1 << _b | 1 << _s | 1 << _ws | 1 << _on | _isolateInitiators | 1 << _pdi;

/// The classes rule L1 resets before a separator and at the end of a line:
/// whitespace and isolate formatting characters, and those X9 removed.
const int _trailing = 1 << _ws | _isolateInitiators | 1 << _pdi | _removed;

/// The classes that can raise a level in a left-to-right paragraph; text
/// without them is left to right throughout.
const int _raising =
    1 << _r |
    1 << _al |
    1 << _an |
    1 << _lre |
    1 << _rle |
    1 << _lro |
    1 << _rlo |
    _isolateInitiators;

/// The deepest embedding level (BD2).
const _maxDepth = 125;

/// The depth of the bracket stack (BD16).
const _maxBrackets = 63;

final _classTable = CodePointTable(bidiClassRanges);

/// The Bidi_Class of [cp].
BidiClass bidiClassOf(int cp) => BidiClass.values[_classTable[cp]];

/// The Bidi_Mirroring_Glyph of [cp], the character that shows it mirrored
/// where a right-to-left run draws it (rule L4); [cp] itself when there is
/// none.
int bidiMirror(int cp) {
  final i = _find(bidiMirroring, 2, cp);
  return i < 0 ? cp : bidiMirroring[i + 1];
}

/// The index in [table], flat groups of [stride] sorted by their first
/// value, of the group of [cp], or -1.
int _find(List<int> table, int stride, int cp) {
  var lo = 0;
  var hi = table.length ~/ stride - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final v = table[mid * stride];
    if (cp < v) {
      hi = mid - 1;
    } else if (cp > v) {
      lo = mid + 1;
    } else {
      return mid * stride;
    }
  }
  return -1;
}

/// A paragraph of a [BidiText]: the range [start, end) of its text, the
/// separator that ends it included.
final class BidiParagraph {
  /// The paragraph of code units [start] to [end] at [level].
  const BidiParagraph(this.start, this.end, this.level);

  /// The index of the paragraph's first code unit.
  final int start;

  /// The index after the paragraph's last code unit, its separator's.
  final int end;

  /// The paragraph embedding level: 0 left to right, 1 right to left.
  final int level;

  /// The paragraph's direction: [TextDirection.rtl] for an odd [level].
  TextDirection get direction =>
      level.isOdd ? TextDirection.rtl : TextDirection.ltr;

  @override
  String toString() => 'BidiParagraph($start, $end, $level)';
}

/// A run of a line at one embedding level: the range [start, end) of its
/// text, drawn right to left when [level] is odd.
final class BidiRun {
  /// The run of code units [start] to [end] at [level].
  const BidiRun(this.start, this.end, this.level);

  /// The index of the run's first code unit in the text.
  final int start;

  /// The index after the run's last code unit.
  final int end;

  /// The run's embedding level: even left to right, odd right to left.
  final int level;

  /// The direction the run is drawn in: [TextDirection.rtl] for an odd
  /// [level].
  TextDirection get direction =>
      level.isOdd ? TextDirection.rtl : TextDirection.ltr;

  @override
  String toString() => 'BidiRun($start, $end, $level)';
}

/// A text's bidirectional layout by UAX #9: its paragraphs, the embedding
/// level of each character and, for a line of a paragraph, the runs it is
/// drawn in.
///
/// Indices are UTF-16 code units of [text], as elsewhere in the core; both
/// units of a surrogate pair carry the same level.
///
/// A line with Hebrew in it, as it is drawn:
///
/// ```dart
/// final bidi = BidiText('abc אבג def');
/// print(bidi.visual(0, bidi.text.length)); // abc גבא def
/// print(bidi.visualRuns(0, bidi.text.length).length); // 3
/// ```
final class BidiText {
  /// Splits [text] into paragraphs after each paragraph separator, CR LF
  /// counted as one (rule P1), and resolves their levels (rules P2 to I2).
  /// Each paragraph runs in [direction] or, when that is null, in the
  /// direction of its first strong character outside isolates, left to
  /// right when there is none (rules P2 and P3).
  factory BidiText(String text, {TextDirection? direction}) {
    final n = text.length;
    final classes = Uint8List(n);
    var seen = 0;
    for (var i = 0; i < n;) {
      var cp = text.codeUnitAt(i);
      if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n) {
        final lo = text.codeUnitAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
        }
      }
      final c = _classTable[cp];
      classes[i++] = c;
      if (cp > 0xFFFF) {
        classes[i++] = c;
      }
      seen |= 1 << c;
    }

    final bounds = <int>[0];
    if ((seen & 1 << _b) != 0) {
      for (var i = 0; i < n; i++) {
        if (classes[i] != _b) {
          continue;
        }
        if (text.codeUnitAt(i) == 0x0D &&
            i + 1 < n &&
            text.codeUnitAt(i + 1) == 0x0A) {
          i++;
        }
        if (i + 1 < n) {
          bounds.add(i + 1);
        }
      }
    }
    bounds.add(n);

    final forced = switch (direction) {
      null => null,
      TextDirection.ltr => 0,
      TextDirection.rtl => 1,
    };
    final levels = Uint8List(n);
    final paragraphs = <BidiParagraph>[];
    if (forced != 1 && (seen & _raising) == 0) {
      for (var p = 0; p + 1 < bounds.length; p++) {
        paragraphs.add(BidiParagraph(bounds[p], bounds[p + 1], 0));
      }
      return BidiText._(text, paragraphs, levels, classes, true);
    }

    var leftToRight = true;
    for (var p = 0; p + 1 < bounds.length; p++) {
      final start = bounds[p];
      final end = bounds[p + 1];
      // the paragraph by code point
      var m = 0;
      final units = Int32List(end - start + 1);
      final cps = Int32List(end - start);
      final types = Uint8List(end - start);
      for (var i = start; i < end;) {
        var cp = text.codeUnitAt(i);
        units[m] = i;
        types[m] = classes[i];
        i++;
        if (cp >= 0xD800 && cp <= 0xDBFF && i < end) {
          final lo = text.codeUnitAt(i);
          if (lo >= 0xDC00 && lo <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            i++;
          }
        }
        cps[m++] = cp;
      }
      units[m] = end;
      final resolved = _Paragraph(
        Uint8List.sublistView(types, 0, m),
        cps,
        forced,
      );
      paragraphs.add(BidiParagraph(start, end, resolved.level));
      for (var k = 0; k < m; k++) {
        final level = resolved.result[k];
        if (level != 0) {
          leftToRight = false;
        }
        levels.fillRange(units[k], units[k + 1], level);
      }
    }
    return BidiText._(text, paragraphs, levels, classes, leftToRight);
  }

  BidiText._(
    this.text,
    this.paragraphs,
    this.levels,
    this._classes,
    this.isLeftToRight,
  );

  /// The text laid out.
  final String text;

  /// The paragraphs, in order, covering [text]; one for an empty text.
  final List<BidiParagraph> paragraphs;

  /// The resolved embedding level of each code unit, before the line's own
  /// rule L1 ([lineLevels]). A character rule X9 removes (an embedding,
  /// override, PDF or boundary neutral) takes the level of the one before
  /// it, its paragraph's at the start.
  final Uint8List levels;

  /// Whether every level is 0: [text] is drawn as it is stored.
  final bool isLeftToRight;

  /// The Bidi_Class of each code unit.
  final Uint8List _classes;

  /// The paragraph [index] is in; the last one for the end of [text].
  BidiParagraph paragraphAt(int index) {
    var lo = 0;
    var hi = paragraphs.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (paragraphs[mid].start <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return paragraphs[lo];
  }

  /// The levels of the line [start, end), which lies in one paragraph,
  /// after rule L1: separators, and the whitespace and isolate formatting
  /// characters before them and at the end of the line, take the
  /// paragraph's level.
  Uint8List lineLevels(int start, int end) {
    assert(
      start <= end && paragraphAt(start).end >= end,
      'a line lies in one paragraph',
    );
    final out = Uint8List.fromList(Uint8List.sublistView(levels, start, end));
    if (start == end) {
      return out;
    }
    final base = paragraphAt(start).level;
    var reset = true;
    for (var i = end - 1; i >= start; i--) {
      final c = _classes[i];
      if (c == _b || c == _s) {
        out[i - start] = base;
        reset = true;
      } else if (reset && (1 << c & _trailing) != 0) {
        out[i - start] = base;
      } else {
        reset = false;
      }
    }
    return out;
  }

  /// The line [start, end) of a paragraph as runs of one level, in the
  /// order they are drawn from left to right (rule L2).
  List<BidiRun> visualRuns(int start, int end) {
    if (start >= end) {
      return const [];
    }
    final lv = lineLevels(start, end);
    final runs = <BidiRun>[];
    var highest = 0;
    var lowestOdd = _maxDepth + 2;
    var from = 0;
    for (var i = 1; i <= lv.length; i++) {
      if (i < lv.length && lv[i] == lv[from]) {
        continue;
      }
      final level = lv[from];
      runs.add(BidiRun(start + from, start + i, level));
      if (level > highest) {
        highest = level;
      }
      if (level.isOdd && level < lowestOdd) {
        lowestOdd = level;
      }
      from = i;
    }
    for (var level = highest; level >= lowestOdd; level--) {
      for (var i = 0; i < runs.length; i++) {
        if (runs[i].level < level) {
          continue;
        }
        var j = i + 1;
        while (j < runs.length && runs[j].level >= level) {
          j++;
        }
        for (var a = i, b = j - 1; a < b; a++, b--) {
          final t = runs[a];
          runs[a] = runs[b];
          runs[b] = t;
        }
        i = j;
      }
    }
    return runs;
  }

  /// The line [start, end) of a paragraph as it is drawn from left to
  /// right: its [visualRuns], each right-to-left one with its grapheme
  /// clusters reversed and its characters mirrored by [bidiMirror].
  String visual(int start, int end) {
    if (isLeftToRight) {
      return text.substring(start, end);
    }
    final sb = StringBuffer();
    for (final run in visualRuns(start, end)) {
      final part = text.substring(run.start, run.end);
      if (run.level.isEven) {
        sb.write(part);
        continue;
      }
      final clusters = graphemeBoundaries(part).toList();
      for (final (from, to) in clusters.reversed) {
        for (final cp in part.substring(from, to).runes) {
          sb.writeCharCode(bidiMirror(cp));
        }
      }
    }
    return sb.toString();
  }
}

/// One paragraph's levels, resolved from its Bidi_Class [initial] and its
/// code points [cps], one of each per character (rules P2 to I2).
final class _Paragraph {
  _Paragraph(this.initial, this.cps, int? level)
    : n = initial.length,
      types = Uint8List.fromList(initial),
      explicit = Uint8List(initial.length),
      result = Uint8List(initial.length),
      matchingPdi = Int32List(initial.length),
      matchingInitiator = Int32List(initial.length) {
    _matchIsolates();
    this.level = level ?? _firstStrong(0, n);
    _explicitLevels();
    _resolveSequences();
    // the characters X9 removed take the level before them
    for (var i = 0; i < n; i++) {
      if ((1 << initial[i] & _removed) != 0) {
        result[i] = i > 0 ? result[i - 1] : this.level;
      }
    }
  }

  final Uint8List initial;
  final Int32List cps;
  final int n;

  /// The classes as rules X1 to X8 leave them, overrides applied.
  final Uint8List types;

  /// The levels rules X1 to X8 give.
  final Uint8List explicit;

  /// The resolved levels.
  final Uint8List result;

  /// For an isolate initiator, the index of its matching PDI, or [n] when
  /// it has none; -1 for other characters (BD9).
  final Int32List matchingPdi;

  /// For a PDI, the index of its isolate initiator, or -1.
  final Int32List matchingInitiator;

  /// The paragraph embedding level.
  var level = 0;

  void _matchIsolates() {
    final open = Int32List(n);
    var depth = 0;
    for (var i = 0; i < n; i++) {
      final t = initial[i];
      matchingInitiator[i] = -1;
      if ((1 << t & _isolateInitiators) != 0) {
        matchingPdi[i] = n;
        open[depth++] = i;
      } else {
        matchingPdi[i] = -1;
        if (t == _pdi && depth > 0) {
          final j = open[--depth];
          matchingPdi[j] = i;
          matchingInitiator[i] = j;
        }
      }
    }
  }

  /// Rules P2 and P3 over [from, to): 1 when the first strong character
  /// outside isolates is R or AL, otherwise 0.
  int _firstStrong(int from, int to) {
    for (var i = from; i < to; i++) {
      final t = initial[i];
      if (t == _l) {
        return 0;
      }
      if (t == _r || t == _al) {
        return 1;
      }
      if ((1 << t & _isolateInitiators) != 0) {
        i = matchingPdi[i];
      }
    }
    return 0;
  }

  /// Rules X1 to X8.
  void _explicitLevels() {
    final stackLevel = Uint8List(_maxDepth + 2);
    final stackOverride = Uint8List(_maxDepth + 2);
    final stackIsolate = Uint8List(_maxDepth + 2);
    var top = 0;
    stackLevel[0] = level;
    stackOverride[0] = _on;
    var overflowIsolates = 0;
    var overflowEmbeddings = 0;
    var validIsolates = 0;
    for (var i = 0; i < n; i++) {
      final t = initial[i];
      switch (t) {
        case _rle || _lre || _rlo || _lro || _rli || _lri || _fsi:
          // X2 to X5c
          final isolate = (1 << t & _isolateInitiators) != 0;
          final rtl = t == _fsi
              ? _firstStrong(i + 1, matchingPdi[i]) == 1
              : t == _rle || t == _rlo || t == _rli;
          explicit[i] = stackLevel[top];
          if (isolate && stackOverride[top] != _on) {
            types[i] = stackOverride[top];
          }
          final next = rtl
              ? (stackLevel[top] + 1) | 1
              : (stackLevel[top] + 2) & ~1;
          if (next <= _maxDepth &&
              overflowIsolates == 0 &&
              overflowEmbeddings == 0) {
            if (isolate) {
              validIsolates++;
            }
            top++;
            stackLevel[top] = next;
            stackOverride[top] = t == _lro
                ? _l
                : t == _rlo
                ? _r
                : _on;
            stackIsolate[top] = isolate ? 1 : 0;
          } else if (isolate) {
            overflowIsolates++;
          } else if (overflowIsolates == 0) {
            overflowEmbeddings++;
          }
        case _pdi:
          // X6a
          if (overflowIsolates > 0) {
            overflowIsolates--;
          } else if (validIsolates > 0) {
            overflowEmbeddings = 0;
            while (stackIsolate[top] == 0) {
              top--;
            }
            top--;
            validIsolates--;
          }
          explicit[i] = stackLevel[top];
          if (stackOverride[top] != _on) {
            types[i] = stackOverride[top];
          }
        case _pdf:
          // X7
          if (overflowIsolates > 0) {
            // within an overflowing isolate
          } else if (overflowEmbeddings > 0) {
            overflowEmbeddings--;
          } else if (stackIsolate[top] == 0 && top > 0) {
            top--;
          }
          explicit[i] = stackLevel[top];
        case _b:
          // X8: a paragraph separator ends the paragraph
          explicit[i] = level;
        case _bn:
          explicit[i] = stackLevel[top];
        default:
          // X6
          explicit[i] = stackLevel[top];
          if (stackOverride[top] != _on) {
            types[i] = stackOverride[top];
          }
      }
    }
  }

  /// Rule X10: the isolating run sequences, each resolved in turn.
  void _resolveSequences() {
    final kept = Int32List(n);
    var m = 0;
    for (var i = 0; i < n; i++) {
      if ((1 << initial[i] & _removed) == 0) {
        kept[m++] = i;
      }
    }
    if (m == 0) {
      return;
    }
    // level runs: [runStart[r], runStart[r + 1]) of kept
    final runStart = Int32List(m + 1);
    final runOf = Int32List(n);
    var runs = 0;
    for (var k = 0; k < m; k++) {
      if (k == 0 || explicit[kept[k]] != explicit[kept[k - 1]]) {
        runStart[runs++] = k;
      }
      runOf[kept[k]] = runs - 1;
    }
    runStart[runs] = m;

    final sequence = Int32List(m);
    for (var r = 0; r < runs; r++) {
      final first = kept[runStart[r]];
      if (initial[first] == _pdi && matchingInitiator[first] >= 0) {
        continue; // it continues the sequence of its isolate initiator
      }
      var length = 0;
      for (var run = r; ;) {
        for (var k = runStart[run]; k < runStart[run + 1]; k++) {
          sequence[length++] = kept[k];
        }
        final pdi = matchingPdi[sequence[length - 1]];
        if (pdi < 0 || pdi == n) {
          break;
        }
        run = runOf[pdi];
      }
      _resolveSequence(Int32List.sublistView(sequence, 0, length));
    }
  }

  /// Rules W1 to I2 for the isolating run sequence [seq].
  void _resolveSequence(Int32List seq) {
    final len = seq.length;
    final embedding = explicit[seq[0]];
    var before = seq[0] - 1;
    while (before >= 0 && (1 << initial[before] & _removed) != 0) {
      before--;
    }
    final levelBefore = before >= 0 ? explicit[before] : level;
    final sos = (levelBefore > embedding ? levelBefore : embedding).isOdd
        ? _r
        : _l;
    final last = seq[len - 1];
    var levelAfter = level;
    if ((1 << initial[last] & _isolateInitiators) == 0) {
      var after = last + 1;
      while (after < n && (1 << initial[after] & _removed) != 0) {
        after++;
      }
      if (after < n) {
        levelAfter = explicit[after];
      }
    }
    final eos = (levelAfter > embedding ? levelAfter : embedding).isOdd
        ? _r
        : _l;

    final t = Uint8List(len);
    var brackets = false;
    for (var k = 0; k < len; k++) {
      t[k] = types[seq[k]];
      if (t[k] == _on) {
        brackets = true;
      }
    }

    // W1: a nonspacing mark takes the class before it
    var prev = sos;
    for (var k = 0; k < len; k++) {
      final c = t[k];
      if (c == _nsm) {
        t[k] = prev;
      } else {
        prev = (1 << c & (_isolateInitiators | 1 << _pdi)) != 0 ? _on : c;
      }
    }
    // W2: a European number after Arabic letters is an Arabic number
    var strong = sos;
    for (var k = 0; k < len; k++) {
      final c = t[k];
      if (c == _l || c == _r || c == _al) {
        strong = c;
      } else if (c == _en && strong == _al) {
        t[k] = _an;
      }
    }
    // W3
    for (var k = 0; k < len; k++) {
      if (t[k] == _al) {
        t[k] = _r;
      }
    }
    // W4: one separator between two numbers of a kind
    for (var k = 1; k < len - 1; k++) {
      final c = t[k];
      if (c != _es && c != _cs) {
        continue;
      }
      final a = t[k - 1];
      final b = t[k + 1];
      if (a == _en && b == _en) {
        t[k] = _en;
      } else if (c == _cs && a == _an && b == _an) {
        t[k] = _an;
      }
    }
    // W5: terminators next to a European number
    for (var k = 0; k < len; k++) {
      if (t[k] != _et) {
        continue;
      }
      var end = k + 1;
      while (end < len && t[end] == _et) {
        end++;
      }
      if ((k > 0 ? t[k - 1] : sos) == _en ||
          (end < len ? t[end] : eos) == _en) {
        t.fillRange(k, end, _en);
      }
      k = end;
    }
    // W6
    for (var k = 0; k < len; k++) {
      final c = t[k];
      if (c == _es || c == _et || c == _cs) {
        t[k] = _on;
      }
    }
    // W7: a European number after L is L
    strong = sos;
    for (var k = 0; k < len; k++) {
      final c = t[k];
      if (c == _l || c == _r) {
        strong = c;
      } else if (c == _en && strong == _l) {
        t[k] = _l;
      }
    }

    final e = embedding.isOdd ? _r : _l;
    if (brackets) {
      _pairBrackets(seq, t, sos, e);
    }

    // N1, N2
    for (var k = 0; k < len; k++) {
      if ((1 << t[k] & _neutrals) == 0) {
        continue;
      }
      var end = k + 1;
      while (end < len && (1 << t[end] & _neutrals) != 0) {
        end++;
      }
      var a = k > 0 ? t[k - 1] : sos;
      if (a == _en || a == _an) {
        a = _r;
      }
      var b = end < len ? t[end] : eos;
      if (b == _en || b == _an) {
        b = _r;
      }
      t.fillRange(k, end, a == b ? a : e);
      k = end;
    }

    // I1, I2
    for (var k = 0; k < len; k++) {
      final c = t[k];
      var lv = embedding;
      if (embedding.isEven) {
        if (c == _r) {
          lv += 1;
        } else if (c == _an || c == _en) {
          lv += 2;
        }
      } else if (c != _r) {
        lv += 1;
      }
      result[seq[k]] = lv;
    }
  }

  /// Rule N0: bracket pairs (BD16) of the sequence [seq], whose classes
  /// are [t], take the direction of what they enclose; [e] is the
  /// embedding direction.
  void _pairBrackets(Int32List seq, Uint8List t, int sos, int e) {
    final openAt = Int32List(_maxBrackets);
    final openKey = Int32List(_maxBrackets);
    var depth = 0;
    final pairs = <(int, int)>[];
    for (var k = 0; k < seq.length; k++) {
      if (t[k] != _on) {
        continue;
      }
      final cp = cps[seq[k]];
      final i = _find(bidiBrackets, 3, cp);
      if (i < 0) {
        continue;
      }
      if (bidiBrackets[i + 2] == 1) {
        if (depth == _maxBrackets) {
          break;
        }
        openAt[depth] = k;
        openKey[depth++] = _canonical(cp);
      } else {
        final key = _canonical(bidiBrackets[i + 1]);
        for (var d = depth - 1; d >= 0; d--) {
          if (openKey[d] == key) {
            pairs.add((openAt[d], k));
            depth = d;
            break;
          }
        }
      }
    }
    if (pairs.isEmpty) {
      return;
    }
    pairs.sort((a, b) => a.$1 - b.$1);

    for (final (open, close) in pairs) {
      var dir = _on;
      for (var k = open + 1; k < close; k++) {
        final s = _strong(t[k]);
        if (s == _on) {
          continue;
        }
        dir = s;
        if (s == e) {
          break;
        }
      }
      if (dir == _on) {
        continue; // N0 d: nothing strong inside
      }
      if (dir != e) {
        // N0 c: only the opposite direction inside; the context decides
        var context = sos;
        for (var k = open - 1; k >= 0; k--) {
          final s = _strong(t[k]);
          if (s != _on) {
            context = s;
            break;
          }
        }
        if (context != dir) {
          dir = e;
        }
      }
      t[open] = dir;
      t[close] = dir;
      // marks after a bracket follow it
      for (var k = open + 1; k < seq.length && initial[seq[k]] == _nsm; k++) {
        t[k] = dir;
      }
      for (var k = close + 1; k < seq.length && initial[seq[k]] == _nsm; k++) {
        t[k] = dir;
      }
    }
  }
}

/// The direction class [c] counts as in rule N0: numbers are R.
int _strong(int c) => switch (c) {
  _l => _l,
  _r || _al || _en || _an => _r,
  _ => _on,
};

/// [cp] with the two brackets that have canonical equivalents replaced by
/// them (BD16).
int _canonical(int cp) => switch (cp) {
  0x2329 => 0x3008,
  0x232A => 0x3009,
  _ => cp,
};
