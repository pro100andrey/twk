/// The text a controller edits, in pieces: [TextBuffer]; and where a
/// caret stops in a text, found from the characters around the offset
/// asked about ([TextStops]).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show ClusterScan, TextSegmenter;

/// A text kept in pieces of up to a few thousand code units, the pieces in
/// blocks of up to [_blockSize]. An edit ([replace]) makes another text
/// that shares the pieces and the blocks it leaves alone, at the cost of
/// the edit, the blocks it touches and the short list of blocks (sixteen
/// to the megabyte); the text edited stays as it was. Read as a String
/// ([text]), the pieces are put together once and kept.
///
/// The line breaks are counted by piece, so that a line is found
/// ([lineOf], [lineStart]) without going through the text; the characters
/// and words around an offset are found from the code units around it
/// ([characterStartBefore], [wordEndAfter], ...). A text tells what
/// changed since the last texts it was edited from ([changeSince]).
final class TextBuffer {
  /// [text] in pieces.
  factory TextBuffer(String text) {
    final pieces = _split(text);
    return TextBuffer._of(
      _Block.chunks(pieces, [for (final p in pieces) _count(p)], null),
      const [],
      text,
    );
  }

  /// The text of [blocks], each end, line break count and first piece
  /// summed up from the blocks.
  factory TextBuffer._of(
    List<_Block> blocks,
    List<int> since,
    String? string,
  ) {
    final n = blocks.length;
    final ends = Int32List(n);
    final breaks = Int32List(n);
    final firsts = Int32List(n + 1);
    var end = 0;
    var lines = 0;
    var pieces = 0;
    for (var k = 0; k < n; k++) {
      final b = blocks[k];
      firsts[k] = pieces;
      ends[k] = end += b.length;
      breaks[k] = lines += b.lines;
      pieces += b.pieces.length;
    }
    firsts[n] = pieces;
    return TextBuffer._(blocks, ends, breaks, firsts, since, string);
  }

  TextBuffer._(
    this._blocks,
    this._ends,
    this._breaks,
    this._firsts,
    this._since,
    this._string,
  ) : _id = ++_lastId;

  /// No text.
  static final empty = TextBuffer('');

  /// How many times a text of more than one piece was put together into
  /// a String ([text]).
  @visibleForTesting
  static var joins = 0;

  // pieces from _least to _most code units, made _size long from a text
  static const _least = 512;
  static const _size = 1024;
  static const _most = 2048;

  // pieces in a block, at most; a block an edit leaves shorter than half
  // of it goes with its neighbour
  static const _blockSize = 64;

  // how many of the texts it was edited from a text remembers
  static const _depth = 16;

  static var _lastId = 0;

  final int _id;

  // the blocks, and for each the offset it ends at, the line breaks up to
  // its end and the index of its first piece (one more: the pieces' count)
  final List<_Block> _blocks;
  final Int32List _ends;
  final Int32List _breaks;
  final Int32List _firsts;

  // the texts it was edited from, the last first: for each its id, then
  // where what changed since starts, ends in it and ends in this one
  final List<int> _since;

  // the text as a String, once put together
  String? _string;

  // the last part [substring] joined across pieces, and where it is
  var _joined = '';
  var _joinedStart = -1;
  var _joinedEnd = -1;

  // where [_locate] found an offset: its block, its piece in the block and
  // the offset the piece starts at
  var _block = 0;
  var _piece = 0;
  var _pieceStart = 0;

  /// How many pieces the text is in.
  @visibleForTesting
  int get pieceCount => _firsts[_blocks.length];

  /// How many blocks the pieces are in.
  @visibleForTesting
  int get blockCount => _blocks.length;

  /// How many code units the text has.
  int get length => _blocks.isEmpty ? 0 : _ends[_blocks.length - 1];

  /// The text, put together the first time it is asked for.
  String get text => _string ??= _join();

  String _join() {
    if (pieceCount < 2) {
      return pieceCount == 0 ? '' : _blocks[0].pieces[0];
    }
    joins++;
    final out = StringBuffer();
    for (final b in _blocks) {
      b.pieces.forEach(out.write);
    }
    return out.toString();
  }

