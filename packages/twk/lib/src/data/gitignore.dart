/// The patterns of a `.gitignore` file: a [Gitignore], which tells the
/// paths below the file's directory it ignores, as git does.
library;

import 'package:meta/meta.dart';

/// The patterns of a `.gitignore` file, read from its text, which tell
/// whether a path below the file's directory is ignored, as git tells.
///
/// Each line is a pattern: blank lines and those starting with `#` are
/// none, and spaces at a line's end are dropped but where a backslash
/// keeps one. `!` at the start re-includes what an earlier pattern
/// ignored. A `/` at the end matches directories only. A pattern with a
/// `/` at its start or in its middle is anchored: it matches the path
/// from the file's directory; one without matches a name at any depth.
/// `*` matches any run of characters but `/`, `?` any one of them, and
/// `[...]` one of those it lists (`a-z` a range, `!` or `^` first those it
/// does not; one not closed makes the pattern match nothing); `**/` at the
/// start matches any directories, `/**` at the end everything inside, and
/// `/**/` in the middle no directory or any. A
/// backslash makes the character after it a character as any other
/// (`\#`, `\!`, `\*`).
///
/// The last pattern that matches a path decides: ignored, or with `!`
/// re-included. A path below a directory that is ignored is ignored with
/// it ([ignores]), as git does not look into such a directory, so no
/// pattern re-includes what is in it.
///
/// ```dart
/// final ignore = Gitignore('build/\n*.log\n!keep.log\n');
/// ignore.ignores('build', isDirectory: true); // true
/// ignore.ignores('build/out.o'); // true: its directory is
/// ignore.ignores('logs/run.log'); // true
/// ignore.ignores('keep.log'); // false
/// ```
///
/// Paths are relative to the directory of the file, `/` between their
/// names. Where files are nested, the patterns of a file deeper down
/// decide before those of one above it: [match] tells whether a file's
/// patterns decide at all.
@immutable
final class Gitignore {
  /// The patterns of [text], a `.gitignore` file's.
  Gitignore(String text) : _patterns = _parse(text);

  final List<_Pattern> _patterns;

  /// Whether no line of the text is a pattern.
  bool get isEmpty => _patterns.isEmpty;

  /// What the patterns decide of [path] itself, a directory where
  /// [isDirectory]: true where the last of them that matches it ignores
  /// it, false where it re-includes it (`!`), and null where none matches.
  /// The directories above it are not looked at: see [ignores].
  bool? match(String path, {bool isDirectory = false}) {
    for (var i = _patterns.length - 1; i >= 0; i--) {
      final pattern = _patterns[i];
      if ((isDirectory || !pattern.directoryOnly) &&
          pattern.regExp.hasMatch(path)) {
        return !pattern.negated;
      }
    }
    return null;
  }

  /// Whether [path] is ignored, a directory where [isDirectory]: it is, or
  /// one of the directories above it is ([match]).
  bool ignores(String path, {bool isDirectory = false}) {
    for (var i = path.indexOf('/'); i > 0; i = path.indexOf('/', i + 1)) {
      if (match(path.substring(0, i), isDirectory: true) ?? false) {
        return true;
      }
    }
    return match(path, isDirectory: isDirectory) ?? false;
  }
}

/// A pattern of a `.gitignore`: the paths it matches, whether only
/// directories and whether it re-includes them.
final class _Pattern {
  _Pattern(this.regExp, {required this.negated, required this.directoryOnly});

  final RegExp regExp;
  final bool negated;
  final bool directoryOnly;
}

List<_Pattern> _parse(String text) => [
  for (final line in text.split('\n')) ?_pattern(line),
];

