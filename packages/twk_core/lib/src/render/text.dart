part of 'render.dart';

// ------------------------------------------------------------------ text --

/// One line of text in one pen (shaped once per change, not per frame),
/// cut off at its right edge; [RenderParagraph] breaks text into lines. As
/// a repaint boundary it fills its bounds with [pen] first, which then
/// needs an opaque background.
///
/// It is as wide as its constraints allow and one row tall
/// ([sizedByParent]); its intrinsic width is the columns the canvas draws
/// its text in. It is drawn as stored in either [TextOrder].
///
/// ```dart
/// final styles = StyleTable();
/// final status = RenderText('Ready', styles.pen(const Pen()));
/// status.text = 'Saving…'; // laid out and painted on the next frame
/// ```
final class RenderText extends RenderObject {
  /// Shows [text] in the pen whose id is [pen]; a repaint boundary when
  /// [boundary] is set.
  RenderText(this._text, this._pen, {this.boundary = false});

  String _text;
  int _pen;

  /// The id of the pen the text is drawn in, in the style table it is
  /// painted with; a new one only repaints it.
  int get pen => _pen;
  set pen(int p) {
    if (p != _pen) {
      _pen = p;
      markNeedsPaint();
    }
  }

  /// Whether it is a repaint boundary ([isRepaintBoundary]), which fills
  /// its bounds with [pen] before the text. False by default.
  final bool boundary;
  GlyphRun? _run;

  /// The line shown; new text is shaped again and laid out again, with a
  /// parent that asked how wide it is.
  String get text => _text;
  set text(String t) {
    if (t == _text) {
      return;
    }
    _text = t;
    _run = null;
    // laying it out repaints it; a parent that asked how wide it is is
    // laid out too
    markNeedsLayout();
  }

  @override
  bool get isRepaintBoundary => boundary;

  @override
  bool get sizedByParent => true;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addValue(_text)
      ..add('pen', _pen);
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.constrainH(1);
  }

  // one line, as wide as the canvas draws it: no line break splits it, so
  // the narrowest and the widest it can use agree

  @override
  int computeMinIntrinsicWidth(int height) => _textWidth(this, _text);

  @override
  int computeMaxIntrinsicWidth(int height) => _textWidth(this, _text);

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void paint(PaintContext ctx) {
    if (boundary) {
      assert(_opaqueBackground(ctx, pen), _translucentBoundary);
      ctx.canvas.fill(0, 0, width, height, pen);
    }
    final run = _run ??= ctx.canvas.shape(_text);
    ctx.canvas.run(0, 0, run, pen);
  }
}

/// Where a [RenderParagraph] may break a line too long for it.
enum TextWrap {
  /// After a space, after a hyphen inside a word, and between two CJK
  /// characters (ideographs, kana, Hangul syllables) but not before
  /// closing punctuation or a small kana, nor after an opening bracket; a
  /// word longer than the line is broken between graphemes. Spaces at the
  /// end of a line hang beyond it: they are neither counted nor drawn.
  word,

  /// Between any two graphemes.
  grapheme,

  /// Nowhere: a line ends only where the text breaks it; one too long is
  /// cut off.
  none,
}

/// How a [RenderParagraph] shows that it cut text off: a line too long for
/// it, or the lines beyond its [RenderParagraph.maxLines].
enum TextOverflow {
  /// It doesn't: the text is cut off at the edge.
  clip,

  /// "…" in place of the end.
  ellipsis,

  /// "…" in place of the start: the end is kept.
  ellipsisStart,

  /// "…" in place of the middle: the start and the end are kept (paths,
  /// names).
  ellipsisMiddle,
}

/// Where a [RenderParagraph] puts each line across its width. A line wider
/// than the paragraph starts at the edge its paragraph starts at: the left
/// one, or the right one for a right-to-left paragraph in visual order
/// ([TextOrder.visual]).
enum TextAlign {
  /// At the left.
  left,

  /// In the middle; the odd cell after the line.
  center,

  /// At the right.
  right,

  /// Stretched to the whole width: the cells it lacks are shared out after
  /// the spaces between its words, the odd ones to the first. The last
  /// line, a line the text breaks, a line with an ellipsis and a line
  /// without spaces stay at the start, as [start] places them.
  justify,

  /// At the edge its paragraph starts at: the left one, or in visual order
  /// ([TextOrder.visual]) the right one for a paragraph that runs right to
  /// left (its first strong character is, rules P2 and P3 of UAX #9).
  start,

  /// At the edge its paragraph ends at: the other one.
  end,
}

/// The order a tree draws text in, from left to right
/// ([PipelineTextOrder.textOrder]): where it holds right-to-left characters,
/// as they are stored or as they are read.
enum TextOrder {
  /// As stored: the characters of a line from left to right in the order
  /// they come, for a terminal that reorders right-to-left text itself
  /// (implicit mode), or that can't be told not to. Every paragraph counts
  /// as left to right.
  logical,

  /// As read: each line in the order the Unicode Bidirectional Algorithm
  /// (UAX #9, [BidiText]) displays it, its right-to-left runs reversed by
  /// grapheme and their brackets mirrored, for a terminal that does no
  /// bidi or was told not to (explicit mode).
  visual,
}

// the text order of each owner that was given one, and whether any was
// given visual order: until one is, a paragraph attached asks nothing
final _textOrders = Expando<TextOrder>('textOrder');
var _anyVisual = false;

/// The order a tree draws text in: [RenderParagraph] and the editing
/// widgets read it from their owner.
extension PipelineTextOrder on PipelineOwner {
  /// The order this owner's tree draws text in: [TextOrder.logical] until
  /// set. Set to another, the tree is laid out and painted again.
  TextOrder get textOrder => _textOrders[this] ?? TextOrder.logical;

  set textOrder(TextOrder order) {
    if (order == textOrder) {
      return;
    }
    _textOrders[this] = order;
    _anyVisual = _anyVisual || order == TextOrder.visual;
    final root = _root;
    if (root != null) {
      _reorder(root, order);
      markAllDirty();
    }
  }
}

/// Lays [o] and those below it out again, in [order] for paragraphs.
void _reorder(RenderObject o, TextOrder order) {
  if (o is RenderParagraph) {
    o
      .._order = order
      .._bidiStale = true;
  }
  o
    ..markNeedsLayout()
    ..visitChildren((c) => _reorder(c, order));
}

// what a cluster of a paragraph is, for breaking lines (bits)
const _space = 1;
const _hyphen = 2;
const _digit = 4;
// an ideograph, kana, Hangul syllable or CJK punctuation; no line starts
// with a _cjkClose one (closing punctuation, small kana, prolonged sound
// mark) and none ends with a _cjkOpen one (opening brackets)
const _cjk = 8;
const _cjkClose = 16;
const _cjkOpen = 32;
// a line break of the text: no width, never drawn
const _newline = 64;
// legacy mode: the next cluster is part of the same grapheme
const _glue = 128;
// a zero width space (dropped) follows
const _zwsp = 256;
// a line may break after it, by word
const _break = 512;
// of several code points: interned in the glyph table when painted
const _multi = 1024;

// the Bidi_Class of a code unit as [BidiClass.index] gives it: L, R, AL,
// a paragraph separator, a segment separator, whitespace, other neutral;
// from LRE on the explicit embeddings, overrides and isolates, their
// terminators and PDF; X9 removes LRE, RLE, LRO, RLO, PDF and BN
const _bcL = 0;
const _bcR = 1;
const _bcAl = 2;
const _bcBn = 9;
const _bcB = 10;
const _bcS = 11;
const _bcWs = 12;
const _bcOn = 13;
const _bcLre = 14;

/// The classes rule L1 resets before a separator and at the end of a line:
/// whitespace, isolate formatting characters and what X9 removes.
const int _bcTrailing = 1 << _bcWs | 1 << _bcBn | 0x1FF << _bcLre;

/// The depth of the bracket stack of rule BD16.
const _maxBrackets = 63;

/// [cp] with the two brackets that have canonical equivalents replaced by
/// them (BD16).
int _canonicalBracket(int cp) => switch (cp) {
  0x2329 => 0x3008,
  0x232A => 0x3009,
  _ => cp,
};

bool _isHighSurrogate(int u) => u >= 0xD800 && u <= 0xDBFF;

bool _isLowSurrogate(int u) => u >= 0xDC00 && u <= 0xDFFF;

/// Whether [cp] is a small hiragana or katakana (ぁ, ッ, ょ), which no line
/// starts with.
bool _isSmallKana(int cp) {
  // katakana are the hiragana 0x60 on
  final h = cp >= 0x30A1 ? cp - 0x60 : cp;
  return (h >= 0x3041 && h <= 0x3049 && h.isOdd) ||
      h == 0x3063 ||
      h == 0x3083 ||
      h == 0x3085 ||
      h == 0x3087 ||
      h == 0x308E ||
      h == 0x3095 ||
      h == 0x3096;
}

/// What the cluster that starts with [cp] and has [length] code points is,
/// for breaking lines.
@pragma('vm:prefer-inline')
int _kindOf(int cp, int length) {
  if (cp < 0x80) {
    if (cp == 0x20) {
      return length == 1 ? _space : 0;
    }
    if (cp == 0x2D) {
      return _hyphen;
    }
    return cp >= 0x30 && cp <= 0x39 ? _digit : 0;
  }
  return _kindOfWide(cp, length);
}

/// [_kindOf] beyond ASCII.
int _kindOfWide(int cp, int length) {
  if (cp < 0x1680) {
    return 0;
  }
  // a space with a mark on it is a letter
  if (length == 1 &&
      (cp == 0x1680 ||
          (cp >= 0x2000 && cp <= 0x200A && cp != 0x2007) ||
          cp == 0x205F ||
          cp == 0x3000)) {
    return _space;
  }
  if (cp >= 0x2010 && cp <= 0x2014 && cp != 0x2011) {
    return _hyphen;
  }
  if (cp >= 0x3001 && cp <= 0x30FF) {
    if (cp >= 0x3008 && cp <= 0x301B) {
      // brackets: opening at even code points, closing at odd ones
      return _cjk | (cp.isEven ? _cjkOpen : _cjkClose);
    }
    final close =
        cp <= 0x3002 ||
        cp == 0x3005 ||
        cp == 0x301C ||
        cp == 0x301E ||
        cp == 0x301F ||
        cp == 0x303B ||
        cp == 0x309D ||
        cp == 0x309E ||
        (cp >= 0x30FB && cp <= 0x30FE) ||
        _isSmallKana(cp);
    return _cjk | (close ? _cjkClose : (cp == 0x301D ? _cjkOpen : 0));
  }
  if (cp >= 0xFF01 && cp <= 0xFF60) {
    return switch (cp) {
      0xFF08 || 0xFF3B || 0xFF5B || 0xFF5F => _cjk | _cjkOpen,
      0xFF01 ||
      0xFF09 ||
      0xFF0C ||
      0xFF0E ||
      0xFF1A ||
      0xFF1B ||
      0xFF1F ||
      0xFF3D ||
      0xFF5D ||
      0xFF60 => _cjk | _cjkClose,
      _ => 0,
    };
  }
  if (cp >= 0x31F0 && cp <= 0x31FF) {
    // small katakana
    return _cjk | _cjkClose;
  }
  return (cp >= 0x2E80 && cp <= 0x2FDF) ||
          (cp >= 0x3400 && cp <= 0x4DBF) ||
          (cp >= 0x4E00 && cp <= 0x9FFF) ||
          (cp >= 0xAC00 && cp <= 0xD7A3) ||
          (cp >= 0xF900 && cp <= 0xFAFF) ||
          (cp >= 0x20000 && cp <= 0x3FFFF)
      ? _cjk
      : 0;
}

/// Whether [cp] breaks a line (LF, CR, VT, FF, NEL, LS, PS).
bool _isNewline(int cp) =>
    (cp >= 0x0A && cp <= 0x0D) || cp == 0x85 || cp == 0x2028 || cp == 0x2029;

/// Whether [s] has a character UAX #9 may draw out of logical order: a
/// letter of a right-to-left script, an Arabic number, or a right-to-left
/// embedding, override or isolate.
bool _mayReorder(String s) {
  for (var i = 0; i < s.length; i++) {
    var cp = s.codeUnitAt(i);
    if (cp < 0x0590) {
      continue;
    }
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < s.length) {
      final lo = s.codeUnitAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
        i++;
      }
    }
    switch (bidiClassOf(cp)) {
      case BidiClass.r ||
          BidiClass.al ||
          BidiClass.an ||
          BidiClass.rle ||
          BidiClass.rlo ||
          BidiClass.rli:
        return true;
      case _:
    }
  }
  return false;
}

final _clusterScan = ClusterScan();

// legacy mode: where the graphemes end, so that a line keeps the clusters
// of one together
final _graphemeSegmenter = TextSegmenter();
final _graphemeScan = ClusterScan();

// a line of a paragraph: the clusters before the ellipsis (start, end),
// those after it (start, end), the span whose pen draws the ellipsis (-1:
// none), the columns, whether wrapping ended it (1), and the first cluster
// it stands for (one an ellipsis at its start hides)
const _lineStride = 8;

// a line as broken, before maxLines and the ellipsis: start, end of what
// is drawn, columns, whether wrapping ended it (1) and whether it is the
// last (2), the last cluster _breakLine read for it, where the next starts
const _rawStride = 6;

/// Whether UTF-16 code unit [c] is a letter or an ideograph of a script
/// without marks of its own: a code point of Grapheme_Cluster_Break Other
/// that takes cells and that nothing before it joins to. Between two of
/// them a cluster ends, as either segmenter splits text and whatever comes
/// before or after, which is where an edited paragraph starts splitting
/// its text again and stops.
bool _plain(int c) =>
    (c >= 0x20 && c < 0x7F) ||
    (c >= 0x4E00 && c <= 0x9FEF) ||
    // Cyrillic А-я, Hebrew א-ת, Arabic ء-غ and ف-ي (the marks are 064B on)
    (c >= 0x0410 && c <= 0x044F) ||
    (c >= 0x05D0 && c <= 0x05EA) ||
    (c >= 0x0621 && c <= 0x063A) ||
    (c >= 0x0641 && c <= 0x064A);

// The empty typed lists a RenderParagraph starts with, one of each type
// for all of them: a paragraph made allocates none of its own before its
// first layout (a scrolling list makes paragraphs all the time). Nothing
// is written into a list of no elements, and a field that grows is given
// a list of its own.
final _noUint32s = Uint32List(0);
final _noUint16s = Uint16List(0);
final _noInt32s = Int32List(0);
final _noUint8s = Uint8List(0);

/// What a [RenderParagraph] splits and breaks an edit again with, shared
/// by all of them as one does it at a time: scratch for the clusters split
/// again before they go in their place and for the lines broken again,
/// what [RenderParagraph._scan] compares and what it found.
final class _Edit {
  var glyphs = Uint32List(0);
  var kinds = Uint16List(0);
  var spanOf = Int32List(0);
  var starts = Int32List(0);
  var ends = Int32List(0);
  var lines = Int32List(0);

  // the last span the edit changed; the span of the text as split it was
  // (-1: none), the offset in it past which its text is as it was, and
  // how much longer it is; how many more spans there are
  var lastChanged = 0;
  var pairedOld = -1;
  var suffixFrom = 0;
  var lengthChange = 0;
  var spanShift = 0;

