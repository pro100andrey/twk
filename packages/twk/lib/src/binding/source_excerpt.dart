/// What a `WidgetError` shows of the code that threw, and a console
/// program's traceback: the lines around the one of the app's own code its
/// stack trace names first ([SourceExcerpt]).
library;

import 'dart:math' show max, min;

import '../platform/platform.dart'
    show
        currentDirectory,
        environment,
        isWindows,
        pathSeparator,
        readLines,
        sourcePath;

// Examples can assume:
// late StackTrace stack;

/// A frame of a stack trace as the VM writes it, `#2  member (uri:line)`
/// or `(uri:line:column)`: its URI, line and column.
final _frame = RegExp(
  r'^#\d+\s.*\(([^()\s]+?):(\d+)(?::(\d+))?\)\r?$',
  multiLine: true,
);

/// The lines of a source file around one of them, [line], which is
/// marked: [lines], numbered from [firstLine], of the file at [path].
///
/// [SourceExcerpt.of] finds the line a stack trace names first in the
/// app's own code, as a `WidgetError` shows it; [SourceExcerpt.read] reads
/// the lines around any line of a file. Its [toString] is the text a
/// `WidgetError` shows:
///
/// ```text
/// at lib/main.dart:52:29
///   50 |     children: [
///   51 |       InputListener(
/// > 52 |         onEvent: (e) => throw StateError('boom'),
///   53 |         child: const SizedBox(),
///   54 |       ),
/// ```
///
/// A program that shows the lines its own way, highlighted, takes them
/// from [lines] (or from [fileLines], to lex the file from its top):
///
/// ```dart
/// final excerpt = SourceExcerpt.of(stack);
/// if (excerpt != null) {
///   print('at ${excerpt.location}');
///   for (final (i, text) in excerpt.lines.indexed) {
///     final n = excerpt.firstLine + i;
///     print('${n == excerpt.line ? '>' : ' '} $n | $text');
///   }
/// }
/// ```
final class SourceExcerpt {
  SourceExcerpt._(
    this.path,
    this.line,
    this.column,
    this.fileLines,
    this.firstLine,
    this.lastLine,
  );

  /// The lines of the app's own code around the line [stack] names first,
  /// [context] lines on each side of it (fewer at the file's ends).
  ///
  /// The app's own code is that of the first frame in neither the SDK,
  /// nor twk (`package:twk`, `package:twk_core`), nor a package in the
  /// pub cache (from pub.dev or git); a `package:` URI is read from the
  /// file the program resolves it to. Null where that file can't be read:
  /// a `package:` URI the program doesn't resolve (an AOT build, the
  /// web), a file that is missing or has fewer lines (changed since), no
  /// frame in the VM's format.
  static SourceExcerpt? of(StackTrace? stack, {int context = 2}) {
    if (stack == null) {
      return null;
    }
    for (final frame in _frame.allMatches('$stack')) {
      final uri = Uri.tryParse(frame[1]!);
      if (uri == null || sdkOrTwk(uri)) {
        continue;
      }
      final path = sourcePath(uri);
      if (path != null && inPubCache(path)) {
        continue;
      }
      if (path == null) {
        return null;
      }
      final column = frame[3];
      return read(
        path,
        int.parse(frame[2]!),
        column: column == null ? null : int.parse(column),
        context: context,
      );
    }
    return null;
  }

  /// The lines of the file at [path] around [line], counted from 1,
  /// [context] lines on each side of it (fewer at the file's ends), at
  /// [column] where it is known. Null where the file can't be read, or
  /// has no line [line].
  static SourceExcerpt? read(
    String path,
    int line, {
    int? column,
    int context = 2,
  }) {
    final lines = readLines(path);
    if (lines == null || line < 1 || line > lines.length) {
      return null;
    }
    final around = max(0, context);
    return SourceExcerpt._(
      path,
      line,
      column,
      List.unmodifiable(lines),
      max(1, line - around),
      min(lines.length, line + around),
    );
  }

  /// The file the lines are of.
  final String path;

  /// The line marked, counted from 1.
  final int line;

  /// The column in [line], from 1; null where it isn't known.
  final int? column;

  /// Every line of the file, as it was read: for a program that lexes
  /// the file from its top, so that the lines shown start in the state
  /// (a comment, a string) the lines above leave them in.
  final List<String> fileLines;

  /// The number of the first line shown, counted from 1.
  final int firstLine;

  /// The number of the last line shown.
  final int lastLine;

  /// The lines shown, from [firstLine] to [lastLine], [line] among them.
  List<String> get lines => fileLines.sublist(firstLine - 1, lastLine);

  /// [path] from the working directory when it is in it.
  String get shownPath => _shownPath(path);

  /// `shownPath:line:column`, or `shownPath:line` without a [column].
  String get location => '$shownPath:$line${column == null ? '' : ':$column'}';

  /// `at location`, then the lines, the marked one after a `>`, each after
  /// its number, right-aligned, and a `|`.
  @override
  String toString() {
    final width = '$lastLine'.length;
    return [
      'at $location',
      for (var n = firstLine; n <= lastLine; n++)
        '${n == line ? '>' : ' '} ${'$n'.padLeft(width)} | ${fileLines[n - 1]}'
            .trimRight(),
    ].join('\n');
  }
}

/// The text of the [SourceExcerpt.of] [stack], as a `WidgetError` shows
/// it; null where there is none.
String? sourceExcerpt(StackTrace? stack) => SourceExcerpt.of(stack)?.toString();

/// Whether [uri] is that of a library of the SDK or of twk.
bool sdkOrTwk(Uri uri) => switch (uri.scheme) {
  'dart' || 'org-dartlang-sdk' => true,
  'package' => switch (uri.pathSegments) {
    ['twk' || 'twk_core', ...] => true,
    _ => false,
  },
  _ => false,
};

/// Whether [path] is in the pub cache, where `dart pub get` keeps the
/// packages from pub.dev and git: under `PUB_CACHE`, or in a `.pub-cache`
/// directory (`Pub\Cache` on Windows).
bool inPubCache(String path) {
  final cache = environment['PUB_CACHE'];
  if (cache != null && cache.isNotEmpty && path.startsWith(cache)) {
    return true;
  }
  final s = pathSeparator;
  return path.contains('$s.pub-cache$s') || path.contains('${s}Pub${s}Cache$s');
}

/// [path] from the working directory when it is in it.
String shownPath(String path) => _shownPath(path);

String _shownPath(String path) {
  final cwd = '$currentDirectory$pathSeparator';
  // Windows' paths are of any case, the drive's letter of a stack's file:
  // URI small where the working directory's is a capital
  final within = isWindows
      ? path.toLowerCase().startsWith(cwd.toLowerCase())
      : path.startsWith(cwd);
  return within ? path.substring(cwd.length) : path;
}
