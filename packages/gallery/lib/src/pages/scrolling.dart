// The Scrolling group of the gallery.
import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';

/// The box each page scrolls in: its width; its window two cells narrower.
const _boxW = 34;

/// The SingleChildScrollView's and the Scrollable's box: its rows.
const _scrollH = 8;

/// A paragraph's width, across.
const _colW = 24;

/// The ruler's rows.
const _ruler = 100;

/// The ListView's box: a window of six rows.
const _listH = 8;

/// The Scrollbar's box.
const _barH = 10;

/// A line of the log this often.
const _growMs = 600;

/// The lines the log starts with.
const _growFrom = 12;

/// The item a button scrolls into view.
const _show = 40;

/// The Scrollbar's rows.
const _rows = 200;

/// The rows' width, scrolled across.
const _wide = 52;

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

/// The Code's lines too long for a line of Dart.
const _rulerLine =
    '                  _Ruler(position, offset: position.offset, length: '
    '$_ruler),';
const _rulerConstructor =
    '  const _Ruler(this.position, {required this.offset, '
    'required this.length});';
const _rulerUpdate =
    '  void updateRenderObject(BuildContext context, '
    '_RenderRuler renderObject) =>';
const _showLine =
    "          Button('item $_show', onPressed: () => "
    '_list.ensureIndexVisible(${_show - 1})),';
const _middleLine =
    "          Button('middle', onPressed: () => "
    '_list.jumpToIndex(_count ~/ 2)),';
const _outermostTail =
    '// each bar shows the outermost Scrollable below it along its axis,';
const _scopeTail =
    '// which a ScrollbarScope hands it: this one the list, the one';
const _noStopTail =
    '// no Tab stop of its own: the keys the list leaves come to it';

/// The pages of the Scrolling group that draw.
final scrollingPages = [
  GalleryPage(
    group: 'Scrolling',
    title: 'SingleChildScrollView',
    options: const [
      ChoiceOption(
        'axis',
        'direction',
        values: ['vertical', 'horizontal'],
      ),
    ],
    build: (context, o) =>
        _Paragraphs(vertical: o.choice<String>('axis') == 'vertical'),
    code: _paragraphsCode,
  ),
  GalleryPage(
    group: 'Scrolling',
    title: 'Scrollable',
    build: (context, o) => const _RulerPage(),
    code: (o) => _rulerCode,
  ),
  GalleryPage(
    group: 'Scrolling',
    title: 'ListView',
    options: [
      const ChoiceOption(
        'items',
        'items',
        values: [100, 10000, 1000000, 'growing', 'chat', 'feed'],
        labels: ['100', '10 000', '1 000 000', 'growing', 'chat', 'feed'],
      ),
      ChoiceOption(
        'heights',
        'heights',
        values: const ['one row', 'different'],
        disabled: (o) => o['items'] == 'chat' || o['items'] == 'feed',
      ),
      const SwitchOption('separated', 'separated'),
      // what keeps the log at its end: the list, or its controller
      ChoiceOption(
        'stick',
        'stuck by',
        values: const ['stickToBottom', 'stickToEnd'],
        disabled: (o) => o['items'] != 'growing',
      ),
    ],
    build: (context, o) {
      final items = o['items'];
      final chat = items == 'chat';
      final feed = items == 'feed';
      final different =
          !chat && !feed && o.choice<String>('heights') == 'different';
      final separated = o.flag('separated');
      final byEnd = items == 'growing' && o['stick'] == 'stickToEnd';
      return _List(
        key: ValueKey('$items/$different/$separated/$byEnd'),
        count: items is int ? items : null,
        chat: chat,
        feed: feed,
        different: different,
        separated: separated,
        stickToEnd: byEnd,
      );
    },
    code: _listCode,
  ),
  GalleryPage(
    group: 'Scrolling',
    title: 'LogView',
    options: const [
      ChoiceOption('level', 'level', values: _logLevels),
      ChoiceOption('filter', 'filter', values: ['none', 'GET', 'slow']),
      ChoiceOption('query', 'search', values: ['none', 'items', 'timeout']),
      SwitchOption('time', 'time', initial: true),
      SwitchOption('showLevel', 'show level', initial: true),
      SwitchOption('wrap', 'wrap'),
      SwitchOption('live', 'live', initial: true),
      ChoiceOption(
        'scrollbar',
        'scrollbar',
        values: ['always', 'onScroll', 'never'],
      ),
    ],
    build: (context, o) => _Log(
      level: LogLevel.values.byName(o.choice('level')),
      filter: o.choice<String>('filter') == 'none' ? '' : o.choice('filter'),
      query: o.choice<String>('query') == 'none' ? '' : o.choice('query'),
      time: o.flag('time'),
      showLevel: o.flag('showLevel'),
      wrap: o.flag('wrap'),
      live: o.flag('live'),
      scrollbar: ScrollbarVisibility.values.byName(o.choice('scrollbar')),
    ),
    codeIn: _logCode,
  ),
  GalleryPage(
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
      style: o.color('color') == 'muted'
          ? null
          : o.colorStyle(context, 'color'),
    ),
    code: _barsCode,
  ),
];

