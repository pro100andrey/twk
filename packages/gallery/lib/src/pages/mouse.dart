// The Mouse group of the gallery.
import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';
import 'common.dart';

/// The pad: its width and rows.
const _padW = 36;
const _padH = 7;

/// The lines of the Listener's log.
const _log = 4;

/// The SelectionArea's width.
const _selW = 44;

const _readsMouse =
    'An app that reads the mouse keeps the terminal from selecting its '
    'text, so it selects the text itself.';

/// A fruit box: its width and rows; the gap between two.
const _fruitW = 15;
const _fruitH = 6;
const _fruitGap = 2;

/// The fruit, the colour of each, and those the red box takes.
const Map<String, Color> _fruitColors = {
  'apple': Color.red,
  'banana': Color.yellow,
  'cherry': Color.red,
  'grape': Color.magenta,
};
const _red = {'apple', 'cherry'};

/// What each box shows while it is empty.
const _empty = {
  'bowl': 'empty',
  'basket': 'drop here',
  'red only': 'drop here',
};

/// The Code's lines too long for a line of Dart.
const _dragStartLine =
    '        onDragStart: (drag) => setState(() => _from = (drag.x, drag.y)),';
const _draggedLine =
    r'          _dragged = (_dragged.$1 + drag.dx, _dragged.$2 + drag.dy);';
const _dragCountLine =
    r"            Span('${_dragged.$1} across, ${_dragged.$2} down'),";
const _pressLine =
    "          onDown: (event) => _saw('press of button "
    r"${event.button}', event),";
const _overLine =
    "                  child: Text(_over ? 'the mouse is over me' : "
    "'move over me'),";
const _copiedLine =
    "                _copied.isEmpty ? 'nothing' : "
    r"_copied.replaceAll('\n', ' '),";
const _candidateLine =
    '                        if (candidate != null && '
    '!fruits.contains(candidate))';
const _canceledLine =
    '    onDragCanceled: () => '
    r"setState(() => _status = '$fruit, back to the $from'),";
const _labelLine =
    "      Text.rich(['● '.fg(_colors[fruit]!), Span(fruit)], style: style);";

/// The pages of the Mouse group that draw.
final mousePages = [
  GalleryPage(
    group: 'Mouse',
    title: 'GestureDetector',
    options: const [
      SwitchOption('double', 'double tap', initial: true),
      ChoiceOption(
        'long',
        'long press after',
        values: [500, 1000],
        labels: ['500 ms', '1 s'],
      ),
      // the buttons whose presses it takes: 0 left, 1 middle, 2 right
      ChoiceOption(
        'buttons',
        'buttons',
        values: ['left', 'right', 'any'],
        labels: ['left', 'right', 'left, middle, right'],
      ),
    ],
    build: (context, o) => _Gestures(
      doubleTap: o.flag('double'),
      longMs: o.choice('long'),
      buttons: _buttons[o.choice<String>('buttons')]!,
    ),
    code: _gesturesCode,
  ),
  GalleryPage(
    group: 'Mouse',
    title: 'Listener, MouseRegion',
    options: const [
      ChoiceOption(
        'cursor',
        'cursor',
        values: [
          'pointer',
          'crosshair',
          'text',
          'grab',
          'move',
          'notAllowed',
          'wait',
          'none',
        ],
      ),
    ],
    build: (context, o) {
      final cursor = o.choice<String>('cursor');
      return _Events(
        cursor: cursor == 'none' ? null : PointerShape.values.byName(cursor),
      );
    },
    code: _eventsCode,
  ),
  GalleryPage(
    group: 'Mouse',
    title: 'IgnorePointer, AbsorbPointer',
    options: const [
      ChoiceOption(
        'gate',
        'around the button',
        values: ['none', 'ignore', 'absorb'],
        labels: ['none', 'IgnorePointer', 'AbsorbPointer'],
        initial: 'ignore',
      ),
    ],
    build: (context, o) => _Gated(gate: o.choice('gate')),
    code: _gatedCode,
  ),
  GalleryPage(
    group: 'Mouse',
    title: 'SelectionArea',
    options: const [
      ChoiceOption(
        'view',
        'selected in',
        values: ['texts', 'log'],
        labels: ['two Texts', 'a painted log'],
      ),
      SwitchOption('copy', 'copy on release', initial: true),
      ChoiceOption(
        'style',
        'style',
        values: ['selection', 'reverse'],
        labels: ["the theme's", 'reverse'],
      ),
    ],
    build: (context, o) => o.choice<String>('view') == 'log'
        ? _SelectionLog(
            copyOnRelease: o.flag('copy'),
            reverse: o.choice<String>('style') == 'reverse',
          )
        : _Selection(
            copyOnRelease: o.flag('copy'),
            reverse: o.choice<String>('style') == 'reverse',
          ),
    code: (o) => o.choice<String>('view') == 'log'
        ? _selectionLogCode(o)
        : _selectionCode(o),
  ),
  GalleryPage(
    group: 'Mouse',
    title: 'Draggable, DragTarget',
    options: const [
      SwitchOption('ghost', 'child when dragging', initial: true),
    ],
    build: (context, o) => _Fruit(ghost: o.flag('ghost')),
    code: _fruitCode,
  ),
];

