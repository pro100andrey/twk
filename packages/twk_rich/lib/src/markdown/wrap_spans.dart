/// Styled text broken into lines of a width: [wrapSpans].
library;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show TextSegmenter, graphemeBoundaries;

final _segmenter = TextSegmenter();

/// One grapheme cluster of the text, its columns and the style it is in.
typedef _Atom = ({String text, int width, Style style});

/// [spans] broken into lines of at most [width] columns, each span's style
/// merged onto [base]; adjacent runs of one style are one span.
///
/// Lines break as a `Text` breaks them by default ([TextWrap.word]): after
/// a space, which hangs beyond the line, after a hyphen inside a word,
/// between two CJK characters (not before closing punctuation or a small
/// kana, nor after an opening bracket), and a word longer than the line
/// between graphemes. With [grapheme] a line breaks between any two
/// graphemes, and spaces count. A `\n` ends a line. A cluster wider than
/// [width] stands on a line of its own.
List<List<Span>> wrapSpans(
  List<Span> spans,
  int width,
  Style base, {
  bool grapheme = false,
}) {
  final atoms = <_Atom>[];
  for (final span in spans) {
    final style = base.merge(span.style);
    final text = span.text;
    for (final (from, to) in graphemeBoundaries(text)) {
      final cluster = text.substring(from, to);
      atoms.add((
        text: cluster,
        width: _segmenter.width(cluster),
        style: style,
      ));
    }
  }
  final lines = <List<Span>>[];
  void emit(int from, int to) {
    var end = to;
    if (!grapheme) {
      while (end > from && atoms[end - 1].text == ' ') {
        end--;
      }
    }
    final line = <Span>[];
    for (var k = from; k < end; k++) {
      final atom = atoms[k];
      if (line.isNotEmpty && line.last.style == atom.style) {
        line.last = Span(line.last.text + atom.text, atom.style);
      } else {
        line.add(Span(atom.text, atom.style));
      }
    }
    lines.add(line);
  }

  var start = 0;
  var used = 0; // columns of atoms[start..i)
  var allowed = -1; // where a line may end, after start
  for (var i = 0; i < atoms.length; i++) {
    final atom = atoms[i];
    if (atom.text == '\n') {
      emit(start, i);
      start = i + 1;
      used = 0;
      allowed = -1;
      continue;
    }
    final hangs = !grapheme && atom.text == ' ';
    if (i > start &&
        (grapheme ||
            _mayBreak(
              atoms[i - 1].text,
              i - 2 >= start ? atoms[i - 2].text : null,
              atom.text,
            ))) {
      allowed = i;
    }
    if (hangs) {
      used += atom.width;
      continue;
    }
    if (i > start && used + atom.width > width) {
      final at = allowed > start ? allowed : i;
      emit(start, at);
      start = at;
      used = 0;
      for (var k = start; k < i; k++) {
        used += atoms[k].width;
      }
      allowed = -1;
      // spaces that hung at the break do not start the next line
      while (!grapheme && start < i && atoms[start].text == ' ') {
        used -= atoms[start].width;
        start++;
      }
    }
    used += atom.width;
  }
  if (start < atoms.length || lines.isEmpty) {
    emit(start, atoms.length);
  }
  return lines;
}

bool _isWordChar(String c) {
  final u = c.runes.first;
  return (u >= 0x30 && u <= 0x39) ||
      (u >= 0x41 && u <= 0x5A) ||
      (u >= 0x61 && u <= 0x7A) ||
      (u > 0x7F && !_isCjk(u));
}

bool _isCjk(int u) =>
    (u >= 0x2E80 && u <= 0x9FFF) ||
    (u >= 0xAC00 && u <= 0xD7AF) ||
    (u >= 0xF900 && u <= 0xFAFF) ||
    (u >= 0xFF00 && u <= 0xFF60) ||
    (u >= 0x20000 && u <= 0x3FFFF);

const _noBreakBefore = '、。，．：；！？）」』】〉》〕ゝゞーぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ々）,.:;!?)]}';
const _noBreakAfter = '（「『【〈《〔([{';

/// Whether a line may break between [prev] and [next], [before] being the
/// cluster before [prev], null where [prev] starts the line.
bool _mayBreak(String prev, String? before, String next) {
  if (next == ' ') {
    return false;
  }
  if (prev == ' ') {
    return true;
  }
  if (prev == '-') {
    return before != null && _isWordChar(before) && _isWordChar(next);
  }
  final p = prev.runes.first;
  final n = next.runes.first;
  if (!_isCjk(p) || !_isCjk(n)) {
    return false;
  }
  return !_noBreakBefore.contains(next) && !_noBreakAfter.contains(prev);
}