/// The Dart of a Box whose border is primary while the focus is in its
/// child, a FocusBuilder's, [pad] columns in; the child's line follows.
List<String> _focusBox(String pad) => [
  '$pad// the border primary while the focus is in it',
  '${pad}child: FocusBuilder(',
  '$pad  builder: (context, hasFocus, child) => Box(',
  '$pad    border: .all(',
  '$pad      type: .rounded,',
  '$pad      style: hasFocus ? theme.primary : theme.border,',
  '$pad    ),',
  '$pad    child: child,',
  '$pad  ),',
];

/// [child] in a rounded box [width] × [height], its border primary while
/// the focus is in it.
Widget _boxed(int width, int height, Widget child) => SizedBox(
  width: width,
  height: height,
  child: FocusBuilder(
    builder: (context, hasFocus, child) {
      final theme = Theme.of(context);
      return Box(
        border: Border.all(
          type: BorderType.rounded,
          style: hasFocus ? theme.primary : theme.border,
        ),
        child: child,
      );
    },
    child: child,
  ),
);

/// The line under a box: `offset 3 of 40`, as [controller] says it.
Widget _offsetLine(ScrollController controller) => ListenableBuilder(
  listenable: controller,
  builder: (context, _) {
    final theme = Theme.of(context);
    return Text.rich([
      Span('offset ', theme.muted),
      Span('${controller.offset}'),
      Span(' of ', theme.muted),
      Span('${controller.position.maxOffset}'),
    ]);
  },
);

/// The Code's lines of the line under a box, [controller]'s.
List<String> _offsetCode(String controller) => [
  '      ListenableBuilder(',
  '        listenable: $controller,',
  '        builder: (context, _) => Text.rich([',
  "          Span('offset ', theme.muted),",
  "          Span('\${$controller.offset}'),",
  "          Span(' of ', theme.muted),",
  "          Span('\${$controller.position.maxOffset}'),",
  '        ]),',
  '      ),',
];

// ---------------------------------------------------- SingleChildScrollView

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
  final vertical = o.choice<String>('axis') == 'vertical';
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

// ------------------------------------------------------------ Scrollable

/// A ruler of numbered rows that a Scrollable scrolls.
final class _RulerPage extends StatefulWidget {
  const _RulerPage();

  @override
  State<_RulerPage> createState() => _RulerPageState();
}

final class _RulerPageState extends State<_RulerPage> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      _boxed(
        _boxW,
        _scrollH,
        Scrollable(
          controller: _controller,
          viewportBuilder: (context, position) => ListenableBuilder(
            listenable: position,
            builder: (_, _) =>
                _Ruler(position, offset: position.offset, length: _ruler),
          ),
        ),
      ),
      _offsetLine(_controller),
    ],
  );
}

/// A viewport of [length] numbered rows from [offset] on, which tells
/// [position] its extents as it is laid out.
final class _Ruler extends LeafRenderObjectWidget {
  const _Ruler(this.position, {required this.offset, required this.length});

  final ScrollPosition position;
  final int offset;
  final int length;

  @override
  _RenderRuler createRenderObject(BuildContext context) =>
      _RenderRuler(position, offset, length);

  @override
  void updateRenderObject(BuildContext context, _RenderRuler renderObject) =>
      renderObject
        ..position = position
        ..offset = offset
        ..length = length;
}

final class _RenderRuler extends RenderObject {
  _RenderRuler(this._position, this._offset, this._length);

  ScrollPosition _position;
  int _offset;
  int _length;