  /// Whether [other], a String or a [TextBuffer], is the same text.
  bool sameText(Object other) {
    if (identical(other, this)) {
      return true;
    }
    final s = _string;
    if (other is String) {
      if (other.length != length) {
        return false;
      }
      if (s != null) {
        return s == other;
      }
      var o = 0;
      for (final b in _blocks) {
        for (final p in b.pieces) {
          if (!other.startsWith(p, o)) {
            return false;
          }
          o += p.length;
        }
      }
      return true;
    }
    if (other is! TextBuffer || other.length != length) {
      return false;
    }
    final t = other._string;
    if (s != null && t != null) {
      return s == t;
    }
    var o = 0;
    for (final b in _blocks) {
      for (final p in b.pieces) {
        other._locate(o);
        final same =
            other._pieceStart == o &&
                identical(
                  other._blocks[other._block].pieces[other._piece],
                  p,
                ) ||
            other.substring(o, o + p.length) == p;
        if (!same) {
          return false;
        }
        o += p.length;
      }
    }
    return true;
  }

  /// The part of the text from [start] to [end] (its end when null).
  String substring(int start, [int? end]) {
    final e = RangeError.checkValidRange(start, end, length);
    if (start == e) {
      return '';
    }
    final s = _string;
    if (s != null) {
      return s.substring(start, e);
    }
    _locate(start);
    var k = _block;
    var j = _piece;
    var at = _pieceStart;
    var b = _blocks[k];
    final first = b.pieces[j];
    if (e <= at + first.length) {
      return first.substring(start - at, e - at);
    }
    // a part across pieces, joined: the same one again (the line being
    // edited, read by its rows, its measure and its paint) is the one kept
    if (start == _joinedStart && e == _joinedEnd) {
      return _joined;
    }
    final out = StringBuffer(first.substring(start - at));
    at += first.length;
    while (true) {
      if (++j == b.pieces.length) {
        b = _blocks[++k];
        j = 0;
      }
      final p = b.pieces[j];
      if (at + p.length >= e) {
        out.write(p.substring(0, e - at));
        break;
      }
      out.write(p);
      at += p.length;
    }
    _joinedStart = start;
    _joinedEnd = e;
    return _joined = out.toString();
  }

  /// The text with [text] in place of the part from [start] to [end].
  TextBuffer replace(int start, int end, String text) {
    RangeError.checkValidRange(start, end, length);
    if (start == end && text.isEmpty) {
      return this;
    }
    final blocks = _blocks;
    if (blocks.isEmpty) {
      final pieces = _split(text);
      return TextBuffer._of(
        _Block.chunks(pieces, [for (final p in pieces) _count(p)], null),
        _sinceAfter(start, end, start + text.length),
        pieces.length == 1 ? text : null,
      );
    }
    final n = pieceCount;
    // the pieces from `from` to `to` (of the text, all blocks counted)
    // give way to those of `joined`
    _locate(start < length ? start : length - 1);
    var from = _firsts[_block] + _piece;
    final fromStart = _pieceStart;
    var to = from;
    var toStart = fromStart;
    if (end > start) {
      _locate(end - 1);
      to = _firsts[_block] + _piece;
      toStart = _pieceStart;
    }
    var joined =
        _pieceOf(from).substring(0, start - fromStart) +
        text +
        _pieceOf(to).substring(end - toStart);
    // a short piece goes with the one after it, or before
    if (joined.length < _least) {
      if (to + 1 < n) {
        joined += _pieceOf(++to);
      } else if (from > 0) {
        joined = _pieceOf(--from) + joined;
      }
    }
    to++;
    final mid = _split(joined);
    // the blocks the pieces are in, and with them a neighbour where what
    // is left of them would make a short block
    var kFrom = _blockOf(from);
    var kTo = _blockOf(to - 1) + 1;
    final kept = (_firsts[kTo] - _firsts[kFrom]) - (to - from) + mid.length;
    if (kept < _blockSize ~/ 2) {
      if (kTo < blocks.length) {
        kTo++;
      } else if (kFrom > 0) {
        kFrom--;
      }
    }
    // the pieces of those blocks, `mid` in place of from..to: their line
    // break counts and found line breaks kept where the piece is
    final first = _firsts[kFrom];
    final count = _firsts[kTo] - first - (to - from) + mid.length;
    final pieces = List<String>.filled(count, '');
    final counts = Int32List(count);
    final found = List<Int32List?>.filled(count, null);
    var at = 0;
    void keep(int a, int b) {
      if (a == b) {
        return;
      }
      var k = _blockOf(a);
      var block = blocks[k];
      var j = a - _firsts[k];
      for (var g = a; g < b; g++, j++) {
        if (j == block.pieces.length) {
          block = blocks[++k];
          j = 0;
        }
        pieces[at] = block.pieces[j];
        counts[at] = block.countOf(j);
        found[at++] = block.newlines[j];
      }
    }

    keep(first, from);
    for (final p in mid) {
      pieces[at] = p;
      counts[at++] = _count(p);
    }
    keep(to, _firsts[kTo]);
    final made = _Block.chunks(pieces, counts, found);
    final all =
        List<_Block>.filled(
            blocks.length - (kTo - kFrom) + made.length,
            made.isEmpty ? blocks[0] : made[0],
          )
          ..setRange(0, kFrom, blocks)
          ..setRange(kFrom, kFrom + made.length, made)
          ..setRange(
            kFrom + made.length,
            blocks.length - (kTo - kFrom) + made.length,
            blocks,
            kTo,
          );
    final m = n - (to - from) + mid.length;
    return TextBuffer._of(
      all,
      _sinceAfter(start, end, start + text.length),
      m == 1 ? all[0].pieces[0] : (m == 0 ? '' : null),
    );
  }

