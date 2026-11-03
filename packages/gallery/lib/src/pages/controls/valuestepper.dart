// The ValueStepper page.
part of 'controls.dart';

/// The values of the ValueStepper page: a theme's modes.
const List<Choice<String>> _stepModes = [
  Choice('dark', 'dark'),
  Choice('light', 'light'),
  Choice('sepia', 'sepia', enabled: false),
  Choice('auto', 'auto-switching'),
];

/// The ValueStepper page's `enabled` option.
const _stepperEnabled = SwitchOption('enabled', 'enabled', initial: true);

final _stepperPage = GalleryPage(
  group: _group,
  title: 'ValueStepper',
  options: const [_stepperEnabled],
  build: (context, o) => _Steps(enabled: o(_stepperEnabled)),
  code: (o) => [
    "var _mode = 'dark';",
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      ValueStepper<String>(',
    '        values: const [',
    for (final c in _stepModes)
      if (c.enabled)
        "          Choice('${c.value}', '${c.label}'),"
      else
        "          Choice('${c.value}', '${c.label}', enabled: false),",
    '        ],',
    '        value: _mode,',
    if (o(_stepperEnabled))
      '        onChanged: (mode) => setState(() => _mode = mode),'
    else
      '        onChanged: null,',
    '      ),',
    "      Text.rich([Span('mode: ', theme.muted), Span(_mode)]),",
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// A mode to step through, and what it is.
final class _Steps extends StatefulWidget {
  const _Steps({required this.enabled});

  final bool enabled;

  @override
  State<_Steps> createState() => _StepsState();
}

final class _StepsState extends State<_Steps> with KeptState {
  @override
  Widget build(BuildContext context) {
    final mode = keptOr('mode', 'dark');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        ValueStepper<String>(
          values: _stepModes,
          value: mode,
          onChanged: widget.enabled ? (mode) => keep('mode', mode) : null,
        ),
        LitLine([('mode: ', true), (mode, false)], serial: serial),
      ],
    );
  }
}