  ScrollPosition get position => _position;
  set position(ScrollPosition value) {
    if (value != _position) {
      _position = value;
      markNeedsLayout();
    }
  }

  int get offset => _offset;
  set offset(int value) {
    if (value != _offset) {
      _offset = value;
      markNeedsPaint();
    }
  }

  int get length => _length;
  set length(int value) {
    if (value != _length) {
      _length = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    _position.applyExtents(height, _length);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = canvas.styles.pen(const Pen());
    final tick = canvas.styles.pen(const Pen(attrs: Attr.dim));
    for (var y = 0; y < height && _offset + y < _length; y++) {
      final row = _offset + y + 1;
      final x = canvas.text(0, y, '${row.toString().padLeft(3)} ', pen);
      canvas.text(
        x,
        y,
        row % 10 == 0 ? '├─────────' : (row % 5 == 0 ? '├────' : '├─'),
        tick,
      );
    }
  }
}

final String _rulerCode = [
  'final _controller = ScrollController();',
  '',
  '@override',
  'void dispose() {',
  '  _controller.dispose();',
  '  super.dispose();',
  '}',
  '',
  '@override',
  'Widget build(BuildContext context) {',
  '  final theme = Theme.of(context);',
  '  return Column(',
  '    mainAxisSize: .min,',
  '    crossAxisAlignment: .start,',
  '    gap: 1,',
  '    children: [',
  '      SizedBox(',
  '        width: $_boxW,',
  '        height: $_scrollH,',
  ..._focusBox('        '),
  '          child: Scrollable(',
  '            controller: _controller,',
  '            viewportBuilder: (context, position) => ListenableBuilder(',
  '              listenable: position,',
  '              builder: (_, _) =>',
  _rulerLine,
  '            ),',
  '          ),',
  '        ),',
  '      ),',
  ..._offsetCode('_controller'),
  '    ],',
  '  );',
  '}',
  '',
  '/// A viewport of [length] numbered rows from [offset] on, which tells',
  '/// [position] its extents as it is laid out.',
  'final class _Ruler extends LeafRenderObjectWidget {',
  _rulerConstructor,
  '',
  '  final ScrollPosition position;',
  '  final int offset;',
  '  final int length;',
  '',
  '  @override',
  '  _RenderRuler createRenderObject(BuildContext context) =>',
  '      _RenderRuler(position, offset, length);',
  '',
  '  @override',
  _rulerUpdate,
  '      renderObject',
  '        ..position = position',
  '        ..offset = offset',
  '        ..length = length;',
  '}',
  '',
  'final class _RenderRuler extends RenderObject {',
  '  _RenderRuler(this._position, this._offset, this._length);',
  '',
  '  ScrollPosition _position;',
  '  int _offset;',
  '  int _length;',
  '',
  '  set position(ScrollPosition value) {',
  '    if (value != _position) {',
  '      _position = value;',
  '      markNeedsLayout();',
  '    }',
  '  }',
  '',
  '  set offset(int value) {',
  '    if (value != _offset) {',
  '      _offset = value;',
  '      markNeedsPaint();',
  '    }',
  '  }',
  '',
  '  set length(int value) {',
  '    if (value != _length) {',
  '      _length = value;',
  '      markNeedsLayout();',
  '    }',
  '  }',
  '',
  '  @override',
  '  void performLayout(BoxConstraints c) {',
  '    width = c.maxW;',
  '    height = c.maxH;',
  '    _position.applyExtents(height, _length);',
  '  }',
  '',
  '  @override',
  '  void paint(PaintContext ctx) {',
  '    final canvas = ctx.canvas;',
  '    final pen = canvas.styles.pen(const Pen());',
  '    final tick = canvas.styles.pen(const Pen(attrs: Attr.dim));',
  '    for (var y = 0; y < height && _offset + y < _length; y++) {',
  '      final row = _offset + y + 1;',
  r"      final x = canvas.text(0, y, '${row.toString().padLeft(3)} ', pen);",
  '      canvas.text(',
  '        x,',
  '        y,',
  "        row % 10 == 0 ? '├─────────' : (row % 5 == 0 ? '├────' : '├─'),",
  '        tick,',
  '      );',
  '    }',
  '  }',
  '}',
].join('\n');

// ------------------------------------------------------------ ListView

/// The time of line [i] of the log: a line every 0.6 s from noon.
String _clock(int i) {
  final t = 12 * 3600 + i * _growMs ~/ 1000;
  String two(int v) => '$v'.padLeft(2, '0');
  return '${two(t ~/ 3600)}:${two(t ~/ 60 % 60)}:${two(t % 60)}';
}

/// The answer to line [i]: mostly 200.
Span _status(int i) => switch ((i % 11, i % 17)) {
  (7, _) => '404'.fg(Color.yellow),
  (_, 5) => '500'.fg(Color.red),
  _ => '200'.fg(Color.green),
};

/// Why line [i] failed; null for a 200.
String? _reason(int i) => switch ((i % 11, i % 17)) {
  (7, _) => 'not found',
  (_, 5) => 'server error',
  _ => null,
};

/// The rows of item [i] of the list of different heights: one to four.
int _itemRows(int i) => 1 + i * 7 % 9 % 4;

/// The chat: who says what, a message every [_growMs], the newest item 0.
const _said = [
  'you: is the build green?',
  'twk: 412 tests, all passed',
  'you: and the bench?',
  'twk: no scenario slower',
  'you: then tag it',
  'twk: tagged 0.4.0',
  'you: the changelog?',
  'twk: written, 9 entries',
];

/// Message [k]: its number and who says what.
String _message(int k) => '${'${k + 1}'.padLeft(3)} ${_said[k % _said.length]}';

/// A list of [count] items, or of a log that grows ([count] null), of
/// one row each or [different] heights, or a [chat] that grows at its
/// bottom; [separated] by lines; and the buttons that move it.
final class _List extends StatefulWidget {
  const _List({
    required this.count,
    required this.chat,
    required this.feed,
    required this.different,
    required this.separated,
    required this.stickToEnd,
    super.key,
  });

