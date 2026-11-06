// The SelectionArea page.
part of 'mouse.dart';

/// The SelectionArea page's `view` option.
const _selectionareaView = ChoiceOption<String>(
  'view',
  'selected in',
  values: ['texts', 'log'],
  labels: ['two Texts', 'a painted log'],
);

/// The SelectionArea page's `copy` option.
const _selectionareaCopy = SwitchOption(
  'copy',
  'copy on release',
  initial: true,
);

/// The SelectionArea page's `style` option.
const _selectionareaStyle = ChoiceOption<String>(
  'style',
  'style',
  values: ['selection', 'reverse'],
  labels: ["the theme's", 'reverse'],
);

final _selectionareaPage = GalleryPage(
  group: _group,
  title: 'SelectionArea',
  options: const [
    _selectionareaView,
    _selectionareaCopy,
    _selectionareaStyle,
  ],
  build: (context, o) => o(_selectionareaView) == 'log'
      ? _SelectionLog(
          copyOnRelease: o(_selectionareaCopy),
          reverse: o(_selectionareaStyle) == 'reverse',
        )
      : _Selection(
          copyOnRelease: o(_selectionareaCopy),
          reverse: o(_selectionareaStyle) == 'reverse',
        ),
  code: (o) =>
      o(_selectionareaView) == 'log' ? _selectionLogCode(o) : _selectionCode(o),
);

/// The SelectionArea's width.
const _selW = 44;

const _readsMouse =
    'An app that reads the mouse keeps the terminal from selecting its '
    'text, so it selects the text itself.';

const _copiedLine =
    "                _copied.isEmpty ? 'nothing' : "
    r"_copied.replaceAll('\n', ' '),";

/// Two paragraphs the mouse selects, and what was copied last.
final class _Selection extends StatefulWidget {
  const _Selection({required this.copyOnRelease, required this.reverse});

  final bool copyOnRelease;
  final bool reverse;

  @override
  State<_Selection> createState() => _SelectionState();
}

