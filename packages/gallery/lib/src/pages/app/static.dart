// The Static page.
part of 'app.dart';

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

/// A run of the build: the app quits on the tick after the last item.
const int _run = (4 + 1) * _stepMs + _pause;

/// The Static page's `mode` option.
const _staticMode = ChoiceOption<String>(
  'mode',
  'mode',
  values: ['inline', 'fullscreen'],
);

final _static = GalleryPage(
  terminalAround: true,
  group: _group,
  title: 'Static',
  options: const [
    _staticMode,
  ],
  build: (context, o) => _StaticRun(inline: o.nameOf(_staticMode) == 'inline'),
  code: (o) {
    final inline = o.nameOf(_staticMode) == 'inline';
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
      '            spacing: 1,',
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
              spacing: 1,
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
