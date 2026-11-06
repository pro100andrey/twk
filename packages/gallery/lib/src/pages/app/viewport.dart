// The Viewport page.
part of 'app.dart';

/// A build in steps, done one a tick, as on the Static page.
const _steps = ['resolving', 'compiling', 'testing', 'writing'];

/// The terminal's screen, and the app's rectangle in it.
const int _sw = _tw - 4;

const int _sh = _th - 2;

const _vw = 20;

const _vh = 4;

const int _vrun = (4 + 1) * _stepMs + _pause;

/// The Viewport page's `left` option.
const _viewportLeft = SliderOption(
  'left',
  'left',
  min: 0,
  max: _sw - _vw,
  initial: _sw - _vw,
);

/// The Viewport page's `top` option.
const _viewportTop = SliderOption(
  'top',
  'top',
  min: 0,
  max: _sh - _vh,
);

/// The Viewport page's `mode` option.
const _viewportMode = ChoiceOption<String>(
  'mode',
  'mode',
  values: ['inline', 'fullscreen'],
);

final _viewport = GalleryPage(
  terminalAround: true,
  group: _group,
  title: 'Viewport',
  options: const [
    _viewportLeft,
    _viewportTop,
    _viewportMode,
  ],
  build: (context, o) => _ViewportRun(
    left: o(_viewportLeft).toInt(),
    top: o(_viewportTop).toInt(),
    inline: o.nameOf(_viewportMode) == 'inline',
  ),
  code: (o) {
    final inline = o.nameOf(_viewportMode) == 'inline';
    final at =
        '${o.nameOf(_viewportLeft)}, ${o.nameOf(_viewportTop)}, $_vw, $_vh';
    return [
      "import 'dart:async';",
      '',
      "import 'package:twk/twk.dart';",
      '',
      codeLine([
        '// the $_vw × $_vh cells from column ${o.nameOf(_viewportLeft)} ',
        'of row ${o.nameOf(_viewportTop)}: nothing else is',
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
        '            Row(spacing: 1, children: ',
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
          Row(spacing: 1, children: [const Spinner(), Text('${_steps[done]}…')])
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
