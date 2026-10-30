/// Unicode support for the terminal core: property lookup, extended grapheme
/// cluster segmentation (UAX #29, [TextSegmenter], [graphemeBoundaries])
/// and terminal column widths ([stringWidth], [TextSegmenter.width],
/// [codePointWidth], [fitText]); the
/// bidirectional algorithm (UAX #9) is in bidi.dart.
///
/// No allocation on the hot path: properties come from flat byte tables
/// (direct lookup below U+20000, binary search above), and segmentation works
/// on UTF-16 indices of the caller's string.
///
/// @docImport '../canvas.dart';
library;

import 'dart:typed_data';

import 'tables.g.dart';

export 'tables.g.dart' show unicodeVersion;

/// Grapheme_Cluster_Break=Other: a code point of none of the classes
/// below. The values are the low 4 bits of [segmentationProperty].
const gcbOther = 0;

/// Grapheme_Cluster_Break=CR, carriage return.
const gcbCR = 1;

/// Grapheme_Cluster_Break=LF, line feed.
const gcbLF = 2;

/// Grapheme_Cluster_Break=Control: other controls, separators and lone
/// surrogates.
const gcbControl = 3;

/// Grapheme_Cluster_Break=Extend: combining marks, variation selectors,
/// emoji modifiers, which join the cluster before them.
const gcbExtend = 4;

/// Grapheme_Cluster_Break=ZWJ, the zero width joiner of emoji sequences.
const gcbZWJ = 5;

/// Grapheme_Cluster_Break=Regional_Indicator: flag letters, joined in
/// pairs.
const gcbRegionalIndicator = 6;

/// Grapheme_Cluster_Break=Prepend, which joins the cluster after it.
const gcbPrepend = 7;

/// Grapheme_Cluster_Break=SpacingMark, which joins the cluster before it.
const gcbSpacingMark = 8;

/// Grapheme_Cluster_Break=L, a Hangul leading consonant jamo.
const gcbL = 9;

/// Grapheme_Cluster_Break=V, a Hangul vowel jamo.
const gcbV = 10;

/// Grapheme_Cluster_Break=T, a Hangul trailing consonant jamo.
const gcbT = 11;

/// Grapheme_Cluster_Break=LV, a Hangul syllable of a leading consonant
/// and a vowel.
const gcbLV = 12;

/// Grapheme_Cluster_Break=LVT, a Hangul syllable of a leading consonant,
/// a vowel and a trailing consonant.
const gcbLVT = 13;

const _segExtPict = 0x10;
const _incbShift = 5;
const _incbLinker = 1;
const _incbConsonant = 2;
const _incbExtend = 3;

// Width byte layout.
const _wClassMask = 0x03; // 0 zero, 1 narrow, 2 wide, 3 ambiguous
const _wEmojiPresentation = 0x04;
const _wEmoji = 0x08;

const _direct = 0x20000;

final Uint8List _segTable = _expand(segmentationRanges);
final Uint8List _widthTable = _expand(widthRanges);
final Int32List _segHigh = _high(segmentationRanges);
final Int32List _widthHigh = _high(widthRanges);

Uint8List _expand(List<int> ranges) {
  final t = Uint8List(_direct);
  for (var i = 0; i < ranges.length; i += 3) {
    final lo = ranges[i];
    if (lo >= _direct) {
      break;
    }
    final hi = ranges[i + 1] < _direct ? ranges[i + 1] : _direct - 1;
    // fillRange is an element loop; long ranges double with setRange (memmove)
    final v = ranges[i + 2];
    final n = hi + 1 - lo;
    if (n <= 64) {
      for (var k = lo; k <= hi; k++) {
        t[k] = v;
      }
    } else {
      for (var k = lo; k < lo + 32; k++) {
        t[k] = v;
      }
      for (var done = 32; done < n;) {
        final c = done < n - done ? done : n - done;
        t.setRange(lo + done, lo + done + c, t, lo);
        done += c;
      }
    }
  }
  return t;
}