  final int? count;
  final bool chat;
  final bool feed;
  final bool different;
  final bool separated;
  final bool stickToEnd;

  @override
  State<_List> createState() => _ListState();
}

final class _ListState extends State<_List> {
  late final _list = ListController(stickToEnd: widget.stickToEnd);
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });
  Duration? _grownFrom;

  @override
  void dispose() {
    _motion.dispose();
    _list.dispose();
    super.dispose();
  }

  /// The lines of the log now: one every [_growMs] on the gallery's clock
  /// from when it was chosen.
  int _grown() {
    final from = _grownFrom ??= _motion.now;
    final k = (_motion.now - from).inMilliseconds ~/ _growMs;
    _motion.wakeAt(from + Duration(milliseconds: (k + 1) * _growMs));
    return _growFrom + k;
  }

  Widget _item(BuildContext context, int i, int count) {
    final theme = Theme.of(context);
    if (widget.chat) {
      return Text(_message(count - 1 - i));
    }
    if (widget.feed) {
      return Text(_message(count - 1 - i), key: ValueKey(count - 1 - i));
    }
    if (widget.count == null) {
      return Text.rich([
        _clock(i).dim,
        Span("  GET /items/${'${i + 1}'.padRight(4)}  "),
        _status(i),
        if (widget.different)
          if (_reason(i) case final reason?) Span('\n│ $reason', theme.muted),
      ]);
    }
    if (!widget.different) {
      return Text('item ${i + 1}');
    }
    return Text.rich([
      Span('item ${i + 1}'),
      for (var row = 2; row <= _itemRows(i); row++)
        Span('\n│ row $row of ${_itemRows(i)}', theme.muted),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final count = widget.count ?? _grown();
    _motion.end();
    final chat = widget.chat;
    Widget item(BuildContext context, int i) => _item(context, i, count);
    final sticks =
        widget.count == null && !chat && !widget.feed && !widget.stickToEnd;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        _boxed(
          _boxW,
          _listH,
          widget.separated
              ? ListView.separated(
                  itemCount: count,
                  controller: _list,
                  stickToBottom: sticks,
                  reverse: chat,
                  wheelAcceleration: const WheelAcceleration(),
                  itemBuilder: item,
                  separatorBuilder: (context, i) =>
                      Divider(style: Theme.of(context).border),
                )
              : ListView.builder(
                  itemCount: count,
                  controller: _list,
                  stickToBottom: sticks,
                  reverse: chat,
                  wheelAcceleration: const WheelAcceleration(),
                  itemBuilder: item,
                ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 1,
          children: chat || widget.feed
              ? [
                  Button('newest', onPressed: () => _list.jumpTo(0)),
                  Button(
                    'oldest',
                    onPressed: () => _list.ensureIndexVisible(count - 1),
                  ),
                  Button(
                    'middle',
                    onPressed: () => _list.jumpToIndex(count ~/ 2),
                  ),
                ]
              : [
                  Button('top', onPressed: () => _list.jumpTo(0)),
                  Button(
                    'item $_show',
                    onPressed: () => _list.ensureIndexVisible(_show - 1),
                  ),
                  Button(
                    'middle',
                    onPressed: () => _list.jumpToIndex(count ~/ 2),
                  ),
                ],
        ),
        _offsetLine(_list),
      ],
    );
  }
}

