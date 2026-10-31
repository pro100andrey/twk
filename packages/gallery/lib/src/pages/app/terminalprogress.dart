// The TerminalProgress page.
part of 'app.dart';

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

/// The progress of the options: the state shown (normal without a value
/// is indeterminate), its percent, and the OSC 9;4 that shows it, null
/// for none.
(String, int?, String?) _progressOf(Options o) {
  final value = o(_progressKnown) ? o(_progressValue) / 100 : null;
  final state = o.nameOf(_progressState) == 'normal' && value == null
      ? 'indeterminate'
      : o.nameOf(_progressState);
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

/// The TerminalProgress page's `state` option.
const _progressState = ChoiceOption<String>(
  'state',
  'state',
  values: ['none', 'normal', 'error', 'indeterminate', 'paused'],
  initial: 'normal',
);

/// The TerminalProgress page's `known` option.
const _progressKnown = SwitchOption(
  'known',
  'value known',
  initial: true,
);

/// The TerminalProgress page's `value` option.
final _progressValue = SliderOption(
  'value',
  'value',
  min: 0,
  max: 100,
  initial: 33,
  format: (v) => '$v%',
);

/// The TerminalProgress page's `shows` option.
const _progressShows = SwitchOption(
  'shows',
  'terminal shows it',
  initial: true,
);

final _progress = GalleryPage(
  terminalAround: true,
  group: _group,
  title: 'TerminalProgress',
  options: [
    _progressState,
    _progressKnown,
    _progressValue,
    _progressShows,
  ],
  build: (context, o) => _Progress(options: o),
  code: (o) {
    final known = o(_progressKnown);
    final v = known ? _number(o(_progressValue) / 100) : null;
    final value = known ? '${o.nameOf(_progressValue)}%' : 'not known';
    // what TerminalStatus wrote last, as the page's widget saw it
    final w = o.pageState['wrote'] as String?;
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
      '  state: .${o.nameOf(_progressState)},',
      if (v != null) '  value: $v,',
      '  child: Column(',
      '    crossAxisAlignment: .start,',
      '    children: [',
      "      const Text('In the tab: ${o.nameOf(_progressState)}, $value'),",
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
    final value = o(_progressValue);
    if (kept['value'] != null && kept['value'] != value && !o(_progressKnown)) {
      final control = PageControl.of(context);
      AppBinding.maybeOf(
        context,
      )?.scheduleFrameCallback((_) => control.setOption(_progressKnown, true));
    }
    kept['value'] = value;
    final seq = _progressOf(o).$3;
    if (!o(_progressShows)) {
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
    return kept['wrote'] as String?;
  }

  @override
  Widget buildTimed(BuildContext context) {
    final t = Tokens(Theme.of(context));
    final theme = Theme.of(context);
    final o = widget.options;
    final (state, percent, _) = _progressOf(o);
    final wrote = _written();
    final shown = o(_progressShows) && state != 'none';
    final color = switch (state) {
      'error' => t.error,
      'paused' => t.warning,
      _ => t.primary,
    };
    final ms = now;
    final value = o(_progressKnown)
        ? '${o.nameOf(_progressValue)}%'
        : 'not known';
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
        state: ProgressState.values.byName(o.nameOf(_progressState)),
        value: o(_progressKnown) ? o(_progressValue) / 100 : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('In the tab: ${o.nameOf(_progressState)}, $value'),
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