/// Ranges at or above U+20000, as a flat Int32List for binary search.
Int32List _high(List<int> ranges) {
  final out = <int>[];
  for (var i = 0; i < ranges.length; i += 3) {
    if (ranges[i + 1] < _direct) {
      continue;
    }
    out
      ..add(ranges[i] < _direct ? _direct : ranges[i])
      ..add(ranges[i + 1])
      ..add(ranges[i + 2]);
  }
  return Int32List.fromList(out);
}

int _lookupHigh(Int32List t, int cp) {
  var lo = 0;
  var hi = t.length ~/ 3 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final i = mid * 3;
    if (cp < t[i]) {
      hi = mid - 1;
    } else if (cp > t[i + 1]) {
      lo = mid + 1;
    } else {
      return t[i + 2];
    }
  }
  return 0;
}

/// A byte-sized property of every code point, from flat [start, end, value]
/// triples (inclusive, sorted; code points left out are 0), looked up as
/// [segmentationProperty] and [widthProperty] are.
final class CodePointTable {
  /// A table of the values [ranges] gives: `start, end, value` triples,
  /// inclusive and sorted by start.
  CodePointTable(List<int> ranges)
    : _low = _expand(ranges),
      _highRanges = _high(ranges);

  final Uint8List _low;
  final Int32List _highRanges;

  /// The value of [cp].
  @pragma('vm:prefer-inline')
  int operator [](int cp) =>
      cp < _direct ? _low[cp] : _lookupHigh(_highRanges, cp);
}

/// The segmentation byte of [cp]: its Grapheme_Cluster_Break in the low 4
/// bits (one of [gcbOther] to [gcbLVT]), Extended_Pictographic in bit 4
/// and Indic_Conjunct_Break above.
@pragma('vm:prefer-inline')
int segmentationProperty(int cp) =>
    cp < _direct ? _segTable[cp] : _lookupHigh(_segHigh, cp);

/// The width byte of [cp]: its width class in the low 2 bits (0 zero,
/// 1 narrow, 2 wide, 3 East Asian Ambiguous), Emoji_Presentation in bit
/// 2 and Emoji in bit 3.
///
/// [codePointWidth] reads the width it makes.
@pragma('vm:prefer-inline')
int widthProperty(int cp) =>
    cp < _direct ? _widthTable[cp] : _lookupHigh(_widthHigh, cp);

/// Column width of a single code point (0, 1 or 2; ambiguous resolved by
/// [ambiguousWidth]).
@pragma('vm:prefer-inline')
int codePointWidth(int cp, [int ambiguousWidth = 1]) {
  final c = widthProperty(cp) & _wClassMask;
  return c == 3 ? ambiguousWidth : c;
}

/// Whether terminals disagree about the width of [cp] drawn on its own.
@pragma('vm:prefer-inline')
bool codePointUncertain(int cp) =>
    cp > 0xFF && (widthProperty(cp) & (_wEmoji | _wEmojiPresentation)) != 0;

/// The widest a terminal may render the code points of a cluster when it
/// does not join them (sum of per-code-point widths, emoji counted as 2).
int maxRenderWidth(String s, int start, int end) {
  var w = 0;
  for (var i = start; i < end;) {
    final cp = _cpAt(s, i);
    i += cp > 0xFFFF ? 2 : 1;
    final p = widthProperty(cp);
    final c = p & _wClassMask;
    if ((p & (_wEmoji | _wEmojiPresentation)) != 0 && cp > 0xFF) {
      w += 2;
    } else if (c == 3) {
      w += 2;
    } else {
      w += c;
    }
  }
  return w;
}

/// How text is split into terminal cells.
enum TextMode {
  /// UAX #29 extended grapheme clusters; emoji sequences (ZWJ, flags, VS16,
  /// skin tones) occupy one 2-column cell. Matches terminals that implement
  /// grapheme clustering (DEC mode 2027: Ghostty, WezTerm, Contour, foot,
  /// Windows Terminal >= 1.22, kitty's own rules are close to this).
  graphemes,

