// The GradientForeground page.
part of 'style.dart';

final _gradientforegroundPage = GalleryPage(
  group: _group,
  title: 'GradientForeground',
  options: _gradientOptions('theme'),
  build: (context, o) => _Flowing(
    options: o,
    sets: _textSets,
    build: (context, gradient) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        GradientForeground(
          gradient: gradient,
          child: Text(_fgRows.join('\n')),
        ),
        Text.rich([
          Span(_spanLead, Theme.of(context).muted),
          _spanText.gradient(gradient),
        ]),
      ],
    ),
  ),
  code: (o) => _gradientCode(o, 'Lettering', _textSets, [
    'Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  spacing: 1,',
    '  children: [',
    '    GradientForeground(',
    '      gradient: gradient,',
    '      child: const Text(',
    for (final (i, l) in _fgRows.indexed)
      "        '$l${i < _fgRows.length - 1 ? r'\n' : ''}'",
    '      ),',
    '    ),',
    '    Text.rich([',
    "      Span('$_spanLead', Theme.of(context).muted),",
    "      '$_spanText'.gradient(gradient),",
    '    ]),',
    '  ],',
    ')',
  ]),
);

/// The sets of the lettering: sunset's and ocean's light colours read only
/// on a dark background, so the text takes them, a little lighter, on a
/// dark theme, and darker ones on a light theme.
const _Sets _textSets = {
  'theme': (_ColorSet.theme(), null),
  'sunset': (
    _ColorSet.rgb([Color.rgb(0xff, 0x5f, 0x6d), Color.rgb(0xff, 0xc3, 0x71)]),
    _ColorSet.rgb([Color.rgb(0xc8, 0x30, 0x4f), Color.rgb(0xb0, 0x5c, 0x00)]),
  ),
  'ocean': (
    _ColorSet.rgb([
      Color.rgb(0x5a, 0xa9, 0xe6),
      Color.rgb(0x4e, 0xcd, 0xc4),
      Color.rgb(0xc8, 0xf7, 0xe8),
    ]),
    _ColorSet.rgb([
      Color.rgb(0x1f, 0x5f, 0x99),
      Color.rgb(0x0f, 0x7f, 0x78),
      Color.rgb(0x2e, 0x7d, 0x4f),
    ]),
  ),
  'palette': (
    _ColorSet.palette([Color.blue, Color.magenta, Color.red]),
    null,
  ),
};

/// "twk" in big letters, of block elements and box lines, a blank line and
/// two of text: what GradientForeground colours.
const _fgRows = [
  '████████╗██╗   ██╗██╗',
  '╚══██╔══╝██║   ██║██║',
  '   ██║   ██║   ██║██║',
  '   ██║   ██║   ██║██║',
  '   ██║   ╚██████╔╝██║',
  '   ╚═╝    ╚═════╝ ╚═╝',
  '',
  'Colors that change from glyph to glyph',
  'along each line, or down the rows.',
];

const _spanLead = 'a span: ';

const _spanText = 'Span.gradient, glyph by glyph';
