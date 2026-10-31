// The Right to left page.
part of 'text.dart';

final _rightToLeftPage = GalleryPage(
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
    for (final (i, l) in _rtl.indexed) _rtlLine(l, last: i == _rtl.length - 1),
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
);

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