  // where the clusters lined up again: the cluster of the text as split
  // they do from, the span (as numbered now) and whether inside it
  var syncOld = 0;
  var syncSpan = 0;
  var syncInside = false;

  // what the clusters scanned add up to: line breaks, columns, the last
  // drawn one (-1: none) and the columns up to it, whether any is of
  // several code points
  var newlines = 0;
  var cells = 0;
  var drawn = -1;
  var drawnCells = 0;
  var multi = false;
}

final _edit = _Edit();

/// The places in a text that rules BD16 and X1 to X10 look at, in order:
/// each paired bracket, keyed by the opening bracket it pairs with (as
/// [_canonicalBracket] gives it; negative for a closing one), and each
/// explicit embedding, override, isolate or terminator of them (key 0).
final class _Marks {
  var at = Int32List(16);
  var key = Int32List(16);
  var count = 0;

  void _add(int i, int k) {
    if (count == at.length) {
      at = Int32List(at.length * 2)..setRange(0, count, at);
      key = Int32List(at.length)..setRange(0, count, key);
    }
    at[count] = i;
    key[count++] = k;
  }

  /// The first mark at or after code unit [i], or the count.
  int firstFrom(int i) {
    var lo = 0;
    var hi = count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (at[mid] < i) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Adds the marks of code units [from, to) of [text], whose classes are
  /// [classes], [by] code units on.
  void addFrom(_Joined text, Uint8List classes, int from, int to, int by) {
    for (var i = from; i < to; i++) {
      final c = classes[i];
      if (c >= _bcLre) {
        _add(i + by, 0);
      } else if (c == _bcOn) {
        // the paired brackets are all in the BMP
        final cp = text.codeUnitAt(i);
        final b = RenderParagraph._bracketIndex(cp);
        if (b >= 0) {
          _add(
            i + by,
            bidiBrackets[b + 2] == 1
                ? _canonicalBracket(cp)
                : -_canonicalBracket(bidiBrackets[b + 1]),
          );
        }
      }
    }
  }

  /// Adds marks [from, to) of [m], [by] code units on.
  void addRange(_Marks m, int from, int to, int by) {
    for (var i = from; i < to; i++) {
      _add(m.at[i] + by, m.key[i]);
    }
  }
}

/// Bracket pairs (open, close) one after another.
final class _Pairs {
  var v = Int32List(32);
  var count = 0;

  void add(int open, int close) {
    if (2 * count == v.length) {
      v = Int32List(v.length * 2)..setRange(0, 2 * count, v);
    }
    v[2 * count] = open;
    v[2 * count++ + 1] = close;
  }

  void reverse() {
    for (var a = 0, b = count - 1; a < b; a++, b--) {
      final o = v[2 * a];
      final c = v[2 * a + 1];
      v[2 * a] = v[2 * b];
      v[2 * a + 1] = v[2 * b + 1];
      v[2 * b] = o;
      v[2 * b + 1] = c;
    }
  }

  /// Whether one of these pairs, in order and apart, spans the place
  /// before code unit [x]: opens before it and closes at or after it.
  bool spans(int x) {
    var lo = 0;
    var hi = count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (v[2 * mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo > 0 && x <= v[2 * lo - 1];
  }
}

/// The texts of a paragraph's spans read as the one text they join into,
/// without joining them: [codeUnitAt] finds the span a code unit is in,
/// starting from the one it read last.
final class _Joined {
  var texts = List<String>.filled(4, '');
  var count = 0;
  var length = 0;
  // where each span ends in the text
  var _ends = Int32List(4);
  // the span read last, and where it starts and ends
  var _s = '';
  var _start = 0;
  var _end = 0;

  void setFrom(List<(String, Pen)> spans) {
    final m = spans.length;
    if (texts.length < m) {
      texts = List<String>.filled(_room(m, texts.length), '');
      _ends = Int32List(texts.length);
    }
    var n = 0;
    for (var k = 0; k < m; k++) {
      final s = spans[k].$1;
      texts[k] = s;
      _ends[k] = n += s.length;
    }
    // those after the count go, not to keep their strings alive
    for (var k = m; k < count; k++) {
      texts[k] = '';
    }
    count = m;
    length = n;
    _s = '';
    _start = 0;
    _end = 0;
  }

  int codeUnitAt(int i) {
    if (i < _start || i >= _end) {
      _seek(i);
    }
    return _s.codeUnitAt(i - _start);
  }

  /// The span code unit [i] is in made the one read.
  void _seek(int i) {
    var lo = 0;
    var hi = count - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_ends[mid] <= i) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _s = texts[lo];
    _end = _ends[lo];
    _start = _end - _s.length;
  }

  /// Code units [from, to), after [lead]: a span's own string where they
  /// are all of one, else a new string; how many code units that copied
  /// goes to [copied].
  String substring(int from, int to, String lead) {
    if (from < to) {
      _seek(from);
      if (lead.isEmpty && to <= _end) {
        if (from == _start && to == _end) {
          return _s;
        }
        copied += to - from;
        return _s.substring(from - _start, to - _start);
      }
    }
    final n = lead.length + to - from;
    var units = _units;
    if (units.length < n) {
      units = _units = Uint16List(_room(n, units.length));
    }
    for (var i = 0; i < lead.length; i++) {
      units[i] = lead.codeUnitAt(i);
    }
    for (var i = from, j = lead.length; i < to; i++, j++) {
      units[j] = codeUnitAt(i);
    }
    copied += n;
    return String.fromCharCodes(units, 0, n);
  }

  /// All of it in one string: the span's own where it is one.
  String join() {
    if (count <= 1) {
      return count == 0 ? '' : texts[0];
    }
    final b = StringBuffer();
    for (var k = 0; k < count; k++) {
      b.write(texts[k]);
    }
    copied += length;
    return b.toString();
  }

  /// How many code units [substring] has copied.
  var copied = 0;
  static var _units = Uint16List(64);
}

/// Whether two texts are the same: the same string most often.
bool _same(String a, String b) => identical(a, b) || a == b;

// a piece of a line painted in one call: column, row, span, columns, where
// its glyphs are (one of the _from constants) and their range there
const _segmentStride = 7;

// where a segment's glyphs are: none, the blank cells of a gap a justified
// line stretches; among the clusters (_glyphs); among the lines ordered
// for drawing (_runGlyphs); the ellipsis
const _fromGap = 0;
const _fromClusters = 1;
const _fromOrdered = 2;
const _fromEllipsis = 3;

/// A length for an array that has [had] entries and needs [least], which
/// is more: half as long again at least, so one that keeps growing by a
/// little is not allocated again each time.
int _room(int least, int had) {
  final more = had + (had >> 1);
  return least > more ? least : more;
}

/// Text in spans, each drawn with its own pen, broken into lines that fit
/// its width as [wrap] says, at most [maxLines] of them, each placed as
/// [align] says; where text is cut off, [overflow] says how it shows. It is
/// as wide as its widest line and as tall as its lines, within its
/// constraints.
///
/// The spans are given as (text, pen) and split into clusters once per
/// change, as the owner's segmenter splits them ([PipelineOwner.segmenter],
/// the canvas's): what a line holds is drawn exactly as wide as it was
/// measured. No line splits a grapheme: a wide glyph that doesn't fit at
/// the end of a line goes to the next. A line break in the text (`\n`,
/// `\r\n` and the like) ends a line; a tab is one blank, other controls
/// take no room. The pens are looked up in the style table it is painted
/// with once per table. Painting it again allocates nothing.
///
/// An edit of the spans is split again only about where the text changed,
/// from a place before it where the clusters are sure to split as they did
/// to one after it where they line up again, and the lines are broken
/// again from the first line that read what changed to one that starts
/// where a line did: the clusters and lines are those the spans give laid
/// out from scratch, at the cost of the lines the edit moved.
///
/// Its min intrinsic width is the widest piece no line break can split, its
/// max intrinsic width its widest line unbroken, and its intrinsic height
/// the lines it has at a width.
///
/// In visual order ([PipelineTextOrder.textOrder]) text with right-to-left
/// characters is broken into lines as stored, then each line drawn in the
/// order UAX #9 gives ([BidiText]): its runs at odd levels reversed by
/// grapheme, their brackets mirrored, an ellipsis where it stands among
/// them. [TextAlign.start] and [TextAlign.end] follow the direction of
/// each line's paragraph. Text without such characters, and any in logical
/// order, is drawn as stored. An edit resolves the levels again only
/// about where the text changed, from a place before it where the levels
/// are sure to resolve as they did to one after it, within its paragraph;
/// the rows whose clusters and levels are as they were are drawn as they
/// were, and only the others ordered again.
///
/// A message in two pens, broken at words, two lines at most:
///
/// ```dart
/// final message = RenderParagraph(
///   [
///     ('Error: ', const Pen(fg: Color.rgb(220, 60, 60))),
///     ('the file could not be saved, the disk is full', const Pen()),
///   ],
///   maxLines: 2,
///   overflow: TextOverflow.ellipsis,
/// );
/// ```
///
/// See also:
///
///  * [RenderText], the leaner object for one line in one pen.
///  * [textRangeAt], the text at a cell as the last layout placed it.
final class RenderParagraph extends RenderObject {
  /// [spans] as (text, pen); replace the list to change them.
  RenderParagraph(
    this._spans, {
    this._wrap = TextWrap.word,
    this._overflow = TextOverflow.clip,
    this._maxLines,
    this._align = TextAlign.left,
  }) : assert((_maxLines ?? 1) > 0, 'one line or more');

  List<(String, Pen)> _spans;

  /// The text as spans of (text, pen), in order; their texts joined are
  /// the paragraph's text. A new list whose texts differ is split and laid
  /// out again about where they changed; one with only new pens is only
  /// repainted. Replace the list to change them: the paragraph does not
  /// see a change made to it in place.
  List<(String, Pen)> get spans => _spans;
  set spans(List<(String, Pen)> s) {
    final old = _spans;
    var sameText = s.length == old.length;
    var samePens = true;
    for (var k = 0; sameText && k < s.length; k++) {
      sameText = s[k].$1 == old[k].$1;
      samePens = samePens && s[k].$2 == old[k].$2;
    }
    _spans = s;
    if (!sameText) {
      // split again where it changed
      _textStale = true;
      _pensIn = null;
      markNeedsLayout();
    } else if (!samePens) {
      _pensIn = null;
      markNeedsPaint();
    }
  }

  TextWrap _wrap;

  /// Where a line too long for the paragraph may break, at words by
  /// default; a new one lays it out again.
  TextWrap get wrap => _wrap;
  set wrap(TextWrap w) {
    if (w != _wrap) {
      _wrap = w;
      _linesChanged();
    }
  }

  TextOverflow _overflow;

  /// How text cut off shows, a line too long or the lines beyond
  /// [maxLines]: cut off at the edge by default. A new one lays it out
  /// again.
  TextOverflow get overflow => _overflow;
  set overflow(TextOverflow o) {
    if (o != _overflow) {
      _overflow = o;
      _linesChanged();
    }
  }

  int? _maxLines;

  /// The most lines it shows, 1 or more; null, the default, for as many as
  /// the text has. A new one lays it out again.
  int? get maxLines => _maxLines;
  set maxLines(int? n) {
    assert((n ?? 1) > 0, 'one line or more');
    if (n != _maxLines) {
      _maxLines = n;
      _linesChanged();
    }
  }

  TextAlign _align;

  /// Where each line goes across the paragraph's width, at the left by
  /// default; a new one only repaints it.
  TextAlign get align => _align;
  set align(TextAlign a) {
    if (a != _align) {
      _align = a;
      _segmentsStale = true;
      _rowsKept = false;
      markNeedsPaint();
    }
  }

  void _linesChanged() {
    _linesAt = -1;
    _rawAt = -1;
    markNeedsLayout();
  }

  /// The start of the text; how many spans there are, or the pen when there
  /// is one; and the settings that aren't the defaults.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    // enough of the text for an excerpt
    final text = StringBuffer();
    for (var i = 0; i < _spans.length && text.length < 100; i++) {
      text.write(_spans[i].$1);
    }
    properties.addValue('$text');
    if (_spans.length > 1) {
      properties.add('spans', _spans.length);
    } else if (_spans.isNotEmpty) {
      properties.add('pen', _spans.first.$2, defaultValue: const Pen());
    }
    properties
      ..add('wrap', _wrap, defaultValue: TextWrap.word)
      ..add('overflow', _overflow, defaultValue: TextOverflow.clip)
      ..add('maxLines', _maxLines, defaultValue: null)
      ..add('align', _align, defaultValue: TextAlign.left);
  }

  // the clusters of the spans in order, as split by the segmenter of
  // _shapedMode and _shapedAmbiguous (null: to be split again); each
  // with its glyph word as a GlyphRun holds it (0 for a line break, and
  // until it is interned for one of several code points), what it is for
  // breaking lines, its span, and for one of several code points where it
  // is in the span's text
  TextMode? _shapedMode;
  var _shapedAmbiguous = 0;
  var _count = 0;
  Uint32List _glyphs = _noUint32s;
  Uint16List _kinds = _noUint16s;
  Int32List _spanOf = _noInt32s;
  Int32List _starts = _noInt32s;
  Int32List _ends = _noInt32s;
  // where each cluster starts in the spans' text joined, what takes no
  // cell before it included, and at [_count] its length; found when
  // textRangeAt first asks after a split
  var _offsets = Int32List(1);
  var _offsetsStale = true;
  var _offsetsFound = 0;
  var _hasMulti = false;
  // the line breaks among the clusters, their columns, and the end and
  // the columns of what is left without the spaces at the end
  var _newlines = 0;
  var _cells = 0;
  var _drawn = 0;
  var _drawnCells = 0;
  // the _break bits are set
  var _wordBreaks = false;
  // the clusters of several code points have their ids in _internedIn,
  // but for [_internFrom, _internTo), split again since
  GlyphTable? _internedIn;
  // _internedIn's sweeps then: since a sweep, the ids may be others'
  var _internedSweeps = 0;
  var _internFrom = 0;
  var _internTo = 0;
  var _ellipsisWidth = 1;
  GlyphRun? _ellipsis;

  // the texts of the spans as split, and whether they changed since
  // (_resplit)
  var _shapedTexts = const <String>[];
  var _textStale = false;
  var _clustersSplit = 0;
  var _linesBroken = 0;

  // the ids in _pensIn of the pens of the spans (null: to be looked up)
  StyleTable? _pensIn;
  Int32List _penIds = _noInt32s;

  // the lines laid out at _linesAt columns (-1: to be laid out again)
  var _linesAt = -1;
  var _lineCount = 0;
  Int32List _lines = _noInt32s;
  // the lines as broken at _rawAt columns (-1: none), and with _edited
  // the edit of the clusters since: those before _editFrom are as they
  // were, those from _editOld on are those from _editNew on now
  var _rawAt = -1;
  var _rawCount = 0;
  Int32List _raw = _noInt32s;
  var _edited = false;
  var _editFrom = 0;
  var _editOld = 0;
  var _editNew = 0;

  // what painting draws, worked out on the first paint after a layout
  var _segmentsStale = true;
  var _segmentCount = 0;
  Int32List _segments = _noInt32s;

