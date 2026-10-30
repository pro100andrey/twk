// The App group of the gallery.
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../page.dart';
import '../paint.dart';
import '../shell/tokens.dart';
import 'cli_code.dart';
import 'cli_stage.dart' if (dart.library.js_interop) 'cli_stage_web.dart';
import 'common.dart' show TimedState, codeLine;

/// The pages of the App group that draw.
final List<GalleryPage> appPages = [
  _input,
  _error,
  _static,
  _progress,
  _viewport,
  _windowTitle,
  _notifications,
  _cli,
];

/// The cells of [free] that flexible children of [flexes] take, as twk's
/// Flex shares them: each its part rounded down, the cells left over one
/// each to the first ones.
List<int> _share(int free, List<int> flexes) {
  final total = flexes.fold(0, (n, f) => n + f);
  final out = [for (final f in flexes) free * f ~/ total];
  var left = free - out.fold(0, (n, s) => n + s);
  for (var i = 0; i < out.length && left > 0; i++, left--) {
    out[i]++;
  }
  return out;
}

// ------------------------------------------------------------ InputListener

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

// ------------------------------------------------------------ ErrorWidget

/// The cards' row.
const _ew = 50;
const _eh = 5;

/// What the weather throws, by the option's name: the Code's expression.
const _errors = {
  'StateError': "StateError('the weather failed to load')",
  'FormatException': "FormatException('not a date', '2026-13-01')",
  'Exception': "Exception('the weather failed to load')",
};

/// A new cpu load this often.
const _loadMs = 600;

/// The loads the cpu card shows, a column each.
final int _loads = _share(_ew - 2, const [1, 2, 1])[0] - 4;

/// The cpu's load at step [i]: a wave and noise, from 4 to 96.
double _loadAt(int i) {
  final s = math.sin(i * 78.233 + 1.7) * 43758.5453;
  final noise = s - s.floorToDouble();
  return (40 + 16 * math.sin(i / 2.3) + 34 * (noise - 0.5))
      .clamp(4, 96)
      .roundToDouble();
}