  /// What a text edited from this one remembers, [start] to [end] having
  /// been replaced by what now ends at [newEnd].
  List<int> _sinceAfter(int start, int end, int newEnd) {
    final since = _since;
    final kept = since.length ~/ 4 < _depth ? since.length : since.length - 4;
    final out = List<int>.filled(4 + kept, 0)
      ..[0] = _id
      ..[1] = start
      ..[2] = end
      ..[3] = newEnd;
    final d = newEnd - end;
    for (var i = 0; i < kept; i += 4) {
      final s = since[i + 1];
      final oldEnd = since[i + 2];
      final midEnd = since[i + 3];
      // the union of both changes, in this text's offsets
      final hi = midEnd > end ? midEnd : end;
      out
        ..[4 + i] = since[i]
        ..[5 + i] = s < start ? s : start
        ..[6 + i] = hi - (midEnd - oldEnd)
        ..[7 + i] = hi + d;
    }
    return out;
  }

  /// What changed since [older], when it is one of the last texts this one
  /// was edited from: the part from `start` to `oldEnd` of it is the part
  /// from `start` to `newEnd` of this one, the rest alike. Null when it is
  /// not.
  ({int start, int oldEnd, int newEnd})? changeSince(TextBuffer older) {
    if (identical(older, this)) {
      return (start: 0, oldEnd: 0, newEnd: 0);
    }
    final since = _since;
    for (var i = 0; i < since.length; i += 4) {
      if (since[i] == older._id) {
        return (
          start: since[i + 1],
          oldEnd: since[i + 2],
          newEnd: since[i + 3],
        );
      }
    }
    return null;
  }

  /// How many lines the text has: one more than its line breaks (`\n`).
  int get lineCount => (_blocks.isEmpty ? 0 : _breaks[_blocks.length - 1]) + 1;

  /// The line [offset] is on; a line break is on the line it ends.
  int lineOf(int offset) {
    if (offset <= 0 || _blocks.isEmpty) {
      return 0;
    }
    final o = (offset < length ? offset : length) - 1;
    _locate(o);
    final b = _blocks[_block];
    final j = _piece;
    final nl = b.newlinesOf(j);
    // the line breaks of the piece at or before o
    final local = o - _pieceStart;
    var lo = 0;
    var hi = nl.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (nl[mid] <= local) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return _linesBefore(_block) + (j > 0 ? b.breaks[j - 1] : 0) + lo;
  }

