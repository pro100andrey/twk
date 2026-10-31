// The InputListener page.
part of 'app.dart';

/// The stage's width and the events kept.
const _iw = 46;

const _imax = 8;

final _input = GalleryPage(
  group: 'App',
  title: 'InputListener',
  build: (context, o) => const _Heard(),
  code: (o) => [
    'final _events = <(String, String)>[];',
    '',
    '/// A key as twk names it: ctrl+x, shift+tab, pageDown, space.',
    'String _name(KeyEvent key) => [',
    "  if (key.ctrl) 'ctrl',",
    "  if (key.alt) 'alt',",
    "  if (key.shift && key.code != KeyCode.char) 'shift',",
    '  switch (key) {',
    "    KeyEvent(code: KeyCode.char, char: ' ') => 'space',",
    '    KeyEvent(code: KeyCode.char, :final char) => char,',
    '    KeyEvent(:final code) => code.name,',
    '  },',
    "].join('+');",
    '',
    'bool _onEvent(InputEvent event) {',
    '  final heard = switch (event) {',
    '    KeyEvent(kind: KeyKind.release) => null,',
    "    final KeyEvent key => ('key', _name(key)),",
    '    MouseEvent(:final kind, :final x, :final y) => (',
    "      'mouse',",
    r"      '${kind.name} $x,$y',",
    '    ),',
    codeLine([
      '    PasteEvent(:final text) => ',
      r"('paste', 'of ${text.length} characters'),",
    ]),
    "    FocusEvent(:final focused) => ('focus', focused ? 'in' : 'out'),",
    '    ResizeEvent(:final width, :final height) => (',
    "      'resize',",
    r"      'to $width×$height',",
    '    ),',
    '    _ => null,',
    '  };',
    '  if (heard != null) {',
    '    setState(() {',
    '      _events.add(heard);',
    '      if (_events.length > $_imax) {',
    '        _events.removeAt(0);',
    '      }',
    '    });',
    '  }',
    '  // not taken: the listeners mounted before this one get it too',
    '  return false;',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  final styles = {',
    "    'key': theme.info,",
    "    'mouse': theme.accent,",
    "    'paste': theme.success,",
    "    'focus': theme.warning,",
    "    'resize': theme.primary,",
    '  };',
    '  return InputListener(',
    '    onEvent: _onEvent,',
    '    child: SizedBox(',
    '      width: $_iw,',
    '      child: Column(',
    '        mainAxisSize: .min,',
    '        crossAxisAlignment: .stretch,',
    '        children: [',
    '          Row(',
    '            children: [',
    '              Expanded(',
    '                child: Text(',
    "                  'Press a key nothing takes, such as x',",
    '                  style: theme.muted,',
    '                ),',
    '              ),',
    codeLine([
      '              // takes Enter and Space while it has the focus, ',
      'and its',
    ]),
    '              // clicks: none of them reach the listener',
    codeLine([
      '              ',
      "Button('Clear', onPressed: () => setState(_events.clear)),",
    ]),
    '            ],',
    '          ),',
    '          Box(',
    '            border: .all(type: .rounded, style: theme.border),',
    '            padding: const .x(1),',
    '            child: SizedBox(',
    '              height: $_imax,',
    '              child: Column(',
    '                crossAxisAlignment: .start,',
    '                children: [',
    '                  if (_events.isEmpty)',
    "                    Text('nothing yet', style: theme.muted),",
    '                  for (final (kind, what) in _events)',
    '                    Text.rich([',
    '                      Span(kind.padRight(7), styles[kind]!),',
    '                      Span(what),',
    '                    ]),',
    '                ],',
    '              ),',
    '            ),',
    '          ),',
    '        ],',
    '      ),',
    '    ),',
    '  );',
    '}',
  ].join('\n'),
);

/// A key as twk names it: ctrl+x, shift+tab, pageDown, space.
String _name(KeyEvent key) => [
  if (key.ctrl) 'ctrl',
  if (key.alt) 'alt',
  if (key.shift && key.code != KeyCode.char) 'shift',
  switch (key) {
    KeyEvent(code: KeyCode.char, char: ' ') => 'space',
    KeyEvent(code: KeyCode.char, :final char) => char,
    KeyEvent(:final code) => code.name,
  },
].join('+');

/// What an InputListener heard: its kind, what it was, its number and
/// when, in ms on the gallery's clock.
typedef _Event = (String kind, String what, int n, int at);

/// The Code's InputListener: the events no widget took, the latest
/// [_imax], each lit for a moment as it comes. They are the page's.
final class _Heard extends StatefulWidget {
  const _Heard();

  @override
  State<_Heard> createState() => _HeardState();
}

final class _HeardState extends TimedState<_Heard> {
  List<_Event> get _events => (kept['events'] ??= <_Event>[]) as List<_Event>;

  bool _onEvent(InputEvent event) {
    final heard = switch (event) {
      KeyEvent(kind: KeyKind.release) => null,
      final KeyEvent key => ('key', _name(key)),
      MouseEvent(:final kind, :final x, :final y) => (
        'mouse',
        '${kind.name} $x,$y',
      ),
      PasteEvent(:final text) => ('paste', 'of ${text.length} characters'),
      FocusEvent(:final focused) => ('focus', focused ? 'in' : 'out'),
      ResizeEvent(:final width, :final height) => (
        'resize',
        'to $width×$height',
      ),
      _ => null,
    };
    if (heard != null && mounted) {
      setState(() {
        final n = ((kept['n'] ?? 0) as int) + 1;
        kept['n'] = n;
        _events.add((heard.$1, heard.$2, n, clockNow));
        if (_events.length > _imax) {
          _events.removeAt(0);
        }
      });
    }
    // not taken: the listeners mounted before this one get it too
    return false;
  }

  @override
  Widget buildTimed(BuildContext context) {
    final theme = Theme.of(context);
    final styles = {
      'key': theme.info,
      'mouse': theme.accent,
      'paste': theme.success,
      'focus': theme.warning,
      'resize': theme.primary,
    };
    return InputListener(
      onEvent: _onEvent,
      child: SizedBox(
        width: _iw,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Press a key nothing takes, such as x',
                    style: theme.muted,
                  ),
                ),
                // takes Enter and Space while it has the focus, and its
                // clicks: none of them reach the listener
                Button(
                  'Clear',
                  onPressed: () => setState(_events.clear),
                ),
              ],
            ),
            Box(
              border: Border.all(type: BorderType.rounded, style: theme.border),
              child: SizedBox(
                height: _imax,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_events.isEmpty)
                      Padding(
                        padding: const EdgeInsets.x(1),
                        child: Text('nothing yet', style: theme.muted),
                      ),
                    for (final (kind, what, n, at) in _events)
                      // the row lit for a moment as the event comes
                      Box(
                        key: ValueKey(n),
                        style: lit(litAt(at)),
                        padding: const EdgeInsets.x(1),
                        child: Text.rich([
                          Span(kind.padRight(7), styles[kind]!),
                          Span(what),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
