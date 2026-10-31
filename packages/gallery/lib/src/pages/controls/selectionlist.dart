// The SelectionList page.
part of 'controls.dart';

final _selectionlistPage = GalleryPage(
  group: 'Controls',
  title: 'SelectionList',
  options: const [
    SwitchOption('multiple', 'multiple'),
    SwitchOption('bar', 'cursor bar', initial: true),
  ],
  build: (context, o) =>
      _Planets(multiple: o.flag('multiple'), bar: o.flag('bar')),
  code: (o) => [
    'static const _planets = [',
    for (final p in _planets) "  '$p',",
    '];',
    '',
    if (o.flag('multiple')) ...[
      'late final _selection = SelectionController<String>(',
      '  multiple: true,',
      "  selected: ['Earth'],",
      ')..addListener(() => setState(() {}));',
    ] else ...[
      _selectionLine,
      '  ..addListener(() => setState(() {}));',
    ],
    '',
    '@override',
    'void dispose() {',
    '  _selection.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  final selected = _selection.selected;',
    '  return SizedBox(',
    '    width: 29,',
    '    height: 8,',
    '    child: Row(',
    '      crossAxisAlignment: .start,',
    '      gap: 2,',
    '      children: [',
    '        SizedBox(',
    '          width: 18,',
    '          // the border primary while the list has the focus',
    '          child: FocusBuilder(',
    '            builder: (context, hasFocus, list) => Box(',
    '              border: .all(',
    '                type: .rounded,',
    '                style: hasFocus ? theme.primary : theme.border,',
    '              ),',
    '              child: list,',
    '            ),',
    '            child: SelectionList<String>(',
    '              itemCount: _planets.length,',
    '              keyOf: (i) => _planets[i],',
    '              itemBuilder: (context, i) => Text(_planets[i]),',
    "              itemEnabled: (i) => _planets[i] != 'Venus',",
    if (!o.flag('bar')) '              bar: false,',
    '              controller: _selection,',
    '            ),',
    '          ),',
    '        ),',
    '        Expanded(',
    '          child: Text.rich([',
    r"            Span('selected\n', theme.muted),",
    '            if (selected.isEmpty)',
    "              Span('nothing', theme.muted)",
    '            else',
    r"              Span(selected.join('\n')),",
    '          ]),',
    '        ),',
    '      ],',
    '    ),',
    '  );',
    '}',
  ].join('\n'),
);

const _planets = [
  'Mercury',
  'Venus',
  'Earth',
  'Mars',
  'Jupiter',
  'Saturn',
  'Uranus',
  'Neptune',
];

const _selectionLine =
    "late final _selection = SelectionController<String>(selected: ['Earth'])";

/// Planets selected in a list, one or several.
final class _Planets extends StatefulWidget {
  const _Planets({required this.multiple, required this.bar});

  final bool multiple;

  /// Whether the list shows its bar on the cursor's row.
  final bool bar;

  @override
  State<_Planets> createState() => _PlanetsState();
}

final class _PlanetsState extends State<_Planets> with KeptState {
  /// The selection, kept with the page: a new one with Earth selected when
  /// [_Planets.multiple] changes.
  SelectionController<String> get _selection {
    final c = kept['selection'] as SelectionController<String>?;
    if (c != null && c.multiple == widget.multiple) {
      return c;
    }
    return kept['selection'] = SelectionController<String>(
      multiple: widget.multiple,
      selected: ['Earth'],
    );
  }

  SelectionController<String>? _listening;
  var _said = '';

  void _changed() {
    final said = _listening?.selected.join(',') ?? '';
    setState(() {
      if (said != _said) {
        kept['serial'] = serial + 1;
      }
      _said = said;
    });
  }

  @override
  void dispose() {
    _listening?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = _selection;
    if (!identical(selection, _listening)) {
      _listening?.removeListener(_changed);
      _listening = selection..addListener(_changed);
      _said = selection.selected.join(',');
    }
    final selected = selection.selected;
    return SizedBox(
      width: 29,
      height: 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 2,
        children: [
          SizedBox(
            width: 18,
            child: FocusBuilder(
              builder: (context, hasFocus, list) => Box(
                border: Border.all(
                  type: BorderType.rounded,
                  style: hasFocus ? theme.primary : theme.border,
                ),
                child: list,
              ),
              child: SelectionList<String>(
                itemCount: _planets.length,
                keyOf: (i) => _planets[i],
                itemBuilder: (context, i) => Text(_planets[i]),
                itemEnabled: (i) => _planets[i] != 'Venus',
                bar: widget.bar,
                controller: selection,
              ),
            ),
          ),
          Expanded(
            child: LitLine([
              ('selected\n', true),
              if (selected.isEmpty)
                ('nothing', true)
              else
                (selected.join('\n'), false),
            ], serial: serial),
          ),
        ],
      ),
    );
  }
}