String _listCode(Options o) {
  final chat = o['items'] == 'chat';
  final feed = o['items'] == 'feed';
  final growing = o['items'] == 'growing';
  final grows = growing || chat || feed;
  final different =
      !chat && !feed && o.choice<String>('heights') == 'different';
  final separated = o.flag('separated');
  final byEnd = growing && o['stick'] == 'stickToEnd';
  final item = feed
      ? [
          '            // keyed by the message, as its index is not: scrolled down,',
          '            // what the window shows stays on its rows as messages come',
          '            itemBuilder: (context, i) => Text(',
          '              _message(_count - 1 - i),',
          '              key: ValueKey(_count - 1 - i),',
          '            ),',
        ]
      : chat
      ? [_chatItemLine]
      : growing
      ? [
          '            itemBuilder: (context, i) => Text.rich([',
          '              _clock(i).dim,',
          r'''              Span("  GET /items/${'${i + 1}'.padRight(4)}  "),''',
          '              _status(i),',
          if (different) ...[
            '              // a request that failed: why, on a row of its own',
            '              if (_reason(i) case final reason?)',
            r"                Span('\n│ $reason', theme.muted),",
          ],
          '            ]),',
        ]
      : different
      ? [
          '            // an item of one to four rows',
          '            itemBuilder: (context, i) => Text.rich([',
          r"              Span('item ${i + 1}'),",
          '              for (var row = 2; row <= _rows(i); row++)',
          r"                Span('\n│ row $row of ${_rows(i)}', theme.muted),",
          '            ]),',
        ]
      : [r"            itemBuilder: (context, i) => Text('item ${i + 1}'),"];
  final buttons = chat || feed
      ? [
          "          Button('newest', onPressed: () => _list.jumpTo(0)),",
          '          // the least move that shows it',
          _oldestLine,
          if (feed)
            '          // at the top, built or not'
          else
            '          // at the bottom, the edge a reverse list reads from',
          _middleLine,
        ]
      : [
          "          Button('top', onPressed: () => _list.jumpTo(0)),",
          '          // the least move that shows it',
          _showLine,
          '          // at the top, built or not: where the estimate puts it',
          _middleLine,
        ];
  return [
    if (grows) ...[
      'var _count = $_growFrom;',
      '',
      if (chat)
        '// a message every $_growMs ms, the newest item 0 at the bottom'
      else if (feed)
        '// a message every $_growMs ms, the newest item 0 at the top'
      else
        '// a line of the log every $_growMs ms',
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_growMs),',
      '    (_) => setState(() => _count++),',
      '  );',
      '}',
      '',
    ] else ...[
      'const _count = ${o['items']};',
      '',
    ],
    if (byEnd)
      'final _list = ListController(stickToEnd: true);'
    else
      'final _list = ListController();',
    '',
    '@override',
    'void dispose() {',
    if (grows) '  _timer.cancel();',
    '  _list.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      SizedBox(',
    '        width: $_boxW,',
    '        height: $_listH,',
    ..._focusBox('        '),
    '          child: ListView.${separated ? 'separated' : 'builder'}(',
    '            itemCount: _count,',
    '            controller: _list,',
    if (growing && !byEnd) '            stickToBottom: true,',
    if (chat) '            reverse: true,',
    '            wheelAcceleration: const WheelAcceleration(),',
    ...item,
    if (separated) _separatorLine,
    '          ),',
    '        ),',
    '      ),',
    '      Row(',
    '        mainAxisSize: .min,',
    '        gap: 1,',
    '        children: [',
    ...buttons,
    '        ],',
    '      ),',
    ..._offsetCode('_list'),
    '    ],',
    '  );',
    '}',
    if (chat || feed) ...[
      '',
      '/// Message [k]: its number and who says what.',
      _messageLine,
      '',
      'const _said = [',
      for (final m in _said) "  '$m',",
      '];',
    ] else if (growing) ...[
      '',
      '/// The time of line [i]: a line every 0.6 s from noon.',
      'String _clock(int i) {',
      '  final t = 12 * 3600 + i * $_growMs ~/ 1000;',
      r"  String two(int v) => '$v'.padLeft(2, '0');",
      r"  return '${two(t ~/ 3600)}:${two(t ~/ 60 % 60)}:${two(t % 60)}';",
      '}',
      '',
      '/// The answer to line [i]: mostly 200.',
      'Span _status(int i) => switch ((i % 11, i % 17)) {',
      "  (7, _) => '404'.fg(.yellow),",
      "  (_, 5) => '500'.fg(.red),",
      "  _ => '200'.fg(.green),",
      '};',
      if (different) ...[
        '',
        '/// Why line [i] failed; null for a 200.',
        'String? _reason(int i) => switch ((i % 11, i % 17)) {',
        "  (7, _) => 'not found',",
        "  (_, 5) => 'server error',",
        '  _ => null,',
        '};',
      ],
    ] else if (different) ...[
      '',
      '/// The rows of item [i]: one to four.',
      'int _rows(int i) => 1 + i * 7 % 9 % 4;',
    ],
  ].join('\n');
}

