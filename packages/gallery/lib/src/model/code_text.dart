// The Code tab's text as the mouse selects in it: where its lines start
// and end, the cluster a cell stands for, and what a copy of it is.
import 'package:twk/twk.dart';

import '../paint.dart';

/// The code as the Code tab selects in it: [source] and where each of its
/// lines starts and ends, offsets in UTF-16 code units.
final class CodeText {
  CodeText(this.source) {
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 0x0A) {
        _ends.add(i);
        _starts.add(i + 1);
      }
    }
    _ends.add(source.length);
  }

  final String source;
  final _starts = [0];
  final _ends = <int>[];

  int get lineCount => _starts.length;

  /// Where line [i] starts and ends, its line break left out.
  (int, int) line(int i) => (_starts[i], _ends[i]);

  /// The range a cell at [column] of line [line] stands for, as
  /// [Selectable.selectableRangeAt] gives it: the cluster drawn there
  /// (what takes no cell with the one after it); left of the line's text
  /// where it starts, right of it where the next line starts; above the
  /// first line the start, below the last the end.
  (int, int) rangeAt(int line, int column) {
    if (line < 0) {
      return (0, 0);
    }
    if (line >= lineCount) {
      return (source.length, source.length);
    }
    final (start, end) = this.line(line);
    if (column < 0) {
      return (start, start);
    }
    var col = 0;
    var from = start;
    var i = start;
    while (i < end) {
      final next = source.characterEndAfter(i);
      final w = widthOf(source.substring(i, next));
      i = next;
      if (w == 0) {
        continue;
      }
      if (column < col + w) {
        return (from, i);
      }
      col += w;
      from = i;
    }
    final next = line + 1 < lineCount ? _starts[line + 1] : source.length;
    return (next, next);
  }

  /// [start, end) as copied, as the design's shell copies it: the code's
  /// own text, its line breaks kept, the blanks that end a line dropped,
  /// those that end what is selected too ([trimLineEnds]).
  String copied(int start, int end) =>
      trimLineEnds(source.substring(start, end));
}

/// [text] with the blanks that end each of its lines dropped, those that
/// end it too, as the design's shell copies a selection of the code
/// (where `SelectionArea` keeps the blanks ending what is selected when
/// text follows on the line, as a terminal does).
String trimLineEnds(String text) => text
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'[ \t]+$'), ''))
    .join('\n');

/// What a toast says [text] is: its lines, or within a line its
/// characters.
String copiedWhat(String text) {
  final n = '\n'.allMatches(text).length + 1;
  if (n > 1) {
    return '$n lines';
  }
  final c = text.characterCount;
  return c == 1 ? '1 character' : '$c characters';
}
