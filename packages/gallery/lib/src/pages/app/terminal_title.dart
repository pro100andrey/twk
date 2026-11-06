// The Window title page.
part of 'app.dart';

/// The window.
const _ww = 46;

const _wh = 7;

/// What the user's shell set.
const _userTitle = 'user@twk: ~/twk';

/// The Window title page's `title` option.
const _windowTitleTitle = ChoiceOption<String>(
  'title',
  'title',
  values: ['twk gallery', 'build: 3 of 5', 'chat · ~/project'],
);

/// The Window title page's `running` option.
const _windowTitleRunning = SwitchOption(
  'running',
  'app running',
  initial: true,
);

final _windowTitle = GalleryPage(
  terminalAround: true,
  group: _group,
  title: 'Window title',
  options: const [
    _windowTitleTitle,
    _windowTitleRunning,
  ],
  build: (context, o) =>
      _Titled(title: o(_windowTitleTitle), running: o(_windowTitleRunning)),
  code: (o) => [
    "// the title of the terminal's window or tab while this is in the",
    codeLine([
      '// tree, set again when it changes: ',
      'of nested ones the innermost, as',
    ]),
    "// Flutter's Title. The user's own comes back when the app ends.",
    'return TerminalTitle(',
    "  title: '${o.nameOf(_windowTitleTitle)}',",
    "  child: const Text('In the title bar: ${o.nameOf(_windowTitleTitle)}'),",
    ');',
  ].join('\n'),
);

/// A terminal's window whose title bar shows [title] while the app runs,
/// the user's own once it ended; the app, a real TerminalTitle.
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
      app: TerminalTitle(
        title: widget.title,
        child: Text('In the title bar: ${widget.title}'),
      ),
    );
  }
}
