// The GestureDetector page.
part of 'mouse.dart';

/// The GestureDetector page's `double` option.
const _gesturedetectorDouble = SwitchOption(
  'double',
  'double tap',
  initial: true,
);

/// The GestureDetector page's `long` option.
const _gesturedetectorLong = ChoiceOption<int>(
  'long',
  'long press after',
  values: [500, 1000],
  labels: ['500 ms', '1 s'],
);

/// The GestureDetector page's `buttons` option.
const _gesturedetectorButtons = ChoiceOption<String>(
  'buttons',
  'buttons',
  values: ['left', 'right', 'any'],
  labels: ['left', 'right', 'left, middle, right'],
);

final _gesturedetectorPage = GalleryPage(
  group: _group,
  title: 'GestureDetector',
  options: const [
    _gesturedetectorDouble,
    _gesturedetectorLong,
    // the buttons whose presses it takes: 0 left, 1 middle, 2 right
    _gesturedetectorButtons,
  ],
  build: (context, o) => _Gestures(
    doubleTap: o(_gesturedetectorDouble),
    longMs: o(_gesturedetectorLong),
    buttons: _buttons[o(_gesturedetectorButtons)]!,
  ),
  code: _gesturesCode,
);

/// The Code's lines too long for a line of Dart.
const _dragStartLine =
    '        onPanStart: (drag) => setState(() => _from = drag.localPosition),';

const _draggedLine =
    r'          _dragged = (_dragged.$1 + drag.delta.dx, _dragged.$2 + drag.delta.dy);';

const _dragCountLine =
    r"            Span('${_dragged.$1} across, ${_dragged.$2} down'),";

/// The buttons GestureDetector's page offers, by the option's value.
const _buttons = {
  'left': {0},
  'right': {2},
  'any': {0, 1, 2},
};

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
  CellOffset? _from;
  CellOffset? _at;

  void _saw(String what, PointerEvent event) =>
      _last = '$what at ${event.x}, ${event.y}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
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
          onPanStart: (drag) => setState(() => _from = drag.localPosition),
          onPanUpdate: (drag) => setState(() {
            _dragged = (
              _dragged.$1 + drag.delta.dx,
              _dragged.$2 + drag.delta.dy,
            );
            _drags++;
            _at = drag.localPosition;
            _saw('drag', drag.event);
          }),
          onPanEnd: (drag) => setState(() {
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
                    if (_from case (dx: final x, dy: final y))
                      Positioned(
                        left: x - 1,
                        top: y - 1,
                        child: Text('○', style: theme.muted),
                      ),
                    if (_at case (dx: final x, dy: final y))
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
  'CellOffset? _from, _at; // the drag: where it started, where it is',
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
  '    spacing: 1,',
  '    children: [',
  '      GestureDetector(',
  '        onTap: (event) => setState(() {',
  '          _taps++;',
  "          _saw('tap', event);",
  '        }),',
  if (o(_gesturedetectorDouble)) ...[
    '        onDoubleTap: (event) => setState(() {',
    '          _doubleTaps++;',
    "          _saw('double tap', event);",
    '        }),',
  ],
  '        onLongPress: (event) => setState(() {',
  '          _longPresses++;',
  "          _saw('long press', event);",
  '        }),',
  if (o(_gesturedetectorLong) != 500)
    '        longPressDuration: const Duration(seconds: 1),',
  if (o(_gesturedetectorButtons) case final b when b != 'left')
    '        buttons: const {${_buttons[b]!.join(', ')}},',
  _dragStartLine,
  '        onPanUpdate: (drag) => setState(() {',
  _draggedLine,
  '          _at = drag.localPosition;',
  "          _saw('drag', drag.event);",
  '        }),',
  '        onPanEnd: (drag) => setState(() {',
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
  '                  if (_from case (dx: final x, dy: final y))',
  '                    Positioned(',
  '                      left: x - 1,',
  '                      top: y - 1,',
  "                      child: Text('○', style: theme.muted),",
  '                    ),',
  '                  if (_at case (dx: final x, dy: final y))',
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
