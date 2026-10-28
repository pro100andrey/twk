// The Text group of the gallery.
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show BidiText, TextDirection;

import '../page.dart';

const _sample =
    'Terminals draw text in a grid of cells. A paragraph breaks its lines '
    'between words to fit its width; wide characters, 漢字 and 🙂, take two '
    'cells each.';

/// The pages of the Text group that draw.
final textPages = [
  GalleryPage(
    group: 'Text',
    title: 'Text',
    options: [
      const ChoiceOption(
        'wrap',
        'wrap',
        values: ['word', 'grapheme', 'none'],
      ),
      const ChoiceOption(
        'overflow',
        'overflow',
        values: ['clip', 'ellipsis', 'ellipsisStart', 'ellipsisMiddle'],
        initial: 'ellipsis',
      ),
      const ChoiceOption(
        'align',
        'align',
        values: ['left', 'center', 'right', 'justify'],
      ),
      const ChoiceOption(
        'lines',
        'max lines',
        values: [null, 3, 1],
        labels: ['all', '3', '1'],
      ),
      SliderOption(
        'width',
        'width',
        min: 14,
        max: 50,
        initial: 32,
        format: (v) => '$v cells',
      ),
    ],
    build: (context, o) {
      final theme = Theme.of(context);
      return SizedBox(
        width: o.number('width').toInt(),
        child: Box(
          border: Border.all(type: BorderType.rounded, style: theme.border),
          child: Text(
            _sample,
            wrap: TextWrap.values.byName(o.choice('wrap')),
            overflow: TextOverflow.values.byName(o.choice('overflow')),
            align: TextAlign.values.byName(o.choice('align')),
            maxLines: o.choice<int?>('lines'),
          ),
        ),
      );
    },
    code: (o) => [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: ${o.label('width')},',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: Text(',
      "      'Terminals draw text in a grid of cells. A paragraph breaks its '",
      "      'lines between words to fit its width; wide characters, 漢字 and '",
      "      '🙂, take two cells each.',",
      '      wrap: .${o.label('wrap')},',
      '      overflow: .${o.label('overflow')},',
      '      align: .${o.label('align')},',
      if (o['lines'] != null) '      maxLines: ${o.label('lines')},',
      '    ),',
      '  ),',
      ');',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Text',
    title: 'Rich text',
    options: const [SwitchOption('labels', 'row labels', initial: true)],
    build: (context, o) => _RichText(labels: o.flag('labels')),
    code: (o) {
      final labels = o.flag('labels');
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
  ),
  GalleryPage(
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
  ),
  GalleryPage(
    group: 'Text',
    title: 'Right to left',
    options: const [
      ChoiceOption('order', 'text order', values: ['visual', 'logical']),
      ChoiceOption('align', 'align', values: ['start', 'end', 'left', 'right']),
    ],
    build: (context, o) => _RightToLeft(
      order: TextOrder.values.byName(o.choice('order')),
      align: TextAlign.values.byName(o.choice('align')),
    ),
    code: (o) => [
      "import 'package:twk/twk.dart';",
      '',
      // lines that fit the Code panel: under 58 columns
      if (o['order'] == 'visual') ...[
        '// The app puts right-to-left text in the order it',
        '// reads (TextOrder.visual), for a terminal that',
        '// shows each character in the cell it is written to.',
        '// Without bidi, as the terminal is found to need.',
        'Future<void> main() =>',
        '    runApp(const RightToLeft(), bidi: BidiReordering.app);',
      ] else ...[
        '// The terminal puts right-to-left text in the order',
        '// it reads, row by row; the app writes it as stored',
        '// (TextOrder.logical). Without bidi, as the terminal',
        '// is found to need.',
        'Future<void> main() =>',
        '    runApp(const RightToLeft(), bidi: BidiReordering.terminal);',
      ],
      '',
      'final class RightToLeft extends StatelessWidget {',
      '  const RightToLeft({super.key});',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    final theme = Theme.of(context);',
      '    return Column(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .start,',
      '      gap: 1,',
      '      children: [',
      '        SizedBox(',
      '          width: $_rtlWidth,',
      '          child: Box(',
      '            border: .all(type: .rounded, style: theme.border),',
      '            padding: const .x(1),',
      '            child: const Text(',
      for (final (i, l) in _rtl.indexed)
        _rtlLine(l, last: i == _rtl.length - 1),
      '              align: .${o.label('align')},',
      '            ),',
      '          ),',
      '        ),',
      '        Text.rich([',
      "          Span('text order: ', theme.muted),",
      '          Span(AppBinding.of(context).textOrder.name),',
      '        ]),',
      '      ],',
      '    );',
      '  }',
      '}',
    ].join('\n'),
  ),
];

// ------------------------------------------------------------ Rich text

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

// ------------------------------------------------------------ DefaultTextStyle

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

// ------------------------------------------------------------ Right to left

/// The Code's line of [line] of the text, the last one ending the string.
String _rtlLine(String line, {required bool last}) =>
    "              '$line${last ? "'," : r"\n'"}";

/// A line of each: a Hebrew word and an Arabic one in left-to-right
/// paragraphs, and a right-to-left paragraph with English in brackets.
const _rtl = [
  'Hello is שלום in Hebrew,',
  'and مرحبا in Arabic.',
  'שלום עולם! (hello world)',
];
const _rtlWidth = 32;

/// The Right to left page: the Code's box of [_rtl] in [order], as the app
/// the Code runs draws it, and the order under it.
///
/// The text order is the app's (its pipeline owner's), and the gallery
/// runs in its own; where that differs from [order], the page puts each
/// line in [order] itself: visual, by `BidiText`, and aligned as a
/// paragraph of its direction is; logical, every paragraph left to right.
final class _RightToLeft extends StatelessWidget {
  const _RightToLeft({required this.order, required this.align});

  final TextOrder order;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appOrder =
        AppBinding.maybeOf(context)?.textOrder ?? TextOrder.logical;
    final Widget text;
    if (order == appOrder) {
      text = Text(_rtl.join('\n'), align: align);
    } else {
      text = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final line in _rtl) _line(line)],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: _rtlWidth,
          child: Box(
            border: Border.all(type: BorderType.rounded, style: theme.border),
            padding: const EdgeInsets.x(1),
            child: text,
          ),
        ),
        Text.rich([Span('text order: ', theme.muted), Span(order.name)]),
      ],
    );
  }

  /// [line] as the app in [order] draws it, where the gallery's order is
  /// the other: visual, put in that order here; logical, held in it by a
  /// left-to-right override (LRO … PDF, after an LRM that makes the
  /// paragraph left to right) the gallery's reordering keeps.
  Widget _line(String line) {
    final bidi = BidiText(line);
    final rtl =
        order == TextOrder.visual &&
        bidi.paragraphs.first.direction == TextDirection.rtl;
    final shown = order == TextOrder.visual
        ? bidi.visual(0, line.length)
        : '\u200E\u202D$line\u202C';
    final right =
        align == TextAlign.right ||
        (align == TextAlign.start && rtl) ||
        (align == TextAlign.end && !rtl);
    return Text(shown, align: right ? TextAlign.right : TextAlign.left);
  }
}
