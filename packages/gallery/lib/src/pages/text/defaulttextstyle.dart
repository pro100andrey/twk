// The DefaultTextStyle page.
part of 'text.dart';

final _defaulttextstylePage = GalleryPage(
  group: 'Text',
  title: 'DefaultTextStyle',
  options: [
    ChoiceOption('style', 'style', values: _defaultStyles.keys.toList()),
  ],
  build: (context, o) => DefaultTextStyle(
    style: _defaultStyles[o.choice<String>('style')]!.$1,
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('This text has the default style.'),
        Text(
          'This one merges yellow over it.',
          style: Style(fg: Color.yellow),
        ),
      ],
    ),
  ),
  code: (o) => [
    'return DefaultTextStyle(',
    '  style: const ${_defaultStyles[o.choice<String>('style')]!.$2},',
    '  child: const Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    children: [',
    "      Text('This text has the default style.'),",
    _yellowLine,
    '    ],',
    '  ),',
    ');',
  ].join('\n'),
);

/// The Code's line of the Text that merges yellow over the default style.
const _yellowLine =
    "      Text('This one merges yellow over it.', "
    'style: .new(fg: .yellow)),';

/// Each style of the DefaultTextStyle page, and its Dart. White on navy
/// rather than on blue: the palette's blue is light in most dark themes,
/// and the yellow merged over it would not read.
const _defaultStyles = <String, (Style, String)>{
  'bold': (Style(attrs: Attr.bold), 'Style(attrs: Attr.bold)'),
  'italic': (Style(attrs: Attr.italic), 'Style(attrs: Attr.italic)'),
  'green': (Style(fg: Color.green), 'Style(fg: Color.green)'),
  'on navy': (
    Style(fg: Color.white, bg: Color.indexed(17)),
    'Style(fg: Color.white, bg: Color.indexed(17))',
  ),
};
