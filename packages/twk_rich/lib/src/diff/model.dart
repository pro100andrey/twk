/// What a diff is made of: [Diff], its [FileDiff]s, their [DiffHunk]s and
/// [DiffLine]s; read from a unified diff ([Diff.parse]) or found between
/// two texts ([Diff.between]).
///
/// @docImport 'package:twk/twk.dart';
library;

import 'dart:math' as math;

import 'myers.dart';

/// What a line of a diff does.
enum DiffLineKind {
  /// A line both sides have, shown around the changes.
  context,

  /// A line the old side has and the new one does not.
  removed,

  /// A line the new side has and the old one does not.
  added,
}

/// A line of a [DiffHunk]: [text] of [kind], and its numbers on the sides
/// that have it.
final class DiffLine {
  /// A line of [kind] holding [text], numbered [oldNumber] in the old
  /// file and [newNumber] in the new, each null on a side without it.
  const DiffLine(this.kind, this.text, {this.oldNumber, this.newNumber});

  /// Whether both sides have the line, the old side only or the new side
  /// only.
  final DiffLineKind kind;

  /// The line, without its line break.
  final String text;

  /// The number of the line in the old file, from 1; null for an added
  /// line.
  final int? oldNumber;

  /// The number of the line in the new file, from 1; null for a removed
  /// line.
  final int? newNumber;

  @override
  bool operator ==(Object other) =>
      other is DiffLine &&
      other.kind == kind &&
      other.text == text &&
      other.oldNumber == oldNumber &&
      other.newNumber == newNumber;

  @override
  int get hashCode => Object.hash(kind, text, oldNumber, newNumber);

  @override
  String toString() =>
      'DiffLine(${kind.name}, $oldNumber, $newNumber, "$text")';
}

/// A run of changed lines and the [DiffLineKind.context] around them, as
/// a unified diff's `@@ -oldStart,oldCount +newStart,newCount @@ section`
/// heads it.
final class DiffHunk {
  /// A hunk of [lines] from line [oldStart] of the old file and
  /// [newStart] of the new, [oldCount] and [newCount] of them, in
  /// [section], none by default.
  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
    this.section = '',
  });

  /// The number of the hunk's first line in the old file, or of the line
  /// before it when it has none of that side ([oldCount] 0).
  final int oldStart;

  /// How many lines of the old file it has.
  final int oldCount;

  /// [oldStart] of the new file.
  final int newStart;

  /// [oldCount] of the new file.
  final int newCount;

  /// What the header names after the line numbers, such as the function
  /// the hunk is in; empty for nothing.
  final String section;

  /// The lines of the hunk, context, removed and added, in the order of
  /// the diff.
  final List<DiffLine> lines;
}

/// The changes to a file: its paths, the lines of a diff's header for it,
/// and its [hunks].
final class FileDiff {
  /// The changes to the file at [oldPath] and [newPath]: [hunks] after the
  /// [headers] lines, and the whole of both texts as [oldLines] and
  /// [newLines] where they are known; every list empty, and every path
  /// and text null, by default.
  const FileDiff({
    this.oldPath,
    this.newPath,
    this.headers = const [],
    this.hunks = const [],
    this.oldLines,
    this.newLines,
  });

  /// The path of the old file; null where there was none (a file added)
  /// or the diff does not name one.
  final String? oldPath;

  /// The path of the new file; null where there is none (a file deleted)
  /// or the diff does not name one.
  final String? newPath;

  /// The lines of the diff from the start of the file's part to its first
  /// hunk: `diff --git …`, `index …`, `--- a/…`, `+++ b/…`.
  final List<String> headers;

  /// The hunks, in the order of the file; empty for a file whose part
  /// has none, such as a renamed file with the same content.
  final List<DiffHunk> hunks;

  /// The lines of the old file, all of them, when the diff was found from
  /// it ([Diff.between]); null when only the hunks are known.
  final List<String>? oldLines;

