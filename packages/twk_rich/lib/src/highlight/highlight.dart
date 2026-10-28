/// Syntax highlighting of source code by lexers of this package's own, one
/// per language, that tokenize line by line.
///
/// A [Language] ([languages], [languageNamed]) has a [Lexer] that splits a
/// line into [Token]s of a [TokenKind], starting in the state the line
/// before ended in. A [Highlighter] keeps source lexed through edits,
/// lexing again only the lines an edit changes. [CodeView] shows source in
/// the styles of the [SyntaxTheme] at its place, with line numbers or
/// without.
library;

import 'code_view.dart';
import 'highlighter.dart';
import 'languages.dart';
import 'lexer.dart';
import 'syntax_theme.dart';
import 'token.dart';

export 'code_view.dart';
export 'highlighter.dart';
export 'languages.dart';
export 'lexer.dart';
export 'syntax_theme.dart';
export 'token.dart';
