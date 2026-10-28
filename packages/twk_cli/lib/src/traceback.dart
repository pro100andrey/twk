/// What a [Cli] shows of an error: [traceback], its lines of spans.
///
/// @docImport 'cli.dart';
library;

import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart'
    show Highlighter, SyntaxTheme, dartLanguage;

import 'theme.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// void load() {}

/// The widest a frame's location is padded to, so that the members line
/// up; a longer one is followed by two blanks.
const _locationColumn = 50;

/// [error] thrown at [stack] as lines of spans, for a console program to
/// write as [Cli.error] does: what was thrown, the source of the app's own
/// code it was thrown in, and the frames that led there.
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
///   indented under it. All of it in [theme]'s [CliTheme.error].
/// * Then the lines around the one the stack names first in the app's own
///   code ([RecordFrame.isAppCode]: neither the SDK, nor twk and its
///   packages, nor the pub cache), [context] on each side of it, under its
///   place ([SourceExcerpt]), highlighted as Dart in [syntax]
///   ([SyntaxTheme.from] the [theme]'s [CliTheme.data] without). Left out
///   where there is no such frame, or its file can't be read (an AOT
///   build, the source changed or gone).
/// * Then the frames, a line each, the location and the member: the runs
///   of frames not of the app's own code between the app's folded into a
///   line saying how many and whose ([stackLines]), unless [allFrames].
///
/// The places are paths from the working directory where they are in it,
/// each a link to its file (OSC 8 where the terminal takes them). The VM
/// keeps no local variables to show.
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
  CliTheme theme = const CliTheme(),
  SyntaxTheme? syntax,
}) {
  final style = theme.error;
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
          theme,
          syntax ??
              SyntaxTheme.from(
                theme.lineData,
              ),
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
            ? [Span('  ${line.text}', theme.hint)]
            : [
                const Span('  '),
                Span(frame.location, _linked(theme.hint, frame.path)),
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

/// The lines of [excerpt]: its place, then its lines, numbered, the
/// marked one after a `▶`, the code highlighted.
List<List<Span>> _excerptLines(
  SourceExcerpt excerpt,
  CliTheme theme,
  SyntaxTheme syntax,
) {
  // the file lexed from its top: the lines shown start in the state the
  // ones above leave them in, inside a comment or a string
  final source = Highlighter(
    dartLanguage,
    excerpt.fileLines.take(excerpt.lastLine).join('\n'),
  );
  final width = '${excerpt.lastLine}'.length;
  final lines = [
    [
      const Span('  '),
      Span(excerpt.location, _linked(theme.hint, excerpt.path)),
    ],
  ];
  for (var n = excerpt.firstLine; n <= excerpt.lastLine; n++) {
    final code = [
      for (final span in syntax.spans(source.tokens(n - 1)))
        if (span.text.isNotEmpty)
          Span(span.text.replaceAll('\t', '  '), span.style),
    ];
    // no blanks at the end of a line
    while (code.isNotEmpty && code.last.text.trim().isEmpty) {
      code.removeLast();
    }
    lines.add([
      if (n == excerpt.line) ...[
        const Span('  '),
        Span('▶ ', theme.error),
        Span('$n'.padLeft(width), theme.error.merge(_bold)),
      ] else
        Span('    ${'$n'.padLeft(width)}', theme.hint),
      Span(code.isEmpty ? ' │' : ' │ ', theme.hint),
      ...code,
    ]);
  }
  return lines;
}