  // what _breakLine found: the end of what the line draws, its columns,
  // whether wrapping ended it, whether it is the last, the last cluster it
  // read (the count when it took the totals)
  var _end = 0;
  var _endWidth = 0;
  var _soft = false;
  var _last = false;
  var _stop = 0;

  // the owner's text order; in visual order, when the text has characters
  // that may reorder it, the levels UAX #9 resolves for it, brought up to
  // date when stale: for each code unit of the text of the spans joined
  // (_bidiWas, read as one without joining it) its level and Bidi_Class,
  // and where each of its
  // paragraphs starts and its level; how many levels are not 0 (when none
  // is, it is drawn as stored); the arrays an edit fills before they swap
  TextOrder _order = TextOrder.logical;
  var _bidiStale = true;
  var _bidiOn = false;
  var _bidiValid = false;
  // the text whose levels are resolved, and the spans' text now; made
  // when first read, as only a text that may reorder reads them
  late var _bidiWas = _Joined();
  late var _bidiNow = _Joined();
  Uint8List _levels = _noUint8s;
  Uint8List _classes = _noUint8s;
  Uint8List _levelsNext = _noUint8s;
  Uint8List _classesNext = _noUint8s;
  var _paraStarts = Int32List(1);
  var _paraLevels = Uint8List(1);
  var _paraCount = 0;
  var _nonZero = 0;
  var _levelsResolved = 0;
  // the levels of a line after rule L1
  Uint8List _lineLevels = _noUint8s;

  // what the rows ordered for drawing were built from, for the next build
  // to take those it can (_buildSegments): whether they can be taken
  // (all are built again otherwise), the box's width then, the rows, the
  // lines then (_lineStride each) and where each row's segments and
  // glyphs start (two each, and at the end their counts), the segments
  // and glyphs as they were; how many rows were ordered for drawing
  var _rowsKept = false;
  var _rowsWidth = 0;
  var _rowsWere = 0;
  Int32List _linesWere = _noInt32s;
  var _rowAt = Int32List(2);
  var _rowAtWere = Int32List(2);
  Int32List _segmentsWere = _noInt32s;
  Uint32List _runGlyphsWere = _noUint32s;
  var _linesOrdered = 0;
  // the clusters changed since the rows were built: those before
  // _changedFrom are as they were, those from _changedTo on are those
  // _changedShift before them then, in spans of the same index unless
  // _spansMoved
  int _changedFrom = 1 << 30;
  var _changedTo = 0;
  var _changedShift = 0;
  var _spansMoved = false;

  // a line ordered for drawing (_orderLine): its items as drawn from left
  // to right, each a cluster or -1 for the ellipsis, and whether each is
  // at an odd level; scratch for the items in logical order, their levels
  // and where each goes
  Int32List _visual = _noInt32s;
  Uint8List _visualOdd = _noUint8s;
  Int32List _items = _noInt32s;
  Uint8List _itemLevels = _noUint8s;
  Int32List _itemOrder = _noInt32s;
  // the glyphs of every line ordered for drawing, one after another, and
  // how many there are
  Uint32List _runGlyphs = _noUint32s;
  var _runGlyphCount = 0;

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    // split by another segmenter: split and laid out again
    final seg = o.segmenter;
    if (_shapedMode != null &&
        (_shapedMode != seg.mode || _shapedAmbiguous != seg.ambiguousWidth)) {
      _shapedMode = null;
      if (_constraints != null) {
        markNeedsLayout();
      }
    }
    final order = _anyVisual ? o.textOrder : TextOrder.logical;
    if (order != _order) {
      _order = order;
      _bidiStale = true;
      if (_constraints != null) {
        markNeedsLayout();
      }
    }
  }

  /// Splits the spans into clusters unless they are split as the owner's
  /// segmenter splits them (an edit: where the text changed), and finds
  /// where lines may break by word if they do.
  void _shape() {
    final seg = owner?.segmenter ?? _detachedSegmenter;
    if (_shapedMode != seg.mode || _shapedAmbiguous != seg.ambiguousWidth) {
      _split(seg);
    } else if (_textStale) {
      _resplit(seg);
    }
    if (_wrap == TextWrap.word && !_wordBreaks) {
      _findWordBreaks();
    }
    if (_bidiStale) {
      _findBidi();
    }
  }

  /// In visual order, resolves the levels of the text when it has a
  /// character that may take it out of logical order, after an edit those
  /// it may have changed ([_resolveEdit]); text without one is drawn as
  /// stored.
  void _findBidi() {
    _bidiStale = false;
    _segmentsStale = true;
    final was = _bidiOn;
    _bidiOn = false;
    var reorders = false;
    if (_order == TextOrder.visual) {
      for (var k = 0; k < _spans.length && !reorders; k++) {
        reorders = _mayReorder(_spans[k].$1);
      }
    }
    if (!reorders) {
      _bidiValid = false;
      _rowsKept = _rowsKept && !was;
      return;
    }
    final text = _bidiNow..setFrom(_spans);
    var from = 0;
    var to = text.length;
    if (_bidiValid) {
      _resolveEdit(text);
      from = _windowFrom;
      to = _windowTo;
    } else {
      _resolveAll(text);
      _rowsKept = false;
    }
    _bidiOn = _nonZero > 0;
    if (_bidiOn != was) {
      _rowsKept = false;
    }
    if (!_bidiOn) {
      return;
    }
    if (_offsetsStale) {
      _findOffsets();
    }
    if (from < to) {
      // the clusters whose levels the edit may have changed
      final offsets = _offsets;
      var lo = 0;
      var hi = _count;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (offsets[mid + 1] <= from) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      final first = lo;
      hi = _count;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (offsets[mid] < to) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      _changed(first, to >= text.length ? _count + 1 : lo);
    }
  }

  /// Counts the clusters [from, to) as changed since the rows were built.
  void _changed(int from, int to) {
    if (from < _changedFrom) {
      _changedFrom = from;
    }
    if (to > _changedTo) {
      _changedTo = to;
    }
  }

  /// The levels of [text] resolved from scratch.
  void _resolveAll(_Joined text) {
    final bidi = BidiText(text.join());
    final n = text.length;
    if (_levels.length < n) {
      _levels = Uint8List(_room(n, _levels.length));
      _classes = Uint8List(_levels.length);
    }
    _levels.setRange(0, n, bidi.levels);
    _classesOf(text, _classes, 0, n);
    final paragraphs = bidi.paragraphs;
    final m = paragraphs.length;
    if (_paraStarts.length < m) {
      _paraStarts = Int32List(_room(m, _paraStarts.length));
      _paraLevels = Uint8List(_paraStarts.length);
    }
    for (var p = 0; p < m; p++) {
      _paraStarts[p] = paragraphs[p].start;
      _paraLevels[p] = paragraphs[p].level;
    }
    _paraCount = m;
    _nonZero = _nonZeroIn(_levels, 0, n);
    _marks.count = 0;
    _marks.addFrom(text, _classes, 0, n, 0);
    _swapTexts();
    _bidiValid = true;
    _levelsResolved += n;
  }

  /// The spans' text now made the one whose levels are resolved, to tell
  /// what the next edit changes.
  void _swapTexts() {
    final was = _bidiWas;
    _bidiWas = _bidiNow;
    _bidiNow = was;
  }

  /// Puts the Bidi_Class of code units [from, to) of [text] into [out],
  /// both of a surrogate pair that of its code point.
  static void _classesOf(_Joined text, Uint8List out, int from, int to) {
    for (var i = from; i < to; i++) {
      var cp = text.codeUnitAt(i);
      if (cp >= 0xD800 && cp <= 0xDFFF) {
        if (cp <= 0xDBFF && i + 1 < text.length) {
          final lo = text.codeUnitAt(i + 1);
          if (lo >= 0xDC00 && lo <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          }
        } else if (cp >= 0xDC00 && i > 0) {
          final hi = text.codeUnitAt(i - 1);
          if (hi >= 0xD800 && hi <= 0xDBFF) {
            cp = 0x10000 + ((hi - 0xD800) << 10) + (cp - 0xDC00);
          }
        }
      }
      out[i] = bidiClassOf(cp).index;
    }
  }

  static int _nonZeroIn(Uint8List levels, int from, int to) {
    var n = 0;
    for (var i = from; i < to; i++) {
      if (levels[i] != 0) {
        n++;
      }
    }
    return n;
  }

  /// The paragraph code unit [unit] is in; the last for the end.
  int _paragraphAt(int unit) {
    var lo = 0;
    var hi = _paraCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_paraStarts[mid] <= unit) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Where paragraph [p] ends.
  int _paragraphEnd(int p) =>
      p + 1 < _paraCount ? _paraStarts[p + 1] : _bidiWas.length;

  // the code units of the text whose levels _resolveEdit resolved again
  var _windowFrom = 0;
  var _windowTo = 0;

  /// Brings the levels of [_bidiWas] up to [text] by resolving again
  /// what the edit between them can have changed, and leaves those code
  /// units in [_windowFrom], [_windowTo].
  ///
  /// Paragraphs resolve apart (UAX #9 rule P1): only those the edit
  /// touched are resolved again. Within one, where no explicit embedding,
  /// override or isolate is and no more brackets are open at once than
  /// rule BD16 keeps, a place no bracket pair spans with a strong
  /// character (L, R or AL) just before it splits the paragraph in two
  /// whose levels don't depend on each other: no rule looks past that
  /// character, and the paragraph's level (P2) is found before it. So the
  /// levels from the last such place before the edit to the first after it
  /// in both texts are resolved, as a paragraph of the paragraph's level
  /// that starts with a strong character of that class; those before and
  /// after are as they were. A bracket the edit pairs with one far off
  /// spans what is between them, and an explicit formatting character
  /// makes its paragraph resolve all of it again.
  void _resolveEdit(_Joined text) {
    final old = _bidiWas;
    final n0 = old.length;
    final n = text.length;
    final most = n0 < n ? n0 : n;
    // what the two have in common at the start and at the end: the spans
    // that are as they were, and on from them
    final texts = old.texts;
    final spans = text.texts;
    final m0 = old.count;
    final m = text.count;
    var k = 0;
    var a = 0;
    while (k < m0 && k < m && _same(texts[k], spans[k])) {
      a += texts[k++].length;
    }
    while (a < most && old.codeUnitAt(a) == text.codeUnitAt(a)) {
      a++;
    }
    _windowFrom = 0;
    _windowTo = 0;
    if (a == n0 && a == n) {
      _swapTexts();
      return;
    }
    var j = 0;
    var c = 0;
    while (j < m0 - k &&
        j < m - k &&
        _same(texts[m0 - 1 - j], spans[m - 1 - j])) {
      c += texts[m0 - 1 - j++].length;
    }
    if (c > most - a) {
      c = most - a;
    }
    while (c < most - a &&
        old.codeUnitAt(n0 - 1 - c) == text.codeUnitAt(n - 1 - c)) {
      c++;
    }
    // a surrogate pair either side goes with what changed
    if (a > 0 && _isHighSurrogate(text.codeUnitAt(a - 1))) {
      a--;
    }
    if (c > 0 && _isLowSurrogate(text.codeUnitAt(n - c))) {
      c--;
    }
    final d = n - n0;
    // [a, e) of the text is what changed, [a, e - d) of the old text
    final e = n - c;
    if (_levelsNext.length < n) {
      _levelsNext = Uint8List(_room(n, _levelsNext.length));
      _classesNext = Uint8List(_levelsNext.length);
    }
    final levels = _levelsNext;
    final classes = _classesNext;
    levels
      ..setRange(0, a, _levels)
      ..setRange(e, n, _levels, e - d);
    classes
      ..setRange(0, a, _classes)
      ..setRange(e, n, _classes, e - d);
    _classesOf(text, classes, a, e);
    final marks = _marks;
    final next = _marksNext..count = 0;
    final i1 = marks.firstFrom(e - d);
    next
      ..addRange(marks, 0, marks.firstFrom(a), 0)
      ..addFrom(text, classes, a, e, 0)
      ..addRange(marks, i1, marks.count, d);
    // the paragraphs the edit touched: [p0, p1] of the old text, from
    // pStart to pEnd of the text
    final int p0;
    final int pStart;
    if (a > 0 &&
        classes[a - 1] == _bcB &&
        (old.codeUnitAt(a - 1) != 0x0D ||
            ((a >= n0 || old.codeUnitAt(a) != 0x0A) &&
                (a >= n || text.codeUnitAt(a) != 0x0A)))) {
      // the edit starts a paragraph in both
      p0 = _paragraphAt(a - 1) + 1;
      pStart = a;
    } else {
      p0 = a > 0 ? _paragraphAt(a - 1) : 0;
      pStart = _paraStarts[p0];
    }
    final p1 = c == 0 ? _paraCount - 1 : _paragraphAt(n0 - c);
    final pEnd = c == 0 ? n : _paragraphEnd(p1) + d;
    var from = pStart;
    var to = pEnd;
    var oldTo = pEnd - d;
    var level = -1;
    var found = false;
    if (p0 == p1 &&
        pStart < pEnd &&
        _oneParagraph(text, classes, a > pStart ? a - 1 : pStart, e, pEnd)) {
      found = _findWindow(text, classes, pStart, pEnd, a, e, d);
      if (found) {
        from = _windowFrom;
        to = _windowTo;
        oldTo = to - d;
        level = _paraLevels[p0];
        if (from == pStart) {
          // the paragraph's level is found in what is resolved
          level = -1;
        }
      }
    }
    var nonZero = _nonZero - _nonZeroIn(_levels, from, oldTo);
    if (from < to) {
      final ctx = level < 0 ? 0 : 1;
      final part = text.substring(
        from,
        to,
        ctx == 0 ? '' : _strongOf(classes[from - 1]),
      );
      final bidi = BidiText(
        part,
        direction: level < 0
            ? null
            : (level.isOdd ? TextDirection.rtl : TextDirection.ltr),
      );
      levels.setRange(from, to, bidi.levels, ctx);
      _levelsResolved += to - from;
      final paragraphs = bidi.paragraphs;
      if (found) {
        final l = paragraphs.first.level;
        if (level < 0 && to < pEnd && l != _paraLevels[p0]) {
          // a paragraph of another direction: all of it again
          _windowFrom = pStart;
          _windowTo = pEnd;
          final f = _resolveParagraphs(text, levels, pStart, pEnd, p0, p1, d);
          _swapLevels(f);
          return;
        }
        _paraLevels[p0] = l;
      } else {
        _setParagraphs(paragraphs, pStart, p0, p1, d);
      }
    } else if (!found) {
      _setParagraphs(const [], pStart, p0, p1, d);
    }
    if (found) {
      for (var p = p0 + 1; p < _paraCount; p++) {
        _paraStarts[p] += d;
      }
    }
    nonZero += _nonZeroIn(levels, from, to);
    _windowFrom = from;
    _windowTo = to;
    _nonZero = nonZero;
    _swapLevels(-1);
  }

