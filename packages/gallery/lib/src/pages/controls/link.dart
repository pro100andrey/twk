// The Link page.
part of 'controls.dart';

/// The Link page's `color` option.
const _linkColor = ColorOption(
  'color',
  'style',
  values: ['primary', 'accent', 'info'],
  initial: 'primary',
);

/// The Link page's `text` option.
const _linkText = ChoiceOption<String>(
  'text',
  'shows',
  values: ['label', 'url'],
  labels: ['text', 'url'],
);

final _linkPage = GalleryPage(
  group: _group,
  title: 'Link',
  options: const [
    _linkColor,
    _linkText,
  ],
  build: (context, o) {
    final c = o(_linkColor);
    final labelled = o(_linkText) == 'label';
    final style = c == 'primary'
        ? null
        : o
              .styleOf(context, _linkColor)
              .merge(const Style(attrs: Attr.underline));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Link(
          'https://dart.dev',
          style: style,
          text: labelled ? 'The Dart language' : null,
        ),
        Link('https://pub.dev', style: style),
        Link(
          'file:///home/user/twk/README.md',
          style: style,
          text: labelled ? 'the README' : null,
        ),
      ],
    );
  },
  code: (o) {
    final c = o(_linkColor);
    final primary = c == 'primary';
    final labelled = o(_linkText) == 'label';
    // a link, its text where the page labels it
    List<String> link(String url, String? text) => [
      "'$url'",
      if (!primary) 'style: style',
      if (labelled && text != null) "text: '$text'",
    ];
    return [
      if (!primary) ...[
        'final theme = Theme.of(context);',
        'final style = theme.$c.merge(const .new(attrs: Attr.underline));',
      ],
      'return ${primary ? 'const ' : ''}Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      ...call(4, 'Link', link('https://dart.dev', 'The Dart language'), ','),
      ...call(4, 'Link', link('https://pub.dev', null), ','),
      ...call(4, 'Link', link(_readme, 'the README'), ','),
      '  ],',
      ');',
    ].join('\n');
  },
);

const _readme = 'file:///home/user/twk/README.md';
