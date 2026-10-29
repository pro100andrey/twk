/// The source of a traceback highlighted as Dart: [dartSourceLines].
library;

import 'package:twk/twk.dart';

import 'highlighter.dart';
import 'lang/dart.dart';
import 'syntax_theme.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late Object error;
// late StackTrace stack;

/// The lines of [excerpt] highlighted as Dart in [theme]'s colors
/// ([SyntaxTheme.from]): the [SourceLines] of a [traceback] that shows the
/// code it was thrown in as an editor would. The file is lexed from its
/// top, so a line inside a comment or a string that opens above it is
/// shown as one.
///
/// ```dart
/// traceback(error, stack, sourceLines: dartSourceLines);
/// ```
List<List<Span>> dartSourceLines(SourceExcerpt excerpt, ThemeData theme) {
  final syntax = SyntaxTheme.from(theme);
  final source = Highlighter(
    dartLanguage,
    excerpt.fileLines.take(excerpt.lastLine).join('\n'),
  );
  return [
    for (var n = excerpt.firstLine; n <= excerpt.lastLine; n++)
      syntax.spans(source.tokens(n - 1)),
  ];
}
