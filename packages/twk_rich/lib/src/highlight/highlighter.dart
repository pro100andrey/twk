/// Source kept lexed through edits: [Highlighter].
///
/// @docImport 'code_view.dart';
library;

import 'lexer.dart';
import 'token.dart';

/// Source in a [language], split into lines and lexed line by line, each
/// line from the state the line before ended in.
///
/// An edit ([replaceLines], [update]) lexes the lines it puts in, then
/// goes on to the lines after them only while one starts in a state other
/// than the one it started in before: an edit inside a line lexes that
/// line alone, one that opens a block comment the lines down to where it
/// closes. The lines it does not lex keep their tokens as the very
/// objects they were.
///
/// A line break is `\n` or `\r\n`; text that ends in one ends in an empty
/// line.
///
/// A line of JSON lexed, and lexed again alone after an edit to it:
///
/// ```dart
/// final source = Highlighter(languageNamed('json'), '{"a": 1}');
/// source.tokens(0); // punctuation `{`, key `"a"`, punctuation `:`, …
/// source.update('{"a": 2}'); // 1, the line changed
/// ```
///
/// See also:
///
///  * [CodeView], which shows source highlighted and keeps one of these
///    through changes to its code.
final class Highlighter {
  /// [text] in [language], empty by default, split into lines and lexed.
  Highlighter(this.language, [String text = '']) {
    replaceLines(0, 0, splitLines(text));
  }

  /// The language the lines are lexed in.
  final Language language;

  final _lines = <_Line>[];

  /// How many lines the source has, at least one.
  int get lineCount => _lines.length;

  /// The text of line [index], without its line break.
  String line(int index) => _lines[index].text;

  /// The tokens of line [index], which give back its text in order.
  List<Token> tokens(int index) => _lines[index].tokens;

  /// Replaces the lines from [start] up to [end] with [lines] and lexes
  /// what the edit changes: [lines], then the lines after them down to the
  /// first that starts in the state it started in before. Returns how many
  /// lines it lexed.
  int replaceLines(int start, int end, List<String> lines) {
    RangeError.checkValidRange(start, end, _lines.length);
    _lines.replaceRange(start, end, [for (final text in lines) _Line(text)]);
    if (_lines.isEmpty) {
      _lines.add(_Line(''));
    }
    final lexer = language.lexer;
    final edited = start + lines.length;
    var state = start == 0 ? null : _lines[start - 1].end;
    var lexed = 0;
    for (var i = start; i < _lines.length; i++) {
      final line = _lines[i];
      if (i >= edited && line.start == state) {
        break;
      }
      final s = TokenScanner(line.text);
      final end = lexer.lexLine(s, state);
      line
        ..start = state
        ..end = end
        ..tokens = s.tokens();
      state = end;
      lexed++;
    }
    return lexed;
  }

  /// Makes [text] the source: replaces the lines from the first that
  /// differs from the old one to the last that does ([replaceLines]).
  /// Returns how many lines it lexed.
  int update(String text) {
    final lines = splitLines(text);
    final shorter = lines.length < _lines.length ? lines.length : _lines.length;
    var head = 0;
    while (head < shorter && lines[head] == _lines[head].text) {
      head++;
    }
    var tail = 0;
    while (tail < shorter - head &&
        lines[lines.length - 1 - tail] ==
            _lines[_lines.length - 1 - tail].text) {
      tail++;
    }
    if (head + tail == lines.length && head + tail == _lines.length) {
      return 0;
    }
    return replaceLines(
      head,
      _lines.length - tail,
      lines.sublist(head, lines.length - tail),
    );
  }

  /// The lines of [text], split at `\n` and `\r\n`.
  static List<String> splitLines(String text) => [
    for (final line in text.split('\n'))
      if (line.endsWith('\r')) line.substring(0, line.length - 1) else line,
  ];
}

/// A line of source, the state it starts and ends in and its tokens.
final class _Line {
  _Line(this.text);

  final String text;
  Object? start;
  Object? end;
  List<Token> tokens = const [];
}