  /// wcwidth-style: every code point with a non-zero width starts a new cell,
  /// zero-width code points attach to the previous one. Matches xterm, VTE,
  /// Konsole, Alacritty, Terminal.app, conhost.
  legacy,
}

/// Result of scanning one cluster; reused to avoid allocation.
final class ClusterScan {
  /// A scan with nothing found yet, for [TextSegmenter.scan] to fill.
  ClusterScan();

  /// UTF-16 index one past the cluster.
  var end = 0;

  /// First code point of the cluster. A lone surrogate is reported as itself
  /// (it is a zero-width control and never drawn).
  var first = 0;

  /// Number of code points in the cluster.
  var length = 0;

  /// Terminal columns (0, 1 or 2). 0 means the cluster should not be drawn
  /// (a control character, or a zero-width mark without a base); see
  /// [isLeadingMark] for the marks with a width the canvas drops too.
  var width = 0;

  /// Whether terminals are known to disagree about this cluster's width
  /// (emoji, multi-code-point clusters with several spacing characters,
  /// presentation selectors; not ambiguous width, which is configured). The
  /// encoder re-synchronises the cursor after such a cluster so a
  /// disagreement can't shift the row.
  var uncertain = false;

  /// Grapheme_Cluster_Break of [first] (control detection).
  var firstGcb = 0;

  /// Grapheme mode: a code point printed right after this cluster could be
  /// joined to it by a terminal that clusters graphemes (the cluster ends
  /// with a virama/linker, an emoji ZWJ, a Prepend, a Hangul L jamo, or is a
  /// lone regional indicator). The next cell must not be printed
  /// contiguously.
  var joinsNext = false;
}

/// Segments text into terminal cells and computes their widths.
///
/// [scan] reads one cluster at a time into a [ClusterScan] the caller
/// keeps, so walking a string allocates nothing. A canvas draws text with
/// one, and layout measures it with the same, so the two agree on every
/// width.
///
/// The clusters of a string and their widths:
///
/// ```dart
/// final segmenter = TextSegmenter();
/// final scan = ClusterScan();
/// const text = 'e\u0301🇺🇦';
/// for (var i = 0; i < text.length; i = scan.end) {
///   segmenter.scan(text, i, scan);
///   print('${text.substring(i, scan.end)}: ${scan.width}'); // é: 1, 🇺🇦: 2
/// }
/// ```
///
/// See also:
///
///  * [width] and [stringWidth], the columns of a whole string.
///  * [fitText], a string cut off with `…` to a number of columns.
///  * [graphemeBoundaries], the clusters of a string as pairs of indices.
final class TextSegmenter {
  /// A segmenter in [mode], graphemes by default, that takes East Asian
  /// Ambiguous characters as [ambiguousWidth] columns, 1 or 2.
  TextSegmenter({this.mode = TextMode.graphemes, this.ambiguousWidth = 1})
    : assert(
        ambiguousWidth == 1 || ambiguousWidth == 2,
        'ambiguousWidth is 1 or 2 columns',
      );

  /// How text is split into cells: as the terminal does.
  TextMode mode;

  /// Width used for East Asian Ambiguous characters (2 in CJK locales).
  int ambiguousWidth;

  /// Columns [s] takes when drawn ([Canvas.text]) with this segmenter: as
  /// [stringWidth] measures it in [mode], East Asian Ambiguous characters
  /// [ambiguousWidth] columns each. Layout that measures with the
  /// segmenter of the canvas (`PipelineOwner.segmenter`) gets the columns
  /// the terminal draws, `│` and `…` two of them where it takes those as
  /// wide.
  ///
  /// ```dart
  /// print(TextSegmenter().width('a │ b')); // 5
  /// print(TextSegmenter(ambiguousWidth: 2).width('a │ b')); // 6
  /// ```
  int width(String s) => _columns(this, s);

