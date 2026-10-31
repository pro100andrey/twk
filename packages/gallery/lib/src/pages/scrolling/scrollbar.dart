// The Scrollbar page.
part of 'scrolling.dart';

final _scrollbarPage = GalleryPage(
  group: 'Scrolling',
  title: 'Scrollbar',
  options: const [
    ChoiceOption(
      'visibility',
      'visibility',
      values: ['always', 'onScroll', 'never'],
    ),
    ChoiceOption(
      'axes',
      'bars',
      values: ['vertical', 'horizontal', 'both'],
    ),
    ColorOption(
      'color',
      'style',
      values: ['muted', 'border', 'primary', 'accent'],
      initial: 'muted',
    ),
    SwitchOption('slim', 'slim'),
    ChoiceOption('track', 'track', values: ['faint', 'border', 'muted']),
  ],
  build: (context, o) => _Bars(
    visibility: ScrollbarVisibility.values.byName(o.choice('visibility')),
    across: o.choice<String>('axes') != 'vertical',
    down: o.choice<String>('axes') != 'horizontal',
    slim: o.flag('slim'),
    track: o.choice('track'),
    style: o.color('color') == 'muted' ? null : o.colorStyle(context, 'color'),
  ),
  code: _barsCode,
);

/// The Scrollbar's box.
const _barH = 10;

/// The Scrollbar's rows.
const _rows = 200;

/// The rows' width, scrolled across.
const _wide = 52;

const _outermostTail =
    '// each bar shows the outermost Scrollable below it along its axis,';

const _scopeTail =
    '// which a ScrollbarScope hands it: this one the list, the one';

const _noStopTail =
    '// no Tab stop of its own: the keys the list leaves come to it';

/// Row [i] of the wide table: a request and its answer, wider than the
/// window.
String _row(int i) {
  String two(int v) => '$v'.padLeft(2, '0');
  final n = '${i + 1}';
  final ms = '${i * 37 % 90 + 4}'.padLeft(2);
  return '${n.padLeft(3)}  2026-10-19 12:${two(i ~/ 60)}:${two(i % 60)}  '
      'GET /items/${n.padRight(3)}  200  $ms ms';
}

/// A list with a scrollbar where [down], and one across where [across].
final class _Bars extends StatelessWidget {
  const _Bars({
    required this.visibility,
    required this.across,
    required this.down,
    this.style,
    this.slim = false,
    this.track = 'faint',
  });

  final ScrollbarVisibility visibility;
  final bool across;
  final bool down;

  /// A line at rest, the whole cell under the mouse.
  final bool slim;

  /// The theme's style the slim track's line is in: `faint`, `border` or
  /// `muted`.
  final String track;

  /// The thumb's; the Scrollbar's own when null.
  final Style? style;

  Widget _list() => ListView.builder(
    itemCount: _rows,
    itemBuilder: (context, i) => Text(across ? _row(i) : 'row ${i + 1}'),
  );

  Widget _bar(
    BuildContext context, {
    required Widget child,
    Axis axis = Axis.vertical,
  }) {
    final theme = Theme.of(context);
    return Scrollbar(
      axis: axis,
      visibility: visibility,
      style: style,
      slim: slim,
      trackStyle: switch (track) {
        'border' => theme.border,
        'muted' => theme.muted,
        _ => null,
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = across
        ? _bar(
            context,
            axis: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              canRequestFocus: false,
              child: SizedBox(width: _wide, child: _list()),
            ),
          )
        : _list();
    return _boxed(_boxW, _barH, down ? _bar(context, child: list) : list);
  }
}

String _barsCode(Options o) {
  final across = o.choice<String>('axes') != 'vertical';
  final down = o.choice<String>('axes') != 'horizontal';
  final args = [
    if (o.choice<String>('visibility') != 'always')
      'visibility: .${o.label('visibility')},',
    if (o.color('color') != 'muted') 'style: theme.${o.color('color')},',
    if (o.flag('slim')) 'slim: true,',
    if (o.flag('slim') && o.choice<String>('track') != 'faint')
      'trackStyle: theme.${o.choice<String>('track')},',
  ];
  List<String> list(String indent) => [
    for (final l in [
      'ListView.builder(',
      '  itemCount: $_rows,',
      if (across)
        '  itemBuilder: (context, i) => Text(_row(i)),'
      else
        r"  itemBuilder: (context, i) => Text('row ${i + 1}'),",
      '),',
    ])
      '$indent$l',
  ];
  // the bar across, [pad] columns in, or the list alone
  List<String> inner(String pad) => [
    if (across) ...[
      if (down) ...[
        '$pad$_outermostTail',
        '$pad$_scopeTail',
        '$pad// below the view across',
      ],
      '${pad}child: Scrollbar(',
      '$pad  axis: .horizontal,',
      for (final a in args) '$pad  $a',
      '$pad  child: SingleChildScrollView(',
      '$pad    scrollDirection: .horizontal,',
      '$pad    $_noStopTail',
      '$pad    canRequestFocus: false,',
      '$pad    child: SizedBox(',
      '$pad      width: $_wide,',
      '$pad      child: ${list('$pad      ').join('\n').trimLeft()}',
      '$pad    ),',
      '$pad  ),',
      '$pad),',
    ] else
      '${pad}child: ${list(pad).join('\n').trimLeft()}',
  ];
  return [
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return SizedBox(',
    '    width: $_boxW,',
    '    height: $_barH,',
    ..._focusBox('    '),
    if (down) ...[
      '      child: Scrollbar(',
      for (final a in args) '        $a',
      ...inner('        '),
      '      ),',
    ] else
      ...inner('      '),
    '    ),',
    '  );',
    '}',
    if (across) ...[
      '',
      '/// Row [i]: a request and its answer, wider than the window.',
      'String _row(int i) {',
      r"  String two(int v) => '$v'.padLeft(2, '0');",
      r"  final n = '${i + 1}';",
      r"  final ms = '${i * 37 % 90 + 4}'.padLeft(2);",
      r"  return '${n.padLeft(3)}  2026-10-19 12:${two(i ~/ 60)}:${two(i % 60)}  '",
      r"      'GET /items/${n.padRight(3)}  200  $ms ms';",
      '}',
    ],
  ].join('\n');
}