  /// [oldLines] of the new file.
  final List<String>? newLines;

  /// The path that names the file: the new one, or the old one where it
  /// was deleted.
  String? get path => newPath ?? oldPath;
}

/// The changes to one file or more ([files]).
///
/// The changes between two versions of a text, in one hunk:
///
/// ```dart
/// final diff = Diff.between('a\nb\nc\n', 'a\nB\nc\n', path: 'notes.txt');
/// diff.files.single.hunks.single.lines.length; // 4: a, -b, +B, c
/// ```
final class Diff {
  /// The changes to [files].
  const Diff(this.files);

  /// The diff [text] is in unified form, as `diff -u` and `git diff` write
  /// it, of any number of files.
  ///
  /// A file's part starts at a `diff ` line, or at a `--- ` line that a
  /// `+++ ` line follows out of a hunk, unless it is the first of a part a
  /// `diff --git` line started. Its paths are those of its `--- ` and
  /// `+++ ` lines (`/dev/null` none), without the time `diff -u` adds after
  /// a tab, or else of its `rename from` and `rename to` lines or its
  /// `diff --git` line; the `a/` and `b/` that start them are taken off
  /// where both have theirs, as `git diff` writes them. A hunk takes as
  /// many lines of each side as its header counts: an empty line in it is
  /// an empty line of context, and a `\` line (no line break at the end of
  /// the file) is left out. The lines of a part before its first hunk are
  /// its [FileDiff.headers]; the other lines out of hunks are left out.
  ///
  /// The text is read as it is: an escape sequence in it is part of its
  /// line, as in a diff of a file that has them. The colors of
  /// `git diff --color` come off with twk's [stripAnsi] first.
  factory Diff.parse(String text) => Diff(_parse(_lines(text)));

  /// The changes that make [before] into [after] ([diffLists] of their
  /// lines), each run of them a hunk with [context] lines of context
  /// before and after; runs at most 2 × [context] lines apart are one
  /// hunk. The file's [FileDiff.oldLines] and [FileDiff.newLines] are
  /// those of the two texts, and both its paths [path].
  ///
  /// A line break is `\n` or `\r\n`, and one at the end of a text ends its
  /// last line rather than starting another.
  factory Diff.between(
    String before,
    String after, {
    int context = 3,
    String? path,
  }) {
    assert(context >= 0, 'a context of 0 lines or more');
    final old = _lines(before);
    final now = _lines(after);
    final changes = diffLists(old, now);
    final hunks = <DiffHunk>[];
    for (var k = 0; k < changes.length;) {
      var last = k;
      while (last + 1 < changes.length &&
          changes[last + 1].oldStart - changes[last].oldEnd <= 2 * context) {
        last++;
      }
      final first = changes[k];
      final oldFrom = math.max(0, first.oldStart - context);
      final newFrom = first.newStart - (first.oldStart - oldFrom);
      final oldTo = math.min(old.length, changes[last].oldEnd + context);
      final newTo = changes[last].newEnd + (oldTo - changes[last].oldEnd);
      final lines = <DiffLine>[];
      var i = oldFrom;
      var j = newFrom;
      void keep(int to) {
        for (; i < to; i++, j++) {
          lines.add(
            DiffLine(
              DiffLineKind.context,
              old[i],
              oldNumber: i + 1,
              newNumber: j + 1,
            ),
          );
        }
      }

      for (final change in changes.getRange(k, last + 1)) {
        keep(change.oldStart);
        for (; i < change.oldEnd; i++) {
          lines.add(DiffLine(DiffLineKind.removed, old[i], oldNumber: i + 1));
        }
        for (; j < change.newEnd; j++) {
          lines.add(DiffLine(DiffLineKind.added, now[j], newNumber: j + 1));
        }
      }
      keep(oldTo);
      hunks.add(
        DiffHunk(
          oldStart: oldTo > oldFrom ? oldFrom + 1 : oldFrom,
          oldCount: oldTo - oldFrom,
          newStart: newTo > newFrom ? newFrom + 1 : newFrom,
          newCount: newTo - newFrom,
          lines: lines,
        ),
      );
      k = last + 1;
    }
    return Diff([
      FileDiff(
        oldPath: path,
        newPath: path,
        hunks: hunks,
        oldLines: old,
        newLines: now,
      ),
    ]);
  }