  /// Resolves the paragraphs [pStart, pEnd) of [text] into [levels], in
  /// place of [p0, p1] of the old text, and returns how many of its
  /// levels are not 0 then.
  int _resolveParagraphs(
    _Joined text,
    Uint8List levels,
    int pStart,
    int pEnd,
    int p0,
    int p1,
    int d,
  ) {
    final nonZero = _nonZero - _nonZeroIn(_levels, pStart, pEnd - d);
    final bidi = BidiText(text.substring(pStart, pEnd, ''));
    levels.setRange(pStart, pEnd, bidi.levels);
    _levelsResolved += pEnd - pStart;
    _setParagraphs(bidi.paragraphs, pStart, p0, p1, d);
    return nonZero + _nonZeroIn(levels, pStart, pEnd);
  }

  /// The levels and classes filled in made the text's, the spans' text
  /// now the one they are of, and [nonZero] the levels not 0 unless it is
  /// -1.
  void _swapLevels(int nonZero) {
    final l = _levels;
    final c = _classes;
    final marks = _marks;
    _levels = _levelsNext;
    _classes = _classesNext;
    _marks = _marksNext;
    _levelsNext = l;
    _classesNext = c;
    _marksNext = marks;
    _swapTexts();
    if (nonZero >= 0) {
      _nonZero = nonZero;
    }
  }

  /// Paragraphs [p0, p1] of the old text replaced by [paragraphs], found
  /// in the text from [pStart] on; those after them [d] code units on.
  void _setParagraphs(
    List<BidiParagraph> paragraphs,
    int pStart,
    int p0,
    int p1,
    int d,
  ) {
    final added = paragraphs.length;
    final kept = _paraCount - 1 - p1;
    final m = p0 + added + kept;
    var starts = _paraStarts;
    var lv = _paraLevels;
    if (starts.length < m) {
      starts = Int32List(_room(m, starts.length))..setRange(0, p0, _paraStarts);
      lv = Uint8List(starts.length)..setRange(0, p0, _paraLevels);
    }
    // those after the edit move first, to where they go
    starts.setRange(p0 + added, m, _paraStarts, p1 + 1);
    lv.setRange(p0 + added, m, _paraLevels, p1 + 1);
    for (var p = p0 + added; p < m; p++) {
      starts[p] += d;
    }
    for (var k = 0; k < added; k++) {
      starts[p0 + k] = pStart + paragraphs[k].start;
      lv[p0 + k] = paragraphs[k].level;
    }
    _paraStarts = starts;
    _paraLevels = lv;
    _paraCount = m;
  }

  /// Whether code units [from, to) of [text], with [classes], end no
  /// paragraph before [pEnd]: the edit that changed them, and the code
  /// unit before them, in a paragraph that ended nowhere else.
  static bool _oneParagraph(
    _Joined text,
    Uint8List classes,
    int from,
    int to,
    int pEnd,
  ) {
    final end = to < pEnd - 1 ? to : pEnd - 1;
    for (var i = from; i < end; i++) {
      if (classes[i] == _bcB &&
          (text.codeUnitAt(i) != 0x0D || text.codeUnitAt(i + 1) != 0x0A)) {
        return false;
      }
    }
    return true;
  }

  /// In the paragraph [pStart, pEnd) of [text] that the edit changed at
  /// [a, e) ([a, e - d) of the old text), finds the last place at or
  /// before [a] and the first after [e] in both texts where the paragraph
  /// splits in two that resolve apart ([_resolveEdit]), the start and the
  /// end of the paragraph when there is none, and leaves them in
  /// [_windowFrom], [_windowTo]. False where the paragraph, as it was or
  /// is, has an explicit embedding, override or isolate, or more brackets
  /// open at once than rule BD16 keeps.
  bool _findWindow(
    _Joined text,
    Uint8List classes,
    int pStart,
    int pEnd,
    int a,
    int e,
    int d,
  ) {
    final now = _spannedNow;
    final was = _spannedWas;
    if (!_pairsIn(_marksNext, pStart, pEnd, now) ||
        !_pairsIn(_marks, pStart, pEnd - d, was)) {
      return false;
    }
    var s = pStart;
    for (var x = a; x > pStart; x--) {
      if (classes[x - 1] <= _bcAl &&
          !now.spans(x) &&
          !was.spans(x) &&
          !_splitsPair(text, x)) {
        s = x;
        break;
      }
    }
    var q = pEnd;
    for (var x = e + 1; x < pEnd; x++) {
      if (classes[x - 1] <= _bcAl &&
          !now.spans(x) &&
          !was.spans(x - d) &&
          !_splitsPair(text, x)) {
        q = x;
        break;
      }
    }
    _windowFrom = s;
    _windowTo = q;
    return true;
  }

  // the brackets and explicit formatting characters of the text, and
  // those of the text after an edit; the outermost bracket pairs of a
  // paragraph of either, and all of them as they are found; made when
  // first read, as only a text that may reorder reads them
  late var _marks = _Marks();
  late var _marksNext = _Marks();
  late final _spannedNow = _Pairs();
  late final _spannedWas = _Pairs();
  late final _found = _Pairs();
  late final _openKeys = Int32List(_maxBrackets);
  late final _openAt = Int32List(_maxBrackets);

  /// Pairs the brackets of [marks] in the paragraph [from, to) as rule
  /// BD16 does, and puts the outermost pairs into [out]. False where the
  /// paragraph has an explicit embedding, override or isolate, or more
  /// brackets open at once than BD16 keeps.
  bool _pairsIn(_Marks marks, int from, int to, _Pairs out) {
    final keys = _openKeys;
    final opens = _openAt;
    final found = _found..count = 0;
    final at = marks.at;
    final key = marks.key;
    var depth = 0;
    for (var i = marks.firstFrom(from); i < marks.count && at[i] < to; i++) {
      final k = key[i];
      if (k == 0) {
        return false;
      }
      if (k > 0) {
        if (depth == _maxBrackets) {
          return false;
        }
        keys[depth] = k;
        opens[depth++] = at[i];
        continue;
      }
      for (var j = depth - 1; j >= 0; j--) {
        if (keys[j] == -k) {
          found.add(opens[j], at[i]);
          depth = j;
          break;
        }
      }
    }
    // found as they close, nested or one after the other: one is
    // outermost when it opens before every one found after it
    out.count = 0;
    var first = 1 << 30;
    for (var p = found.count - 1; p >= 0; p--) {
      final o = found.v[2 * p];
      if (o < first) {
        out.add(o, found.v[2 * p + 1]);
        first = o;
      }
    }
    out.reverse();
    return true;
  }

