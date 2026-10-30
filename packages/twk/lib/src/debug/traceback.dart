/// What a program shows of an error it ends on: [traceback], its lines of
/// spans, the source it was thrown in given by [SourceLines].
library;

import 'package:twk_core/twk_core.dart' show Attr, Brightness, Color;

import '../binding/source_excerpt.dart';
import '../style/style.dart';
import 'console_record.dart';

// Examples can assume:
// void load() {}

/// The lines of code of [excerpt], from its first line to its last, as
/// spans in [theme]: what a [traceback] shows of the source an error was
/// thrown in, after each line's number. The lines of the file
/// ([SourceExcerpt.fileLines]) are there from its top, for code that reads
/// the lines above to show the first of them (inside a comment or a
/// string).
typedef SourceLines = List<List<Span>> Function(
  SourceExcerpt excerpt,
  ThemeData theme,
);

/// The widest a frame's location is padded to, so that the members line
/// up; a longer one is followed by two blanks.
const _locationColumn = 50;

/// [error] thrown at [stack] as lines of spans, for a program to write
/// where it ends on it: what was thrown, the source of the app's own code
/// it was thrown in, and the frames that led there.
///
/// ```text
/// ✗ StateError: Bad state: the config has no "name"
///
///   lib/src/config.dart:42:7
///     40 │   final map = jsonDecode(text) as Map<String, Object?>;
///     41 │   if (map['name'] == null) {
///   ▶ 42 │     throw StateError('the config has no "name"');
///     43 │   }
///
///   lib/src/config.dart:42:7  Config.load
///   … 3 frames of dart:async
///   bin/tool.dart:12:3        main
/// ```
///
/// * The first line is the error's type and its `toString()`, the type
///   left out where the text starts with it (`FormatException: …`) or the
///   error is a string; the lines after it, where the text has more, are
///   indented under it. All of it in [errorStyle], the [theme]'s
///   [ThemeData.error] without, red without either.
/// * Then the lines around the one the stack names first in the app's own
///   code ([RecordFrame.isAppCode]: neither the SDK, nor twk and its
///   packages, nor the pub cache), [context] on each side of it, under its
///   place ([SourceExcerpt]), the code as [sourceLines] gives it, the text
///   of the lines without. Left out where there is no such frame, or its
///   file can't be read (an AOT build, the source changed or gone).
/// * Then the frames, a line each, the location and the member: the runs
///   of frames not of the app's own code between the app's folded into a
///   line saying how many and whose ([stackLines]), unless [allFrames].
///
/// The places, the line numbers and the folded frames are in [hintStyle],
/// the [theme]'s [ThemeData.muted] without, and without either in the
/// terminal's own colour dim, which reads on a dark background and a light
/// one alike. [sourceLines] gets the [theme], the terminal's own colours
/// without one. The places are paths from the
/// working directory where they are in it, each a link to its file. The
/// VM keeps no local variables to show.
///
/// ```dart
/// try {
///   load();
/// } on Object catch (error, stack) {
///   for (final line in traceback(error, stack)) {
///     print(line.map((span) => span.text).join());
///   }
/// }
/// ```
List<List<Span>> traceback(
  Object error,
  StackTrace stack, {
  bool allFrames = false,
  int context = 2,
  ThemeData? theme,
  Style? errorStyle,
  Style? hintStyle,
  SourceLines? sourceLines,
}) {
  final style = errorStyle ?? theme?.error ?? const Style(fg: Color.red);
  final hint =
      hintStyle ??
      theme?.muted ??
      const Style(fg: Color.defaultColor, attrs: Attr.dim);
  final text = _describe(error).split('\n');
  final lines = <List<Span>>[
    [Span('✗ ', style), Span(text.first, style.merge(_bold))],
    for (final line in text.skip(1))
      [if (line.isNotEmpty) Span('  $line', style)],
  ];

  final frames = stackLines(stack, fold: false);
  final app = frames
      .map((line) => line.frame)
      .firstWhere(
        (f) => f != null && f.isAppCode && f.path != null && f.line != null,
        orElse: () => null,
      );
  final excerpt = app == null
      ? null
      : SourceExcerpt.read(
          app.path!,
          app.line!,
          column: app.column,
          context: context,
        );
  if (excerpt != null) {
    lines
      ..add(const [])
      ..addAll(
        _excerptLines(
          excerpt,
          (sourceLines ?? _plain)(
            excerpt,
            theme ?? const ThemeData.terminal(Brightness.dark),
          ),
          style,
          hint,
        ),
      );
  }

  final shown = allFrames ? frames : stackLines(stack);
  if (shown.isNotEmpty) {
    var width = 0;
    for (final line in shown) {
      final location = line.frame?.location.length ?? 0;
      if (location <= _locationColumn && location > width) {
        width = location;
      }
    }
    lines.add(const []);
    for (final line in shown) {
      final frame = line.frame;
      lines.add(
        frame == null
            ? [Span('  ${line.text}', hint)]
            : [
                const Span('  '),
                Span(frame.location, _linked(hint, frame.path)),
                Span(
                  '${' ' * (width - frame.location.length).clamp(0, width)}'
                  '  ${frame.member}',
                ),
              ],
      );
    }
  }
  return lines;
}