  /// The files the diff changes, in the order it names them; empty for a
  /// text that has no diff in it.
  final List<FileDiff> files;
}

/// The lines of [text], split at `\n` and `\r\n`; a line break at its end
/// ends the last line.
List<String> _lines(String text) {
  if (text.isEmpty) {
    return [];
  }
  final lines = [
    for (final line in text.split('\n'))
      if (line.endsWith('\r')) line.substring(0, line.length - 1) else line,
  ];
  if (text.endsWith('\n')) {
    lines.removeLast();
  }
  return lines;
}

/// The header of a hunk with its counts: `@@ -1,3 +1,4 @@ section`, a
/// count left out being 1. Numbers of more than 9 digits, which no file
/// has lines for, make it no header, rather than one past an int.
final _hunkHeader = RegExp(
  r'^@@ -(\d{1,9})(?:,(\d{1,9}))? \+(\d{1,9})(?:,(\d{1,9}))? @@ ?(.*)$',
);

/// The files of the unified diff of [lines]; see [Diff.parse].
List<FileDiff> _parse(List<String> lines) {
  final files = <_Part>[];
  _Part? part;
  // the hunk being read, and how many lines of each side it has to come
  _Hunk? hunk;
  for (var k = 0; k < lines.length; k++) {
    final line = lines[k];
    if (hunk != null) {
      if (hunk.take(line)) {
        if (hunk.oldLeft == 0 && hunk.newLeft == 0) {
          part!.hunks.add(hunk.done());
          hunk = null;
        }
        continue;
      }
      part!.hunks.add(hunk.done());
      hunk = null;
    }
    if (line.startsWith(r'\')) {
      continue;
    }
    if (line.startsWith('diff ')) {
      files.add(part = _Part(git: line.startsWith('diff --git ')));
      part.header(line);
      continue;
    }
    if (line.startsWith('--- ') &&
        k + 1 < lines.length &&
        lines[k + 1].startsWith('+++ ') &&
        (part == null || !part.git || part.minus || part.hunks.isNotEmpty)) {
      files.add(part = _Part(git: false));
    }
    if (_hunkHeader.firstMatch(line) case final match?) {
      if (part == null) {
        files.add(part = _Part(git: false));
      }
      hunk = _Hunk(match);
      if (hunk.oldLeft == 0 && hunk.newLeft == 0) {
        part.hunks.add(hunk.done());
        hunk = null;
      }
      continue;
    }
    if (part != null && part.hunks.isEmpty) {
      part.header(line);
    }
  }
  if (hunk != null) {
    part!.hunks.add(hunk.done());
  }
  return [for (final part in files) part.done()];
}

/// The part of a unified diff about a file, being read: [git] when it
/// started at a `diff --git` line.
final class _Part {
  _Part({required this.git});

  final bool git;
  final headers = <String>[];
  final hunks = <DiffHunk>[];

  /// Whether it had its `--- ` line, and its `+++ ` line.
  var minus = false;
  var plus = false;

  // the paths as the lines of the header name them
  String? _old;
  String? _new;
  String? _gitOld;
  String? _gitNew;
  var _added = false;
  var _deleted = false;

  /// Takes [line] as a line of the header.
  void header(String line) {
    headers.add(line);
    if (line.startsWith('--- ') && !minus) {
      minus = true;
      _old = _path(line.substring(4));
    } else if (line.startsWith('+++ ') && minus && !plus) {
      plus = true;
      _new = _path(line.substring(4));
    } else if (line.startsWith('rename from ')) {
      _gitOld = line.substring(12);
    } else if (line.startsWith('rename to ')) {
      _gitNew = line.substring(10);
    } else if (line.startsWith('new file mode')) {
      _added = true;
    } else if (line.startsWith('deleted file mode')) {
      _deleted = true;
    } else if (line.startsWith('diff --git ')) {
      // a/<path> b/<path>: the same path twice, unless renamed
      final paths = line.substring(11);
      final half = (paths.length - 1) ~/ 2;
      if (paths.length.isOdd &&
          paths.startsWith('a/') &&
          paths.startsWith(' b/', half) &&
          paths.substring(2, half) == paths.substring(half + 3)) {
        _gitOld = _gitNew = paths.substring(2, half);
      } else if (paths.indexOf(' b/') case final at when at > 2) {
        _gitOld = paths.substring(2, at);
        _gitNew = paths.substring(at + 3);
      }
    }
  }

  FileDiff done() {
    var old = _old;
    var now = _new;
    if ((old != null || now != null) &&
        (old?.startsWith('a/') ?? true) &&
        (now?.startsWith('b/') ?? true)) {
      old = old?.substring(2);
      now = now?.substring(2);
    }
    return FileDiff(
      oldPath: minus ? old : (_added ? null : _gitOld),
      newPath: plus ? now : (_deleted ? null : _gitNew),
      headers: headers,
      hunks: hunks,
    );
  }
}

/// The path [text] names after `--- ` or `+++ `, without the time after a
/// tab and the quotes around it; null for `/dev/null`.
String? _path(String text) {
  var path = text;
  final tab = path.indexOf('\t');
  if (tab >= 0) {
    path = path.substring(0, tab);
  }
  if (path.length > 1 && path.startsWith('"') && path.endsWith('"')) {
    path = path
        .substring(1, path.length - 1)
        .replaceAllMapped(
          RegExp(r'\\(.)'),
          (m) => switch (m[1]) {
            't' => '\t',
            'n' => '\n',
            final c => c!,
          },
        );
  }
  return path == '/dev/null' ? null : path;
}

/// A hunk being read: its header, its lines so far, and how many of each
/// side it has still to come.
final class _Hunk {
  _Hunk(RegExpMatch header)
    : oldStart = int.parse(header[1]!),
      oldCount = int.parse(header[2] ?? '1'),
      newStart = int.parse(header[3]!),
      newCount = int.parse(header[4] ?? '1'),
      section = header[5]!.trimRight() {
    oldLeft = oldCount;
    newLeft = newCount;
    _old = oldCount == 0 ? oldStart + 1 : oldStart;
    _new = newCount == 0 ? newStart + 1 : newStart;
  }

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String section;
  final _lines = <DiffLine>[];
  late int oldLeft;
  late int newLeft;

  // the numbers of the next line of each side
  late int _old;
  late int _new;

  /// Takes [line] as the hunk's next line; false when it is not one.
  bool take(String line) {
    final sign = line.isEmpty ? ' ' : line[0];
    final text = line.isEmpty ? '' : line.substring(1);
    if (sign == ' ' && oldLeft > 0 && newLeft > 0) {
      _lines.add(
        DiffLine(
          DiffLineKind.context,
          text,
          oldNumber: _old++,
          newNumber: _new++,
        ),
      );
      oldLeft--;
      newLeft--;
    } else if (sign == '-' && oldLeft > 0) {
      _lines.add(DiffLine(DiffLineKind.removed, text, oldNumber: _old++));
      oldLeft--;
    } else if (sign == '+' && newLeft > 0) {
      _lines.add(DiffLine(DiffLineKind.added, text, newNumber: _new++));
      newLeft--;
    } else if (sign != r'\') {
      return false;
    }
    return true;
  }

  DiffHunk done() => DiffHunk(
    oldStart: oldStart,
    oldCount: oldCount,
    newStart: newStart,
    newCount: newCount,
    section: section,
    lines: _lines,
  );
}
