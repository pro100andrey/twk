// The Notifications page.
part of 'app.dart';

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

/// The Notifications page's `terminal` option.
final _notificationsTerminal = ChoiceOption<String>(
  'terminal',
  'terminal',
  values: _notifiers.keys.toList(),
);

final _notifications = GalleryPage(
  terminalAround: true,
  group: _group,
  title: 'Notifications',
  options: [
    _notificationsTerminal,
  ],
  build: (context, o) => _Notify(terminal: o(_notificationsTerminal)),
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
    '    spacing: 1,',
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
        spacing: 1,
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
