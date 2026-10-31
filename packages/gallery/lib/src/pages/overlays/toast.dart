// The Toast page.
part of 'overlays.dart';

final _toastPage = GalleryPage(
  group: 'Overlays',
  title: 'Toast',
  options: [
    const ChoiceOption(
      'alignment',
      'alignment',
      values: ['bottomRight', 'topRight', 'bottomCenter'],
    ),
    const ChoiceOption(
      'duration',
      'duration',
      values: [1000, 3000, 5000],
      labels: ['1 s', '3 s', '5 s'],
      initial: 3000,
    ),
    _lookOption,
  ],
  build: (context, o) => _Toasts(
    alignment: o.choice('alignment'),
    ms: o.choice('duration'),
    look: _lookOf(o),
  ),
  code: (o) => [
    'var _n = 0;',
    '',
    'void _show() {',
    '  final theme = Theme.of(context);',
    '  final (message, style) = [',
    "    ('Saved 3 files.', theme.success),",
    "    ('Copied the path.', theme.info),",
    "    ('Disk nearly full.', theme.warning),",
    "    ('Upload failed.', theme.error),",
    '  ][_n++ % 4];',
    '  showToast(',
    '    context,',
    '    message,',
    '    alignment: .${o.label('alignment')},',
    if (o.choice<int>('duration') != 3000)
      '    duration: const Duration(seconds: ${_seconds(o)}),',
    '    style: style,',
    ..._lookLine(o, '    '),
    '  );',
    '}',
    '',
    '@override',
    _toastBuildLine,
  ].join('\n'),
);

/// The Toast page's duration in seconds.
int _seconds(Options o) => o.choice<int>('duration') ~/ 1000;

/// The Code's line that builds the Toast page's button.
const _toastBuildLine =
    "Widget build(BuildContext context) => Button('Show a toast', "
    'onPressed: _show);';

/// A button that shows a toast, the next of four each time.
final class _Toasts extends StatefulWidget {
  const _Toasts({
    required this.alignment,
    required this.ms,
    required this.look,
  });

  final String alignment;
  final int ms;
  final PanelLook look;

  @override
  State<_Toasts> createState() => _ToastsState();
}

final class _ToastsState extends State<_Toasts> with KeptState {
  void _show() {
    final theme = Theme.of(context);
    final n = kept['n'] as int? ?? 0;
    kept['n'] = n + 1;
    final (message, style) = [
      ('Saved 3 files.', theme.success),
      ('Copied the path.', theme.info),
      ('Disk nearly full.', theme.warning),
      ('Upload failed.', theme.error),
    ][n % 4];
    showToast(
      context,
      message,
      alignment: alignmentByName[widget.alignment] ?? Alignment.bottomRight,
      duration: Duration(milliseconds: widget.ms),
      style: style,
      look: widget.look,
    );
  }

  @override
  Widget build(BuildContext context) =>
      Button('Show a toast', onPressed: _show);
}