const _bold = Style(attrs: Attr.bold);

/// The buttons GestureDetector's page offers, by the option's value.
const _buttons = {
  'left': {0},
  'right': {2},
  'any': {0, 1, 2},
};

/// [text] in [style], its background lit for a moment when [serial]
/// changes, as [LitLine] lights its values, on up to [maxLines] lines.
final class _LitText extends StatefulWidget {
  const _LitText(
    this.text, {
    required this.serial,
    this.style = const Style(),
    this.maxLines,
  });

  final String text;
  final int serial;
  final Style style;
  final int? maxLines;

  @override
  State<_LitText> createState() => _LitTextState();
}

final class _LitTextState extends State<_LitText> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });
  int? _serial;
  Duration? _litAt;

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final theme = Theme.of(context);
    if (_serial != null && _serial != widget.serial) {
      _litAt = _motion.now;
    }
    _serial = widget.serial;
    final at = _litAt;
    final k = at == null ? 0.0 : 1 - _motion.progress(at, 900);
    _motion.end();
    final style = widget.style.merge(litStyle(theme, k));
    return Text(
      widget.text,
      style: style,
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null
          ? TextOverflow.clip
          : TextOverflow.ellipsis,
    );
  }
}

// ------------------------------------------------------------ GestureDetector

/// A pad that tells its taps, double taps, long presses and drags.
final class _Gestures extends StatefulWidget {
  const _Gestures({
    required this.doubleTap,
    required this.longMs,
    required this.buttons,
  });

  final bool doubleTap;
  final int longMs;
  final Set<int> buttons;

  @override
  State<_Gestures> createState() => _GesturesState();
}

final class _GesturesState extends State<_Gestures> {
  var _taps = 0;
  var _doubleTaps = 0;
  var _longPresses = 0;
  var _dragged = (0, 0);
  var _drags = 0;
  String? _last;
  (int, int)? _from;
  (int, int)? _at;

  void _saw(String what, PointerEvent event) =>
      _last = '$what at ${event.x}, ${event.y}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        GestureDetector(
          onTap: (event) => setState(() {
            _taps++;
            _saw('tap', event);
          }),
          onDoubleTap: widget.doubleTap
              ? (event) => setState(() {
                  _doubleTaps++;
                  _saw('double tap', event);
                })
              : null,
          onLongPress: (event) => setState(() {
            _longPresses++;
            _saw('long press', event);
          }),
          longPressDuration: Duration(milliseconds: widget.longMs),
          buttons: widget.buttons,
          onDragStart: (drag) => setState(() => _from = (drag.x, drag.y)),
          onDragUpdate: (drag) => setState(() {
            _dragged = (_dragged.$1 + drag.dx, _dragged.$2 + drag.dy);
            _drags++;
            _at = (drag.x, drag.y);
            _saw('drag', drag.event);
          }),
          onDragEnd: (drag) => setState(() {
            _from = _at = null;
            _saw('drag ended', drag.event);
          }),
          child: SizedBox(
            width: _padW,
            height: _padH,
            child: Box(
              border: Border.all(type: BorderType.rounded, style: theme.border),
              child: Box(
                style: theme.surface,
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        _last ?? 'tap, hold or drag me',
                        style: _last == null ? theme.muted : const Style(),
                      ),
                    ),
                    if (_from case (final x, final y))
                      Positioned(
                        left: x - 1,
                        top: y - 1,
                        child: Text('○', style: theme.muted),
                      ),
                    if (_at case (final x, final y))
                      Positioned(
                        left: x - 1,
                        top: y - 1,
                        child: Text('●', style: theme.primary),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LitLine([('taps ', true), ('$_taps', false)], serial: _taps),
                LitLine([
                  (', double ', true),
                  ('$_doubleTaps', false),
                ], serial: _doubleTaps),
                LitLine([
                  (', long ', true),
                  ('$_longPresses', false),
                ], serial: _longPresses),
              ],
            ),
            LitLine([
              ('dragged ', true),
              ('${_dragged.$1} across, ${_dragged.$2} down', false),
            ], serial: _drags),
          ],
        ),
      ],
    );
  }
}