/// The ListView Code's lines too long for a line of Dart.
const _oldestLine =
    "          Button('oldest', onPressed: () => "
    '_list.ensureIndexVisible(_count - 1)),';
const _chatItemLine =
    '            itemBuilder: (context, i) => '
    'Text(_message(_count - 1 - i)),';
const _separatorLine =
    '            separatorBuilder: (context, i) => '
    'Divider(style: theme.border),';
const _messageLine =
    r"String _message(int k) => '${'${k + 1}'.padLeft(3)} "
    r"${_said[k % _said.length]}';";

// ------------------------------------------------------------ Scrollbar

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

// ------------------------------------------------------------ LogView

/// The LogView's box; its lines a column narrower than inside it.
const _logW = 50;

/// A line this often while live.
const _logMs = 400;

/// The lines logged before the page opens.
const _logFrom = 30;

const _logLevels = ['debug', 'info', 'warning', 'error'];

/// The box's rows in [room]: 12, or the room's where it is lower, 6 at
/// least.
int _logRows(int room) => room < 6 ? 6 : (room > 12 ? 12 : room);

/// Line [i] of the log: its level and text, as the Code's `_add` makes it.
(LogLevel, String) _logEntry(int i) => switch (i) {
  _ when i % 13 == 5 => (
    LogLevel.error,
    'POST /api/orders 500 upstream timeout after 5000 ms',
  ),
  _ when i % 7 == 3 => (
    LogLevel.warning,
    'slow query: SELECT * FROM items took ${300 + i * 29 % 900} ms',
  ),
  _ when i % 5 == 1 => (LogLevel.debug, 'cache hit items/${i * 37 % 500}'),
  _ => (
    LogLevel.info,
    'GET /api/items/${i * 37 % 500} 200 ${3 + i * 13 % 90} ms',
  ),
};

/// The LogView page's stage: a log the gallery's clock adds a line to
/// every [_logMs] while [live], kept while the gallery runs.
final class _Log extends StatefulWidget {
  const _Log({
    required this.level,
    required this.filter,
    required this.query,
    required this.time,
    required this.showLevel,
    required this.wrap,
    required this.live,
    required this.scrollbar,
  });

  final LogLevel level;
  final String filter;
  final String query;
  final bool time;
  final bool showLevel;
  final bool wrap;
  final bool live;
  final ScrollbarVisibility scrollbar;

  @override
  State<_Log> createState() => _LogState();
}

