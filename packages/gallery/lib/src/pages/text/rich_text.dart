// The Rich text page.
part of 'text.dart';

/// The Rich text page's `labels` option.
const _richTextLabels = SwitchOption(
  'labels',
  'row labels',
  initial: true,
);

final _richTextPage = GalleryPage(
  group: _group,
  title: 'Rich text',
  options: const [_richTextLabels],
  build: (context, o) => _RichText(labels: o(_richTextLabels)),
  code: (o) {
    final labels = o(_richTextLabels);
    return [
      if (labels) 'final theme = Theme.of(context);',
      'return Text.rich([',
      for (final (i, row) in _rich.indexed) ...[
        if (labels) "  Span('${_richLabels[i]}\\n', theme.muted),",
        for (final (k, (_, dart)) in row.indexed) ...[
          for (final (j, l) in dart.indexed)
            '  $l${j == dart.length - 1 ? ',' : ''}',
          if (k < row.length - 1) "  const Span(' '),",
        ],
        if (i < _rich.length - 1) r"  const Span('\n\n'),",
      ],
      ']);',
    ].join('\n');
  },
);

/// The spans of each row of the Rich text page: the span, and the Dart
/// that makes it, a line or more. The colours read on a dark background
/// and a light one alike: palette colours, colour 166, an rgb of the
/// middle, white on navy (colour 17, which no theme changes).
final List<List<(Span, List<String>)>> _rich = [
  [
    ('bold'.bold, ["'bold'.bold"]),
    ('dim'.dim, ["'dim'.dim"]),
    ('italic'.italic, ["'italic'.italic"]),
    ('reverse'.reverse, ["'reverse'.reverse"]),
    ('strike'.strike, ["'strike'.strike"]),
    ('overline'.overline, ["'overline'.overline"]),
  ],
  [
    ('underline'.underline, ["'underline'.underline"]),
    ('double'.doubleUnderline, ["'double'.doubleUnderline"]),
    ('curly'.curlyUnderline, ["'curly'.curlyUnderline"]),
    ('dotted'.dottedUnderline, ["'dotted'.dottedUnderline"]),
    ('dashed'.dashedUnderline, ["'dashed'.dashedUnderline"]),
  ],
  [
    ('red'.fg(Color.red), ["'red'.fg(.red)"]),
    (
      'color 166'.fg(const Color.indexed(166)),
      ["'color 166'.fg(const .indexed(166))"],
    ),
    (
      'rgb'.fg(const Color.rgb(64, 128, 224)),
      ["'rgb'.fg(const .rgb(64, 128, 224))"],
    ),
    (
      ' on navy '.fg(Color.white).bg(const Color.indexed(17)),
      ["' on navy '.fg(.white).bg(const .indexed(17))"],
    ),
    // an underline of a colour of its own (SGR 58), the text's kept
    (
      const Span(
        'red curly',
        Style(attrs: Attr.curlyUnderline, underlineColor: Color.red),
      ),
      [
        'const Span(',
        "  'red curly',",
        '  Style(attrs: Attr.curlyUnderline, underlineColor: Color.red),',
        ')',
      ],
    ),
  ],
  [
    (
      'a link to dart.dev'.link(_dartDev).underline,
      ["'a link to dart.dev'.link('https://dart.dev').underline"],
    ),
  ],
];

const _richLabels = ['attributes', 'underlines', 'colors', 'links'];

const _dartDev = 'https://dart.dev';

/// The Rich text page's spans, its rows labelled with [labels]; a click on
/// the link says what it does, where the terminal knows hyperlinks (OSC 8).
final class _RichText extends StatelessWidget {
  const _RichText({required this.labels});

  final bool labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      [
        for (final (i, row) in _rich.indexed) ...[
          if (labels) Span('${_richLabels[i]}\n', theme.muted),
          for (final (k, (span, _)) in row.indexed) ...[
            span,
            if (k < row.length - 1) const Span(' '),
          ],
          if (i < _rich.length - 1) const Span('\n\n'),
        ],
      ],
      onLinkTap: (url) => PageControl.of(
        context,
      ).toast('Opens $url where the terminal knows hyperlinks'),
    );
  }
}
