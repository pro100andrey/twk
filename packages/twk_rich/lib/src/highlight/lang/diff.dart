/// Diffs.
library;

import '../lexer.dart';
import '../token.dart';

/// Unified diffs, as `diff -u` and `git diff` write them: the headers of
/// files and hunks, and the lines a hunk adds, removes and keeps, each a
/// token of its own kind; the text after a hunk's header is plain, and the
/// note of a missing newline a comment.
///
/// A hunk's header counts the lines of each side that follow it, so in a
/// hunk a line that starts with `---` or `+++` is one removed or added;
/// out of one, or in a hunk whose header has no counts, a line is what it
/// starts with.
const diffLanguage = Language(
  name: 'diff',
  aliases: ['patch'],
  lexer: _DiffLexer(),
);

/// What the header lines of a file start with.
const _headers = [
  'diff ', 'index ', 'Index: ', '=====', '--- ', '+++ ', 'new file mode', //
  'deleted file mode', 'old mode', 'new mode', 'similarity index',
  'dissimilarity index', 'rename from', 'rename to', 'copy from', 'copy to',
  'Binary files ',
];

/// The header of a hunk with counts: `@@ -1,3 +1,4 @@`, a count left out
/// being 1; numbers of more than 9 digits make it one without counts.
final _counted = RegExp(
  r'@@ -\d{1,9}(?:,(\d{1,9}))? \+\d{1,9}(?:,(\d{1,9}))? @@',
);

/// The header of a hunk without counts, or of one of a combined diff:
/// `@@ … @@`, `@@@ -1 -1 +1 @@@`.
final _range = RegExp(r'(@@+)[^@]*\1');

final class _DiffLexer extends Lexer {
  const _DiffLexer();

  /// The state is how many lines of each side the hunk has still to come,
  /// `(int, int)`, or null out of a hunk.
  @override
  Object? lexLine(TokenScanner s, Object? state) {
    final c = s.current;
    if (state case (final int old, final int now)) {
      final left = switch (c) {
        _space || -1 when old > 0 && now > 0 => (old - 1, now - 1),
        _minus when old > 0 => (old - 1, now),
        _plus when now > 0 => (old, now - 1),
        _backslash => (old, now),
        _ => null,
      };
      if (left != null) {
        s.emitRest(_kindOf(c));
        return left == (0, 0) ? null : left;
      }
    }
    final line = s.line;
    if (c == _at) {
      final counted = _counted.matchAsPrefix(line);
      final header = counted ?? _range.matchAsPrefix(line);
      s
        ..emit(TokenKind.heading, header?.end ?? line.length)
        ..emitRest(TokenKind.plain);
      if (counted != null) {
        return (
          int.parse(counted.group(1) ?? '1'),
          int.parse(counted.group(2) ?? '1'),
        );
      }
      return null;
    }
    s.emitRest(
      _headers.any(line.startsWith) ? TokenKind.heading : _kindOf(c),
    );
    return null;
  }
}

/// The kind of a line that starts with [unit].
TokenKind _kindOf(int unit) => switch (unit) {
  _minus => TokenKind.deleted,
  _plus => TokenKind.inserted,
  _backslash => TokenKind.comment,
  _ => TokenKind.plain,
};

const _space = 0x20;
const _minus = 0x2D;
const _plus = 0x2B;
const _backslash = 0x5C;
const _at = 0x40;
