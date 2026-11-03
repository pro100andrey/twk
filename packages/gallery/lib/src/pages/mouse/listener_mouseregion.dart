// The Listener, MouseRegion page.
part of 'mouse.dart';

/// The Listener, MouseRegion page's `cursor` option.
const _listenerMouseregionCursor = ChoiceOption<String>(
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
);

final _listenerMouseregionPage = GalleryPage(
  group: _group,
  title: 'Listener, MouseRegion',
  options: const [
    _listenerMouseregionCursor,
  ],
  build: (context, o) {
    final cursor = o(_listenerMouseregionCursor);
    return _Events(
      cursor: cursor == 'none' ? null : PointerShape.values.byName(cursor),
    );
  },
  code: _eventsCode,
);

/// The lines of the Listener's log.
const _log = 4;

const _pressLine =
    "          onDown: (event) => _saw('press of button "
    r"${event.button}', event),";

const _overLine =
    "                  child: Text(_over ? 'the mouse is over me' : "
    "'move over me'),";

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
                LitText(event, serial: _seen)
              else
                Text(event, style: theme.muted),
          ],
        ),
      ],
    );
  }
}

String _eventsCode(Options o) {
  final cursor = o(_listenerMouseregionCursor);
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