  /// Scans the cluster that starts at [start] (which must be < s.length).
  @pragma('vm:prefer-inline')
  void scan(String s, int start, ClusterScan out) {
    final c0 = s.codeUnitAt(start);
    // ASCII fast path: printable ASCII is its own cluster unless the next
    // code unit could extend it (every Extend/SpacingMark/ZWJ is >= U+0300).
    if (c0 >= 0x20 && c0 < 0x7F) {
      final n = start + 1;
      if (n == s.length || s.codeUnitAt(n) < 0x300) {
        out
          ..end = n
          ..first = c0
          ..length = 1
          ..width = 1
          ..uncertain = false
          ..firstGcb = gcbOther
          ..joinsNext = false;
        return;
      }
    }
    if (mode == TextMode.graphemes) {
      // BMP fast path: a letter or an ideograph that is Other, with no
      // Extended_Pictographic or Indic_Conjunct_Break, is its own cluster
      // unless the code unit after it extends it (Extend, ZWJ,
      // SpacingMark) or is a surrogate, which the full scan looks at
      if (c0 >= 0x80 && (c0 < 0xD800 || c0 > 0xDFFF)) {
        if ((_segTable[c0] & 0xFF) == 0) {
          final n = start + 1;
          var alone = n == s.length;
          if (!alone) {
            final c1 = s.codeUnitAt(n);
            if (c1 < 0xD800 || c1 > 0xDFFF) {
              final g = _segTable[c1] & 0x0F;
              alone = g != gcbExtend && g != gcbZWJ && g != gcbSpacingMark;
            }
          }
          if (alone) {
            final wp = _widthTable[c0];
            final cls = wp & _wClassMask;
            out
              ..end = n
              ..first = c0
              ..length = 1
              ..width = cls == 3 ? ambiguousWidth : cls
              ..uncertain =
                  c0 > 0xFF && (wp & (_wEmoji | _wEmojiPresentation)) != 0
              ..firstGcb = gcbOther
              ..joinsNext = false;
            return;
          }
        }
      }
      _scanGrapheme(s, start, out);
    } else {
      _scanLegacy(s, start, out);
    }
  }

  void _scanGrapheme(String s, int start, ClusterScan out) {
    final len = s.length;
    var i = start;
    var cp = s.codeUnitAt(i++);
    if (cp >= 0xD800 && cp <= 0xDBFF && i < len) {
      final lo = s.codeUnitAt(i);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
        i++;
      }
    }
    final first = cp;
    final prop = segmentationProperty(cp);
    var prev = prop & 0x0F;
    final firstGcb = prev;
    var count = 1;

    // GB11 state: 0 none, 1 after ExtPict Extend*, 2 after ExtPict Extend* ZWJ
    var emoji = (prop & _segExtPict) != 0 ? 1 : 0;
    // GB9c state: after InCB=Linker InCB=Extend*
    var linker = ((prop >> _incbShift) & 3) == _incbLinker;
    var riCount = prev == gcbRegionalIndicator ? 1 : 0;

    // width accumulation
    var spacing = (widthProperty(cp) & _wClassMask) != 0 ? 1 : 0;
    var hasVS16 = false;
    var hasVS15 = false;
    var hasZWJ = false;

    while (i < len) {
      var next = s.codeUnitAt(i);
      var step = 1;
      if (next >= 0xD800 && next <= 0xDBFF && i + 1 < len) {
        final lo = s.codeUnitAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          next = 0x10000 + ((next - 0xD800) << 10) + (lo - 0xDC00);
          step = 2;
        }
      }
      final p = segmentationProperty(next);
      final g = p & 0x0F;

