// The SingleChildScrollView page.
part of 'scrolling.dart';

/// The SingleChildScrollView page's `axis` option.
const _singlechildscrollviewAxis = ChoiceOption<String>(
  'axis',
  'direction',
  values: ['vertical', 'horizontal'],
);

final _singlechildscrollviewPage = GalleryPage(
  group: _group,
  title: 'SingleChildScrollView',
  options: const [
    _singlechildscrollviewAxis,
  ],
  build: (context, o) =>
      _Paragraphs(vertical: o(_singlechildscrollviewAxis) == 'vertical'),
  code: _paragraphsCode,
);

/// A paragraph's width, across.
const _colW = 24;

const _scrolls =
    'A scroll view lays its child out as long as it likes along the axis, '
    'and shows a window of it.';

const _keysMove =
    'The arrows move it a cell, PageUp and PageDown a window, Home and End '
    'to the ends.';

const _rowsStay =
    'Scrolled while all of it is on the screen, it has the terminal move the '
    'rows that stay.';

const _listens =
    'Its controller reads the offset and moves it; the line under the box '
    'listens to it.';

const List<String> _paragraphs = [
  _scrolls,
  _keysMove,
  'A notch of the wheel over it scrolls three cells.',
  _rowsStay,
  'A Column in it is as tall as its children, whatever its mainAxisSize.',
  _listens,
];

/// The paragraphs in a scroll view, down or across, and a button that
/// lights the next one and scrolls the least that shows it.
final class _Paragraphs extends StatefulWidget {
  const _Paragraphs({required this.vertical});

  final bool vertical;

  @override
  State<_Paragraphs> createState() => _ParagraphsState();
}

final class _ParagraphsState extends State<_Paragraphs> {
  final _controller = ScrollController();
  final List<GlobalKey> _keys = [for (final _ in _paragraphs) GlobalKey()];
  var _shown = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showNext() {
    setState(() => _shown = (_shown + 1) % _paragraphs.length);
    _controller.ensureVisible(_keys[_shown].currentContext!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paragraphs = [
      for (final (i, text) in _paragraphs.indexed)
        Text(
          text,
          key: _keys[i],
          style: i == _shown ? theme.primary : const Style(),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        _boxed(
          _boxW,
          _scrollH,
          SingleChildScrollView(
            scrollDirection: widget.vertical ? Axis.vertical : Axis.horizontal,
            controller: _controller,
            child: widget.vertical
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    gap: 1,
                    children: paragraphs,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    gap: 2,
                    children: [
                      for (final paragraph in paragraphs)
                        SizedBox(width: _colW, child: paragraph),
                    ],
                  ),
          ),
        ),
        Button('next paragraph', onPressed: _showNext),
        _offsetLine(_controller),
      ],
    );
  }
}

/// A paragraph in the Code's list: on a line, or in two strings as dart
/// format leaves them.
List<String> _paragraphLines(String t) {
  if (t.length + 5 <= 80) {
    return ["  '$t',"];
  }
  final cut = t.lastIndexOf(' ', 75);
  return ["  '${t.substring(0, cut + 1)}'", "      '${t.substring(cut + 1)}',"];
}

String _paragraphsCode(Options o) {
  final vertical = o(_singlechildscrollviewAxis) == 'vertical';
  return [
    'const _paragraphs = [',
    for (final t in _paragraphs) ..._paragraphLines(t),
    '];',
    '',
    'final _controller = ScrollController();',
    'final _keys = [for (final _ in _paragraphs) GlobalKey()];',
    'var _shown = -1;',
    '',
    '@override',
    'void dispose() {',
    '  _controller.dispose();',
    '  super.dispose();',
    '}',
    '',
    '/// Lights the next paragraph and scrolls the least that shows it.',
    'void _showNext() {',
    '  setState(() => _shown = (_shown + 1) % _paragraphs.length);',
    '  _controller.ensureVisible(_keys[_shown].currentContext!);',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  final paragraphs = [',
    '    for (final (i, text) in _paragraphs.indexed)',
    '      Text(',
    '        text,',
    '        key: _keys[i],',
    '        style: i == _shown ? theme.primary : const Style(),',
    '      ),',
    '  ];',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      SizedBox(',
    '        width: $_boxW,',
    '        height: $_scrollH,',
    ..._focusBox('        '),
    '          child: SingleChildScrollView(',
    if (!vertical) '            scrollDirection: .horizontal,',
    '            controller: _controller,',
    if (vertical) ...[
      '            child: Column(',
      '              crossAxisAlignment: .start,',
      '              gap: 1,',
      '              children: paragraphs,',
      '            ),',
    ] else ...[
      '            child: Row(',
      '              crossAxisAlignment: .start,',
      '              gap: 2,',
      '              children: [',
      '                for (final paragraph in paragraphs)',
      '                  SizedBox(width: $_colW, child: paragraph),',
      '              ],',
      '            ),',
    ],
    '          ),',
    '        ),',
    '      ),',
    "      Button('next paragraph', onPressed: _showNext),",
    ..._offsetCode('_controller'),
    '    ],',
    '  );',
    '}',
  ].join('\n');
}
