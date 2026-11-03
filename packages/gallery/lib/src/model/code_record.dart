// The Code tab of a page as it was last shown: its lines, their tokens,
// and when each last changed, so that a line an option changed is lit.
import 'package:twk_rich/twk_rich.dart';

import 'code_text.dart';

/// A page's Code as last shown: [source], its [lines] and their [tokens],
/// and when each line last [changed] (null: not since the page showed).
final class CodeRecord {
  CodeRecord(this.source, this.lines, this.changed, this.tokens)
    : text = CodeText(source);

  /// [source] at [now], after [old], the record of the Code before: a line
  /// that differs from the one before it changed now, the others when
  /// they did.
  factory CodeRecord.after(CodeRecord? old, String source, Duration now) {
    final lines = source.split('\n');
    final h = Highlighter(dartLanguage, source);
    return CodeRecord(
      source,
      lines,
      [
        for (var i = 0; i < lines.length; i++)
          if (old == null)
            null
          else if (i >= old.lines.length || old.lines[i] != lines[i])
            now
          else if (i < old.changed.length)
            old.changed[i]
          else
            null,
      ],
      [for (var i = 0; i < h.lineCount; i++) h.tokens(i)],
    );
  }

  final String source;

  /// The code as the mouse selects in it.
  final CodeText text;
  final List<String> lines;
  final List<Duration?> changed;
  final List<List<Token>> tokens;
}