      // ---- UAX #29 rules, in order ----
      bool join;
      if (prev == gcbCR && g == gcbLF) {
        join = true; // GB3
      } else if (prev == gcbControl || prev == gcbCR || prev == gcbLF) {
        join = false; // GB4
      } else if (g == gcbControl || g == gcbCR || g == gcbLF) {
        join = false; // GB5
      } else if (prev == gcbL &&
          (g == gcbL || g == gcbV || g == gcbLV || g == gcbLVT)) {
        join = true; // GB6
      } else if ((prev == gcbLV || prev == gcbV) && (g == gcbV || g == gcbT)) {
        join = true; // GB7
      } else if ((prev == gcbLVT || prev == gcbT) && g == gcbT) {
        join = true; // GB8
      } else if (g == gcbExtend || g == gcbZWJ) {
        join = true; // GB9
      } else if (g == gcbSpacingMark) {
        join = true; // GB9a
      } else if (prev == gcbPrepend) {
        join = true; // GB9b
      } else if (linker && ((p >> _incbShift) & 3) == _incbConsonant) {
        join = true; // GB9c
      } else if (emoji == 2 && (p & _segExtPict) != 0) {
        join = true; // GB11
      } else if (prev == gcbRegionalIndicator &&
          g == gcbRegionalIndicator &&
          riCount.isOdd) {
        join = true; // GB12, GB13
      } else {
        join = false; // GB999
      }
      if (!join) {
        break;
      }

      // ---- state update ----
      if ((p & _segExtPict) != 0) {
        emoji = 1;
      } else if (g == gcbExtend && emoji == 1) {
        emoji = 1;
      } else if (g == gcbZWJ && emoji == 1) {
        emoji = 2;
      } else {
        emoji = 0;
      }
      final incb = (p >> _incbShift) & 3;
      if (incb == _incbLinker) {
        linker = true;
      } else if (incb != _incbExtend) {
        linker = false;
      }
      riCount = g == gcbRegionalIndicator ? riCount + 1 : 0;
      if (next == 0xFE0F) {
        hasVS16 = true;
      } else if (next == 0xFE0E) {
        hasVS15 = true;
      } else if (g == gcbZWJ) {
        hasZWJ = true;
      }
      if ((widthProperty(next) & _wClassMask) != 0) {
        spacing++;
      }

      prev = g;
      count++;
      i += step;
    }

    out
      ..end = i
      ..first = first
      ..length = count
      ..firstGcb = firstGcb
      ..joinsNext =
          linker ||
          emoji == 2 ||
          prev == gcbPrepend ||
          prev == gcbL ||
          riCount.isOdd;
    _clusterWidth(s, start, i, out, spacing, hasVS16, hasVS15, hasZWJ);
  }

  void _clusterWidth(
    String s,
    int start,
    int end,
    ClusterScan out,
    int spacing,
    bool vs16,
    bool vs15,
    bool zwj,
  ) {
    final first = out.first;
    final g = out.firstGcb;
    if (g == gcbControl || g == gcbCR || g == gcbLF) {
      out
        ..width = 0
        ..uncertain = false;
      return;
    }
    final wp = widthProperty(first);
    var cls = wp & _wClassMask;
    // Ambiguous width is resolved by configuration ([ambiguousWidth]), so it
    // is not treated as uncertain; emoji widths genuinely vary by terminal.
    var uncertain = (wp & (_wEmoji | _wEmojiPresentation)) != 0;
    if (cls == 3) {
      cls = ambiguousWidth;
    }
    if (out.length == 1) {
      out
        ..width = cls
        ..uncertain = uncertain && first > 0xFF; // (c), (r) are safe
      return;
    }
    int w;
    if (vs16 && (wp & _wEmoji) != 0) {
      w = 2;
      uncertain = true;
    } else if (g == gcbRegionalIndicator) {
      w = 2; // a flag (or a lone RI followed by marks)
      uncertain = true;
    } else if (zwj && (segmentationProperty(first) & _segExtPict) != 0) {
      w = 2;
      uncertain = true;
    } else {
      // Width of the first spacing code point (Prepend + base, Hangul L V T,
      // base + combining marks, Indic conjuncts).
      w = cls;
      if (w == 0) {
        for (var i = start; i < end;) {
          final cp = _cpAt(s, i);
          i += cp > 0xFFFF ? 2 : 1;
          final c = widthProperty(cp) & _wClassMask;
          if (c != 0) {
            w = c == 3 ? ambiguousWidth : c;
            break;
          }
        }
      }
      if (spacing > 1 || vs15 || vs16) {
        uncertain = true;
      }
    }
    out
      ..width = w
      ..uncertain = uncertain;
  }

  void _scanLegacy(String s, int start, ClusterScan out) {
    final len = s.length;
    var i = start;
    final first = _cpAt(s, i);
    i += first > 0xFFFF ? 2 : 1;
    final firstGcb = segmentationProperty(first) & 0x0F;
    var count = 1;
    final isControl =
        firstGcb == gcbControl || firstGcb == gcbCR || firstGcb == gcbLF;
    if (!isControl) {
      // attach following zero-width, non-control code points
      while (i < len) {
        final cp = _cpAt(s, i);
        if ((widthProperty(cp) & _wClassMask) != 0) {
          break;
        }
        final g = segmentationProperty(cp) & 0x0F;
        if (g == gcbControl || g == gcbCR || g == gcbLF) {
          break;
        }
        i += cp > 0xFFFF ? 2 : 1;
        count++;
      }
    }
    final wp = widthProperty(first);
    var cls = isControl ? 0 : wp & _wClassMask;
    final uncertain =
        ((wp & (_wEmoji | _wEmojiPresentation)) != 0 && first > 0xFF) ||
        count > 1 && (wp & _wEmoji) != 0;
    if (cls == 3) {
      cls = ambiguousWidth;
    }
    out
      ..end = i
      ..first = first
      ..length = count
      ..width = cls
      ..uncertain = uncertain
      ..firstGcb = firstGcb
      ..joinsNext = false;
  }
}

