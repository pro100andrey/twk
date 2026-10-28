/// The styles of tokens by kind: [SyntaxTheme], derived from the app's
/// [ThemeData] unless a [SyntaxThemeScope] sets one.
///
/// @docImport '../diff/diff_view.dart';
/// @docImport 'code_view.dart';
library;

import 'package:twk/twk.dart';

import 'token.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late BuildContext context;
// late String source;

/// The style of each [TokenKind]. A style left unset is the empty style:
/// the token is drawn in the style of the text around it.
///
/// See also:
///
///  * [SyntaxThemeScope], which sets one for the code below it.
///  * [TokenKind], what each kind is for.
final class SyntaxTheme {
  /// The style of each kind, the empty style unless given.
  const SyntaxTheme({
    this.plain = const Style(),
    this.keyword = const Style(),
    this.type = const Style(),
    this.function = const Style(),
    this.variable = const Style(),
    this.constant = const Style(),
    this.string = const Style(),
    this.escape = const Style(),
    this.number = const Style(),
    this.comment = const Style(),
    this.annotation = const Style(),
    this.key = const Style(),
    this.punctuation = const Style(),
    this.operator = const Style(),
    this.inserted = const Style(),
    this.deleted = const Style(),
    this.heading = const Style(),
  });

  /// The styles in the colors of [theme], so that code follows the app's
  /// theme and the terminal's brightness with it: keywords in its accent,
  /// functions and keys in its primary color, types, escapes and operators
  /// in its info color, strings and inserted lines in its success color,
  /// numbers, constants and annotations in its warning color, variables and
  /// deleted lines in its error color, comments muted and italic, headings
  /// of a diff bold in its info color; plain text and punctuation in the
  /// style of the text around them.
  SyntaxTheme.from(ThemeData theme)
    : this(
        keyword: theme.accent,
        type: theme.info,
        function: theme.primary,
        variable: theme.error,
        constant: theme.warning,
        string: theme.success,
        escape: theme.info,
        number: theme.warning,
        comment: theme.muted.merge(const Style(attrs: Attr.italic)),
        annotation: theme.warning,
        key: theme.primary,
        operator: theme.info,
        inserted: theme.success,
        deleted: theme.error,
        heading: theme.info.merge(const Style(attrs: Attr.bold)),
      );

  /// The syntax theme at [context]: that of the nearest
  /// [SyntaxThemeScope], or else one [SyntaxTheme.from] the [Theme] there.
  /// [context] depends on what it is taken from.
  factory SyntaxTheme.of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyntaxThemeScope>()?.theme ??
      SyntaxTheme.from(Theme.of(context));

  /// Text of no other kind: names, blanks, what a lexer does not know.
  final Style plain;

  /// Keywords.
  final Style keyword;

  /// The names of types.
  final Style type;

  /// The names of functions where they are declared or called.
  final Style function;

  /// Variables a language marks as such, such as `$x` in a shell.
  final Style variable;

  /// Literal constants other than numbers: `true`, `false`, `null`.
  final Style constant;

  /// Strings and characters, their quotes included.
  final Style string;

  /// Escape sequences in strings.
  final Style escape;

  /// Numbers.
  final Style number;

  /// Comments.
  final Style comment;

  /// Annotations, decorators, attributes and directives.
  final Style annotation;

  /// The keys of mappings in data: JSON objects, YAML mappings.
  final Style key;

  /// Brackets, separators and delimiters.
  final Style punctuation;

  /// Operators.
  final Style operator;

  /// The lines a diff adds.
  final Style inserted;

  /// The lines a diff removes.
  final Style deleted;

  /// The headers of a diff: of a file, of a hunk.
  final Style heading;

  /// The style of tokens of [kind].
  Style styleOf(TokenKind kind) => switch (kind) {
    TokenKind.plain => plain,
    TokenKind.keyword => keyword,
    TokenKind.type => type,
    TokenKind.function => function,
    TokenKind.variable => variable,
    TokenKind.constant => constant,
    TokenKind.string => string,
    TokenKind.escape => escape,
    TokenKind.number => number,
    TokenKind.comment => comment,
    TokenKind.annotation => annotation,
    TokenKind.key => key,
    TokenKind.punctuation => punctuation,
    TokenKind.operator => operator,
    TokenKind.inserted => inserted,
    TokenKind.deleted => deleted,
    TokenKind.heading => heading,
  };

  /// [tokens] as spans, each in the style of its kind.
  List<Span> spans(List<Token> tokens) => [
    for (final token in tokens) Span(token.text, styleOf(token.kind)),
  ];

  /// This theme with the styles given replaced.
  SyntaxTheme copyWith({
    Style? plain,
    Style? keyword,
    Style? type,
    Style? function,
    Style? variable,
    Style? constant,
    Style? string,
    Style? escape,
    Style? number,
    Style? comment,
    Style? annotation,
    Style? key,
    Style? punctuation,
    Style? operator,
    Style? inserted,
    Style? deleted,
    Style? heading,
  }) => SyntaxTheme(
    plain: plain ?? this.plain,
    keyword: keyword ?? this.keyword,
    type: type ?? this.type,
    function: function ?? this.function,
    variable: variable ?? this.variable,
    constant: constant ?? this.constant,
    string: string ?? this.string,
    escape: escape ?? this.escape,
    number: number ?? this.number,
    comment: comment ?? this.comment,
    annotation: annotation ?? this.annotation,
    key: key ?? this.key,
    punctuation: punctuation ?? this.punctuation,
    operator: operator ?? this.operator,
    inserted: inserted ?? this.inserted,
    deleted: deleted ?? this.deleted,
    heading: heading ?? this.heading,
  );

  @override
  bool operator ==(Object other) =>
      other is SyntaxTheme &&
      TokenKind.values.every((kind) => other.styleOf(kind) == styleOf(kind));

  @override
  int get hashCode => Object.hashAll(TokenKind.values.map(styleOf));
}

/// Sets the [SyntaxTheme] of the code below it ([SyntaxTheme.of]) in
/// place of the one derived from the [Theme].
///
/// A [CodeView] whose comments stand out more than the theme's muted
/// italic, the rest as the theme has it:
///
/// ```dart
/// SyntaxThemeScope(
///   theme: SyntaxTheme.from(Theme.of(context)).copyWith(
///     comment: const Style(fg: Color.green, attrs: Attr.bold),
///   ),
///   child: CodeView(source, language: languageNamed('dart')),
/// )
/// ```
///
/// A [DiffView] and a `MarkdownView`'s code blocks below it take it as
/// well.
final class SyntaxThemeScope extends InheritedWidget {
  /// Sets [theme] for [child] and what is below it.
  const SyntaxThemeScope({
    required this.theme,
    required super.child,
    super.key,
  });

  /// The theme [SyntaxTheme.of] gives below this scope.
  final SyntaxTheme theme;

  @override
  bool updateShouldNotify(SyntaxThemeScope oldWidget) =>
      theme != oldWidget.theme;
}