  /// The offset [line] starts at.
  int lineStart(int line) {
    if (line <= 0) {
      return 0;
    }
    RangeError.checkValueInInterval(line, 0, lineCount - 1, 'line');
    // the block, then the piece, with the line break before the line
    var lo = 0;
    var hi = _blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_breaks[mid] < line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final k = lo;
    final b = _blocks[k];
    final inBlock = line - _linesBefore(k);
    lo = 0;
    hi = b.pieces.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (b.breaks[mid] < inBlock) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final before = lo > 0 ? b.breaks[lo - 1] : 0;
    final pieceStart = _startOfBlock(k) + (lo > 0 ? b.ends[lo - 1] : 0);
    return pieceStart + b.newlinesOf(lo)[inBlock - before - 1] + 1;
  }

  /// The offset [line] ends at: of its line break, or the text's end.
  int lineEnd(int line) =>
      line + 1 < lineCount ? lineStart(line + 1) - 1 : length;

  static final _stops = TextStops();

  /// The start of the character before [offset] in the part of the text
  /// from [from] to [to] (its end when null), as
  /// [TextStops.characterStartBefore] finds it.
  int characterStartBefore(int offset, {int from = 0, int? to}) =>
      _stops.characterStartBefore(substring, from, to ?? length, offset);

  /// The end of the character at [offset] in the part of the text from
  /// [from] to [to], as [TextStops.characterEndAfter] finds it.
  int characterEndAfter(int offset, {int from = 0, int? to}) =>
      _stops.characterEndAfter(substring, from, to ?? length, offset);

  /// The start of the word before [offset] in the part of the text from
  /// [from] to [to], as [TextStops.wordStartBefore] finds it.
  int wordStartBefore(
    int offset, {
    bool blankDelimited = false,
    int from = 0,
    int? to,
  }) => _stops.wordStartBefore(
    substring,
    from,
    to ?? length,
    offset,
    blankDelimited: blankDelimited,
  );

  /// The end of the word after [offset] in the part of the text from
  /// [from] to [to], as [TextStops.wordEndAfter] finds it.
  int wordEndAfter(
    int offset, {
    bool blankDelimited = false,
    int from = 0,
    int? to,
  }) => _stops.wordEndAfter(
    substring,
    from,
    to ?? length,
    offset,
    blankDelimited: blankDelimited,
  );

  @override
  String toString() => 'TextBuffer($length, $pieceCount pieces)';

  int _startOfBlock(int k) => k > 0 ? _ends[k - 1] : 0;

  int _linesBefore(int k) => k > 0 ? _breaks[k - 1] : 0;