/// Code point at UTF-16 index [i]; a lone surrogate is returned as is.
@pragma('vm:prefer-inline')
int _cpAt(String s, int i) {
  final c = s.codeUnitAt(i);
  if (c < 0xD800 || c > 0xDFFF) {
    return c;
  }
  if (c <= 0xDBFF && i + 1 < s.length) {
    final lo = s.codeUnitAt(i + 1);
    if (lo >= 0xDC00 && lo <= 0xDFFF) {
      return 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
    }
  }
  return c;
}

/// Iterates the extended grapheme clusters of [s] as (start, end) pairs.
/// Convenience API for tests and non-hot paths.
Iterable<(int, int)> graphemeBoundaries(String s) sync* {
  final seg = TextSegmenter();
  final scan = ClusterScan();
  var i = 0;
  while (i < s.length) {
    seg._scanGrapheme(s, i, scan);
    yield (i, scan.end);
    i = scan.end;
  }
}

/// Grapheme mode: a cluster that *starts* with a mark (Extend, ZWJ,
/// SpacingMark) or a zero-width code point has no base - e.g. its base
/// character was deleted. Such leading code points are not drawn: a
/// grapheme-clustering terminal would join them to the cell on the left,
/// damaging a neighbour that no cursor re-sync can protect. (In legacy
/// mode a spacing mark is an ordinary cell and zero-width code points
/// always belong to the cluster before them.)
@pragma('vm:prefer-inline')
bool isLeadingMark(int cp) {
  final g = segmentationProperty(cp) & 0x0F;
  return g == gcbExtend ||
      g == gcbZWJ ||
      g == gcbSpacingMark ||
      codePointWidth(cp) == 0;
}

final _widthSegmenter = TextSegmenter();
final _widthScan = ClusterScan();

/// Columns [s] takes when drawn ([Canvas.text]) under [mode]: a tab is one
/// blank, other controls take none, and in grapheme mode a mark without a
/// base is dropped.
///
/// [ambiguousWidth] is the width of East Asian Ambiguous characters, 1 or
/// 2.
///
/// ```dart
/// print(stringWidth('héllo')); // 5
/// print(stringWidth('你好')); // 4
/// print(stringWidth('👍🏽')); // 2: an emoji and its skin tone, one cluster
/// ```
///
/// See also:
///
///  * [TextSegmenter.width], the same with a segmenter's mode and
///    ambiguous width: those of the terminal, where it is the canvas's.
int stringWidth(
  String s, {
  TextMode mode = TextMode.graphemes,
  int ambiguousWidth = 1,
}) {
  assert(
    ambiguousWidth == 1 || ambiguousWidth == 2,
    'ambiguousWidth is 1 or 2 columns',
  );
  // stringWidth calls nothing that could call it again, so one segmenter
  // serves every call: asserted, so that a change that makes it do so
  // fails here rather than measuring with another call's settings
  assert(!_measuring, 'stringWidth called within itself');
  assert(() {
    _measuring = true;
    return true;
  }(), 'stringWidth begins');
  final seg = _widthSegmenter
    ..mode = mode
    ..ambiguousWidth = ambiguousWidth;
  final columns = _columns(seg, s);
  assert(() {
    _measuring = false;
    return true;
  }(), 'stringWidth ends');
  return columns;
}