final class _LogState extends State<_Log> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kept = PageControl.of(context).state;
    final log = (kept['log'] ??= LogController()) as LogController;
    _motion.begin(context);
    final now = _motion.now.inMilliseconds;
    // the lines logged by now: _logFrom, then one every _logMs while live;
    // the count stands while it is not
    var base = (kept['base'] ??= _logFrom) as int;
    var since = (kept['since'] ??= 0) as int;
    final was = (kept['live'] ??= widget.live) as bool;
    if (was != widget.live) {
      if (was) {
        base += (now - since) ~/ _logMs;
      }
      since = now;
      kept
        ..['base'] = base
        ..['since'] = since
        ..['live'] = widget.live;
    }
    var count = base;
    if (widget.live) {
      final k = (now - since) ~/ _logMs;
      _motion.wakeAt(Duration(milliseconds: since + (k + 1) * _logMs));
      count += k;
    }
    _motion.end();
    final added = (kept['added'] ??= 0) as int;
    if (count > added) {
      for (var i = added; i < count; i++) {
        final (level, text) = _logEntry(i);
        log.add(
          text,
          level: level,
          time: DateTime(2026, 10, 19, 12).add(
            Duration(milliseconds: _logMs * i),
          ),
        );
      }
      kept['added'] = count;
    }
    log
      ..level = widget.level
      ..filter = widget.filter
      ..query = widget.query;
    return LayoutBuilder(
      builder: (context, c) => _boxed(
        _logW,
        _logRows(c.maxH < BoxConstraints.unbounded ? c.maxH : 1 << 20),
        LogView(
          controller: log,
          wrap: widget.wrap,
          showTime: widget.time,
          showLevel: widget.showLevel,
          scrollbar: widget.scrollbar,
        ),
      ),
    );
  }
}

String _logCode(Options o, StageRoom room) {
  final level = o.choice<String>('level');
  final filter = o.choice<String>('filter');
  final query = o.choice<String>('query');
  final live = o.flag('live');
  final args = [
    if (level != 'debug') 'level: .$level',
    if (filter != 'none') "filter: '$filter'",
    if (query != 'none') "query: '$query'",
  ];
  final view = [
    if (o.flag('wrap')) 'wrap: true,',
    if (!o.flag('time')) 'showTime: false,',
    if (!o.flag('showLevel')) 'showLevel: false,',
    if (o.choice<String>('scrollbar') != 'always')
      'scrollbar: .${o.label('scrollbar')},',
  ];
  return [
    if (args.isNotEmpty) ...[
      'final _log = LogController(',
      for (final a in args) '  $a,',
      ');',
    ] else
      'final _log = LogController();',
    if (live) ...['var _lines = $_logFrom;', 'late final Timer _timer;'],
    '',
    '@override',
    'void initState() {',
    '  super.initState();',
    '  // the lines logged before it opens',
    '  for (var i = 0; i < $_logFrom; i++) {',
    '    _add(i);',
    '  }',
    if (live) ...[
      '  // then one every $_logMs ms',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_logMs),',
      '    (_) => _add(_lines++),',
      '  );',
    ],
    '}',
    '',
    '@override',
    'void dispose() {',
    if (live) '  _timer.cancel();',
    '  _log.dispose();',
    '  super.dispose();',
    '}',
    '',
    '/// Line [i]: what it says, at what level, and when.',
    'void _add(int i) {',
    '  final (level, text) = switch (i) {',
    _logErrorLine,
    '    _ when i % 7 == 3 => (',
    '      LogLevel.warning,',
    r"      'slow query: SELECT * FROM items took ${300 + i * 29 % 900} ms',",
    '    ),',
    _logDebugLine,
    _logInfoLine,
    '  };',
    '  _log.add(',
    '    text,',
    '    level: level,',
    _logTimeLine,
    '  );',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return SizedBox(',
    '    width: $_logW,',
    '    height: ${_logRows(room.height)},',
    ..._focusBox('    '),
    if (view.isEmpty)
      '      child: LogView(controller: _log),'
    else ...[
      '      child: LogView(',
      '        controller: _log,',
      for (final v in view) '        $v',
      '      ),',
    ],
    '    ),',
    '  );',
    '}',
  ].join('\n');
}

/// The Code's lines too long for a line of Dart.
const _logErrorLine =
    "    _ when i % 13 == 5 => (LogLevel.error, 'POST /api/orders 500 "
    "upstream timeout after 5000 ms'),";
const _logDebugLine =
    r"    _ when i % 5 == 1 => (LogLevel.debug, 'cache hit items/${i * 37 % 500}'),";
const _logInfoLine =
    r"    _ => (LogLevel.info, 'GET /api/items/${i * 37 % 500} 200 "
    r"${3 + i * 13 % 90} ms'),";
const _logTimeLine =
    '    time: DateTime(2026, 10, 19, 12).add(Duration(milliseconds: '
    '$_logMs * i)),';