final _error = GalleryPage(
  group: 'App',
  title: 'ErrorWidget',
  options: [
    const SwitchOption('fails', 'weather fails', initial: true),
    ChoiceOption('error', 'what it throws', values: _errors.keys.toList()),
  ],
  build: (context, o) =>
      _Cards(fails: o.flag('fails'), error: o.choice<String>('error')),
  code: (o) {
    final thrown = _errors[o.choice<String>('error')]!;
    final build = o.flag('fails')
        ? [
            '  // throws: the app shows an ErrorWidget in its place, as',
            '  // ErrorWidget($thrown) would,',
            codeLine([
              '  // and logs the error with the path of the widget ',
              'at LogLevel.error',
            ]),
            '  @override',
            '  Widget build(BuildContext context) =>',
            '      throw $thrown;',
          ]
        : [
            '  @override',
            '  Widget build(BuildContext context) => Column(',
            '    crossAxisAlignment: .start,',
            '    children: [',
            "      const Text('12°C', style: Style(attrs: Attr.bold)),",
            "      const Text('light rain'),",
            "      Text('wind 14 km/h', style: Theme.of(context).muted),",
            '    ],',
            '  );',
          ];
    return [
      "/// The weather card's content.",
      'final class _Weather extends StatelessWidget {',
      '  const _Weather();',
      '',
      ...build,
      '}',
      '',
      "/// The cpu's load at step [i]: a wave and noise, from 4 to 96.",
      'static double _loadAt(int i) {',
      '  final s = sin(i * 78.233 + 1.7) * 43758.5453;',
      '  final noise = s - s.floorToDouble();',
      '  return (40 + 16 * sin(i / 2.3) + 34 * (noise - 0.5))',
      '      .clamp(4, 96)',
      '      .roundToDouble();',
      '}',
      '',
      '// the last $_loads loads, a new one every $_loadMs ms',
      'var _step = 0;',
      'var _load = [for (var i = ${1 - _loads}; i <= 0; i++) _loadAt(i)];',
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_loadMs),',
      codeLine([
        '    (_) => ',
        'setState(() => _load = [..._load.skip(1), _loadAt(++_step)]),',
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
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  const bold = Style(attrs: Attr.bold);',
      codeLine([
        '  Widget card(String title, Widget child, {int flex = 1}) => ',
        'Expanded(',
      ]),
      '    flex: flex,',
      '    child: Box(',
      '      border: .all(type: .rounded, style: theme.border),',
      r"      titles: [BorderTitle(' $title ')],",
      '      padding: const .x(1),',
      '      child: child,',
      '    ),',
      '  );',
      '  return SizedBox(',
      '    width: $_ew,',
      '    height: $_eh,',
      '    child: Row(',
      '      crossAxisAlignment: .stretch,',
      '      gap: 1,',
      '      children: [',
      '        card(',
      "          'cpu',",
      '          Column(',
      '            crossAxisAlignment: .stretch,',
      '            children: [',
      r"              Text('${_load.last.round()}%', style: bold),",
      '              Expanded(',
      codeLine([
        '                child: ',
        'Sparkline(data: _load, max: 100, style: theme.primary),',
      ]),
      '              ),',
      '            ],',
      '          ),',
      '        ),',
      "        card('weather', const _Weather(), flex: 2),",
      '        card(',
      "          'disk',",
      '          Column(',
      '            crossAxisAlignment: .stretch,',
      '            children: [',
      "              const Text('61%', style: bold),",
      '              LineGauge(',
      '                ratio: 0.61,',
      "                label: '',",
      '                type: .heavy,',
      '                filledStyle: theme.primary,',
      '                unfilledStyle: theme.border,',
      '              ),',
      "              Text('512 GB', style: theme.muted),",
      '            ],',
      '          ),',
      '        ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The weather card's content: what the Code's builds, or a throw of
/// [error] (its option's name) when [fails].
final class _Weather extends StatelessWidget {
  const _Weather({required this.fails, required this.error});

  final bool fails;
  final String error;

  @override
  Widget build(BuildContext context) {
    if (fails) {
      // throws: the app shows an ErrorWidget in its place
      switch (error) {
        case 'FormatException':
          throw const FormatException('not a date', '2026-13-01');
        case 'Exception':
          throw Exception('the weather failed to load');
        default:
          throw StateError('the weather failed to load');
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('12°C', style: Style(attrs: Attr.bold)),
        const Text('light rain'),
        Text('wind 14 km/h', style: Theme.of(context).muted),
      ],
    );
  }
}

/// The Code's three cards, the cpu's load on the gallery's clock.
final class _Cards extends StatefulWidget {
  const _Cards({required this.fails, required this.error});

  final bool fails;
  final String error;

  @override
  State<_Cards> createState() => _CardsState();
}

final class _CardsState extends TimedState<_Cards> {
  @override
  Widget buildTimed(BuildContext context) {
    final theme = Theme.of(context);
    const bold = Style(attrs: Attr.bold);
    final step = now ~/ _loadMs;
    wake((step + 1) * _loadMs);
    final load = [for (var i = step + 1 - _loads; i <= step; i++) _loadAt(i)];
    Widget card(String title, Widget child, {int flex = 1}) => Expanded(
      flex: flex,
      child: Box(
        border: Border.all(type: BorderType.rounded, style: theme.border),
        titles: [BorderTitle(' $title ')],
        padding: const EdgeInsets.x(1),
        child: child,
      ),
    );
    return SizedBox(
      width: _ew,
      height: _eh,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        gap: 1,
        children: [
          card(
            'cpu',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${load.last.round()}%', style: bold),
                Expanded(
                  child: Sparkline(data: load, max: 100, style: theme.primary),
                ),
              ],
            ),
          ),
          card(
            'weather',
            _Weather(fails: widget.fails, error: widget.error),
            flex: 2,
          ),
          card(
            'disk',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('61%', style: bold),
                LineGauge(
                  ratio: 0.61,
                  label: '',
                  type: BorderType.heavy,
                  filledStyle: theme.primary,
                  unfilledStyle: theme.border,
                ),
                Text('512 GB', style: theme.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------- the terminal around an app

/// The stage of a page that draws a terminal around its app: [under], the
/// terminal [width] × [height]; the app at [at] (x, y, w, h), when it
/// shows; [over], what is drawn over them, such as a background lit
/// under the app's text.
Widget _terminal({
  required int width,
  required int height,
  required void Function(Painter p) under,
  Widget? app,
  (int, int, int, int)? at,
  void Function(Painter p)? over,
}) => SizedBox(
  width: width,
  height: height,
  child: Stack(
    children: [
      CellPaint(under, width: width, height: height),
      if (app != null && at != null)
        Positioned(
          left: at.$1,
          top: at.$2,
          width: at.$3,
          height: at.$4,
          child: CodeApp(child: app),
        ),
      if (over != null)
        CellPaint(over, width: width, height: height, hit: false),
    ],
  ),
);

/// A rounded box's border at [x], [y], [w] × [h] in [fg], with [title]
/// on its top edge after the corner in [titleFg] (the border's where
/// null), as twk's Box draws a BorderTitle.
void _box(
  Painter p,
  int x,
  int y,
  int w,
  int h,
  Color fg, {
  String? title,
  Color? titleFg,
}) {
  if (w < 2 || h < 2) {
    return;
  }
  final s = Style(fg: fg);
  p
    ..text(x, y, '╭', s)
    ..text(x + w - 1, y, '╮', s)
    ..text(x, y + h - 1, '╰', s)
    ..text(x + w - 1, y + h - 1, '╯', s)
    ..hline(x + 1, y, w - 2, fg, '─')
    ..hline(x + 1, y + h - 1, w - 2, fg, '─')
    ..vline(x, y + 1, h - 2, fg, '│')
    ..vline(x + w - 1, y + 1, h - 2, fg, '│');
  if (title != null) {
    p.text(x + 1, y, ' $title ', Style(fg: titleFg ?? fg), max: w - 2);
  }
}

/// Spans of text and their style, drawn one after another from [x], at
/// most [max] columns; returns the columns they take.
int _spans(Painter p, int x, int y, List<(String, Style)> spans, int max) {
  var cx = x;
  for (final (text, style) in spans) {
    final left = x + max - cx;
    if (left <= 0) {
      break;
    }
    cx += p.text(cx, y, text, style, max: left);
  }
  return cx - x;
}

/// The shell's prompt, then [cmd].
List<(String, Style)> _prompt(Tokens t, String cmd) => [
  (r'$ ', Style(fg: t.success)),
  (cmd, Style(fg: t.text)),
];

/// The terminal's cursor's blink.
const _blink = 530;

/// The terminal's cursor, a blinking block, at [x], [y], at [now] ms;
/// asks for a build when it blinks.
void _blinking(
  Painter p,
  Tokens t,
  int x,
  int y,
  int now,
  void Function(int) wake,
) {
  final k = now ~/ _blink;
  wake((k + 1) * _blink);
  if (k.isEven) {
    p.fill(x, y, 1, 1, Style(bg: t.text));
  }
}

/// The background of a strip of the terminal's window: the surface, a
/// shade nearer the background on a dark theme.
Color _strip(Tokens t) =>
    t.dark ? mix(t.background, t.surface, 0.9) : t.surface;

/// twk's LineGauge without a label: a line filled from the left to the
/// nearest half cell.
void _lineGauge(
  Painter p,
  int x,
  int y,
  int w,
  double ratio,
  Color filled,
  Color unfilled,
) {
  final halves = (ratio.clamp(0, 1) * w * 2).round();
  final full = halves >> 1;
  for (var i = 0; i < w; i++) {
    if (i < full) {
      p.text(x + i, y, '━', Style(fg: filled));
    } else if (i == full && halves.isOdd) {
      p.text(x + i, y, '╸', Style(fg: filled));
    } else {
      p.text(x + i, y, '━', Style(fg: unfilled));
    }
  }
}

/// The frame of [frames], stepping each [ms], at [now] ms; asks for a
/// build at the next step.
String _frame(List<String> frames, int ms, int now, void Function(int) wake) {
  final step = now ~/ ms;
  wake((step + 1) * ms);
  return frames[step % frames.length];
}

// ------------------------------------------------------------ Static

const _doing = [
  'resolving packages',
  'compiling',
  'running tests',
  'writing build/app.js',
];
const _did = [
  'resolved 42 packages',
  'compiled 118 libraries',
  'ran 214 tests',
  'wrote build/app.js',
];

/// A step of the build; the pause after it ends, before it runs again.
const _stepMs = 800;
const _pause = 2000;

/// A run of the build: the app quits on the tick after the last item.
const int _run = (4 + 1) * _stepMs + _pause;
const _cmd = 'dart run tool/build.dart';

/// The terminal.
const _tw = 44;
const _th = 10;

final _static = GalleryPage(
  terminalAround: true,
  group: 'App',
  title: 'Static',
  options: const [
    ChoiceOption('mode', 'mode', values: ['inline', 'fullscreen']),
  ],
  build: (context, o) => _StaticRun(inline: o.label('mode') == 'inline'),
  code: (o) {
    final inline = o.label('mode') == 'inline';
    return [
      "import 'dart:async';",
      '',
      "import 'package:twk/twk.dart';",
      '',
      if (inline)
        'void main() => runApp(const Build(), mode: ScreenMode.inline);'
      else
        'void main() => runApp(const Build());',
      '',
      'final class Build extends StatefulWidget {',
      '  const Build({super.key});',
      '',
      '  @override',
      '  State<Build> createState() => _BuildState();',
      '}',
      '',
      'final class _BuildState extends State<Build> {',
      '  static const _doing = [',
      for (final d in _doing) "    '$d',",
      '  ];',
      '  static const _did = [',
      for (final d in _did) "    '$d',",
      '  ];',
      '',
      '  // the steps done, each shown once: finished output',
      '  final _done = <String>[];',
      '  Timer? _timer;',
      '',
      '  @override',
      '  void initState() {',
      '    super.initState();',
      codeLine([
        '    _timer = Timer.periodic(',
        'const Duration(milliseconds: $_stepMs), (_) => _step());',
      ]),
      '  }',
      '',
      '  void _step() {',
      '    if (_done.length == _did.length) {',
      '      // a tick after the last item: the frame that built it wrote it',
      '      _timer?.cancel();',
      '      AppBinding.of(context).quit();',
      '      return;',
      '    }',
      '    setState(() => _done.add(_did[_done.length]));',
      '  }',
      '',
      '  @override',
      '  void dispose() {',
      '    _timer?.cancel();',
      '    super.dispose();',
      '  }',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    final theme = Theme.of(context);',
      '    return Column(',
      '      crossAxisAlignment: .start,',
      '      children: [',
      if (inline)
        "        // each item goes to the terminal's history, above the region"
      else
        codeLine([
          '        // shown in place, ',
          'gone with the alternate screen when the app ends',
        ]),
      '        Static<String>(',
      '          items: _done,',
      '          builder: (context, step) =>',
      "              Text.rich([Span('✓ ', theme.success), Span(step)]),",
      '        ),',
      '        if (_done.length < _did.length)',
      '          Row(',
      '            gap: 1,',
      '            children: [',
      '              const Spinner(),',
      r"              Text('${_doing[_done.length]}…'),",
      codeLine([
        '              ',
        r"Text(' ${_done.length + 1}/${_did.length}', style: theme.muted),",
      ]),
      '            ],',
      '          ),',
      '      ],',
      '    );',
      '  }',
      '}',
    ].join('\n');
  },
);

/// A row of the terminal: its spans, and when it was lit, an item of the
/// Static as it was built.
typedef _Row = (List<(String, Style)> spans, int? at);

/// The Code's build, again and again on the gallery's clock, in a
/// terminal: in the [inline] mode its items go to the history above the
/// region, else they show in place on the alternate screen.
final class _StaticRun extends StatefulWidget {
  const _StaticRun({required this.inline});

  final bool inline;

  @override
  State<_StaticRun> createState() => _StaticRunState();
}

final class _StaticRunState extends TimedState<_StaticRun> {
  @override
  Widget buildTimed(BuildContext context) {
    final t = Tokens(Theme.of(context));
    final theme = Theme.of(context);
    final inline = widget.inline;
    final ms = now;
    final r = ms ~/ _run;
    final u = ms - r * _run;
    final done = math.min(_did.length, u ~/ _stepMs);
    final busy = done < _did.length;
    final running = u < (_did.length + 1) * _stepMs;
    wake(r * _run + (running ? (done + 1) * _stepMs : _run));

    List<(String, Style)> item(int i) => [
      ('✓ ', Style(fg: t.success)),
      (_did[i], Style(fg: t.text)),
    ];
    final rows = <_Row>[];
    final String screen;
    if (inline || !running) {
      // the normal screen: what was before, and in the inline mode the
      // items of each run, written above the region into the history
      rows
        ..add((_prompt(t, 'git pull'), null))
        ..add(([('Already up to date.', Style(fg: t.text))], null));
      for (var k = 0; k <= r; k++) {
        rows.add((_prompt(t, _cmd), null));
        if (inline) {
          final n = k < r ? _did.length : done;
          for (var i = 0; i < n; i++) {
            rows.add((item(i), k == r ? r * _run + (i + 1) * _stepMs : null));
          }
        }
      }
      screen = 'normal screen';
    } else {
      // the alternate screen: the app's alone, the items in place
      for (var i = 0; i < done; i++) {
        rows.add((item(i), r * _run + (i + 1) * _stepMs));
      }
      screen = 'alternate screen';
    }
    // the region: the step that runs; none once the last item is written;
    // the shell's prompt once the app ended
    int? cursorRow;
    if (busy) {
      rows.add((const [], null));
    } else if (!running) {
      rows.add((_prompt(t, ''), null));
      cursorRow = rows.length - 1;
    }
    const ih = _th - 2;
    final from = math.max(0, rows.length - ih);
    final shown = rows.sublist(from);
    // the app's rows: the alternate screen's all, or in the inline mode
    // the items of this run and the step that runs
    final own = !running
        ? 0
        : inline
        ? done + (busy ? 1 : 0)
        : ih;
    final appY = inline ? 1 + shown.length - own : 1;

    void under(Painter p) {
      _box(p, 0, 0, _tw, _th, t.border, title: 'terminal', titleFg: t.muted);
      p.text(
        _tw - 2 - widthOf(screen) - 2,
        _th - 1,
        ' $screen ',
        Style(fg: t.muted),
      );
      // the rows the app draws in, marked at the terminal's edge
      if (running && (busy || !inline)) {
        final (a, b) = inline ? (shown.length, shown.length) : (1, ih);
        for (var y = a; y <= b; y++) {
          p.text(0, y, '┃', Style(fg: t.primary));
        }
        _spans(p, 1, _th - 1, [
          (' ┃', Style(fg: t.primary)),
          (' the app ', Style(fg: t.muted)),
        ], _tw);
      }
      for (var i = 0; i < shown.length; i++) {
        final y = 1 + i;
        if (own > 0 && y >= appY && y < appY + own) {
          continue;
        }
        final w = _spans(p, 2, y, shown[i].$1, _tw - 4);
        if (from + i == cursorRow) {
          _blinking(p, t, 2 + w, y, ms, wake);
        }
      }
    }

    void over(Painter p) {
      // an item of the Static, lit for a moment as it is built
      for (var i = 0; i < shown.length; i++) {
        final k = litAt(shown[i].$2, 700);
        if (k > 0) {
          p.bg(1, 1 + i, _tw - 2, 1, mix(t.background, t.selection, k));
        }
      }
    }

    return _terminal(
      width: _tw,
      height: _th,
      under: under,
      over: over,
      at: own > 0 ? (2, appY, _tw - 4, own) : null,
      app: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // a run's own: its items shown once each
          Static<String>(
            key: ValueKey(r),
            items: _did.sublist(0, done),
            builder: (context, step) =>
                Text.rich([Span('✓ ', theme.success), Span(step)]),
          ),
          if (busy)
            Row(
              gap: 1,
              children: [
                const Spinner(),
                Text('${_doing[done]}…'),
                Text(' ${done + 1}/${_did.length}', style: theme.muted),
              ],
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ TerminalProgress

/// The window, and the app's tab in it.
const _pw = 46;
const _ph = 8;
const _tab = 14;

/// TerminalStatus.progressRefresh, in ms.
const _refresh = 10000;

/// What puts the progress away.
const _takenAway = r'ESC]9;4;0ESC\';

/// The pie the tab shows of how much is done.
const _pie = ['○', '◔', '◑', '◕', '●'];

/// The arc spinner's frames, stepping each 100 ms.
const _arc = ['◜', '◠', '◝', '◞', '◡', '◟'];

/// What TerminalStatus wrote last, as the page's widget saw it: what the
/// Code tab writes.
String? _progressWrote;

/// The progress of the options: the state shown (normal without a value
/// is indeterminate), its percent, and the OSC 9;4 that shows it, null
/// for none.
(String, int?, String?) _progressOf(Options o) {
  final value = o.flag('known') ? o.number('value') / 100 : null;
  final state = o.label('state') == 'normal' && value == null
      ? 'indeterminate'
      : o.label('state');
  final percent = value == null
      ? null
      : value >= 1
      ? 100
      : value > 0
      ? (value * 100).round()
      : 0;
  final code = ProgressState.values.firstWhere((s) => s.name == state).index;
  final p = percent == null || state == 'indeterminate' ? '' : ';$percent';
  return (state, percent, state == 'none' ? null : 'ESC]9;4;$code${p}ESC\\');
}

/// [v] as JavaScript writes a number: no trailing zeros.
String _number(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

final _progress = GalleryPage(
  terminalAround: true,
  group: 'App',
  title: 'TerminalProgress',
  options: [
    const ChoiceOption(
      'state',
      'state',
      values: ['none', 'normal', 'error', 'indeterminate', 'paused'],
      initial: 'normal',
    ),
    const SwitchOption('known', 'value known', initial: true),
    SliderOption(
      'value',
      'value',
      min: 0,
      max: 100,
      initial: 33,
      format: (v) => '$v%',
    ),
    const SwitchOption('shows', 'terminal shows it', initial: true),
  ],
  build: (context, o) => _Progress(options: o),
  code: (o) {
    final known = o.flag('known');
    final v = known ? _number(o.number('value') / 100) : null;
    final value = known ? '${o.label('value')}%' : 'not known';
    final w = _progressWrote;
    final wrote = w == null
        ? null
        : [
            for (final part in w.split(RegExp('(?=ESC)|(?<=ESC)')))
              if (part.isNotEmpty) part,
          ];
    return [
      '// written where the terminal is known to show it (OSC 9;4,',
      codeLine([
        '// TerminalInfo.progressReports): when what is shown changes, ',
        'and every',
      ]),
      '// 10 s while it does not; taken away when it leaves the tree',
      'final theme = Theme.of(context);',
      'return TerminalProgress(',
      '  state: .${o.label('state')},',
      if (v != null) '  value: $v,',
      '  child: Column(',
      '    crossAxisAlignment: .start,',
      '    children: [',
      "      const Text('In the tab: ${o.label('state')}, $value'),",
      '      Text.rich([',
      "        Span('wrote: ', theme.muted),",
      if (wrote == null)
        "        Span('nothing', theme.muted),"
      else
        for (final x in wrote)
          if (x == 'ESC')
            "        Span('ESC', theme.muted),"
          else
            '        const Span(${x.contains(r'\') ? "r'$x'" : "'$x'"}),',
      '      ]),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);

/// The Code's TerminalProgress in a terminal's window whose tab shows it,
/// and what TerminalStatus wrote, as the options say.
final class _Progress extends StatefulWidget {
  const _Progress({required this.options});

  final Options options;

  @override
  State<_Progress> createState() => _ProgressState();
}

final class _ProgressState extends TimedState<_Progress> {
  /// What TerminalStatus wrote last for the options as they are now:
  /// where the terminal shows a progress, one when it changes and again
  /// every 10 s while it does not, ESC]9;4;0ESC\ once one shown is taken
  /// away; nothing where it shows none. Moving the value makes it known.
  String? _written() {
    final o = widget.options;
    final value = o.number('value');
    if (kept['value'] != null && kept['value'] != value && !o.flag('known')) {
      final control = PageControl.of(context);
      AppBinding.maybeOf(
        context,
      )?.scheduleFrameCallback((_) => control.setOption('known', true));
    }
    kept['value'] = value;
    final seq = _progressOf(o).$3;
    if (!o.flag('shows')) {
      kept
        ..['shown'] = null
        ..['wrote'] = null
        ..['at'] = null;
    } else if (seq != kept['shown']) {
      final write = seq ?? (kept['shown'] != null ? _takenAway : null);
      kept['shown'] = seq;
      if (write != null) {
        kept
          ..['wrote'] = write
          ..['at'] = now
          ..['litAt'] = now;
      }
    } else if (seq != null && kept['at'] != null) {
      var at = kept['at']! as int;
      final n = (now - at) ~/ _refresh;
      if (n > 0) {
        at += n * _refresh;
        kept
          ..['at'] = at
          ..['litAt'] = at;
      }
      wake(at + _refresh);
    }
    return _progressWrote = kept['wrote'] as String?;
  }

  @override
  Widget buildTimed(BuildContext context) {
    final t = Tokens(Theme.of(context));
    final theme = Theme.of(context);
    final o = widget.options;
    final (state, percent, _) = _progressOf(o);
    final wrote = _written();
    final shown = o.flag('shows') && state != 'none';
    final color = switch (state) {
      'error' => t.error,
      'paused' => t.warning,
      _ => t.primary,
    };
    final ms = now;
    final value = o.flag('known') ? '${o.label('value')}%' : 'not known';
    final lit = litAt(kept['litAt'] as int?);

    void under(Painter p) {
      // the terminal's window: its tabs, the app's lit with its progress;
      // without a value, error and paused show the bar full in their colour
      _box(p, 0, 0, _pw, _ph, t.border);
      final strip = _strip(t);
      p
        ..fill(1, 1, _pw - 2, 2, Style(bg: strip))
        ..fill(1, 1, _tab, 2, Style(bg: t.background));
      final full = percent ?? 100;
      var icon = ' ';
      if (shown && state == 'indeterminate') {
        icon = _frame(_arc, 100, ms, wake);
      } else if (shown) {
        icon =
            _pie[full >= 100
                ? 4
                : full <= 0
                ? 0
                : full < 38
                ? 1
                : full < 63
                ? 2
                : 3];
      }
      p
        ..text(2, 1, icon, Style(fg: color, bg: t.background))
        ..text(4, 1, 'build', Style(fg: t.text, attrs: Attr.bold));
      if (shown && state != 'indeterminate' && percent != null) {
        final pc = '$percent%';
        p.text(_tab - widthOf(pc), 1, pc, Style(fg: t.muted));
      }
      if (shown) {
        const gx = 2;
        const gw = _tab - 2;
        final track = mix(t.background, t.border, 0.6);
        if (state == 'indeterminate') {
          // a block going from one end to the other and back
          p.hline(gx, 2, gw, track, '━');
          final step = ms ~/ 50;
          const bw = gw >> 2;
          const room = gw - bw;
          final ph = step % (2 * room);
          p.hline(gx + (ph <= room ? ph : 2 * room - ph), 2, bw, color, '━');
          wake((step + 1) * 50);
        } else {
          _lineGauge(p, gx, 2, gw, full / 100, color, track);
        }
      }
      p.text(1 + _tab + 2, 1, 'zsh', Style(fg: t.muted, bg: strip));
    }

    void over(Painter p) {
      if (lit > 0) {
        p.bg(
          10,
          5,
          wrote == null ? 7 : widthOf(wrote),
          1,
          mix(t.background, t.selection, lit),
        );
      }
    }

    return _terminal(
      width: _pw,
      height: _ph,
      under: under,
      over: over,
      at: (3, 4, _pw - 6, 2),
      app: TerminalProgress(
        state: ProgressState.values.byName(o.label('state')),
        value: o.flag('known') ? o.number('value') / 100 : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('In the tab: ${o.label('state')}, $value'),
            Text.rich([
              Span('wrote: ', theme.muted),
              if (wrote == null)
                Span('nothing', theme.muted)
              else
                for (final part in wrote.split(RegExp('(?=ESC)|(?<=ESC)')))
                  if (part.isNotEmpty)
                    Span(part, part == 'ESC' ? theme.muted : const Style()),
            ]),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ Viewport

/// A build in steps, done one a tick, as on the Static page.
const _steps = ['resolving', 'compiling', 'testing', 'writing'];

/// The terminal's screen, and the app's rectangle in it.
const int _sw = _tw - 4;
const int _sh = _th - 2;
const _vw = 20;
const _vh = 4;
const int _vrun = (4 + 1) * _stepMs + _pause;

final _viewport = GalleryPage(
  terminalAround: true,
  group: 'App',
  title: 'Viewport',
  options: const [
    SliderOption('left', 'left', min: 0, max: _sw - _vw, initial: _sw - _vw),
    SliderOption('top', 'top', min: 0, max: _sh - _vh),
    ChoiceOption('mode', 'mode', values: ['inline', 'fullscreen']),
  ],
  build: (context, o) => _ViewportRun(
    left: o.number('left').toInt(),
    top: o.number('top').toInt(),
    inline: o.label('mode') == 'inline',
  ),
  code: (o) {
    final inline = o.label('mode') == 'inline';
    final at = '${o.label('left')}, ${o.label('top')}, $_vw, $_vh';
    return [
      "import 'dart:async';",
      '',
      "import 'package:twk/twk.dart';",
      '',
      codeLine([
        '// the $_vw × $_vh cells from column ${o.label('left')} ',
        'of row ${o.label('top')}: nothing else is',
      ]),
      if (inline)
        '// written, so what the terminal showed around them stays'
      else
        '// written, on the alternate screen',
      if (inline) ...[
        'void main() => runApp(',
        '  const Build(),',
        '  mode: ScreenMode.inline,',
        '  viewport: const Viewport.fixed($at),',
        ');',
      ] else ...[
        'void main() =>',
        codeLine([
          '    runApp(const Build(), ',
          'viewport: const Viewport.fixed($at));',
        ]),
      ],
      '',
      'final class Build extends StatefulWidget {',
      '  const Build({super.key});',
      '',
      '  @override',
      '  State<Build> createState() => _BuildState();',
      '}',
      '',
      'final class _BuildState extends State<Build> {',
      "  static const _steps = [${_steps.map((x) => "'$x'").join(', ')}];",
      '',
      '  var _done = 0;',
      '  Timer? _timer;',
      '',
      '  @override',
      '  void initState() {',
      '    super.initState();',
      codeLine([
        '    _timer = Timer.periodic(',
        'const Duration(milliseconds: $_stepMs), (_) => _step());',
      ]),
      '  }',
      '',
      '  void _step() {',
      '    if (_done == _steps.length) {',
      if (inline)
        '      // a tick after the last step: its frame stays in the cells'
      else
        '      // a tick after the last step: the frame that showed it was drawn',
      '      _timer?.cancel();',
      '      AppBinding.of(context).quit();',
      '      return;',
      '    }',
      '    setState(() => _done++);',
      '  }',
      '',
      '  @override',
      '  void dispose() {',
      '    _timer?.cancel();',
      '    super.dispose();',
      '  }',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    final theme = Theme.of(context);',
      '    final busy = _done < _steps.length;',
      "    // laid out at the viewport's size, as a full screen of it",
      '    return Box(',
      '      border: .all(type: .rounded, style: theme.border),',
      "      titles: const [BorderTitle(' build ')],",
      '      padding: const .x(1),',
      '      child: Column(',
      '        crossAxisAlignment: .start,',
      '        children: [',
      '          if (busy)',
      codeLine([
        '            Row(gap: 1, children: ',
        r"[const Spinner(), Text('${_steps[_done]}…')])",
      ]),
      '          else',
      codeLine([
        '            ',
        "Text.rich([Span('✓ ', theme.success), const Span('built')]),",
      ]),
      '          Text(',
      r"            '${busy ? _done + 1 : _done}/${_steps.length}',",
      '            style: theme.muted,',
      '          ),',
      '        ],',
      '      ),',
      '    );',
      '  }',
      '}',
    ].join('\n');
  },
);

/// The Code's Build at [done] steps.
Widget _buildBox(ThemeData theme, int done) {
  final busy = done < _steps.length;
  return Box(
    border: Border.all(type: BorderType.rounded, style: theme.border),
    titles: const [BorderTitle(' build ')],
    padding: const EdgeInsets.x(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy)
          Row(gap: 1, children: [const Spinner(), Text('${_steps[done]}…')])
        else
          Text.rich([Span('✓ ', theme.success), const Span('built')]),
        Text('${busy ? done + 1 : done}/${_steps.length}', style: theme.muted),
      ],
    ),
  );
}

/// The Code's build, again and again on the gallery's clock, in the
/// viewport at [left], [top] of a terminal, around what the shell showed
/// ([inline]) or on the alternate screen.
final class _ViewportRun extends StatefulWidget {
  const _ViewportRun({
    required this.left,
    required this.top,
    required this.inline,
  });

  final int left;
  final int top;
  final bool inline;

  @override
  State<_ViewportRun> createState() => _ViewportRunState();
}

final class _ViewportRunState extends TimedState<_ViewportRun> {
  @override
  Widget buildTimed(BuildContext context) {
    final t = Tokens(Theme.of(context));
    final ms = now;
    final r = ms ~/ _vrun;
    final u = ms - r * _vrun;
    final done = math.min(_steps.length, u ~/ _stepMs);
    final running = u < (_steps.length + 1) * _stepMs;
    wake(r * _vrun + (running ? (done + 1) * _stepMs : _vrun));
    final alternate = running && !widget.inline;
    final shows = running || widget.inline;
    const sx = 2;
    const sy = 1;
    final ax = sx + widget.left;
    final ay = sy + widget.top;
    // what the shell showed when the app started, the cursor on the line
    // below the command: on the normal screen, written around the app
    final shell = [
      _prompt(t, 'git log --oneline -3'),
      [('67bc09f Add the pages the design lacks', Style(fg: t.text))],
      [('30f691a Make the design pages consistent', Style(fg: t.text))],
      [('8234979 Design the Editing pages', Style(fg: t.text))],
      _prompt(t, _cmd),
    ];

    void under(Painter p) {
      _box(p, 0, 0, _tw, _th, t.border, title: 'terminal', titleFg: t.muted);
      final screen = alternate ? 'alternate screen' : 'normal screen';
      p.text(
        _tw - 2 - widthOf(screen) - 2,
        _th - 1,
        ' $screen ',
        Style(fg: t.muted),
      );
      if (!alternate) {
        for (var y = 0; y < shell.length; y++) {
          _spans(p, sx, sy + y, shell[y], _sw);
        }
      }
      // the app's rectangle: its frames, which cover what was there
      if (shows) {
        p.fill(ax, ay, _vw, _vh, Style(fg: t.text));
      }
      // the cursor back where the app found it, where the shell goes on
      if (!running) {
        final y = sy + shell.length;
        final w = _spans(p, sx, y, _prompt(t, ''), _sw);
        _blinking(p, t, sx + w, y, ms, wake);
      }
    }

    return _terminal(
      width: _tw,
      height: _th,
      under: under,
      at: shows ? (ax, ay, _vw, _vh) : null,
      app: _buildBox(Theme.of(context), done),
    );
  }
}

// ------------------------------------------------------------ Window title

/// The window.
const _ww = 46;
const _wh = 7;

/// What the user's shell set.
const _userTitle = 'user@twk: ~/twk';

final _windowTitle = GalleryPage(
  terminalAround: true,
  group: 'App',
  title: 'Window title',
  options: const [
    ChoiceOption(
      'title',
      'title',
      values: ['twk gallery', 'build: 3 of 5', 'chat · ~/project'],
    ),
    SwitchOption('running', 'app running', initial: true),
  ],
  build: (context, o) =>
      _Titled(title: o.choice<String>('title'), running: o.flag('running')),
  code: (o) => [
    "// the title of the terminal's window or tab while this is in the",
    codeLine([
      '// tree, set again when it changes: ',
      'of nested ones the innermost, as',
    ]),
    "// Flutter's Title. The user's own comes back when the app ends.",
    'return WindowTitle(',
    "  title: '${o.label('title')}',",
    "  child: const Text('In the title bar: ${o.label('title')}'),",
    ');',
  ].join('\n'),
);

/// A terminal's window whose title bar shows [title] while the app runs,
/// the user's own once it ended; the app, a real WindowTitle.
final class _Titled extends StatefulWidget {
  const _Titled({required this.title, required this.running});

  final String title;
  final bool running;

  @override
  State<_Titled> createState() => _TitledState();
}

final class _TitledState extends TimedState<_Titled> {
  @override
  Widget buildTimed(BuildContext context) {
    final t = Tokens(Theme.of(context));
    final ms = now;
    // the title the terminal shows: the app's while it runs, the user's
    // own once it ended
    final title = widget.running ? widget.title : _userTitle;
    if (title != kept['title']) {
      if (kept['title'] != null) {
        kept['titleAt'] = ms;
      }
      kept['title'] = title;
    }
    final k = litAt(kept['titleAt'] as int?);

    void under(Painter p) {
      // the terminal's window: its title bar, the title in its middle
      _box(p, 0, 0, _ww, _wh, t.border);
      final bar = _strip(t);
      final lit = k > 0 ? mix(bar, t.selection, k) : bar;
      p.fill(1, 1, _ww - 2, 1, Style(bg: lit));
      final shown = cut(title, _ww - 6);
      p.text(
        (_ww - widthOf(shown)) >> 1,
        1,
        shown,
        Style(fg: t.text, bg: lit, attrs: Attr.bold),
      );
      if (!widget.running) {
        // the normal screen again, the shell going on
        _spans(p, 3, 3, _prompt(t, 'dart run bin/app.dart'), _ww - 6);
        final w = _spans(p, 3, 4, _prompt(t, ''), _ww - 6);
        _blinking(p, t, 3 + w, 4, ms, wake);
      }
    }

    return _terminal(
      width: _ww,
      height: _wh,
      under: under,
      // the app, on the alternate screen
      at: widget.running ? (3, 3, _ww - 6, 1) : null,
      app: WindowTitle(
        title: widget.title,
        child: Text('In the title bar: ${widget.title}'),
      ),
    );
  }
}

// ------------------------------------------------------------ Notifications

/// The stage, and the notification in its corner.
const _nw = 50;
const _nh = 12;
const _nx = 22;
const int _npw = _nw - _nx - 1;
const _nph = 5;

/// The terminals of the option: how each shows a notification, none for
/// xterm.
const Map<String, String?> _notifiers = {
  'kitty': 'OSC 99',
  'Ghostty': 'OSC 777',
  'iTerm2': 'OSC 9',
  'xterm': null,
};
const _note = ('Build finished', 'ran 214 tests in 3.2 s');

/// How long the desktop shows one.
const _noteMs = 5000;

/// [s] broken at blanks into lines of at most [w] cells.
List<String> _wrapWords(String s, int w) {
  final out = <String>[];
  var line = '';
  for (final word in s.split(' ')) {
    if (line.isNotEmpty && widthOf(line) + 1 + widthOf(word) > w) {
      out.add(line);
      line = word;
    } else {
      line = line.isEmpty ? word : '$line $word';
    }
  }
  if (line.isNotEmpty) {
    out.add(line);
  }
  return out;
}

final _notifications = GalleryPage(
  terminalAround: true,
  group: 'App',
  title: 'Notifications',
  options: [
    ChoiceOption('terminal', 'terminal', values: _notifiers.keys.toList()),
  ],
  build: (context, o) => _Notify(terminal: o.choice<String>('terminal')),
  code: (o) => [
    'var _notified = 0;',
    '',
    '// shown where the terminal is known to show one (OSC 9, 777 or 99,',
    '// TerminalInfo.notifications); nothing elsewhere',
    'void _notify() {',
    "  AppBinding.of(context).notify('${_note.$1}', '${_note.$2}');",
    '  setState(() => _notified++);',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    "      Button('Notify', onPressed: _notify),",
    '      Text.rich([',
    "        Span('notified: ', theme.muted),",
    '        if (_notified == 0)',
    "          Span('nothing', theme.muted)",
    '        else',
    r"          Span('$_notified'),",
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// The Code's Notify button in a terminal's window, and the desktop's
/// notification for a few seconds where [terminal] shows one.
final class _Notify extends StatefulWidget {
  const _Notify({required this.terminal});

  final String terminal;

  @override
  State<_Notify> createState() => _NotifyState();
}

final class _NotifyState extends TimedState<_Notify> {
  int get _count => (kept['count'] ?? 0) as int;

  void _notify() {
    AppBinding.of(context).notify(_note.$1, _note.$2);
    final at = clockNow;
    setState(() {
      kept
        ..['count'] = _count + 1
        ..['countAt'] = at;
      if (_notifiers[widget.terminal] != null) {
        kept
          ..['at'] = at
          ..['by'] = widget.terminal;
      }
    });
  }

  @override
  Widget buildTimed(BuildContext context) {
    final t = Tokens(Theme.of(context));
    final theme = Theme.of(context);
    final ms = now;
    const ty = 2;
    final at = kept['at'] as int?;
    final by = kept['by'] as String?;
    final showing = at != null && by != null && ms - at < _noteMs;
    if (showing) {
      wake(at + _noteMs);
    }
    final lit = litAt(kept['countAt'] as int?);

    void under(Painter p) {
      // the terminal's window, the app in it
      _box(
        p,
        0,
        ty,
        _nx + 18,
        _nh - ty,
        t.border,
        title: 'terminal',
        titleFg: t.muted,
      );
      final how = _notifiers[widget.terminal];
      final legend = ' ${widget.terminal}: ${how ?? 'none'} ';
      p.text(
        _nx + 18 - 2 - widthOf(legend),
        _nh - 1,
        legend,
        Style(fg: t.muted),
      );
    }

    void over(Painter p) {
      if (lit > 0) {
        p.bg(12, ty + 3, 7, 1, mix(t.background, t.selection, lit));
      }
      if (!showing) {
        return;
      }
      // the desktop's notification, in its corner, for a few seconds
      const x = _nx;
      const y = 0;
      final surface = Style(fg: t.text, bg: t.surface);
      final k = t.dark ? 0.55 : 0.18;
      const black = Color.rgb(0, 0, 0);
      p
        ..fill(x, y, _npw, _nph, surface)
        ..tint(x + _npw, y + 1, 1, _nph, black, k)
        ..tint(x + 1, y + _nph, _npw - 1, 1, black, k)
        ..text(x + 2, y + 1, by, Style(fg: t.muted, bg: t.surface))
        ..text(x + _npw - 5, y + 1, 'now', Style(fg: t.dim, bg: t.surface));
      // OSC 9 is one message, `title: body`; the others a title and a body
      final lines = _notifiers[by] == 'OSC 9'
          ? [
              for (final l in _wrapWords(
                '${_note.$1}: ${_note.$2}',
                _npw - 4,
              ).take(2))
                (l, surface),
            ]
          : [
              (_note.$1, surface.merge(const Style(attrs: Attr.bold))),
              (_note.$2, surface),
            ];
      for (var i = 0; i < lines.length; i++) {
        p.text(x + 2, y + 2 + i, lines[i].$1, lines[i].$2, max: _npw - 4);
      }
    }

    final count = _count;
    return _terminal(
      width: _nw,
      height: _nh,
      under: under,
      over: over,
      at: (2, ty + 1, _nx - 2, _nh - ty - 2),
      app: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          Button('Notify', onPressed: _notify),
          Text.rich([
            Span('notified: ', theme.muted),
            if (count == 0) Span('nothing', theme.muted) else Span('$count'),
          ]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Cli

/// The terminal's frame in [room]: all of it, a terminal of at most
/// 74 × 20 inside its border; 76 × 22 before the stage was laid out.
(int, int) _cliBox(StageRoom room) => room == StageRoom.unbounded
    ? (76, 22)
    : (
        math.max(30, math.min(76, room.width)),
        math.max(8, math.min(22, room.height)),
      );

final _cli = GalleryPage(
  terminalAround: true,
  group: 'App',
  title: 'Cli',
  options: const [
    ChoiceOption('program', 'program', values: ['create', 'install', 'check']),
  ],
  build: (context, o) => LayoutBuilder(
    builder: (context, c) {
      const most = 1 << 20;
      final (w, h) = _cliBox(
        StageRoom(
          c.maxW < BoxConstraints.unbounded ? c.maxW : most,
          c.maxH < BoxConstraints.unbounded ? c.maxH : most,
        ),
      );
      return cliStage(context, o.label('program'), width: w, height: h);
    },
  ),
  heightIn: (o, room) => _cliBox(room).$2,
  code: (o) => cliCode[o.label('program')]!,
);
