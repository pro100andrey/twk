// The Link page.
part of 'controls.dart';

final _linkPage = GalleryPage(
  group: 'Controls',
  title: 'Link',
  options: const [
    ColorOption(
      'color',
      'style',
      values: ['primary', 'accent', 'info'],
      initial: 'primary',
    ),
    ChoiceOption(
      'text',
      'shows',
      values: ['label', 'url'],
      labels: ['text', 'url'],
    ),
  ],
  build: (context, o) {
    final c = o.color('color');
    final labelled = o.choice<String>('text') == 'label';
    final style = c == 'primary'
        ? null
        : o
              .colorStyle(context, 'color')
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
    final c = o.color('color');
    final primary = c == 'primary';
    final labelled = o.choice<String>('text') == 'label';
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