  /// The index of [cp]'s triple in [bidiBrackets], or -1.
  static int _bracketIndex(int cp) {
    if (cp < 0x28) {
      return -1;
    }
    var lo = 0;
    var hi = bidiBrackets.length ~/ 3 - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = bidiBrackets[mid * 3];
      if (cp < v) {
        hi = mid - 1;
      } else if (cp > v) {
        lo = mid + 1;
      } else {
        return mid * 3;
      }
    }
    return -1;
  }

  /// Whether a place before code unit [i] of [text] is inside a surrogate
  /// pair.
  static bool _splitsPair(_Joined text, int i) =>
      i > 0 &&
      i < text.length &&
      _isLowSurrogate(text.codeUnitAt(i)) &&
      _isHighSurrogate(text.codeUnitAt(i - 1));

  /// A strong character of Bidi_Class [k] (L, R or AL).
  static String _strongOf(int k) => switch (k) {
    _bcL => 'a',
    _bcR => '\u05D0',
    _ => '\u0627',
  };

  /// Splits the spans into clusters as [seg] splits them.
  void _split(TextSegmenter seg) {
    _bidiStale = true;
    _wordBreaks = false;
    _textStale = false;
    _shapedMode = seg.mode;
    _shapedAmbiguous = seg.ambiguousWidth;
    _linesAt = -1;
    _rawAt = -1;
    _edited = false;
    _segmentsStale = true;
    _rowsKept = false;
    _offsetsStale = true;
    _internedIn = null;
    _internFrom = 0;
    _internTo = 0;
    // the ellipsis is one code point: its run holds only its width
    final ellipsisWidth = codePointWidth(0x2026, seg.ambiguousWidth);
    if (ellipsisWidth != _ellipsisWidth) {
      _ellipsis = null;
      _ellipsisWidth = ellipsisWidth;
    }
    var units = 0;
    for (var k = 0; k < _spans.length; k++) {
      units += _spans[k].$1.length;
    }
    if (_glyphs.length < units) {
      final n = _room(units, _glyphs.length);
      _glyphs = Uint32List(n);
      _kinds = Uint16List(n);
      _spanOf = Int32List(n);
      _starts = Int32List(n);
      _ends = Int32List(n);
    }
    _count = _scan(seg, 0, 0, 0, edit: false);
    final e = _edit;
    _hasMulti = e.multi;
    _newlines = e.newlines;
    _cells = e.cells;
    _drawn = e.drawn + 1;
    _drawnCells = e.drawnCells;
    _keepTexts();
  }

  /// Keeps the texts of the spans as split, to tell what an edit changes.
  void _keepTexts() {
    final m = _spans.length;
    if (_shapedTexts.length != m) {
      _shapedTexts = List<String>.filled(m, '');
    }
    final texts = _shapedTexts;
    for (var k = 0; k < m; k++) {
      texts[k] = _spans[k].$1;
    }
  }

  /// Splits the spans into clusters as [seg] splits them, from offset [at]
  /// of span [first] on (a place a cluster starts), numbering the first
  /// [base]: into the paragraph's arrays to the end, or for an [edit] into
  /// the scratch ones until the clusters line up with those of the text as
  /// split before (where [_edit] says). Returns how many it found, and
  /// leaves in [_edit] what they add up to.
  int _scan(
    TextSegmenter seg,
    int first,
    int at,
    int base, {
    required bool edit,
  }) {
    final e = _edit;
    final glyphs = edit ? e.glyphs : _glyphs;
    final kinds = edit ? e.kinds : _kinds;
    final spanOf = edit ? e.spanOf : _spanOf;
    final starts = edit ? e.starts : _starts;
    final ends = edit ? e.ends : _ends;
    final spans = _spans;
    final scan = _clusterScan;
    final graphemes = seg.mode == TextMode.graphemes;
    // an edit: the last span it changed, where that span's text is the
    // same to the end as it was, and how the spans after it moved
    final last = e.lastChanged;
    final suffixFrom = e.suffixFrom;
    final shift = e.spanShift;
    var n = 0;
    var multi = false;
    var newlines = 0;
    var cells = 0;
    var drawn = -1;
    var drawnCells = 0;
    e
      ..syncOld = _count
      ..syncSpan = spans.length
      ..syncInside = false;
    spans:
    for (var k = first; k < spans.length; k++) {
      final s = spans[k].$1;
      var i = k == first ? at : 0;
      if (edit && i == 0 && k > last && _cleanStart(k - shift)) {
        // a span as it was, which adds nothing to the cluster before
        e
          ..syncOld = _firstOf(k - shift)
          ..syncSpan = k;
        break;
      }
      var grapheme = i;
      while (i < s.length) {
        final start = i;
        if (edit &&
            i > 0 &&
            (k > last || (k == last && i >= suffixFrom)) &&
            _plain(s.codeUnitAt(i - 1)) &&
            _plain(s.codeUnitAt(i))) {
          // what is from here on is as it was, and clusters end here
          final c = k > last
              ? _oldClusterAt(k - shift, i)
              : _oldClusterAt(e.pairedOld, i - e.lengthChange);
          assert(c >= 0, 'a cluster of the text as split starts at $i');
          if (c >= 0) {
            e
              ..syncOld = c
              ..syncSpan = k
              ..syncInside = true;
            break spans;
          }
        }
        seg.scan(s, i, scan);
        i = scan.end;
        final cp = scan.first;
        var glyph = cp;
        int kind;
        if (scan.width == 0) {
          if (_isNewline(cp)) {
            // CR LF breaks once; legacy mode scans the two apart
            if (cp == 0x0D &&
                i == start + 1 &&
                i < s.length &&
                s.codeUnitAt(i) == 0x0A) {
              continue;
            }
            glyph = 0;
            kind = _newline;
            newlines++;
          } else if (cp == 0x09) {
            glyph = kBlank;
            kind = _space;
          } else {
            if (cp == 0x200B) {
              if (n > 0) {
                kinds[n - 1] |= _zwsp;
              } else if (base > 0) {
                _kinds[base - 1] |= _zwsp;
              }
            }
            continue;
          }
        } else if (graphemes && isLeadingMark(cp)) {
          // a mark without a base is dropped, as the canvas drops it
          i = start + (cp > 0xFFFF ? 2 : 1);
          continue;
        } else {
          kind = _kindOf(cp, scan.length);
          if (scan.length > 1) {
            glyph = 0;
            kind |= _multi;
            multi = true;
          }
          if (scan.uncertain || scan.joinsNext) {
            glyph |= kUncertain;
          }
          if (scan.width == 2) {
            glyph |= kWide;
          }
        }
        if (!graphemes) {
          while (grapheme < start) {
            _graphemeSegmenter.scan(s, grapheme, _graphemeScan);
            grapheme = _graphemeScan.end;
          }
          // where it starts a grapheme starts, or a span: the first
          // cluster it finds glues none before it to itself
          if (grapheme > start && n > 0 && spanOf[n - 1] == k) {
            kinds[n - 1] |= _glue;
          }
        }
        glyphs[n] = glyph;
        kinds[n] = kind;
        spanOf[n] = k;
        starts[n] = start;
        ends[n] = i;
        n++;
        if ((kind & _newline) == 0) {
          cells += (glyph & kWide) != 0 ? 2 : 1;
          if ((kind & _space) == 0) {
            drawn = n - 1;
            drawnCells = cells;
          }
        }
      }
    }
    _clustersSplit += n;
    e
      ..multi = multi
      ..newlines = newlines
      ..cells = cells
      ..drawn = drawn
      ..drawnCells = drawnCells;
    return n;
  }

  /// The cluster of span [k] of the text as split that starts at offset
  /// [at] of it, or -1.
  int _oldClusterAt(int k, int at) {
    var lo = _firstOf(k);
    final end = _firstOf(k + 1);
    var hi = end;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_starts[mid] < at) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < end && _starts[lo] == at ? lo : -1;
  }

  /// Whether the text as split from span [k] on added nothing to the
  /// cluster before it (a zero width space after it): its first cluster
  /// starts where the first of those spans with text starts, or there is
  /// none of them.
  bool _cleanStart(int k) {
    final texts = _shapedTexts;
    var j = k;
    while (j < texts.length && texts[j].isEmpty) {
      j++;
    }
    if (j == texts.length) {
      return true;
    }
    final c = _firstOf(j);
    return c < _count && _spanOf[c] == j && _starts[c] == 0;
  }

  /// The first cluster of span [k] of the text as split, or of the first
  /// span after it with one, or the count: the clusters are in the order
  /// of their spans.
  int _firstOf(int k) {
    var lo = 0;
    var hi = _count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_spanOf[mid] < k) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Splits again what an edit of the spans changed: from a place the text
  /// as split and the text now split alike before the first change (where
  /// two plain characters meet, else the start of the span) up to the
  /// first such place after the last one where the clusters line up again,
  /// and moves the clusters after it into place. Splits all of it when it
  /// can't tell where to start.
  void _resplit(TextSegmenter seg) {
    _textStale = false;
    final old = _shapedTexts;
    final spans = _spans;
    final m = old.length;
    final m2 = spans.length;
    // spans [a, oldEnd) of the text as split are spans [a, newEnd) now
    var a = 0;
    while (a < m && a < m2 && _same(old[a], spans[a].$1)) {
      a++;
    }
    if (a == m && a == m2) {
      return;
    }
    var b = 0;
    while (b < m - a &&
        b < m2 - a &&
        _same(old[m - 1 - b], spans[m2 - 1 - b].$1)) {
      b++;
    }
    final oldEnd = m - b;
    final newEnd = m2 - b;
    final paired = oldEnd > a && newEnd > a;
    // split again from cluster from, at offset at of span a
    var from = _firstOf(a);
    var at = 0;
    var p = 0;
    if (paired) {
      final o = old[a];
      final s = spans[a].$1;
      final most = o.length < s.length ? o.length : s.length;
      while (p < most && o.codeUnitAt(p) == s.codeUnitAt(p)) {
        p++;
      }
      // the last cluster that starts before p, and back from it
      final firstOfA = from;
      var lo = firstOfA;
      var hi = _firstOf(a + 1);
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (_starts[mid] < p) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      for (var c = lo - 1; c >= firstOfA; c--) {
        final x = _starts[c];
        if (x > 0 && _plain(s.codeUnitAt(x - 1)) && _plain(s.codeUnitAt(x))) {
          from = c;
          at = x;
          break;
        }
      }
    }
    if (at == 0 && from > 0 && !_cleanStart(a)) {
      _split(seg);
      return;
    }
    // where the clusters may line up again: in the last span changed,
    // past what its text and that of the span it was have in common at
    // the end; in any span after it
    final e = _edit
      ..lastChanged = newEnd - 1
      ..spanShift = m2 - m
      ..pairedOld = -1
      ..suffixFrom = 1 << 30
      ..lengthChange = 0;
    if (paired) {
      final o = old[oldEnd - 1];
      final s = spans[newEnd - 1].$1;
      var most = o.length - (oldEnd - 1 == a ? p : 0);
      final room = s.length - (newEnd - 1 == a ? p : 0);
      if (room < most) {
        most = room;
      }
      var q = 0;
      while (q < most &&
          o.codeUnitAt(o.length - 1 - q) == s.codeUnitAt(s.length - 1 - q)) {
        q++;
      }
      e
        ..pairedOld = oldEnd - 1
        ..suffixFrom = s.length - q + 1
        ..lengthChange = s.length - o.length;
    }
    var units = -at;
    for (var k = a; k < m2; k++) {
      units += spans[k].$1.length;
    }
    if (e.glyphs.length < units) {
      final n = _room(units, e.glyphs.length);
      e
        ..glyphs = Uint32List(n)
        ..kinds = Uint16List(n)
        ..spanOf = Int32List(n)
        ..starts = Int32List(n)
        ..ends = Int32List(n);
    }
    final found = _scan(seg, a, at, from, edit: true);
    // clusters [from, os) were, [from, ns) are
    final os = e.syncOld;
    final ns = from + found;
    final delta = ns - os;
    final count = _count;
    final total = count + delta;
    var newlines = 0;
    var cells = 0;
    for (var i = from; i < os; i++) {
      if ((_kinds[i] & _newline) != 0) {
        newlines++;
      } else {
        cells += (_glyphs[i] & kWide) != 0 ? 2 : 1;
      }
    }
    final drawnKept = _drawn > os;
    if (_glyphs.length < total) {
      final n = _room(total, _glyphs.length);
      _glyphs = _move(_glyphs, Uint32List(n), from, os, ns, count);
      _kinds = _move(_kinds, Uint16List(n), from, os, ns, count);
      _spanOf = _move(_spanOf, Int32List(n), from, os, ns, count);
      _starts = _move(_starts, Int32List(n), from, os, ns, count);
      _ends = _move(_ends, Int32List(n), from, os, ns, count);
    } else if (delta != 0) {
      _move(_glyphs, _glyphs, from, os, ns, count);
      _move(_kinds, _kinds, from, os, ns, count);
      _move(_spanOf, _spanOf, from, os, ns, count);
      _move(_starts, _starts, from, os, ns, count);
      _move(_ends, _ends, from, os, ns, count);
    }
    // the clusters kept in the span they lined up in moved in its text,
    // and those of later spans to another span when spans came or went
    final shift = e.spanShift;
    final moved = e.syncInside && e.syncSpan == e.lastChanged
        ? e.pairedOld
        : -1;
    if (shift != 0 || moved >= 0) {
      final change = e.lengthChange;
      for (var i = ns; i < total; i++) {
        final k = _spanOf[i];
        if (k == moved) {
          _starts[i] += change;
          _ends[i] += change;
        } else if (shift == 0) {
          break;
        }
        _spanOf[i] = k + shift;
      }
    }
    _glyphs.setRange(from, ns, e.glyphs);
    _kinds.setRange(from, ns, e.kinds);
    _spanOf.setRange(from, ns, e.spanOf);
    _starts.setRange(from, ns, e.starts);
    _ends.setRange(from, ns, e.ends);
    _count = total;
    _hasMulti = _hasMulti || e.multi;
    _newlines += e.newlines - newlines;
    _cells += e.cells - cells;
    if (drawnKept) {
      _drawn += delta;
      _drawnCells += e.cells - cells;
    } else {
      var d = total;
      while (d > 0 && (_kinds[d - 1] & (_space | _newline)) != 0) {
        d--;
      }
      _drawn = d;
      _drawnCells = _cells - _widthOf(d, total);
    }
    if (_wordBreaks) {
      _breaksIn(from > 0 ? from - 1 : 0, ns + 1 < total ? ns + 1 : total);
    }
    if (_internedIn != null) {
      var f = from;
      var t = ns;
      if (_internFrom < _internTo) {
        final f0 = _internFrom;
        final t0 = _internTo;
        final mf = f0 < from ? f0 : (f0 >= os ? f0 + delta : from);
        final mt = t0 <= from ? t0 : (t0 >= os ? t0 + delta : ns);
        f = mf < f ? mf : f;
        t = mt > t ? mt : t;
      }
      _internFrom = f;
      _internTo = t;
    }
    _keepTexts();
    _bidiStale = true;
    if (_bidiOn && !_offsetsStale) {
      // drawn in visual order, which finds them after each edit
      _moveOffsets(from, os, ns, count);
    } else {
      _offsetsStale = true;
    }
    _segmentsStale = true;
    // the clusters the rows were built from that are as they were
    if (from < _changedFrom) {
      _changedFrom = from;
    }
    _changedTo = _changedTo + delta > ns ? _changedTo + delta : ns;
    _changedShift += delta;
    _spansMoved = _spansMoved || shift != 0;
    _linesAt = -1;
    if (_rawAt >= 0) {
      if (!_edited) {
        _edited = true;
        _editFrom = from;
        _editOld = os;
        _editNew = ns;
      } else {
        // the clusters as broken into lines are kept from the later of
        // the two places either edit kept them from
        final before = _editNew - _editOld;
        final kept = os - before > _editOld ? os - before : _editOld;
        _editFrom = from < _editFrom ? from : _editFrom;
        _editOld = kept;
        _editNew = kept + before + delta;
      }
    }
  }

  /// The offsets of the clusters brought up to an edit that split clusters
  /// [from, os) of [count] again into [from, ns): those of the clusters
  /// after them moved, those of the clusters split found.
  void _moveOffsets(int from, int os, int ns, int count) {
    final total = _count;
    final spans = _spans;
    var length = 0;
    for (var k = 0; k < spans.length; k++) {
      length += spans[k].$1.length;
    }
    final change = length - _offsets[count];
    var offsets = _offsets;
    if (offsets.length <= total) {
      offsets = Int32List(_room(total + 1, offsets.length))
        ..setRange(0, from + 1, _offsets);
    }
    offsets.setRange(ns + 1, total + 1, _offsets, os + 1);
    for (var i = ns + 1; i <= total; i++) {
      offsets[i] += change;
    }
    // where the span of each cluster split starts; the end of the one
    // before them too, which the end of the text was at the end
    var k = 0;
    var base = 0;
    for (var i = from > 0 ? from - 1 : 0; i < ns; i++) {
      final at = _spanOf[i];
      while (k < at) {
        base += spans[k++].$1.length;
      }
      offsets[i + 1] = base + _ends[i];
    }
    // the start; what takes no cell at the end goes with none
    offsets[0] = 0;
    offsets[total] = length;
    _offsets = offsets;
  }

  /// [to] with clusters [0, from) of [l] where they are, and clusters
  /// [os, count) at [ns] on; [to] may be [l].
  static T _move<T extends List<int>>(
    T l,
    T to,
    int from,
    int os,
    int ns,
    int count,
  ) {
    if (!identical(l, to)) {
      to.setRange(0, from, l);
    }
    to.setRange(ns, ns + count - os, l, os);
    return to;
  }

  /// Finds where each cluster starts in the spans' text joined: where the
  /// one before it ends, as what takes no cell goes with the cluster after
  /// it.
  void _findOffsets() {
    _offsetsStale = false;
    _offsetsFound++;
    final n = _count;
    if (_offsets.length <= n) {
      _offsets = Int32List(_room(n + 1, _offsets.length));
    }
    final offsets = _offsets;
    final spans = _spans;
    final spanOf = _spanOf;
    final ends = _ends;
    // where span k starts
    var k = 0;
    var base = 0;
    offsets[0] = 0;
    for (var i = 0; i + 1 < n; i++) {
      final at = spanOf[i];
      while (k < at) {
        base += spans[k++].$1.length;
      }
      offsets[i + 1] = base + ends[i];
    }
    while (k < spans.length) {
      base += spans[k++].$1.length;
    }
    offsets[n] = base;
  }

  /// Marks the clusters a line may break after by word.
  void _findWordBreaks() {
    _wordBreaks = true;
    _breaksIn(0, _count);
  }

  /// Marks which of clusters [from, to) a line may break after by word,
  /// what they were marked before cleared.
  void _breaksIn(int from, int to) {
    final n = _count;
    for (var i = from; i < to; i++) {
      final a = _kinds[i] & ~_break;
      _kinds[i] = a;
      if (i + 1 >= n) {
        break;
      }
      final b = _kinds[i + 1];
      if (((a | b) & _newline) != 0 || (a & _glue) != 0) {
        continue;
      }
      final bool breaks;
      if ((a & _space) != 0) {
        breaks = (b & _space) == 0;
      } else if ((b & _space) != 0) {
        // after the spaces
        breaks = false;
      } else if ((a & _zwsp) != 0) {
        breaks = true;
      } else if ((a & _hyphen) != 0) {
        // inside a word, not before a number: "well-known", not "-v",
        // "--", "-1"
        breaks =
            i > 0 &&
            (_kinds[i - 1] & (_space | _hyphen | _newline)) == 0 &&
            (b & (_hyphen | _digit)) == 0;
      } else {
        breaks =
            (a & b & _cjk) != 0 && (a & _cjkOpen) == 0 && (b & _cjkClose) == 0;
      }
      if (breaks) {
        _kinds[i] |= _break;
      }
    }
  }

  /// Columns of cluster [i].
  int _cellsOf(int i) =>
      (_glyphs[i] & kWide) != 0 ? 2 : ((_kinds[i] & _newline) != 0 ? 0 : 1);

  /// Columns of clusters [a, b).
  int _widthOf(int a, int b) {
    var w = 0;
    for (var i = a; i < b; i++) {
      w += _cellsOf(i);
    }
    return w;
  }

  /// Breaks the line that starts at cluster [from] to fit [maxW] columns;
  /// returns where the next one starts and leaves the end of what the line
  /// draws in [_end], its columns in [_endWidth], whether wrapping ended
  /// it in [_soft], whether it is the last in [_last] and in [_stop] the
  /// last cluster it read: clusters [from, _stop] decide the line, and
  /// for the first line of a text without line breaks the totals (then
  /// [_stop] is the count).
  int _breakLine(int from, int maxW) {
    final n = _count;
    final word = _wrap == TextWrap.word;
    final wraps = _wrap != TextWrap.none;
    if (from == 0 && _newlines == 0) {
      // all of it on one line, if it fits
      final w = word ? _drawnCells : _cells;
      if (!wraps || w <= maxW) {
        _end = word ? _drawn : n;
        _endWidth = w;
        _soft = false;
        _last = true;
        _stop = n;
        return n;
      }
    }
    // [from, j) is w columns; [from, end) is drawn, endW columns; a break
    // by word ends the line at brkEnd (brkW columns), the next starts at
    // brk
    var w = 0;
    var end = from;
    var endW = 0;
    var brk = -1;
    var brkEnd = from;
    var brkW = 0;
    for (var j = from; j < n;) {
      final kind = _kinds[j];
      if ((kind & _newline) != 0) {
        _end = end;
        _endWidth = endW;
        _soft = false;
        _last = false;
        _stop = j;
        return j + 1;
      }
      final cells = (_glyphs[j] & kWide) != 0 ? 2 : 1;
      if (word && (kind & _space) != 0) {
        // spaces hang: they never take a line over
        w += cells;
      } else {
        if (wraps && w + cells > maxW && j > from) {
          _soft = true;
          _last = false;
          _stop = j;
          if (brk >= 0) {
            _end = brkEnd;
            _endWidth = brkW;
            return brk;
          }
          // no break by word: between graphemes, unless one is wider than
          // the whole line
          var b = j;
          while (b > from && (_kinds[b - 1] & _glue) != 0) {
            b--;
          }
          if (b == from) {
            b = j;
          }
          _end = b;
          _endWidth = endW - _widthOf(b, j);
          return b;
        }
        w += cells;
        end = j + 1;
        endW = w;
      }
      j++;
      if (word && (kind & _break) != 0) {
        brk = j;
        brkEnd = end;
        brkW = endW;
      }
    }
    _end = end;
    _endWidth = endW;
    _soft = false;
    _last = true;
    _stop = n;
    return n;
  }

  /// The lines at [maxW] columns, up to [maxLines].
  int _countLines(int maxW) {
    _shape();
    if (maxW == _rawAt) {
      // the lines laid out, kept up with the text
      _updateRaw(maxW);
      final limit = _maxLines;
      return limit != null && _rawCount > limit ? limit : _rawCount;
    }
    var lines = 0;
    for (var from = 0; ;) {
      from = _breakLine(from, maxW);
      lines++;
      if (_last || lines == _maxLines) {
        return lines;
      }
    }
  }

  /// Lays the lines out at [maxW] columns, unless they are.
  void _layoutLines(int maxW) {
    _shape();
    if (_linesAt == maxW) {
      return;
    }
    _linesAt = maxW;
    _segmentsStale = true;
    _updateRaw(maxW);
    final limit = _maxLines;
    final overflow = _overflow;
    final t = _rawCount;
    final n = limit != null && t > limit ? limit : t;
    if (n * _lineStride > _lines.length) {
      _lines = Int32List(n * _lineStride * 2);
    }
    _lineCount = n;
    if (n == t || overflow == TextOverflow.clip) {
      for (var i = 0; i < n; i++) {
        _fromRaw(i, i, maxW);
      }
      return;
    }
    switch (overflow) {
      case TextOverflow.ellipsis:
        for (var i = 0; i < n - 1; i++) {
          _fromRaw(i, i, maxW);
        }
        // the last line runs on to the next line break of the text
        final s = _raw[(n - 1) * _rawStride];
        var e = _newlines == 0 ? _count : s;
        while (e < _count && (_kinds[e] & _newline) == 0) {
          e++;
        }
        _fitEnd(n - 1, s, e, maxW);
      case TextOverflow.ellipsisStart:
        // the first line shown runs back to the line break before it
        final f = t - n;
        var s = _newlines == 0 ? 0 : _raw[f * _rawStride];
        while (s > 0 && (_kinds[s - 1] & _newline) == 0) {
          s--;
        }
        _fitStart(0, s, _raw[f * _rawStride + 1], maxW);
        for (var i = 1; i < n; i++) {
          _fromRaw(i, f + i, maxW);
        }
      case TextOverflow.ellipsisMiddle:
        // the lines from the start and from the end around one with what
        // is between them
        final top = (n - 1) ~/ 2;
        final bottom = n - 1 - top;
        for (var i = 0; i < top; i++) {
          _fromRaw(i, i, maxW);
        }
        _fitMiddle(
          top,
          _raw[top * _rawStride],
          _raw[(t - 1 - bottom) * _rawStride + 1],
          maxW,
        );
        for (var i = 0; i < bottom; i++) {
          _fromRaw(top + 1 + i, t - bottom + i, maxW);
        }
      case TextOverflow.clip:
        break;
    }
  }

  /// Brings the lines as broken up to [maxW] columns: breaks them all
  /// again at another width, and after an edit those it may have changed.
  void _updateRaw(int maxW) {
    if (maxW != _rawAt) {
      _rawAt = maxW;
      _edited = false;
      _breakFrom(0, 0, maxW);
    } else if (_edited) {
      _edited = false;
      _rebreak(maxW);
    }
  }

  /// Whether all the lines are broken, not only one past [maxLines] (one
  /// more tells that text is cut off): the start or the middle cut off
  /// needs the last lines too.
  bool get _allLines =>
      _maxLines == null ||
      _overflow == TextOverflow.ellipsisStart ||
      _overflow == TextOverflow.ellipsisMiddle;

  /// Breaks the lines from line [t] on, which starts at cluster [from], at
  /// [maxW] columns, to the last or one past [maxLines].
  void _breakFrom(int t, int from, int maxW) {
    final limit = _maxLines;
    final all = _allLines;
    var raw = _raw;
    var line = t;
    for (var at = from; ;) {
      final next = _breakLine(at, maxW);
      raw = _putLine(raw, line++, at, next);
      if (_last || (!all && line > limit!)) {
        break;
      }
      at = next;
    }
    _linesBroken += line - t;
    _raw = raw;
    _rawCount = line;
  }

  /// Breaks again the lines an edit of the clusters may have changed: from
  /// the first that read a cluster at or after the one before the first
  /// that changed, up to one that starts where a line started before, past
  /// the changed clusters and the one after them (whose break by word
  /// depends on the cluster before); the lines from it on are those that
  /// were, moved with the clusters.
  void _rebreak(int maxW) {
    final raw = _raw;
    final count = _rawCount;
    final changed = _editFrom - 1;
    var keep = 0;
    while (keep < count && raw[keep * _rawStride + 4] < changed) {
      keep++;
    }
    if (keep == count) {
      // cut off at maxLines before the edit
      return;
    }
    final limit = _maxLines;
    final all = _allLines;
    final kept = _editNew;
    final delta = _editNew - _editOld;
    var fresh = _edit.lines;
    var made = 0;
    var old = keep;
    for (var from = raw[keep * _rawStride]; ;) {
      final next = _breakLine(from, maxW);
      fresh = _putLine(fresh, made++, from, next);
      if (_last || (!all && keep + made > limit!)) {
        break;
      }
      from = next;
      if (from <= kept) {
        continue;
      }
      final was = from - delta;
      while (old < count && raw[old * _rawStride] < was) {
        old++;
      }
      if (old == count || raw[old * _rawStride] != was) {
        continue;
      }
      // line old starts here: it and those after it are as they were
      final tail = count - old;
      var total = keep + made + tail;
      final cut = (raw[(count - 1) * _rawStride + 3] & 2) == 0;
      var lines = raw;
      if (total * _rawStride > lines.length) {
        lines = _grown(lines, total * _rawStride);
      }
      lines.setRange(
        (keep + made) * _rawStride,
        total * _rawStride,
        lines,
        old * _rawStride,
      );
      if (delta != 0) {
        for (var j = keep + made; j < total; j++) {
          final at = j * _rawStride;
          lines
            ..[at] += delta
            ..[at + 1] += delta
            ..[at + 4] += delta
            ..[at + 5] += delta;
        }
      }
      lines.setRange(keep * _rawStride, (keep + made) * _rawStride, fresh);
      _raw = lines;
      _edit.lines = fresh;
      _linesBroken += made;
      if (!all && total > limit! + 1) {
        total = limit + 1;
      }
      _rawCount = total;
      if (cut && total <= limit!) {
        // they were cut off at maxLines, which is further on now
        _breakFrom(total, lines[(total - 1) * _rawStride + 5], maxW);
      }
      return;
    }
    // no line lined up again
    var lines = raw;
    if ((keep + made) * _rawStride > lines.length) {
      lines = _grown(lines, (keep + made) * _rawStride);
    }
    lines.setRange(keep * _rawStride, (keep + made) * _rawStride, fresh);
    _raw = lines;
    _edit.lines = fresh;
    _linesBroken += made;
    _rawCount = keep + made;
  }

  /// [raw] with line [t] in it as [_breakLine] broke it from cluster
  /// [from], the next starting at [next]; grown when it has no room.
  Int32List _putLine(Int32List raw, int t, int from, int next) {
    final at = t * _rawStride;
    return (at + _rawStride > raw.length ? _grown(raw, at + _rawStride) : raw)
      ..[at] = from
      ..[at + 1] = _end
      ..[at + 2] = _endWidth
      ..[at + 3] = (_soft ? 1 : 0) | (_last ? 2 : 0)
      ..[at + 4] = _stop
      ..[at + 5] = next;
  }

  static Int32List _grown(Int32List l, int least) {
    var n = l.length < 16 ? 16 : l.length * 2;
    while (n < least) {
      n *= 2;
    }
    return Int32List(n)..setRange(0, l.length, l);
  }

  /// Line [i] is the line broken as [r], with an ellipsis if it is too long.
  void _fromRaw(int i, int r, int maxW) {
    final at = r * _rawStride;
    final s = _raw[at];
    final e = _raw[at + 1];
    final w = _raw[at + 2];
    if (w > maxW) {
      switch (_overflow) {
        case TextOverflow.clip:
          break;
        case TextOverflow.ellipsis:
          _fitEnd(i, s, e, maxW);
          return;
        case TextOverflow.ellipsisStart:
          _fitStart(i, s, e, maxW);
          return;
        case TextOverflow.ellipsisMiddle:
          _fitMiddle(i, s, e, maxW);
          return;
      }
    }
    _setLine(i, s, e, e, e, -1, w, soft: (_raw[at + 3] & 1) != 0);
  }

  void _setLine(
    int i,
    int headStart,
    int headEnd,
    int tailStart,
    int tailEnd,
    int ellipsis,
    int width, {
    bool soft = false,
    int? from,
  }) {
    final at = i * _lineStride;
    _lines
      ..[at] = headStart
      ..[at + 1] = headEnd
      ..[at + 2] = tailStart
      ..[at + 3] = tailEnd
      ..[at + 4] = ellipsis
      ..[at + 5] = width
      ..[at + 6] = soft ? 1 : 0
      ..[at + 7] = from ?? headStart;
  }

  /// [h] moved back so that it splits no grapheme and no space comes before
  /// the ellipsis; not before [s].
  int _trimBack(int s, int h) {
    var at = h;
    while (at > s && (_kinds[at - 1] & _glue) != 0) {
      at--;
    }
    while (at > s && (_kinds[at - 1] & _space) != 0) {
      at--;
    }
    return at;
  }

  /// [t] moved on so that it splits no grapheme and no space comes after
  /// the ellipsis; not past [e].
  int _trimFront(int t, int e) {
    var at = t;
    while (at < e && at > 0 && (_kinds[at - 1] & _glue) != 0) {
      at++;
    }
    while (at < e && (_kinds[at] & _space) != 0) {
      at++;
    }
    return at;
  }

  /// The span whose pen draws an ellipsis in place of cluster [i] (one of
  /// those it stands for, next to what is kept).
  int _spanAt(int i) => _spanOf[i < _count ? i : _count - 1];

  /// Line [i] as clusters [s, e) (no line break among them) to fit [maxW]
  /// columns, "…" in place of the end. With no room for it, cut off.
  void _fitEnd(int i, int s, int e, int maxW) {
    final room = maxW - _ellipsisWidth;
    if (room < 0) {
      _setLine(i, s, e, e, e, -1, _widthOf(s, e));
      return;
    }
    var h = s;
    for (var w = 0; h < e; h++) {
      w += _cellsOf(h);
      if (w > room) {
        break;
      }
    }
    h = _trimBack(s, h);
    _setLine(i, s, h, h, h, _spanAt(h), _widthOf(s, h) + _ellipsisWidth);
  }

  /// Line [i] as clusters [s, e) (no line break among them) to fit [maxW]
  /// columns, "…" in place of the start. With no room for it, cut off.
  void _fitStart(int i, int s, int e, int maxW) {
    final room = maxW - _ellipsisWidth;
    if (room < 0) {
      _setLine(i, s, e, e, e, -1, _widthOf(s, e));
      return;
    }
    var t = e;
    for (var w = 0; t > s; t--) {
      w += _cellsOf(t - 1);
      if (w > room) {
        break;
      }
    }
    t = _trimFront(t, e);
    _setLine(
      i,
      t,
      t,
      t,
      e,
      _spanAt(t > 0 ? t - 1 : 0),
      _widthOf(t, e) + _ellipsisWidth,
      from: s,
    );
  }

  /// Line [i] as clusters [s, e) to fit [maxW] columns, "…" in place of the
  /// middle: what is before it from the start, up to a line break of the
  /// text, half the room or more; what is after it from the end, up to a
  /// line break, the rest. With no room for it, cut off.
  void _fitMiddle(int i, int s, int e, int maxW) {
    final room = maxW - _ellipsisWidth;
    if (room < 0) {
      var h = s;
      while (h < e && (_kinds[h] & _newline) == 0) {
        h++;
      }
      _setLine(i, s, h, h, h, -1, _widthOf(s, h));
      return;
    }
    var h = _grow(s, e, (room + 1) >> 1);
    h = _trimBack(s, h);
    var t = e;
    final tailRoom = room - _widthOf(s, h);
    for (var w = 0; t > h && (_kinds[t - 1] & _newline) == 0; t--) {
      w += _cellsOf(t - 1);
      if (w > tailRoom) {
        break;
      }
    }
    t = _trimFront(t, e);
    // the room the end left over
    h = _trimBack(s, _grow(s, t, room - _widthOf(t, e)));
    if (h >= t) {
      _setLine(i, s, e, e, e, -1, _widthOf(s, e));
      return;
    }
    _setLine(
      i,
      s,
      h,
      t,
      e,
      _spanAt(h),
      _widthOf(s, h) + _ellipsisWidth + _widthOf(t, e),
    );
  }

  /// The end of the most clusters from [s], before [e] and any line break,
  /// that fit [room] columns.
  int _grow(int s, int e, int room) {
    var h = s;
    for (var w = 0; h < e && (_kinds[h] & _newline) == 0; h++) {
      w += _cellsOf(h);
      if (w > room) {
        break;
      }
    }
    return h;
  }

  @override
  void performLayout(BoxConstraints c) {
    _layoutLines(c.maxW);
    var widest = 0;
    for (var i = 0; i < _lineCount; i++) {
      final w = _lines[i * _lineStride + 5];
      widest = w > widest ? w : widest;
    }
    width = c.constrainW(widest);
    height = c.constrainH(_lineCount);
    _segmentsStale = true;
  }

  @override
  int computeMinIntrinsicWidth(int height) {
    _shape();
    if (_wrap == TextWrap.none) {
      return _widestLine();
    }
    // the widest piece between two places a line may break
    final word = _wrap == TextWrap.word;
    var widest = 0;
    var w = 0;
    var drawn = 0;
    for (var i = 0; i < _count; i++) {
      final kind = _kinds[i];
      if ((kind & _newline) == 0) {
        w += _cellsOf(i);
        if (!word || (kind & _space) == 0) {
          drawn = w;
        }
        if (word ? (kind & _break) == 0 : (kind & _glue) != 0) {
          continue;
        }
      }
      widest = drawn > widest ? drawn : widest;
      w = 0;
      drawn = 0;
    }
    return drawn > widest ? drawn : widest;
  }

  @override
  int computeMaxIntrinsicWidth(int height) {
    _shape();
    return _widestLine();
  }

  /// The widest line between line breaks of the text.
  int _widestLine() {
    final word = _wrap == TextWrap.word;
    var widest = 0;
    var w = 0;
    var drawn = 0;
    for (var i = 0; i < _count; i++) {
      final kind = _kinds[i];
      if ((kind & _newline) != 0) {
        widest = drawn > widest ? drawn : widest;
        w = 0;
        drawn = 0;
        continue;
      }
      w += _cellsOf(i);
      if (!word || (kind & _space) == 0) {
        drawn = w;
      }
    }
    return drawn > widest ? drawn : widest;
  }

  @override
  int computeMinIntrinsicHeight(int width) => _countLines(width);

  @override
  int computeMaxIntrinsicHeight(int width) => _countLines(width);

  /// How many times this paragraph has found where its clusters start in
  /// its text, which [textRangeAt] does the first time it is asked after
  /// the text is split, and a layout in visual order of text it reorders.
  int get debugOffsetsFound => _offsetsFound;

  /// How many clusters this paragraph has split its text into, counting
  /// each split: all of them when it first splits it, about those an edit
  /// touched after.
  int get debugClustersSplit => _clustersSplit;

  /// How many lines this paragraph has broken its clusters into, counting
  /// each layout: all of them at a new width, about those an edit touched
  /// after.
  int get debugLinesBroken => _linesBroken;

  /// How many code units of its text this paragraph has resolved the
  /// bidirectional levels of in visual order, counting each time: all of
  /// it the first time, about what an edit can have changed after.
  int get debugLevelsResolved => _levelsResolved;

  /// How many code units of its text this paragraph has copied into
  /// strings to resolve the bidirectional levels of in visual order,
  /// counting each time: the text of its spans joined the first time,
  /// about what an edit can have changed after.
  int get debugBidiUnitsCopied => _bidiWas.copied + _bidiNow.copied;

  /// How many rows this paragraph has ordered for drawing in visual order,
  /// counting each paint after a change: all of them the first time, those
  /// a change can have touched after.
  int get debugLinesOrdered => _linesOrdered;

  /// For tests: what differs between the clusters and lines this paragraph
  /// keeps up with its edits and those of its spans split and broken from
  /// scratch at the width it last broke them at; null when nothing does.
  /// It splits and breaks again what changed first, as a layout would.
  String? debugDiffFromFresh() {
    final seg = owner?.segmenter ?? _detachedSegmenter;
    if (_shapedMode == null) {
      return null;
    }
    _shape();
    final fresh = RenderParagraph(
      _spans,
      wrap: _wrap,
      overflow: _overflow,
      maxLines: _maxLines,
      align: _align,
    ).._split(seg);
    if (_wordBreaks) {
      fresh._findWordBreaks();
    }
    String? differ(String what, int a, int b) =>
        a == b ? null : '$what: $a, from scratch $b';
    final totals =
        differ('clusters', _count, fresh._count) ??
        differ('line breaks', _newlines, fresh._newlines) ??
        differ('columns', _cells, fresh._cells) ??
        differ('drawn', _drawn, fresh._drawn) ??
        differ('drawn columns', _drawnCells, fresh._drawnCells);
    if (totals != null) {
      return totals;
    }
    if (fresh._hasMulti && !_hasMulti) {
      return 'no clusters of several code points';
    }
    for (var i = 0; i < _count; i++) {
      final multi = (fresh._kinds[i] & _multi) != 0;
      final mask = multi ? ~kGlyphMask : -1;
      final d =
          differ('glyph $i', _glyphs[i] & mask, fresh._glyphs[i] & mask) ??
          differ('kind $i', _kinds[i], fresh._kinds[i]) ??
          differ('span of $i', _spanOf[i], fresh._spanOf[i]) ??
          differ('start of $i', _starts[i], fresh._starts[i]) ??
          differ('end of $i', _ends[i], fresh._ends[i]);
      if (d != null) {
        return d;
      }
    }
    if (!_offsetsStale) {
      fresh._findOffsets();
      for (var i = 0; i <= _count; i++) {
        final d = differ('offset $i', _offsets[i], fresh._offsets[i]);
        if (d != null) {
          return d;
        }
      }
    }
    final bidi = _bidiDiff();
    if (bidi != null) {
      return bidi;
    }
    if (_rawAt < 0) {
      return null;
    }
    _updateRaw(_rawAt);
    fresh._updateRaw(_rawAt);
    final lines = differ('lines', _rawCount, fresh._rawCount);
    if (lines != null) {
      return lines;
    }
    for (var j = 0; j < _rawCount * _rawStride; j++) {
      final d = differ(
        'line ${j ~/ _rawStride} field ${j % _rawStride}',
        _raw[j],
        fresh._raw[j],
      );
      if (d != null) {
        return d;
      }
    }
    return null;
  }

  /// What differs between the levels this paragraph keeps up with its
  /// edits and those its text resolves to from scratch; null when nothing
  /// does.
  String? _bidiDiff() {
    if (!_bidiValid) {
      return _bidiOn ? 'reordered without levels' : null;
    }
    final was = _bidiWas;
    final copied = was.copied;
    final text = was.join();
    was.copied = copied;
    final b = StringBuffer();
    for (var k = 0; k < _spans.length; k++) {
      b.write(_spans[k].$1);
    }
    if (b.toString() != text) {
      return 'levels of another text';
    }
    final fresh = BidiText(text);
    if (_bidiOn == fresh.isLeftToRight) {
      return 'reordered: $_bidiOn';
    }
    final classes = Uint8List(text.length);
    _classesOf(was, classes, 0, text.length);
    for (var i = 0; i < text.length; i++) {
      if (_levels[i] != fresh.levels[i]) {
        return 'level at $i: ${_levels[i]}, from scratch ${fresh.levels[i]}';
      }
      if (_classes[i] != classes[i]) {
        return 'class at $i: ${_classes[i]}, from scratch ${classes[i]}';
      }
    }
    final paragraphs = fresh.paragraphs;
    if (_paraCount != paragraphs.length) {
      return 'paragraphs: $_paraCount, from scratch ${paragraphs.length}';
    }
    for (var p = 0; p < _paraCount; p++) {
      if (_paraStarts[p] != paragraphs[p].start ||
          _paraLevels[p] != paragraphs[p].level) {
        return 'paragraph $p: ${_paraStarts[p]} at ${_paraLevels[p]}, '
            'from scratch ${paragraphs[p]}';
      }
    }
    if (_nonZero != _nonZeroIn(fresh.levels, 0, text.length)) {
      return 'levels not 0: $_nonZero';
    }
    return null;
  }

  /// The text at column [x] of row [y] as the last layout placed it, as
  /// offsets (start, end) into the text of the spans joined, in UTF-16
  /// code units: the cluster drawn there, at either cell of a wide one (at
  /// an ellipsis, the clusters it stands for; in a gap a justified row
  /// stretches, the space before it). Left of a row's text it is the empty
  /// range where the row starts; right of it, and past the width, the
  /// empty range where the next row starts, after the spaces the row hangs
  /// and its line break, which right of the last row is the end of the
  /// text. Above the first row it is (0, 0), below the last (length,
  /// length). What takes no cell (a zero-width control, the CR of CR LF)
  /// goes with the cluster after it, so that the ranges tile the text. In
  /// visual order ([TextOrder.visual]) it is the cluster drawn there too,
  /// and the sides of a row keep their logical meaning: left of the text
  /// the start, right of it the next row's, in either direction.
  (int, int) textRangeAt(int x, int y) {
    final c = _constraints;
    if (c == null || y < 0) {
      return (0, 0);
    }
    _layoutLines(c.maxW);
    if (_offsetsStale) {
      _findOffsets();
    }
    final offsets = _offsets;
    final rows = _lineCount < height ? _lineCount : height;
    if (y >= rows) {
      final end = offsets[_count];
      return (end, end);
    }
    final at = y * _lineStride;
    final from = y == 0 ? 0 : _lines[at + 7];
    final next = y + 1 < _lineCount ? _lines[at + _lineStride + 7] : _count;
    final free = width - _lines[at + 5];
    final headStart = _lines[at];
    final headEnd = _lines[at + 1];
    final tailStart = _lines[at + 2];
    final tailEnd = _lines[at + 3];
    final ellipsis = _lines[at + 4];
    final stretch =
        _align == TextAlign.justify &&
        _lines[at + 6] != 0 &&
        ellipsis < 0 &&
        free > 0;
    final visual = _bidiOn;
    final n = visual ? _orderLine(y) : 0;
    final rtl = visual && _rtlLine(y);
    final gaps = !stretch
        ? 0
        : (visual ? _visualGaps(n, rtl) : _gapsIn(headStart, headEnd));
    var col = gaps > 0 ? 0 : _lineX(free, rtl);
    if (x < 0 || x < col) {
      return (offsets[from], offsets[from]);
    }
    if (x >= width) {
      return (offsets[next], offsets[next]);
    }
    if (visual) {
      var gap = 0;
      for (var j = 0; j < n; j++) {
        final i = _visual[j];
        if (i < 0) {
          col += _ellipsisWidth;
          if (x < col) {
            final hidden = headStart < headEnd ? headEnd : from;
            final shown = tailStart < tailEnd ? tailStart : next;
            return (offsets[hidden], offsets[shown]);
          }
          continue;
        }
        // a gap goes with its space
        col += _cellsOf(i);
        if (gaps > 0 && _gapAt(j, i, rtl)) {
          col += _part(free, gaps, rtl ? gaps - 1 - gap : gap);
          gap++;
        }
        if (x < col) {
          return (offsets[i], offsets[i + 1]);
        }
      }
      return (offsets[next], offsets[next]);
    }
    var gap = 0;
    var words = false;
    for (var i = headStart; i < headEnd; i++) {
      col += _cellsOf(i);
      final space = (_kinds[i] & _space) != 0;
      if (gaps > 0 && space && words) {
        col += _part(free, gaps, gap++);
      }
      if (x < col) {
        return (offsets[i], offsets[i + 1]);
      }
      words = words || !space;
    }
    if (ellipsis >= 0) {
      col += _ellipsisWidth;
      if (x < col) {
        final hidden = headStart < headEnd ? headEnd : from;
        final shown = tailStart < tailEnd ? tailStart : next;
        return (offsets[hidden], offsets[shown]);
      }
    }
    for (var i = tailStart; i < tailEnd; i++) {
      col += _cellsOf(i);
      if (x < col) {
        return (offsets[i], offsets[i + 1]);
      }
    }
    return (offsets[next], offsets[next]);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    if (_linesAt < 0) {
      // split again since the layout: the lines at the width it had
      _layoutLines(_constraints!.maxW);
    }
    if (_hasMulti) {
      if (!identical(_internedIn, canvas.glyphs) ||
          canvas.glyphs.sweeps != _internedSweeps) {
        _intern(canvas.glyphs, 0, _count);
        _rowsKept = false;
      } else if (_internFrom < _internTo) {
        _changed(_internFrom, _internTo);
        _intern(canvas.glyphs, _internFrom, _internTo);
      }
    }
    if (_segmentsStale) {
      _buildSegments();
    }
    _resolvePens(canvas.styles);
    final ids = _penIds;
    final seg = _segments;
    for (var k = 0; k < _segmentCount; k++) {
      final at = k * _segmentStride;
      final x = seg[at];
      final y = seg[at + 1];
      final pen = ids[seg[at + 2]];
      switch (seg[at + 4]) {
        case _fromClusters:
          canvas.runRange(x, y, _glyphs, seg[at + 5], seg[at + 6], pen);
        case _fromOrdered:
          canvas.runRange(x, y, _runGlyphs, seg[at + 5], seg[at + 6], pen);
        case _fromEllipsis:
          canvas.run(x, y, _ellipsisRun, pen);
        default:
          canvas.fill(x, y, seg[at + 3], 1, pen);
      }
    }
  }

  /// Looks the pens of the spans up in [styles] unless they were.
  void _resolvePens(StyleTable styles) {
    if (identical(styles, _pensIn)) {
      return;
    }
    _pensIn = styles;
    final n = _spans.length;
    if (_penIds.length < n) {
      _penIds = Int32List(_room(n, _penIds.length));
    }
    for (var k = 0; k < n; k++) {
      _penIds[k] = styles.pen(_spans[k].$2);
    }
  }

  /// Gives the clusters of several code points among [from, to) their
  /// ids in [glyphs], which the others have.
  void _intern(GlyphTable glyphs, int from, int to) {
    for (var i = from; i < to; i++) {
      if ((_kinds[i] & _multi) != 0) {
        final id = glyphs.intern(_spans[_spanOf[i]].$1, _starts[i], _ends[i]);
        _glyphs[i] = (_glyphs[i] & ~kGlyphMask) | id;
      }
    }
    _internedIn = glyphs;
    _internedSweeps = glyphs.sweeps;
    _internFrom = 0;
    _internTo = 0;
    // the lines ordered for drawing hold copies
    _segmentsStale = true;
  }

  /// Works out what painting draws: a glyph run for each piece of a line
  /// in one span, the ellipsis, and the gaps a justified line stretches.
  void _buildSegments() {
    final rows = _lineCount < height ? _lineCount : height;
    if (_bidiOn) {
      _buildOrdered(rows);
    } else {
      _buildStored(rows);
      _rowsKept = false;
    }
    _segmentsStale = false;
    _changedFrom = 1 << 30;
    _changedTo = 0;
    _changedShift = 0;
    _spansMoved = false;
  }

  /// [_buildSegments] for [rows] rows of a line ordered for drawing each:
  /// those of the rows built before that are drawn from clusters the
  /// changes since left as they were, at the same width, are taken from
  /// them; the others are ordered again.
  void _buildOrdered(int rows) {
    final keep = _rowsKept && width == _rowsWidth;
    // what the rows were built into is taken from, and built into next
    final segments = _segments;
    final glyphs = _runGlyphs;
    final rowAt = _rowAt;
    _segments = _segmentsWere;
    _segmentsWere = segments;
    _runGlyphs = _runGlyphsWere;
    _runGlyphsWere = glyphs;
    _rowAt = _rowAtWere;
    _rowAtWere = rowAt;
    _segmentCount = 0;
    _runGlyphCount = 0;
    if (_rowAt.length < 2 * rows + 2) {
      _rowAt = Int32List(_room(2 * rows + 2, _rowAt.length));
    }
    final lines = _lines;
    final were = _linesWere;
    final from = _changedFrom;
    final to = _changedTo;
    final shift = _changedShift;
    var j = 0;
    for (var y = 0; y < rows; y++) {
      _rowAt[2 * y] = _segmentCount;
      _rowAt[2 * y + 1] = _runGlyphCount;
      final at = y * _lineStride;
      if (keep) {
        // the clusters the row is drawn from
        final first = lines[at + 7];
        final hs = lines[at];
        final lo = first < hs ? first : hs;
        var hi = lines[at + 1] > lines[at + 3] ? lines[at + 1] : lines[at + 3];
        hi = first + 1 > hi ? first + 1 : hi;
        final before = hi <= from;
        if (before || (lo >= to && !_spansMoved)) {
          final by = before ? 0 : shift;
          while (j < _rowsWere && _rowStart(were, j) < lo - by) {
            j++;
          }
          if (j < _rowsWere && _sameRow(were, j, at, by)) {
            _copyRow(j, y);
            continue;
          }
        }
      }
      _orderRow(y);
    }
    _rowAt[2 * rows] = _segmentCount;
    _rowAt[2 * rows + 1] = _runGlyphCount;
    final n = rows * _lineStride;
    if (_linesWere.length < n) {
      _linesWere = Int32List(_room(n, _linesWere.length));
    }
    _linesWere.setRange(0, n, lines);
    _rowsWere = rows;
    _rowsWidth = width;
    _rowsKept = true;
  }

  /// The first cluster row [j] of [lines] is drawn from.
  static int _rowStart(Int32List lines, int j) {
    final first = lines[j * _lineStride + 7];
    final hs = lines[j * _lineStride];
    return first < hs ? first : hs;
  }

  /// Whether row [j] as it was built is the line at [at] of [_lines] with
  /// its clusters [by] before.
  bool _sameRow(Int32List were, int j, int at, int by) {
    final w = j * _lineStride;
    final l = _lines;
    return were[w] + by == l[at] &&
        were[w + 1] + by == l[at + 1] &&
        were[w + 2] + by == l[at + 2] &&
        were[w + 3] + by == l[at + 3] &&
        were[w + 4] == l[at + 4] &&
        were[w + 5] == l[at + 5] &&
        were[w + 6] == l[at + 6] &&
        were[w + 7] + by == l[at + 7];
  }

  /// Row [j] as it was built, as row [y].
  void _copyRow(int j, int y) {
    final s0 = _rowAtWere[2 * j];
    final s1 = _rowAtWere[2 * j + 2];
    final g0 = _rowAtWere[2 * j + 1];
    final n = _rowAtWere[2 * j + 3] - g0;
    final had = _runGlyphCount;
    if (_runGlyphs.length < had + n) {
      _runGlyphs = Uint32List(_room(had + n, _runGlyphs.length))
        ..setRange(0, had, _runGlyphs);
    }
    _runGlyphs.setRange(had, had + n, _runGlyphsWere, g0);
    _runGlyphCount = had + n;
    final by = had - g0;
    final were = _segmentsWere;
    for (var k = s0; k < s1; k++) {
      final at = k * _segmentStride;
      final from = were[at + 4];
      final o = from == _fromOrdered ? by : 0;
      _addSegment(
        from,
        were[at + 5] + o,
        were[at + 6] + o,
        were[at],
        y,
        were[at + 2],
        were[at + 3],
      );
    }
  }

  /// Orders row [y] for drawing and adds its segments.
  void _orderRow(int y) {
    _linesOrdered++;
    final at = y * _lineStride;
    final ellipsis = _lines[at + 4];
    final free = width - _lines[at + 5];
    final stretch =
        _align == TextAlign.justify &&
        _lines[at + 6] != 0 &&
        ellipsis < 0 &&
        free > 0;
    final n = _orderLine(y);
    final rtl = _rtlLine(y);
    final gaps = stretch ? _visualGaps(n, rtl) : 0;
    final x = gaps > 0 ? 0 : _lineX(free, rtl);
    _addVisual(n, x, y, gaps, free, rtl, ellipsis);
  }

  /// [_buildSegments] for [rows] rows of text drawn as stored.
  void _buildStored(int rows) {
    _segmentCount = 0;
    _runGlyphCount = 0;
    for (var y = 0; y < rows; y++) {
      final at = y * _lineStride;
      final ellipsis = _lines[at + 4];
      final free = width - _lines[at + 5];
      final stretch =
          _align == TextAlign.justify &&
          _lines[at + 6] != 0 &&
          ellipsis < 0 &&
          free > 0;
      final gaps = stretch ? _gapsIn(_lines[at], _lines[at + 1]) : 0;
      var x = gaps > 0 ? 0 : _lineX(free, false);
      x = _addClusters(
        _lines[at],
        _lines[at + 1],
        x,
        y,
        gaps,
        free,
        ellipsis < 0 ? _lines[at + 5] : -1,
      );
      if (ellipsis >= 0) {
        final e = _ellipsisWidth;
        _addSegment(_fromEllipsis, 0, 0, x, y, ellipsis, e);
        x += e;
      }
      _addClusters(_lines[at + 2], _lines[at + 3], x, y, 0, 0);
    }
  }

  GlyphRun get _ellipsisRun {
    final e = _ellipsisWidth;
    return _ellipsis ??= GlyphRun(
      Uint32List(1)..[0] = e == 2 ? 0x2026 | kWide : 0x2026,
      e,
    );
  }

  /// The column a line that leaves [free] columns starts at, as [align]
  /// places it in a paragraph that runs right to left when [rtl].
  int _lineX(int free, bool rtl) {
    if (free < 0) {
      return rtl ? free : 0;
    }
    return switch (_align) {
      TextAlign.left => 0,
      TextAlign.center => free ~/ 2,
      TextAlign.right => free,
      TextAlign.justify || TextAlign.start => rtl ? free : 0,
      TextAlign.end => rtl ? 0 : free,
    };
  }

  /// Whether line [y] is in a paragraph that runs right to left; in visual
  /// order only.
  bool _rtlLine(int y) {
    final k = _lines[y * _lineStride + 7];
    final unit = k < _count ? _offsets[k + 1] - 1 : _offsets[_count];
    return _paraLevels[_paragraphAt(unit)].isOdd;
  }

  /// Puts the items of line [y] in the order they are drawn from left to
  /// right ([_visual], [_visualOdd]) and returns how many there are: its
  /// clusters at the levels UAX #9 resolves for the paragraph, rule L1
  /// applied to the line; its ellipsis at the lower level of what is
  /// either side of it, the paragraph's at an end; each run at a level or
  /// above reversed, from the highest level to the lowest odd one (rule
  /// L2), and the clusters of a grapheme kept in their order.
  int _orderLine(int y) {
    final at = y * _lineStride;
    final hs = _lines[at];
    final he = _lines[at + 1];
    final ts = _lines[at + 2];
    final te = _lines[at + 3];
    final ellipsis = _lines[at + 4] >= 0;
    final h = he - hs;
    final n = h + te - ts + (ellipsis ? 1 : 0);
    if (_items.length < n) {
      _items = Int32List(n * 2);
      _itemLevels = Uint8List(n * 2);
      _itemOrder = Int32List(n * 2);
      _visual = Int32List(n * 2);
      _visualOdd = Uint8List(n * 2);
    }
    final items = _items;
    final levels = _itemLevels;
    _levelsOf(hs, he, 0);
    if (ellipsis) {
      _levelsOf(ts, te, h + 1);
      final k = _lines[at + 7];
      final unit = k < _count ? _offsets[k + 1] - 1 : _offsets[_count];
      final base = _paraLevels[_paragraphAt(unit)];
      final before = h > 0 ? levels[h - 1] : base;
      final after = te > ts ? levels[h + 1] : base;
      items[h] = -1;
      levels[h] = before < after ? before : after;
    }
    final order = _itemOrder;
    var highest = 0;
    var lowestOdd = 0xFF;
    for (var k = 0; k < n; k++) {
      order[k] = k;
      final l = levels[k];
      highest = l > highest ? l : highest;
      if (l.isOdd && l < lowestOdd) {
        lowestOdd = l;
      }
    }
    for (var level = highest; level >= lowestOdd; level--) {
      for (var i = 0; i < n; i++) {
        if (levels[order[i]] < level) {
          continue;
        }
        var j = i + 1;
        while (j < n && levels[order[j]] >= level) {
          j++;
        }
        for (var a = i, b = j - 1; a < b; a++, b--) {
          final t = order[a];
          order[a] = order[b];
          order[b] = t;
        }
        i = j;
      }
    }
    final vis = _visual;
    for (var j = 0; j < n; j++) {
      final k = order[j];
      vis[j] = items[k];
      _visualOdd[j] = levels[k] & 1;
    }
    if (_shapedMode != TextMode.graphemes) {
      // legacy mode: a grapheme of several clusters reversed with its run,
      // its clusters one before the other from the right, is put back
      for (var j = 0; j + 1 < n; j++) {
        var e = j;
        while (e + 1 < n &&
            vis[e] > 0 &&
            vis[e + 1] == vis[e] - 1 &&
            (_kinds[vis[e + 1]] & _glue) != 0) {
          e++;
        }
        for (var a = j, b = e; a < b; a++, b--) {
          final t = vis[a];
          vis[a] = vis[b];
          vis[b] = t;
        }
        j = e;
      }
    }
    return n;
  }

  /// Puts clusters [a, b) of a line into the items from [k] on, with
  /// their levels by rule L1 for them as the line, in pieces where a
  /// paragraph separator that breaks no line (FS, GS, RS) ends one.
  void _levelsOf(int a, int b, int k) {
    if (a == b) {
      return;
    }
    final end = _offsets[b];
    var from = _offsets[a];
    var to = from;
    var at = k;
    for (var i = a; i < b; i++) {
      final unit = _offsets[i + 1] - 1;
      while (unit >= to) {
        from = to;
        final p = _paragraphAt(from);
        final e = _paragraphEnd(p);
        to = e < end ? e : end;
        _lineLevelsOf(from, to, _paraLevels[p]);
      }
      _items[at] = i;
      _itemLevels[at++] = _lineLevels[unit - from];
    }
  }

  /// Puts the levels of code units [start, end) of a line, in a paragraph
  /// of level [base], into [_lineLevels] after rule L1: separators, and
  /// the whitespace and isolate formatting characters before them and at
  /// the end of the line, take the paragraph's level.
  void _lineLevelsOf(int start, int end, int base) {
    final n = end - start;
    if (_lineLevels.length < n) {
      _lineLevels = Uint8List(_room(n, _lineLevels.length));
    }
    final out = _lineLevels;
    final levels = _levels;
    final classes = _classes;
    var reset = true;
    for (var i = end - 1; i >= start; i--) {
      final c = classes[i];
      if (c == _bcB || c == _bcS) {
        out[i - start] = base;
        reset = true;
      } else if (reset && (1 << c & _bcTrailing) != 0) {
        out[i - start] = base;
      } else {
        reset = false;
        out[i - start] = levels[i];
      }
    }
  }

  // the first and the last item of a line ordered for drawing that is not
  // a space, found by _visualGaps
  var _firstWord = 0;
  var _lastWord = 0;

  /// The spaces among the [n] items of a line ordered for drawing that a
  /// justified line stretches: those after a word as it reads, from the
  /// left or, when [rtl], from the right.
  int _visualGaps(int n, bool rtl) {
    _firstWord = n;
    _lastWord = -1;
    for (var j = 0; j < n; j++) {
      final i = _visual[j];
      if (i < 0 || (_kinds[i] & _space) == 0) {
        if (_firstWord == n) {
          _firstWord = j;
        }
        _lastWord = j;
      }
    }
    var gaps = 0;
    for (var j = 0; j < n; j++) {
      final i = _visual[j];
      if (i >= 0 && _gapAt(j, i, rtl)) {
        gaps++;
      }
    }
    return gaps;
  }

  /// Whether item [j], cluster [i], of a line ordered for drawing is a
  /// space a justified line stretches ([_visualGaps]).
  bool _gapAt(int j, int i, bool rtl) =>
      (_kinds[i] & _space) != 0 && (rtl ? j < _lastWord : j > _firstWord);

  /// Adds the [n] items of line [y] ordered for drawing at column [x]: a
  /// run for each piece in one span, the clusters at an odd level with
  /// their mirrored glyphs (rule L4), the ellipsis in the pen of span
  /// [ellipsis]; with [gaps], [free] blank cells shared out beside the
  /// spaces after words as the line reads, from the right when [rtl].
  void _addVisual(
    int n,
    int x,
    int y,
    int gaps,
    int free,
    bool rtl,
    int ellipsis,
  ) {
    final had = _runGlyphCount;
    if (_runGlyphs.length < had + n) {
      _runGlyphs = Uint32List(_room(had + n, _runGlyphs.length))
        ..setRange(0, had, _runGlyphs);
    }
    final glyphs = _runGlyphs;
    var at = x;
    // the glyphs gathered for the piece being added end at _runGlyphCount
    var count = 0;
    var w = 0;
    var span = -1;
    var gap = 0;
    for (var j = 0; j < n; j++) {
      final i = _visual[j];
      if (count > 0 && (i < 0 || _spanOf[i] != span)) {
        _addGlyphs(count, at, y, span, w);
        at += w;
        count = 0;
        w = 0;
      }
      if (i < 0) {
        _addSegment(_fromEllipsis, 0, 0, at, y, ellipsis, _ellipsisWidth);
        at += _ellipsisWidth;
        continue;
      }
      final stretched = gaps > 0 && _gapAt(j, i, rtl);
      final extra = stretched
          ? _part(free, gaps, rtl ? gaps - 1 - gap++ : gap++)
          : 0;
      if (extra > 0 && rtl) {
        if (count > 0) {
          _addGlyphs(count, at, y, span, w);
          at += w;
          count = 0;
          w = 0;
        }
        _addSegment(_fromGap, 0, 0, at, y, _spanOf[i], extra);
        at += extra;
      }
      span = _spanOf[i];
      var g = _glyphs[i];
      if (_visualOdd[j] != 0 && (_kinds[i] & (_multi | _newline)) == 0) {
        g = (g & ~kGlyphMask) | bidiMirror(g & kGlyphMask);
      }
      glyphs[_runGlyphCount++] = g;
      count++;
      w += _cellsOf(i);
      if (extra > 0 && !rtl) {
        _addGlyphs(count, at, y, span, w);
        at += w;
        count = 0;
        w = 0;
        _addSegment(_fromGap, 0, 0, at, y, span, extra);
        at += extra;
      }
    }
    if (count > 0) {
      _addGlyphs(count, at, y, span, w);
    }
  }

  /// Adds the last [count] glyphs gathered for a line, [w] columns, at
  /// column [x] of row [y] in the pen of [span].
  void _addGlyphs(int count, int x, int y, int span, int w) => _addSegment(
    _fromOrdered,
    _runGlyphCount - count,
    _runGlyphCount,
    x,
    y,
    span,
    w,
  );

  /// The spaces among clusters [a, b) after the first that isn't one.
  int _gapsIn(int a, int b) {
    var gaps = 0;
    var words = false;
    for (var i = a; i < b; i++) {
      if ((_kinds[i] & _space) == 0) {
        words = true;
      } else if (words) {
        gaps++;
      }
    }
    return gaps;
  }

  /// Adds clusters [a, b) at column [x] of row [y], one run per span; with
  /// [gaps], [free] blank cells shared out after the spaces between words.
  /// Returns the column after them.
  /// [width] is their columns when known, else -1.
  int _addClusters(
    int a,
    int b,
    int x,
    int y,
    int gaps,
    int free, [
    int width = -1,
  ]) {
    if (a == b) {
      return x;
    }
    if (gaps == 0 && _spanOf[a] == _spanOf[b - 1]) {
      final w = width < 0 ? _widthOf(a, b) : width;
      _addRun(a, b, x, y, w);
      return x + w;
    }
    if (gaps == 0) {
      // a run a span, as the loop below makes them without gaps, with the
      // arrays in locals and no test for a gap at each cluster: a line of
      // two spans (text and a link, a highlight) is the common case
      final spanOf = _spanOf;
      final glyphs = _glyphs;
      final kinds = _kinds;
      var at = x;
      var i = a;
      while (i < b) {
        final span = spanOf[i];
        final from = i;
        var w = 0;
        do {
          w += (glyphs[i] & kWide) != 0
              ? 2
              : ((kinds[i] & _newline) != 0 ? 0 : 1);
          i++;
        } while (i < b && spanOf[i] == span);
        _addRun(from, i, at, y, w);
        at += w;
      }
      return at;
    }
    var at = x;
    var start = a;
    var w = 0;
    var gap = 0;
    var words = false;
    for (var i = a; i < b; i++) {
      if (i > start && _spanOf[i] != _spanOf[start]) {
        _addRun(start, i, at, y, w);
        at += w;
        start = i;
        w = 0;
      }
      w += _cellsOf(i);
      final space = (_kinds[i] & _space) != 0;
      if (gaps > 0 && space && words) {
        _addRun(start, i + 1, at, y, w);
        at += w;
        start = i + 1;
        w = 0;
        final extra = _part(free, gaps, gap++);
        if (extra > 0) {
          _addSegment(_fromGap, 0, 0, at, y, _spanOf[i], extra);
          at += extra;
        }
      }
      words = words || !space;
    }
    if (start < b) {
      _addRun(start, b, at, y, w);
      at += w;
    }
    return at;
  }

  /// Adds clusters [a, b), [w] columns, at column [x] of row [y]: drawn
  /// from [_glyphs] where they are.
  void _addRun(int a, int b, int x, int y, int w) =>
      _addSegment(_fromClusters, a, b, x, y, _spanOf[a], w);

  /// Adds a segment of [w] columns at column [x] of row [y] in the pen of
  /// [span], its glyphs [start, end) of what [from] names.
  void _addSegment(
    int from,
    int start,
    int end,
    int x,
    int y,
    int span,
    int w,
  ) {
    final at = _segmentCount++ * _segmentStride;
    if (at + _segmentStride > _segments.length) {
      _segments = _grown(_segments, at + _segmentStride);
    }
    _segments
      ..[at] = x
      ..[at + 1] = y
      ..[at + 2] = span
      ..[at + 3] = w
      ..[at + 4] = from
      ..[at + 5] = start
      ..[at + 6] = end;
  }
}