final class _SelectionState extends State<_Selection> {
  var _copied = '';
  var _copies = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _selW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          SelectionArea(
            copyOnRelease: widget.copyOnRelease,
            style: widget.reverse ? const Style(attrs: Attr.reverse) : null,
            onCopy: (text) => setState(() {
              _copied = text;
              _copies++;
            }),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                Text(_readsMouse),
                Text('A drag goes on from one paragraph to the next.'),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              Text('copied:', style: theme.muted),
              Expanded(
                child: LitText(
                  _copied.isEmpty ? 'nothing' : _copied.replaceAll('\n', ' '),
                  serial: _copies,
                  style: _copied.isEmpty ? theme.muted : const Style(),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _selectionCode(Options o) => [
  "var _copied = '';",
  '',
  '@override',
  'Widget build(BuildContext context) {',
  '  final theme = Theme.of(context);',
  '  return SizedBox(',
  '    width: $_selW,',
  '    child: Column(',
  '      mainAxisSize: .min,',
  '      crossAxisAlignment: .start,',
  '      spacing: 1,',
  '      children: [',
  '        SelectionArea(',
  if (!o(_selectionareaCopy)) '          copyOnRelease: false,',
  if (o(_selectionareaStyle) == 'reverse')
    '          style: const Style(attrs: Attr.reverse),',
  '          onCopy: (text) => setState(() => _copied = text),',
  '          child: const Column(',
  '            mainAxisSize: .min,',
  '            crossAxisAlignment: .start,',
  '            spacing: 1,',
  '            children: [',
  '              Text(',
  "                'An app that reads the mouse keeps the terminal from '",
  "                'selecting its text, so it selects the text itself.',",
  '              ),',
  "              Text('A drag goes on from one paragraph to the next.'),",
  '            ],',
  '          ),',
  '        ),',
  '        // what was copied, in the width the label leaves',
  '        Row(',
  '          crossAxisAlignment: .start,',
  '          spacing: 1,',
  '          children: [',
  "            Text('copied:', style: theme.muted),",
  '            Expanded(',
  '              child: Text(',
  _copiedLine,
  '                style: _copied.isEmpty ? theme.muted : const Style(),',
  '                maxLines: 2,',
  '                overflow: .ellipsis,',
  '              ),',
  '            ),',
  '          ],',
  '        ),',
  '      ],',
  '    ),',
  '  );',
  '}',
].join('\n');

/// The painted log's lines.
final List<String> _logLines = [
  for (var i = 1; i <= 20; i++)
    '12:00:${'$i'.padLeft(2, '0')} GET /files/$i ${i % 7 == 0 ? 404 : 200}',
];

/// A SelectionArea over a [_Log] in a box that Tab focuses, and what was
/// copied from it.
final class _SelectionLog extends StatefulWidget {
  const _SelectionLog({required this.copyOnRelease, required this.reverse});

  final bool copyOnRelease;
  final bool reverse;

  @override
  State<_SelectionLog> createState() => _SelectionLogState();
}

final class _SelectionLogState extends State<_SelectionLog> {
  var _copied = '';
  var _copies = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _selW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          SelectionArea(
            copyOnRelease: widget.copyOnRelease,
            style: widget.reverse ? const Style(attrs: Attr.reverse) : null,
            onCopy: (text) => setState(() {
              _copied = text;
              _copies++;
            }),
            child: FocusBuilder(
              builder: (context, hasFocus, log) => Box(
                border: Border.all(
                  type: BorderType.rounded,
                  style: hasFocus ? theme.primary : theme.border,
                ),
                child: log,
              ),
              child: Focus(child: _Log(_logLines)),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              Text('copied:', style: theme.muted),
              Expanded(
                child: LitText(
                  _copied.isEmpty ? 'nothing' : _copied.replaceAll('\n', ' '),
                  serial: _copies,
                  style: _copied.isEmpty ? theme.muted : const Style(),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A log painted row by row, the number of each line in a gutter that is
/// no text: a Selectable, which a SelectionArea selects in as in a Text,
/// and which a drag past its top or bottom scrolls.
final class _Log extends LeafRenderObjectWidget {
  const _Log(this.lines);

  final List<String> lines;

  @override
  _RenderLog createRenderObject(BuildContext context) =>
      _RenderLog(lines, Theme.of(context).muted);

  @override
  void updateRenderObject(BuildContext context, _RenderLog renderObject) =>
      renderObject.numbers = Theme.of(context).muted;
}

final class _RenderLog extends RenderObject with Selectable {
  _RenderLog(this.lines, this._numbers)
    : selectableText = lines.map((line) => '$line\n').join();

  final List<String> lines;

  @override
  final String selectableText;

  Style _numbers;
  Style get numbers => _numbers;
  set numbers(Style value) {
    if (value != _numbers) {
      _numbers = value;
      markNeedsPaint();
    }
  }

  /// The first line shown, and the columns of the numbers.
  var _top = 0;
  static const _gutter = 4;

  /// Where line [i] starts in [selectableText].
  int _start(int i) => [
    for (final line in lines.take(i)) line.length + 1,
  ].fold(0, (a, b) => a + b);

  @override
  (int, int) selectableRangeAt(int x, int y) {
    final i = _top + y;
    final end = selectableText.length;
    if (i < 0 || i >= lines.length) {
      return i < 0 ? (0, 0) : (end, end);
    }
    final start = _start(i);
    final column = x - _gutter;
    if (column < 0) {
      return (start, start);
    }
    if (column >= lines[i].length) {
      final next = start + lines[i].length + 1;
      return (next, next);
    }
    return (start + column, start + column + 1);
  }

  @override
  bool scrollSelectionBy(int rows) {
    final most = lines.length > height ? lines.length - height : 0;
    final top = (_top + rows).clamp(0, most);
    if (top == _top) {
      return false;
    }
    _top = top;
    markNeedsPaint();
    return true;
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.constrainH(5);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final numbers = _numbers.penIn(styles);
    for (var y = 0; y < height && _top + y < lines.length; y++) {
      final i = _top + y;
      canvas.text(0, y, '${i + 1}'.padLeft(_gutter - 1), numbers);
      final start = _start(i);
      for (var k = 0; k < lines[i].length && _gutter + k < width; k++) {
        final style = selectionStyleAt(start + k, const Style());
        canvas.text(_gutter + k, y, lines[i][k], style.penIn(styles));
      }
    }
  }
}

// The log Code's lines too long for a line of Dart.
const _logLine0 =
    r"    '12:00:${'$i'.padLeft(2, '0')} GET /files/$i ${i % 7 == 0 ? 404 : 200}',";

const _logLine1 =
    r"                _copied.isEmpty ? 'nothing' : _copied.replaceAll('\n', ' '),";

String _selectionLogCode(Options o) => [
  "var _copied = '';",
  '',
  'static final _lines = [',
  '  for (var i = 1; i <= 20; i++)',
  _logLine0,
  '];',
  '',
  '@override',
  'Widget build(BuildContext context) {',
  '  final theme = Theme.of(context);',
  '  return SizedBox(',
  '    width: 44,',
  '    child: Column(',
  '      mainAxisSize: .min,',
  '      crossAxisAlignment: .start,',
  '      spacing: 1,',
  '      children: [',
  '        SelectionArea(',
  if (!o(_selectionareaCopy)) '          copyOnRelease: false,',
  if (o(_selectionareaStyle) == 'reverse')
    '          style: const Style(attrs: Attr.reverse),',
  '          onCopy: (text) => setState(() => _copied = text),',
  '          // the border primary while the focus is in it: Escape clears',
  '          child: FocusBuilder(',
  '            builder: (context, hasFocus, log) => Box(',
  '              border: .all(',
  '                type: .rounded,',
  '                style: hasFocus ? theme.primary : theme.border,',
  '              ),',
  '              child: log,',
  '            ),',
  '            child: Focus(child: _Log(_lines)),',
  '          ),',
  '        ),',
  '        // what was copied, in the width the label leaves',
  '        Row(',
  '          crossAxisAlignment: .start,',
  '          spacing: 1,',
  '          children: [',
  "            Text('copied:', style: theme.muted),",
  '            Expanded(',
  '              child: Text(',
  _logLine1,
  '                style: _copied.isEmpty ? theme.muted : const Style(),',
  '                maxLines: 2,',
  '                overflow: .ellipsis,',
  '              ),',
  '            ),',
  '          ],',
  '        ),',
  '      ],',
  '    ),',
  '  );',
  '}',
  '',
  '/// A log painted row by row, the number of each line in a gutter that',
  '/// is no text: a Selectable, which a SelectionArea selects in as in a',
  '/// Text, and which a drag past its top or bottom scrolls.',
  'final class _Log extends LeafRenderObjectWidget {',
  '  const _Log(this.lines);',
  '',
  '  final List<String> lines;',
  '',
  '  @override',
  '  _RenderLog createRenderObject(BuildContext context) =>',
  '      _RenderLog(lines, Theme.of(context).muted);',
  '',
  '  @override',
  '  void updateRenderObject(BuildContext context, _RenderLog renderObject) =>',
  '      renderObject.numbers = Theme.of(context).muted;',
  '}',
  '',
  'final class _RenderLog extends RenderObject with Selectable {',
  '  _RenderLog(this.lines, this._numbers)',
  r"    : selectableText = lines.map((line) => '$line\n').join();",
  '',
  '  final List<String> lines;',
  '',
  '  @override',
  '  final String selectableText;',
  '',
  '  Style _numbers;',
  '  Style get numbers => _numbers;',
  '  set numbers(Style value) {',
  '    if (value != _numbers) {',
  '      _numbers = value;',
  '      markNeedsPaint();',
  '    }',
  '  }',
  '',
  '  /// The first line shown, and the columns of the numbers.',
  '  var _top = 0;',
  '  static const _gutter = 4;',
  '',
  '  /// Where line [i] starts in [selectableText].',
  '  int _start(int i) => [',
  '    for (final line in lines.take(i)) line.length + 1,',
  '  ].fold(0, (a, b) => a + b);',
  '',
  '  @override',
  '  (int, int) selectableRangeAt(int x, int y) {',
  '    final i = _top + y;',
  '    final end = selectableText.length;',
  '    if (i < 0 || i >= lines.length) {',
  '      return i < 0 ? (0, 0) : (end, end);',
  '    }',
  '    final start = _start(i);',
  '    final column = x - _gutter;',
  '    if (column < 0) {',
  '      return (start, start);',
  '    }',
  '    if (column >= lines[i].length) {',
  '      final next = start + lines[i].length + 1;',
  '      return (next, next);',
  '    }',
  '    return (start + column, start + column + 1);',
  '  }',
  '',
  '  @override',
  '  bool scrollSelectionBy(int rows) {',
  '    final most = lines.length > height ? lines.length - height : 0;',
  '    final top = (_top + rows).clamp(0, most);',
  '    if (top == _top) {',
  '      return false;',
  '    }',
  '    _top = top;',
  '    markNeedsPaint();',
  '    return true;',
  '  }',
  '',
  '  @override',
  '  void performLayout(BoxConstraints c) {',
  '    width = c.maxW;',
  '    height = c.constrainH(5);',
  '  }',
  '',
  '  @override',
  '  void paint(PaintContext ctx) {',
  '    final canvas = ctx.canvas;',
  '    final styles = canvas.styles;',
  '    final numbers = _numbers.penIn(styles);',
  '    for (var y = 0; y < height && _top + y < lines.length; y++) {',
  '      final i = _top + y;',
  r"      canvas.text(0, y, '${i + 1}'.padLeft(_gutter - 1), numbers);",
  '      final start = _start(i);',
  '      for (var k = 0; k < lines[i].length && _gutter + k < width; k++) {',
  '        final style = selectionStyleAt(start + k, const Style());',
  '        canvas.text(_gutter + k, y, lines[i][k], style.penIn(styles));',
  '      }',
  '    }',
  '  }',
  '}',
].join('\n');