/// The lines of [excerpt] as their text, unstyled.
List<List<Span>> _plain(SourceExcerpt excerpt, ThemeData theme) => [
  for (var n = excerpt.firstLine; n <= excerpt.lastLine; n++)
    [Span(excerpt.fileLines[n - 1])],
];

/// What the first line of a [traceback] says of [error]: its type and its
/// `toString()`, the type left out where the text starts with it, or the
/// error is a string.
String _describe(Object error) {
  String text;
  try {
    text = '$error';
  } on Object catch (e) {
    text = '<toString() threw ${e.runtimeType}>';
  }
  if (error is String || text.startsWith("Instance of '")) {
    return text;
  }
  var type = '${error.runtimeType}';
  final arguments = type.indexOf('<');
  if (arguments > 0) {
    type = type.substring(0, arguments);
  }
  // a private class of the SDK's stands for the public one: _TypeError
  while (type.startsWith('_')) {
    type = type.substring(1);
  }
  return type.isEmpty || text.startsWith(type) ? text : '$type: $text';
}

const _bold = Style(attrs: Attr.bold);

/// [style] linking to the file at [path], where there is one.
Style _linked(Style style, String? path) =>
    path == null ? style : style.merge(Style(link: Uri.file(path).toString()));

/// The lines of [excerpt]: its place, then its lines of [code], numbered,
/// the marked one after a `▶`.
List<List<Span>> _excerptLines(
  SourceExcerpt excerpt,
  List<List<Span>> code,
  Style error,
  Style hint,
) {
  final width = '${excerpt.lastLine}'.length;
  final lines = [
    [const Span('  '), Span(excerpt.location, _linked(hint, excerpt.path))],
  ];
  for (var n = excerpt.firstLine; n <= excerpt.lastLine; n++) {
    final i = n - excerpt.firstLine;
    final spans = [
      if (i < code.length)
        for (final span in code[i])
          if (span.text.isNotEmpty)
            Span(span.text.replaceAll('\t', '  '), span.style),
    ];
    // no blanks at the end of a line
    while (spans.isNotEmpty && spans.last.text.trim().isEmpty) {
      spans.removeLast();
    }
    lines.add([
      if (n == excerpt.line) ...[
        const Span('  '),
        Span('▶ ', error),
        Span('$n'.padLeft(width), error.merge(_bold)),
      ] else
        Span('    ${'$n'.padLeft(width)}', hint),
      Span(spans.isEmpty ? ' │' : ' │ ', hint),
      ...spans,
    ]);
  }
  return lines;
}
