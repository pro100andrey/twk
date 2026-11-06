// The Toast page.
part of 'overlays.dart';

/// The Toast page's `alignment` option.
const _toastAlignment = ChoiceOption<String>(
  'alignment',
  'alignment',
  values: ['bottomRight', 'topRight', 'bottomCenter'],
);

/// The Toast page's `duration` option.
const _toastDuration = ChoiceOption<int>(
  'duration',
  'duration',
  values: [1000, 3000, 5000],
  labels: ['1 s', '3 s', '5 s'],
  initial: 3000,
);

final _toastPage = GalleryPage(
  group: _group,
  title: 'Toast',
  options: [
    _toastAlignment,
    _toastDuration,
    _lookOption,
  ],
  build: (context, o) => _Toasts(
    alignment: o(_toastAlignment),
    ms: o(_toastDuration),
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
    '    context: context,',
    '    message: message,',
    '    alignment: .${o.nameOf(_toastAlignment)},',
    if (o(_toastDuration) != 3000)
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
int _seconds(Options o) => o(_toastDuration) ~/ 1000;

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
      context: context,
      message: message,
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
