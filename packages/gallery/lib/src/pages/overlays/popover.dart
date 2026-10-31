// The Popover page.
part of 'overlays.dart';

final _popoverPage = GalleryPage(
  group: 'Overlays',
  title: 'Popover',
  about:
      'A widget by another while the app says so, placed by an '
      'AnchorTarget around it and an AnchorFollower in the overlay; Escape '
      'or a click outside closes it.',
  options: [
    const SwitchOption('dismissible', 'dismissible', initial: true),
    _lookOption,
  ],
  build: (context, o) =>
      _Pop(dismissible: o.flag('dismissible'), look: _lookOf(o)),
  code: (o) => [
    'var _open = false;',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Popover(',
    '    open: _open,',
    if (o.flag('dismissible'))
      '    onDismiss: () => setState(() => _open = false),',
    '    popover: Panel(',
    ..._lookLine(o, '      '),
    '      padding: const .x(1),',
    '      child: Column(',
    '        mainAxisSize: .min,',
    '        crossAxisAlignment: .start,',
    '        children: [',
    "          const Text('${_pop[0]}'),",
    "          Text('${_pop[o.flag('dismissible') ? 1 : 2]}', $_muted),",
    '        ],',
    '      ),',
    '    ),',
    '    child: Button(',
    "      _open ? 'Close' : 'Open',",
    '      onPressed: () => setState(() => _open = !_open),',
    '    ),',
    '  );',
    '}',
  ].join('\n'),
);

/// The muted style argument of the Code.
const _muted = 'style: theme.muted';

/// What the Popover page's popover says.
const _pop = [
  'The popover, by the button.',
  'Escape or a click outside closes it.',
  'Only the button closes it.',
];

/// A button that opens a popover by it and closes it.
final class _Pop extends StatefulWidget {
  const _Pop({required this.dismissible, required this.look});

  final bool dismissible;
  final PanelLook look;

  @override
  State<_Pop> createState() => _PopState();
}

final class _PopState extends State<_Pop> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Popover(
      open: _open,
      onDismiss: widget.dismissible
          ? () => setState(() => _open = false)
          : null,
      popover: Panel(
        look: widget.look,
        padding: const EdgeInsets.x(1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_pop[0]),
            Text(_pop[widget.dismissible ? 1 : 2], style: theme.muted),
          ],
        ),
      ),
      child: Button(
        _open ? 'Close' : 'Open',
        onPressed: () => setState(() => _open = !_open),
      ),
    );
  }
}
