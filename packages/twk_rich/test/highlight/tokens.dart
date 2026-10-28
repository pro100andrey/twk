/// How the highlighting tests write tokens: a line of text per line of
/// source, each token as its kind and its text in JSON, a plain one as its
/// text alone.
library;

import 'dart:convert';

import 'package:twk_rich/twk_rich.dart';

/// The tokens of [source] in [language], as [describe] writes them, a line
/// per line of source.
String lexed(Language language, String source) {
  final code = Highlighter(language, source);
  return [
    for (var i = 0; i < code.lineCount; i++) describe(code.tokens(i)),
  ].join('\n');
}

/// [tokens] written apart by blanks: `keyword"final"`, a plain one as
/// `" x "`.
String describe(List<Token> tokens) => [
  for (final token in tokens)
    if (token.kind == TokenKind.plain) jsonEncode(token.text) else '$token',
].join(' ');
