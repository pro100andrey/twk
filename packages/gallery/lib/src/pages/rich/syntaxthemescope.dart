// The SyntaxThemeScope page.
part of 'rich.dart';

/// The source the SyntaxThemeScope page shows, a line each.
const _scoped = [
  '/// Says hello to the user, twice.',
  '@override',
  'Widget build(BuildContext context) {',
  "  final name = 'user', times = 2;",
  r"  return Text('Hello, $name! ' * times);",
  '}',
];

/// The theme of its own the SyntaxThemeScope page sets: the kinds it
/// leaves unset in the style of the text around them.
const _ownSyntax = SyntaxTheme(
  keyword: Style(attrs: Attr.bold),
  type: Style(attrs: Attr.bold),
  string: Style(attrs: Attr.italic),
  variable: Style(attrs: Attr.underline),
  comment: Style(attrs: Attr.dim),
);

/// The SyntaxThemeScope page's `syntax` option.
const _syntaxThemeScopeSyntax = ChoiceOption<String>(
  'syntax',
  'syntax theme',
  values: ['copyWith', 'own', 'none'],
);

final _syntaxThemeScope = GalleryPage(
  group: _group,
  title: 'SyntaxThemeScope',
  options: const [
    _syntaxThemeScopeSyntax,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final view = CodeView('${_scoped.join('\n')}\n', language: dartLanguage);
    return switch (o(_syntaxThemeScopeSyntax)) {
      'copyWith' => SyntaxThemeScope(
        theme: SyntaxTheme.from(theme).copyWith(
          keyword: theme.error.merge(const Style(attrs: Attr.bold)),
          string: theme.warning,
          comment: theme.muted,
        ),
        child: view,
      ),
      'own' => SyntaxThemeScope(theme: _ownSyntax, child: view),
      _ => view,
    };
  },
  code: (o) {
    final source = ["const _source = r'''", ..._scoped, "''';", ''];
    return switch (o(_syntaxThemeScopeSyntax)) {
      'none' => [
        ...source,
        '// no scope above it: SyntaxTheme.of finds none and',
        '// derives the styles from the Theme',
        '@override',
        'Widget build(BuildContext context) =>',
        '    const CodeView(_source, language: dartLanguage);',
      ],
      'own' => [
        ...source,
        '// a theme of its own: the kinds it leaves unset are',
        '// drawn in the style of the text around them',
        'const _syntax = SyntaxTheme(',
        '  keyword: Style(attrs: Attr.bold),',
        '  type: Style(attrs: Attr.bold),',
        '  string: Style(attrs: Attr.italic),',
        '  variable: Style(attrs: Attr.underline),',
        '  comment: Style(attrs: Attr.dim),',
        ');',
        '',
        '@override',
        'Widget build(BuildContext context) => const SyntaxThemeScope(',
        '  theme: _syntax,',
        '  child: CodeView(_source, language: dartLanguage),',
        ');',
      ],
      _ => [
        ...source,
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  return SyntaxThemeScope(',
        '    // the theme derived from the Theme, three kinds',
        '    // of token changed',
        '    theme: SyntaxTheme.from(theme).copyWith(',
        '      keyword: theme.error.merge(const .new(attrs: Attr.bold)),',
        '      string: theme.warning,',
        '      comment: theme.muted,',
        '    ),',
        '    child: const CodeView(_source, language: dartLanguage),',
        '  );',
        '}',
      ],
    }.join('\n');
  },
);