String _gesturesCode(Options o) => [
  'var _taps = 0, _doubleTaps = 0, _longPresses = 0;',
  'var _dragged = (0, 0);',
  'String? _last;',
  '(int, int)? _from, _at; // the drag: where it started, where it is',
  '',
  'void _saw(String what, PointerEvent event) =>',
  r"    _last = '$what at ${event.x}, ${event.y}';",
  '',
  '@override',
  'Widget build(BuildContext context) {',
  '  final theme = Theme.of(context);',
  '  return Column(',
  '    mainAxisSize: .min,',
  '    crossAxisAlignment: .start,',
  '    gap: 1,',
  '    children: [',
  '      GestureDetector(',
  '        onTap: (event) => setState(() {',
  '          _taps++;',
  "          _saw('tap', event);",
  '        }),',
  if (o.flag('double')) ...[
    '        onDoubleTap: (event) => setState(() {',
    '          _doubleTaps++;',
    "          _saw('double tap', event);",
    '        }),',
  ],
  '        onLongPress: (event) => setState(() {',
  '          _longPresses++;',
  "          _saw('long press', event);",
  '        }),',
  if (o.choice<int>('long') != 500)
    '        longPressDuration: const Duration(seconds: 1),',
  if (o.choice<String>('buttons') case final b when b != 'left')
    '        buttons: const {${_buttons[b]!.join(', ')}},',
  _dragStartLine,
  '        onDragUpdate: (drag) => setState(() {',
  _draggedLine,
  '          _at = (drag.x, drag.y);',
  "          _saw('drag', drag.event);",
  '        }),',
  '        onDragEnd: (drag) => setState(() {',
  '          _from = _at = null;',
  "          _saw('drag ended', drag.event);",
  '        }),',
  '        child: SizedBox(',
  '          width: $_padW,',
  '          height: $_padH,',
  '          child: Box(',
  '            border: .all(type: .rounded, style: theme.border),',
  '            child: Box(',
  '              style: theme.surface,',
  '              child: Stack(',
  '                children: [',
  '                  Center(',
  '                    child: Text(',
  "                      _last ?? 'tap, hold or drag me',",
  '                      style: _last == null ? theme.muted : const Style(),',
  '                    ),',
  '                  ),',
  "                  // the detector's cells, less the border",
  '                  if (_from case (final x, final y))',
  '                    Positioned(',
  '                      left: x - 1,',
  '                      top: y - 1,',
  "                      child: Text('○', style: theme.muted),",
  '                    ),',
  '                  if (_at case (final x, final y))',
  '                    Positioned(',
  '                      left: x - 1,',
  '                      top: y - 1,',
  "                      child: Text('●', style: theme.primary),",
  '                    ),',
  '                ],',
  '              ),',
  '            ),',
  '          ),',
  '        ),',
  '      ),',
  '      Column(',
  '        mainAxisSize: .min,',
  '        crossAxisAlignment: .start,',
  '        children: [',
  '          Text.rich([',
  "            Span('taps ', theme.muted),",
  r"            Span('$_taps'),",
  "            Span(', double ', theme.muted),",
  r"            Span('$_doubleTaps'),",
  "            Span(', long ', theme.muted),",
  r"            Span('$_longPresses'),",
  '          ]),',
  '          Text.rich([',
  "            Span('dragged ', theme.muted),",
  _dragCountLine,
  '          ]),',
  '        ],',
  '      ),',
  '    ],',
  '  );',
  '}',
].join('\n');

