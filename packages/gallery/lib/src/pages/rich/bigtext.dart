// The BigText page.
part of 'rich.dart';

// ------------------------------------------------------------ BigText

const _fieldWidth = 30;

/// The BigText page's text of two lines, one wider than the other.
const _bigLines = 'twk\ngallery';

/// Whether the BigText page's text is of one line, which BigText is as wide
/// as: align then moves nothing.
bool _oneLine(Options o) => o(_bigTextText) != 'lines';

const _maxLength = 24;

/// The page's state the field last kept its text in
/// (`PageControl.state`), for the Code: the text typed, kept while the
/// gallery runs.
Map<String, Object?>? _bigState;

String get _typed => _bigState?['text'] as String? ?? 'Hello';

/// The clock from 9:41 at [ms], a second a tick.
String _clockText(int ms) {
  final s = 9 * 3600 + 41 * 60 + ms ~/ 1000;
  String two(int n) => '$n'.padLeft(2, '0');
  return '${two(s ~/ 3600 % 24)}:${two(s ~/ 60 % 60)}:${two(s % 60)}';
}

/// The rows BigText and its field take in [room], as the design's size:
/// the text in the first font it fits in, in what the field leaves.
int _bigHeightIn(Options o, StageRoom room) {
  final name = o(_bigTextFont);
  // no field under it
  final clock = o(_bigTextText) != 'typed';
  final big =
      RenderBigText(
        switch (o(_bigTextText)) {
          'clock' => _clockText(0),
          'lines' => _bigLines,
          _ => _typed,
        },
        fonts: name == 'fit'
            ? BigFont.sizes
            : [BigFont.values.firstWhere((f) => f.name == name)],
      )..layout(
        BoxConstraints(
          0,
          room.width,
          0,
          clock ? room.height : math.max(0, room.height - 4),
        ),
      );
  return clock ? big.height : big.height + 4;
}

/// The BigText page's `font` option.
const _bigTextFont = ChoiceOption<String>(
  'font',
  'font',
  values: ['fit', 'large', 'block', 'thin', 'small'],
);

/// The BigText page's `text` option.
const _bigTextText = ChoiceOption<String>(
  'text',
  'text',
  values: ['typed', 'clock', 'lines'],
  labels: ['typed', 'clock', 'two lines'],
);

/// The BigText page's `align` option.
const _bigTextAlign = ChoiceOption<String>(
  'align',
  'align',
  values: ['left', 'center', 'right'],
  disabled: _oneLine,
);

/// The BigText page's `color` option.
const _bigTextColor = ColorOption(
  'color',
  'style',
  values: ['primary', 'accent', 'success', 'warning', 'info'],
  initial: 'primary',
);

final _bigText = GalleryPage(
  group: _group,
  title: 'BigText',
  options: const [
    _bigTextFont,
    _bigTextText,
    // each line across the widest: of a text of more than one
    _bigTextAlign,
    _bigTextColor,
  ],
  build: (context, o) {
    final name = o(_bigTextFont);
    final font = name == 'fit'
        ? null
        : BigFont.values.firstWhere((f) => f.name == name);
    final style = o.styleOf(context, _bigTextColor);
    if (o(_bigTextText) == 'lines') {
      return BigText(
        _bigLines,
        font: font,
        align: TextAlign.values.byName(o(_bigTextAlign)),
        style: style,
      );
    }
    if (o(_bigTextText) == 'clock') {
      return Timed((context, ms, wake) {
        wake((ms ~/ 1000 + 1) * 1000);
        return BigText(_clockText(ms), font: font, style: style);
      });
    }
    return _TypedBig(font: font, style: style);
  },
  heightIn: _bigHeightIn,
  code: (o) {
    final name = o(_bigTextFont);
    final font = name == 'fit' ? '' : ', font: BigFont.$name';
    final color = o(_bigTextColor);
    if (o(_bigTextText) == 'lines') {
      final align = o(_bigTextAlign);
      return [
        '@override',
        'Widget build(BuildContext context) => BigText(',
        "  '${_bigLines.replaceAll('\n', r'\n')}',",
        if (font.isNotEmpty) '  font: BigFont.$name,',
        if (align != 'left') '  align: .$align,',
        '  style: Theme.of(context).$color,',
        ');',
      ].join('\n');
    }
    if (o(_bigTextText) == 'clock') {
      return [
        '// a clock from 9:41, a second a tick',
        'var _now = DateTime(2026, 10, 19, 9, 41);',
        'late final Timer _timer;',
        '',
        '@override',
        'void initState() {',
        '  super.initState();',
        '  _timer = Timer.periodic(',
        '    const Duration(seconds: 1),',
        codeLine([
          '    (_) => setState(() => _now = _now.add(const Duration(seconds: ',
          '1))),',
        ]),
        '  );',
        '}',
        '',
        '@override',
        'void dispose() {',
        '  _timer.cancel();',
        '  super.dispose();',
        '}',
        '',
        r"String _two(int n) => '$n'.padLeft(2, '0');",
        '',
        '@override',
        'Widget build(BuildContext context) => BigText(',
        r"  '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',",
        if (font.isNotEmpty) '  font: BigFont.$name,',
        '  style: Theme.of(context).$color,',
        ');',
      ].join('\n');
    }
    final text = _typed
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$');
    return [
      "final _controller = TextEditingController(text: '$text');",
      "final _focus = FocusNode(debugLabel: 'text');",
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _focus.addListener(() => setState(() {}));',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _controller.dispose();',
      '  _focus.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    gap: 1,',
      '    children: [',
      '      // what the field and the gap leave: the font that fits in it',
      codeLine([
        '      Flexible(child: BigText(_controller.text$font, ',
        'style: theme.$color)),',
      ]),
      '      SizedBox(',
      '        width: $_fieldWidth,',
      '        child: Box(',
      '          border: .all(',
      '            type: .rounded,',
      '            style: _focus.hasFocus ? theme.primary : theme.border,',
      '          ),',
      '          child: TextField(',
      '            controller: _controller,',
      '            focusNode: _focus,',
      "            placeholder: 'type here',",
      '            maxLength: $_maxLength,',
      '            onChanged: (_) => setState(() {}),',
      '          ),',
      '        ),',
      '      ),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// BigText of what is typed in the field under it, as the Code builds it.
final class _TypedBig extends StatefulWidget {
  const _TypedBig({required this.font, required this.style});

  final BigFont? font;
  final Style style;

  @override
  State<_TypedBig> createState() => _TypedBigState();
}

final class _TypedBigState extends State<_TypedBig> with KeptState {
  late final _controller = TextEditingController(
    text: kept['text'] as String? ?? 'Hello',
  );
  final _focus = FocusNode(debugLabel: 'text');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bigState = kept;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      gap: 1,
      children: [
        // what the field and the gap leave: the font that fits in it
        Flexible(
          child: BigText(
            _controller.text,
            font: widget.font,
            style: widget.style,
          ),
        ),
        PageHints(
          hints: const [('type', 'big text'), ('←→', 'move')],
          child: SizedBox(
            width: _fieldWidth,
            child: Box(
              border: Border.all(
                type: BorderType.rounded,
                style: _focus.hasFocus ? theme.primary : theme.border,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                placeholder: 'type here',
                maxLength: _maxLength,
                onChanged: (text) => setState(() => kept['text'] = text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