/// The pattern of [line]; null for a blank line or a comment.
_Pattern? _pattern(String line) {
  var p = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
  // the spaces at its end, but one a backslash keeps
  var end = p.length;
  while (end > 0 && p.codeUnitAt(end - 1) == 0x20) {
    var slashes = 0;
    while (end - 2 - slashes >= 0 && p.codeUnitAt(end - 2 - slashes) == 0x5C) {
      slashes++;
    }
    if (slashes.isOdd) {
      break;
    }
    end--;
  }
  p = p.substring(0, end);
  if (p.isEmpty || p.startsWith('#')) {
    return null;
  }
  final negated = p.startsWith('!');
  if (negated) {
    p = p.substring(1);
  }
  final directoryOnly = p.endsWith('/') && !_escapedAt(p, p.length - 1);
  if (directoryOnly) {
    p = p.substring(0, p.length - 1);
  }
  final anchored = p.contains('/');
  if (p.startsWith('/')) {
    p = p.substring(1);
  }
  if (p.isEmpty) {
    return null;
  }
  final source = StringBuffer('^');
  if (!anchored) {
    source.write('(?:.*/)?');
  }
  _translate(p, source);
  source.write(r'$');
  return _Pattern(
    RegExp(source.toString()),
    negated: negated,
    directoryOnly: directoryOnly,
  );
}

/// Whether the character at [i] of [p] follows a backslash that escapes
/// it.
bool _escapedAt(String p, int i) {
  var slashes = 0;
  while (i - 1 - slashes >= 0 && p.codeUnitAt(i - 1 - slashes) == 0x5C) {
    slashes++;
  }
  return slashes.isOdd;
}

/// Writes the regular expression of the glob [p] to [out].
void _translate(String p, StringBuffer out) {
  var i = 0;
  while (i < p.length) {
    final c = p[i];
    switch (c) {
      case r'\':
        if (i + 1 < p.length) {
          out.write(RegExp.escape(p[i + 1]));
          i += 2;
        } else {
          i++;
        }
      case '*':
        var stars = 1;
        while (i + stars < p.length && p[i + stars] == '*') {
          stars++;
        }
        final atStart = i == 0 || p[i - 1] == '/';
        final next = i + stars;
        if (stars == 2 && atStart && next < p.length && p[next] == '/') {
          // **/: no directory or any
          out.write('(?:.*/)?');
          i = next + 1;
        } else if (stars == 2 && atStart && next == p.length) {
          // /** at the end, or the whole pattern: everything
          out.write('.*');
          i = next;
        } else {
          out.write('[^/]*');
          i = next;
        }
      case '?':
        out.write('[^/]');
        i++;
      case '[':
        final end = _classEnd(p, i);
        if (end < 0) {
          // as git, a class not closed matches nothing
          out.write('(?!)');
          return;
        } else {
          _class(p.substring(i + 1, end), out);
          i = end + 1;
        }
      default:
        // a character as a whole, a pair of surrogates together
        final unit = p.codeUnitAt(i);
        final wide = unit >= 0xD800 && unit < 0xDC00 && i + 1 < p.length;
        out.write(RegExp.escape(p.substring(i, wide ? i + 2 : i + 1)));
        i += wide ? 2 : 1;
    }
  }
}

/// The index of the `]` that closes the class opened at [start] of [p];
/// -1 where none does. A `]` first in the class, after its `!` or `^`, is
/// one of its characters.
int _classEnd(String p, int start) {
  var i = start + 1;
  if (i < p.length && (p[i] == '!' || p[i] == '^')) {
    i++;
  }
  if (i < p.length && p[i] == ']') {
    i++;
  }
  while (i < p.length) {
    if (p[i] == r'\') {
      i += 2;
      continue;
    }
    if (p[i] == ']') {
      return i;
    }
    i++;
  }
  return -1;
}

/// Writes the class of the characters [body] lists, between `[` and `]`,
/// to [out]: never `/`.
void _class(String body, StringBuffer out) {
  var i = 0;
  var negated = false;
  if (body.isNotEmpty && (body[0] == '!' || body[0] == '^')) {
    negated = true;
    i = 1;
  }
  out.write(negated ? '[^/' : '[');
  while (i < body.length) {
    var c = body[i];
    if (c == r'\' && i + 1 < body.length) {
      i++;
      c = body[i];
    } else if (c == '-' && i > (negated ? 1 : 0) && i + 1 < body.length) {
      // a range
      out.write('-');
      i++;
      continue;
    }
    out.write(switch (c) {
      r'\' || ']' || '[' || '^' || '-' => '\\$c',
      _ => c,
    });
    i++;
  }
  out.write(']');
}
