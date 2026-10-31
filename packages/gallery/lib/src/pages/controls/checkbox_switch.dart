// The Checkbox, Switch page.
part of 'controls.dart';

final _checkboxSwitchPage = GalleryPage(
  group: 'Controls',
  title: 'Checkbox, Switch',
  options: const [
    ChoiceOption('switch', 'switch', values: ['pill', 'brackets']),
  ],
  build: (context, o) => _Toggles(pill: o.choice<String>('switch') == 'pill'),
  code: (o) => [
    'var _wrap = true;',
    'var _dark = false;',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    '    Checkbox(',
    '      value: _wrap,',
    "      label: 'wrap lines',",
    '      onChanged: (value) => setState(() => _wrap = value),',
    '    ),',
    '    Switch(',
    '      value: _dark,',
    "      label: 'dark mode',",
    if (o.choice<String>('switch') == 'brackets') '      pill: false,',
    '      onChanged: (value) => setState(() => _dark = value),',
    '    ),',
    "    const Checkbox(value: true, label: 'disabled', onChanged: null),",
    '  ],',
    ');',
  ].join('\n'),
);

/// A checkbox, a switch and a disabled checkbox.
final class _Toggles extends StatefulWidget {
  const _Toggles({required this.pill});

  /// Whether the switch is the pill, not `[on ]` and `[off]`.
  final bool pill;

  @override
  State<_Toggles> createState() => _TogglesState();
}

final class _TogglesState extends State<_Toggles> with KeptState {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Checkbox(
        value: keptOr('wrap', true),
        label: 'wrap lines',
        onChanged: (value) => keep('wrap', value),
      ),
      Switch(
        value: keptOr('dark', false),
        label: 'dark mode',
        pill: widget.pill,
        onChanged: (value) => keep('dark', value),
      ),
      const Checkbox(value: true, label: 'disabled', onChanged: null),
    ],
  );
}