  /// Finds the piece the code unit at [offset] is in: its block ([_block]),
  /// its index in the block ([_piece]) and where it starts ([_pieceStart]).
  void _locate(int offset) {
    final e = _ends;
    var lo = 0;
    var hi = _blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (e[mid] <= offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final b = _blocks[lo];
    final local = offset - _startOfBlock(lo);
    final be = b.ends;
    var l = 0;
    var h = b.pieces.length - 1;
    while (l < h) {
      final mid = (l + h) >> 1;
      if (be[mid] <= local) {
        l = mid + 1;
      } else {
        h = mid;
      }
    }
    _block = lo;
    _piece = l;
    _pieceStart = _startOfBlock(lo) + (l > 0 ? be[l - 1] : 0);
  }

  /// The block of the piece of index [g] in the text.
  int _blockOf(int g) {
    final f = _firsts;
    var lo = 0;
    var hi = _blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (f[mid] <= g) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The piece of index [g] in the text.
  String _pieceOf(int g) {
    final k = _blockOf(g);
    return _blocks[k].pieces[g - _firsts[k]];
  }

  /// How many line breaks [text] has.
  static int _count(String text) {
    var n = 0;
    for (var i = text.indexOf('\n'); i >= 0; i = text.indexOf('\n', i + 1)) {
      n++;
    }
    return n;
  }

  /// [text] in pieces: none for none, one up to [_most] code units, else
  /// pieces of about [_size].
  static List<String> _split(String text) {
    final len = text.length;
    if (len <= _most) {
      return len == 0 ? const [] : [text];
    }
    final n = (len + _size - 1) ~/ _size;
    return [
      for (var i = 0; i < n; i++)
        text.substring(i * len ~/ n, (i + 1) * len ~/ n),
    ];
  }
}

/// Up to [TextBuffer._blockSize] pieces of a [TextBuffer], which the texts
/// edited from it share while an edit leaves them alone: the pieces, and
/// for each the offset it ends at in the block, the line breaks up to its
/// end, and the offsets of its line breaks in it, found when asked.
final class _Block {
  _Block(this.pieces, List<int> counts, this.newlines)
    : ends = Int32List(pieces.length),
      breaks = Int32List(pieces.length) {
    var end = 0;
    var lines = 0;
    for (var i = 0; i < pieces.length; i++) {
      ends[i] = end += pieces[i].length;
      breaks[i] = lines += counts[i];
    }
  }

  /// [pieces], whose line break counts are [counts] and found line breaks
  /// [found] (none found when null), in blocks of about the same size; a
  /// block of them all, when they make one, keeps the lists given.
  static List<_Block> chunks(
    List<String> pieces,
    List<int> counts,
    List<Int32List?>? found,
  ) {
    final n = pieces.length;
    if (n == 0) {
      return const [];
    }
    final k = (n + TextBuffer._blockSize - 1) ~/ TextBuffer._blockSize;
    if (k == 1) {
      return [
        _Block(pieces, counts, found ?? List<Int32List?>.filled(n, null)),
      ];
    }
    final out = <_Block>[];
    for (var i = 0; i < k; i++) {
      final a = i * n ~/ k;
      final b = (i + 1) * n ~/ k;
      out.add(
        _Block(
          pieces.sublist(a, b),
          counts.sublist(a, b),
          found == null
              ? List<Int32List?>.filled(b - a, null)
              : found.sublist(a, b),
        ),
      );
    }
    return out;
  }

  final List<String> pieces;
  final Int32List ends;
  final Int32List breaks;
  final List<Int32List?> newlines;

  /// The code units in the block.
  int get length => pieces.isEmpty ? 0 : ends[pieces.length - 1];

  /// The line breaks in the block.
  int get lines => pieces.isEmpty ? 0 : breaks[pieces.length - 1];

  /// The line breaks in piece [j].
  int countOf(int j) => breaks[j] - (j > 0 ? breaks[j - 1] : 0);

  /// The offsets in piece [j] of its line breaks, found once.
  Int32List newlinesOf(int j) {
    final found = newlines[j];
    if (found != null) {
      return found;
    }
    final p = pieces[j];
    final at = Int32List(countOf(j));
    var n = 0;
    for (var i = p.indexOf('\n'); i >= 0; i = p.indexOf('\n', i + 1)) {
      at[n++] = i;
    }
    return newlines[j] = at;
  }
}

/// Reads the part of a text from `start` to `end`.
typedef TextReader = String Function(int start, int end);

/// Where a caret stops in the part of a text from `lo` to `hi` (offsets in
/// the text, the rest of it as if it were not there): the stops of
/// `TextBoundaries`, found from the characters around the offset asked
/// about only. It reads a window of the text on either side of it, wider
/// until it holds the character or the word; a window ends where the code
/// points on either side of its end are apart whatever comes before them
/// (UAX #29), as letters, digits, blanks, punctuation and CJK are.
final class TextStops {
  /// Stops found in windows of [margin] code units on either side of the
  /// offset first.
  TextStops({int margin = 64}) : _margin = margin < 1 ? 1 : margin;

  final int _margin;

  final _segmenter = TextSegmenter();
  final _scan = ClusterScan();
  final _pair = ClusterScan();

  // the bounds of the characters in the window: from the first bound
  // certain from the code units around it to the last (lo and hi where it
  // reaches them)
  var _bounds = Int32List(256);
  var _count = 0;

  // the window, and the offset of its start in the text
  var _text = '';
  var _base = 0;

  // whether the first bound is lo, and the last hi
  var _atLo = false;
  var _atHi = false;

  /// The start of the character before [offset]; [lo] at the start.
  int characterStartBefore(TextReader read, int lo, int hi, int offset) {
    for (var margin = _margin; ; margin *= 8) {
      _take(read, lo, hi, offset, margin);
      final found = _characterStartBefore(offset);
      if (found >= 0) {
        return found;
      }
    }
  }

  /// The end of the character at [offset]; [hi] at the end.
  int characterEndAfter(TextReader read, int lo, int hi, int offset) {
    for (var margin = _margin; ; margin *= 8) {
      _take(read, lo, hi, offset, margin);
      final found = _characterEndAfter(offset);
      if (found >= 0) {
        return found;
      }
    }
  }

  /// The start of the word before [offset], past the blanks before it.
  int wordStartBefore(
    TextReader read,
    int lo,
    int hi,
    int offset, {
    bool blankDelimited = false,
  }) {
    for (var margin = _margin; ; margin *= 8) {
      _take(read, lo, hi, offset, margin);
      final found = _wordStartBefore(offset, blankDelimited);
      if (found >= 0) {
        return found;
      }
    }
  }

  /// The end of the word after [offset], past the blanks before it.
  int wordEndAfter(
    TextReader read,
    int lo,
    int hi,
    int offset, {
    bool blankDelimited = false,
  }) {
    for (var margin = _margin; ; margin *= 8) {
      _take(read, lo, hi, offset, margin);
      final found = _wordEndAfter(offset, blankDelimited);
      if (found >= 0) {
        return found;
      }
    }
  }

  /// Whether [text] has a blank at [offset].
  static bool blankAt(String text, int offset) =>
      _blankRe.matchAsPrefix(text, offset) != null;

  static const _blank = 0;
  static const _word = 1;
  static const _other = 2;

  static final _blankRe = RegExp(r'\s', unicode: true);
  // letters, digits, marks, connectors, emoji and flags
  static const _wordClass =
      r'[\p{L}\p{N}\p{M}\p{Pc}\p{Extended_Pictographic}\p{Regional_Indicator}]';
  static final _wordRe = RegExp(_wordClass, unicode: true);

  /// The class of the character at [offset] of the text: a blank, a word
  /// character or another.
  int _classAt(int offset) {
    final i = offset - _base;
    if (_blankRe.matchAsPrefix(_text, i) != null) {
      return _blank;
    }
    return _wordRe.matchAsPrefix(_text, i) != null ? _word : _other;
  }

  static bool _sameWord(int kind, int first, bool blankDelimited) =>
      blankDelimited ? kind != _blank : kind == first;

  /// Reads the window of the part from [lo] to [hi] [margin] code units on
  /// either side of [offset], and finds the bounds in it.
  void _take(TextReader read, int lo, int hi, int offset, int margin) {
    final c = offset < lo ? lo : (offset > hi ? hi : offset);
    final a = c - margin > lo ? c - margin : lo;
    final b = c + margin < hi ? c + margin : hi;
    final t = _text = read(a, b);
    _base = a;
    _atLo = a == lo;
    _atHi = b == hi;
    _count = 0;
    final p0 = _atLo ? 0 : _firstCertain(t);
    final p1 = _atHi ? t.length : _lastCertain(t);
    if (p0 < 0 || p1 < 0 || p0 > p1) {
      return;
    }
    _add(a + p0);
    for (var i = p0; i < p1;) {
      _segmenter.scan(t, i, _scan);
      i = _scan.end;
      _add(a + i);
    }
  }

  void _add(int bound) {
    if (_count == _bounds.length) {
      _bounds = Int32List(_count * 2)..setRange(0, _count, _bounds);
    }
    _bounds[_count++] = bound;
  }

  int _firstCertain(String t) {
    for (var q = 1; q < t.length; q++) {
      if (_certain(t, q)) {
        return q;
      }
    }
    return -1;
  }

  int _lastCertain(String t) {
    for (var q = t.length - 1; q >= 1; q--) {
      if (_certain(t, q)) {
        return q;
      }
    }
    return -1;
  }

  /// Whether a character of [t] starts at [q] whatever comes before the
  /// code point before it: the two code points are apart by a rule of
  /// UAX #29 that looks at them alone. That holds after a code point that
  /// takes no part in the rules that look further back (an emoji's ZWJ, an
  /// Indic linker or its marks, a regional indicator), and before one
  /// below U+0300 after any but a ZWJ.
  bool _certain(String t, int q) {
    final b = t.codeUnitAt(q);
    final before = t.codeUnitAt(q - 1);
    // the code point after is cut off
    if (b >= 0xD800 && b <= 0xDBFF && q + 1 == t.length) {
      return false;
    }
    var aStart = q - 1;
    var a = before;
    if (before >= 0xDC00 && before <= 0xDFFF && q >= 2) {
      final h = t.codeUnitAt(q - 2);
      if (h >= 0xD800 && h <= 0xDBFF) {
        aStart = q - 2;
        a = 0x10000 + ((h - 0xD800) << 10) + (before - 0xDC00);
      }
    }
    if (!_inert(a) && !(b < 0x300 && a != 0x200D)) {
      return false;
    }
    _segmenter.scan(t, aStart, _pair);
    return _pair.end == q;
  }

  /// Whether [cp] is a letter, digit, blank or punctuation of the scripts
  /// most text is in, which no rule of UAX #29 looks back past.
  static bool _inert(int cp) =>
      cp < 0x300 ||
      cp >= 0x370 && cp <= 0x482 ||
      cp >= 0x5D0 && cp <= 0x5EA ||
      cp >= 0x620 && cp <= 0x64A ||
      cp >= 0x3041 && cp <= 0x3096 ||
      cp >= 0x30A1 && cp <= 0x30FA ||
      cp >= 0x4E00 && cp <= 0x9FFF ||
      cp >= 0xAC00 && cp <= 0xD7A3;

  /// The index of the last bound at or before [offset]; 0 before the
  /// first.
  int _indexOf(int offset) {
    final b = _bounds;
    var lo = 0;
    var hi = _count - 1;
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

  // Each lookup in the window gives -1 where it is too narrow to tell.

  /// Whether [offset] is outside what the window tells.
  bool _outside(int offset) =>
      _count == 0 ||
      offset < _bounds[0] && !_atLo ||
      offset > _bounds[_count - 1] && !_atHi;

  int _characterStartBefore(int offset) {
    if (_outside(offset)) {
      return -1;
    }
    final b = _bounds;
    final k = _indexOf(offset);
    if (b[k] < offset) {
      return b[k];
    }
    if (k > 0) {
      return b[k - 1];
    }
    return _atLo ? b[0] : -1;
  }

  int _characterEndAfter(int offset) {
    if (_outside(offset)) {
      return -1;
    }
    final k = _indexOf(offset);
    if (k + 1 < _count) {
      return _bounds[k + 1];
    }
    return _atHi ? _bounds[k] : -1;
  }

  int _wordStartBefore(int offset, bool blankDelimited) {
    if (_outside(offset)) {
      return -1;
    }
    final b = _bounds;
    var k = _indexOf(offset);
    while (k > 0 && _classAt(b[k - 1]) == _blank) {
      k--;
    }
    if (k == 0) {
      return _atLo ? b[0] : -1;
    }
    final kind = _classAt(b[k - 1]);
    while (k > 0 && _sameWord(_classAt(b[k - 1]), kind, blankDelimited)) {
      k--;
    }
    return k == 0 && !_atLo ? -1 : b[k];
  }

  int _wordEndAfter(int offset, bool blankDelimited) {
    if (_outside(offset)) {
      return -1;
    }
    final b = _bounds;
    final last = _count - 1;
    var k = _indexOf(offset);
    while (k < last && _classAt(b[k]) == _blank) {
      k++;
    }
    if (k == last) {
      return _atHi ? b[last] : -1;
    }
    final kind = _classAt(b[k]);
    while (k < last && _sameWord(_classAt(b[k]), kind, blankDelimited)) {
      k++;
    }
    return k == last && !_atHi ? -1 : b[k];
  }
}