// ---------------------------------------------------- Listener, MouseRegion

/// A pad that logs the mouse events over it, lit while the mouse is.
final class _Events extends StatefulWidget {
  const _Events({required this.cursor});

  final PointerShape? cursor;

  @override
  State<_Events> createState() => _EventsState();
}

final class _EventsState extends State<_Events> {
  var _over = false;
  final _events = <String>[];
  var _seen = 0;

  void _saw(String what, PointerEvent event) => setState(() {
    _events.insert(0, '$what at ${event.x}, ${event.y}');
    if (_events.length > _log) {
      _events.removeLast();
    }
    _seen++;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        MouseRegion(
          onEnter: (event) {
            _over = true;
            _saw('enter', event);
          },
          onExit: (event) {
            _over = false;
            _saw('exit', event);
          },
          cursor: widget.cursor,
          child: Listener(
            onDown: (event) => _saw('press of button ${event.button}', event),
            onUp: (event) => _saw('release', event),
            onMove: (event) => _saw('move', event),
            onDrag: (event) => _saw('drag', event),
            onScroll: (event) => _saw(event.kind.name, event),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: _padW,
              height: _padH,
              child: Box(
                border: Border.all(
                  type: BorderType.rounded,
                  style: _over ? theme.primary : theme.border,
                ),
                child: Box(
                  style: _over ? theme.selection : theme.surface,
                  child: Center(
                    child: Text(
                      _over ? 'the mouse is over me' : 'move over me',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_events.isEmpty) Text('nothing yet', style: theme.muted),
            for (final (i, event) in _events.indexed)
              if (i == 0)
                _LitText(event, serial: _seen)
              else
                Text(event, style: theme.muted),
          ],
        ),
      ],
    );
  }
}

String _eventsCode(Options o) {
  final cursor = o.choice<String>('cursor');
  return [
    'var _over = false;',
    'final _events = <String>[];',
    '',
    '// what came, the newest first',
    'void _saw(String what, PointerEvent event) => setState(() {',
    r"  _events.insert(0, '$what at ${event.x}, ${event.y}');",
    '  if (_events.length > $_log) _events.removeLast();',
    '});',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      MouseRegion(',
    '        onEnter: (event) {',
    '          _over = true;',
    "          _saw('enter', event);",
    '        },',
    '        onExit: (event) {',
    '          _over = false;',
    "          _saw('exit', event);",
    '        },',
    if (cursor != 'none') '        cursor: .$cursor,',
    '        child: Listener(',
    _pressLine,
    "          onUp: (event) => _saw('release', event),",
    "          onMove: (event) => _saw('move', event),",
    "          onDrag: (event) => _saw('drag', event),",
    '          onScroll: (event) => _saw(event.kind.name, event),',
    '          behavior: .opaque,',
    '          child: SizedBox(',
    '            width: $_padW,',
    '            height: $_padH,',
    '            child: Box(',
    '              border: .all(',
    '                type: .rounded,',
    '                style: _over ? theme.primary : theme.border,',
    '              ),',
    '              child: Box(',
    '                style: _over ? theme.selection : theme.surface,',
    '                child: Center(',
    _overLine,
    '                ),',
    '              ),',
    '            ),',
    '          ),',
    '        ),',
    '      ),',
    '      Column(',
    '        mainAxisSize: .min,',
    '        crossAxisAlignment: .start,',
    '        children: [',
    "          if (_events.isEmpty) Text('nothing yet', style: theme.muted),",
    '          for (final (i, event) in _events.indexed)',
    '            Text(event, style: i == 0 ? const Style() : theme.muted),',
    '        ],',
    '      ),',
    '    ],',
    '  );',
    '}',
  ].join('\n');
}

// ------------------------------------------------------------ SelectionArea

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
        gap: 1,
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
              gap: 1,
              children: [
                Text(_readsMouse),
                Text('A drag goes on from one paragraph to the next.'),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            gap: 1,
            children: [
              Text('copied:', style: theme.muted),
              Expanded(
                child: _LitText(
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
  '      gap: 1,',
  '      children: [',
  '        SelectionArea(',
  if (!o.flag('copy')) '          copyOnRelease: false,',
  if (o.choice<String>('style') == 'reverse')
    '          style: const Style(attrs: Attr.reverse),',
  '          onCopy: (text) => setState(() => _copied = text),',
  '          child: const Column(',
  '            mainAxisSize: .min,',
  '            crossAxisAlignment: .start,',
  '            gap: 1,',
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
  '          gap: 1,',
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

// ------------------------------------------- SelectionArea, a painted log

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
        gap: 1,
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
            gap: 1,
            children: [
              Text('copied:', style: theme.muted),
              Expanded(
                child: _LitText(
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
  '      gap: 1,',
  '      children: [',
  '        SelectionArea(',
  if (!o.flag('copy')) '          copyOnRelease: false,',
  if (o.choice<String>('style') == 'reverse')
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
  '          gap: 1,',
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

// ---------------------------------------------------- Draggable, DragTarget

/// Three boxes of fruit, dragged from one to another.
final class _Fruit extends StatefulWidget {
  const _Fruit({required this.ghost});

  /// Whether a dragged fruit leaves a muted one in its place.
  final bool ghost;

  @override
  State<_Fruit> createState() => _FruitState();
}

final class _FruitState extends State<_Fruit> {
  final _in = {
    'bowl': ['apple', 'banana', 'cherry', 'grape'],
    'basket': <String>[],
    'red only': <String>[],
  };
  String? _status;
  var _drops = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: _fruitGap,
          children: [
            for (final MapEntry(key: name, value: fruits) in _in.entries)
              DragTarget<String>(
                onWillAccept: (drag) =>
                    name != 'red only' || _red.contains(drag.data),
                onAccept: (drop) => setState(() {
                  if (!fruits.contains(drop.data)) {
                    for (final list in _in.values) {
                      list.remove(drop.data);
                    }
                    fruits.add(drop.data);
                  }
                  _status = '${drop.data} → $name';
                  _drops++;
                }),
                builder: (context, candidate, rejected) {
                  final over = candidate != null || rejected != null;
                  final style = candidate != null
                      ? theme.primary
                      : rejected != null
                      ? theme.error
                      : theme.border;
                  return SizedBox(
                    width: _fruitW,
                    height: _fruitH,
                    child: Box(
                      border: Border.all(
                        type: BorderType.rounded,
                        style: style,
                      ),
                      titles: [
                        BorderTitle(
                          ' $name ',
                          style: over ? style.merge(_bold) : theme.muted,
                        ),
                      ],
                      padding: const EdgeInsets.x(1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (fruits.isEmpty && !over)
                            Text(_empty[name]!, style: theme.muted),
                          for (final fruit in fruits)
                            _draggable(fruit, name, theme),
                          if (candidate != null && !fruits.contains(candidate))
                            Text('+ $candidate', style: theme.primary),
                          if (rejected != null)
                            Text('✗ red only', style: theme.error),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        LitLine([
          ('dropped: ', true),
          (_status ?? 'nothing', _status == null),
        ], serial: _drops),
      ],
    );
  }

  Widget _draggable(String fruit, String from, ThemeData theme) {
    Widget label([Style style = const Style()]) =>
        Text.rich(['● '.fg(_fruitColors[fruit]!), Span(fruit)], style: style);
    return Draggable<String>(
      data: fruit,
      feedback: Shadow(
        shadow: const BoxShadow(dx: 1),
        child: Box(
          style: theme.surface,
          padding: const EdgeInsets.x(1),
          child: label(theme.text.merge(_bold)),
        ),
      ),
      childWhenDragging: widget.ghost
          ? Text('● $fruit', style: theme.muted)
          : null,
      onDragCanceled: () => setState(() {
        _status = '$fruit, back to the $from';
        _drops++;
      }),
      child: label(),
    );
  }
}

String _fruitCode(Options o) => [
  "const _red = {'apple', 'cherry'};",
  'const _colors = {',
  "  'apple': Color.red,",
  "  'banana': Color.yellow,",
  "  'cherry': Color.red,",
  "  'grape': Color.magenta,",
  '};',
  '',
  'final _in = {',
  "  'bowl': ['apple', 'banana', 'cherry', 'grape'],",
  "  'basket': <String>[],",
  "  'red only': <String>[],",
  '};',
  'String? _status;',
  '',
  '@override',
  'Widget build(BuildContext context) {',
  '  final theme = Theme.of(context);',
  '  const empty = {',
  "    'bowl': 'empty',",
  "    'basket': 'drop here',",
  "    'red only': 'drop here',",
  '  };',
  '  return Column(',
  '    mainAxisSize: .min,',
  '    crossAxisAlignment: .start,',
  '    gap: 1,',
  '    children: [',
  '      Row(',
  '        mainAxisSize: .min,',
  '        gap: $_fruitGap,',
  '        children: [',
  '          for (final MapEntry(key: name, value: fruits) in _in.entries)',
  '            DragTarget<String>(',
  '              onWillAccept: (drag) =>',
  "                  name != 'red only' || _red.contains(drag.data),",
  '              onAccept: (drop) => setState(() {',
  '                // dropped back on its own box, it stays where it is',
  '                if (!fruits.contains(drop.data)) {',
  '                  for (final list in _in.values) {',
  '                    list.remove(drop.data);',
  '                  }',
  '                  fruits.add(drop.data);',
  '                }',
  r"                _status = '${drop.data} → $name';",
  '              }),',
  '              builder: (context, candidate, rejected) {',
  '                final over = candidate != null || rejected != null;',
  '                final style = candidate != null',
  '                    ? theme.primary',
  '                    : rejected != null',
  '                    ? theme.error',
  '                    : theme.border;',
  '                return SizedBox(',
  '                  width: $_fruitW,',
  '                  height: $_fruitH,',
  '                  child: Box(',
  '                    border: .all(type: .rounded, style: style),',
  '                    titles: [',
  '                      BorderTitle(',
  r"                        ' $name ',",
  '                        style: over ? style.merge(bold) : theme.muted,',
  '                      ),',
  '                    ],',
  '                    padding: const .x(1),',
  '                    child: Column(',
  '                      crossAxisAlignment: .start,',
  '                      children: [',
  '                        if (fruits.isEmpty && !over)',
  '                          Text(empty[name]!, style: theme.muted),',
  '                        for (final fruit in fruits)',
  '                          _draggable(fruit, name, theme),',
  _candidateLine,
  r"                          Text('+ $candidate', style: theme.primary),",
  '                        if (rejected != null)',
  "                          Text('✗ red only', style: theme.error),",
  '                      ],',
  '                    ),',
  '                  ),',
  '                );',
  '              },',
  '            ),',
  '        ],',
  '      ),',
  '      Text.rich([',
  "        Span('dropped: ', theme.muted),",
  '        Span(',
  "          _status ?? 'nothing',",
  '          _status == null ? theme.muted : const Style(),',
  '        ),',
  '      ]),',
  '    ],',
  '  );',
  '}',
  '',
  '/// [fruit] in the box [from], dragged with the mouse: the pointer a',
  '/// hand over it, a closed one while it is dragged, no-drop over a box',
  "/// that refuses it (Draggable's pointerShapes).",
  'Widget _draggable(String fruit, String from, ThemeData theme) {',
  '  Widget label([Style style = const Style()]) =>',
  _labelLine,
  '  return Draggable<String>(',
  '    data: fruit,',
  '    // what follows the mouse: a chip on the surface, with a shadow',
  '    feedback: Shadow(',
  '      shadow: const BoxShadow(dx: 1),',
  '      child: Box(',
  '        style: theme.surface,',
  '        padding: const .x(1),',
  '        child: label(theme.text.merge(bold)),',
  '      ),',
  '    ),',
  if (o.flag('ghost'))
    r"    childWhenDragging: Text('● $fruit', style: theme.muted),",
  _canceledLine,
  '    child: label(),',
  '  );',
  '}',
  '',
  'const bold = Style(attrs: Attr.bold);',
].join('\n');

// ------------------------------------------------ IgnorePointer, AbsorbPointer

/// The backdrop: its width and rows.
const _backdropW = 36;
const _backdropH = 7;

const _backdropTap =
    "            onTap: (_) => setState(() => _heard = 'the backdrop'),";
const _backdropTitle =
    "                titles: [BorderTitle(' backdrop ', style: theme.muted)],";
const _heardLine =
    "        if (_heard.isEmpty) Span('nothing', theme.muted) else "
    'Span(_heard),';

/// A button over a backdrop, in a Stack, the button inside an
/// IgnorePointer or an AbsorbPointer as [gate] says (`none`, `ignore`,
/// `absorb`): what heard a click says so under them.
final class _Gated extends StatefulWidget {
  const _Gated({required this.gate});

  final String gate;

  @override
  State<_Gated> createState() => _GatedState();
}

final class _GatedState extends State<_Gated> {
  var _over = false;
  var _heard = '';
  var _serial = 0;

  void _hear(String what) => setState(() {
    _heard = what;
    _serial++;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget button = MouseRegion(
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: GestureDetector(
        onTap: (_) => _hear('the button'),
        child: Box(
          border: Border.all(
            type: BorderType.rounded,
            style: _over ? theme.primary : theme.border,
          ),
          padding: const EdgeInsets.x(2),
          child: const Text('click me'),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: (_) => _hear('the backdrop'),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: _backdropW,
                height: _backdropH,
                child: Box(
                  border: _roundedBorder(theme),
                  titles: [BorderTitle(' backdrop ', style: theme.muted)],
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: switch (widget.gate) {
                  'ignore' => IgnorePointer(child: button),
                  'absorb' => AbsorbPointer(child: button),
                  _ => button,
                },
              ),
            ),
          ],
        ),
        LitLine([
          ('heard: ', true),
          if (_heard.isEmpty) ('nothing', true) else (_heard, false),
        ], serial: _serial),
      ],
    );
  }
}

Border _roundedBorder(ThemeData theme) =>
    Border.all(type: BorderType.rounded, style: theme.border);

String _gatedCode(Options o) {
  final gate = switch (o.choice<String>('gate')) {
    'ignore' => 'IgnorePointer',
    'absorb' => 'AbsorbPointer',
    _ => null,
  };
  const button = [
    'MouseRegion(',
    '  onEnter: (_) => setState(() => _over = true),',
    '  onExit: (_) => setState(() => _over = false),',
    '  child: GestureDetector(',
    "    onTap: (_) => setState(() => _heard = 'the button'),",
    '    child: Box(',
    '      border: .all(',
    '        type: .rounded,',
    '        style: _over ? theme.primary : theme.border,',
    '      ),',
    '      padding: const .x(2),',
    "      child: const Text('click me'),",
    '    ),',
    '  ),',
    '),',
  ];
  List<String> pad(int n, Iterable<String> lines) => [
    for (final l in lines) '${' ' * n}$l',
  ];
  final child = gate != null
      ? [
          '              child: $gate(',
          '                child: ${button.first}',
          ...pad(16, button.sublist(1, button.length - 1)),
          '                ),',
          '              ),',
        ]
      : [
          '              child: ${button.first}',
          ...pad(14, button.sublist(1)),
        ];
  return [
    'var _over = false;',
    "var _heard = '';",
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      Stack(',
    '        children: [',
    '          GestureDetector(',
    _backdropTap,
    '            behavior: .opaque,',
    '            child: SizedBox(',
    '              width: $_backdropW,',
    '              height: $_backdropH,',
    '              child: Box(',
    '                border: .all(type: .rounded, style: theme.border),',
    _backdropTitle,
    '              ),',
    '            ),',
    '          ),',
    '          Positioned.fill(',
    '            child: Center(',
    ...child,
    '            ),',
    '          ),',
    '        ],',
    '      ),',
    '      Text.rich([',
    "        Span('heard: ', theme.muted),",
    _heardLine,
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n');
}