// whether stringWidth runs, with asserts
var _measuring = false;

/// The columns [s] takes when drawn with [seg], as [stringWidth] says.
@pragma('vm:prefer-inline')
int _columns(TextSegmenter seg, String s) {
  // ASCII: a printable character and a tab take a column, other controls
  // none, in either mode (nothing below U+0300 extends a cluster)
  var w = 0;
  var last = 0; // w before the last character
  var i = 0;
  for (; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x80) {
      break;
    }
    last = w;
    if ((c >= 0x20 && c < 0x7F) || c == 0x09) {
      w++;
    }
  }
  if (i == s.length) {
    return w;
  }
  // a cluster starts at the last ASCII character, which the character
  // after it may extend (but for the LF of a CR LF: no columns either way)
  if (i > 0) {
    i--;
    w = last;
  }
  final scan = _widthScan;
  final graphemes = seg.mode == TextMode.graphemes;
  for (; i < s.length;) {
    final start = i;
    seg.scan(s, i, scan);
    i = scan.end;
    if (scan.width == 0) {
      if (scan.first == 0x09) {
        w++;
      }
    } else if (graphemes && isLeadingMark(scan.first)) {
      // re-segment what follows the dropped mark
      i = start + (scan.first > 0xFFFF ? 2 : 1);
    } else {
      w += scan.width;
    }
  }
  return w;
}

/// [text] cut off at its end to fit [width] columns as [segmenter]
/// measures them ([TextSegmenter.width]), `…` in place of what is cut:
/// [text] itself where it fits; else the clusters that fit before the
/// ellipsis and the ellipsis, which takes the columns of an East Asian
/// Ambiguous character ([TextSegmenter.ambiguousWidth]), as on a line
/// that `RenderParagraph` cuts with `TextOverflow.ellipsis`; where the
/// ellipsis does not fit either, the clusters that fit, with none, as
/// there; and nothing at all for a [width] of 0 or less. No cluster is
/// split, and blanks before the ellipsis are kept.
///
/// ```dart
/// final narrow = TextSegmenter();
/// print(fitText(narrow, 'Warnings (12)', 8)); // Warning…
/// final cjk = TextSegmenter(ambiguousWidth: 2);
/// print(fitText(cjk, 'Warnings (12)', 8)); // Warnin…
/// print(fitText(cjk, 'Warnings (12)', 1)); // W
/// ```
String fitText(TextSegmenter segmenter, String text, int width) {
  if (_columns(segmenter, text) <= width) {
    return text;
  }
  if (width <= 0) {
    return '';
  }
  final ellipsis = codePointWidth(0x2026, segmenter.ambiguousWidth);
  final room = width < ellipsis ? width : width - ellipsis;
  final graphemes = segmenter.mode == TextMode.graphemes;
  final scan = _widthScan;
  var w = 0;
  var end = 0;
  for (var i = 0; i < text.length;) {
    final start = i;
    segmenter.scan(text, i, scan);
    i = scan.end;
    var cells = scan.width;
    if (cells == 0) {
      cells = scan.first == 0x09 ? 1 : 0;
    } else if (graphemes && isLeadingMark(scan.first)) {
      i = start + (scan.first > 0xFFFF ? 2 : 1);
      cells = 0;
    }
    if (w + cells > room) {
      break;
    }
    w += cells;
    end = i;
  }
  final kept = text.substring(0, end);
  return width < ellipsis ? kept : '$kept…';
}
