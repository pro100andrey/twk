// The Select, MultiSelect page.
part of 'controls.dart';

/// The Select, MultiSelect page's `inline` option.
const _selectMultiselectInline = SwitchOption('inline', 'inline');

/// The Select, MultiSelect page's `rows` option.
const _selectMultiselectRows = ChoiceOption<int>(
  'rows',
  'rows',
  values: [4, 8],
  initial: 4,
);

final _selectMultiselectPage = GalleryPage(
  group: _group,
  title: 'Select, MultiSelect',
  options: [
    _selectMultiselectInline,
    _selectMultiselectRows,
    // an inline list shows no popup
    popupLookOption(disabled: (o) => o(_selectMultiselectInline)),
  ],
  build: (context, o) => _Selects(
    inline: o(_selectMultiselectInline),
    rows: o(_selectMultiselectRows),
    popupLook: popupLookOf(o),
  ),
  code: (o) {
    final extra = [
      if (o(_selectMultiselectInline)) 'inline: true,',
      'rows: ${o.nameOf(_selectMultiselectRows)},',
      if (!o(_selectMultiselectInline)) ...popupLookArg(o, ''),
    ];
    return [
      'const _fruit = [',
      for (final c in _fruits) _choiceLine(c),
      '];',
      '',
      'final _popup = PopupController();',
      'String? _one;',
      'var _some = <String>{};',
      '',
      '@override',
      'void dispose() {',
      '  _popup.dispose();',
      '  super.dispose();',
      '}',
      '',
      '// Open, each shows its choices in an OptionList,',
      '// as Autocomplete and CommandPalette do: the',
      '// letters typed lit, the highlighted one on the',
      '// selection.',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  spacing: 1,',
      '  children: [',
      '    Row(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .start,',
      '      spacing: 4,',
      '      children: [',
      '        Select<String>(',
      '          choices: _fruit,',
      '          value: _one,',
      "          hint: 'a fruit',",
      for (final l in extra) '          $l',
      '          controller: _popup,',
      '          onChanged: (value) => setState(() => _one = value),',
      '        ),',
      '        MultiSelect<String>(',
      '          choices: _fruit,',
      '          values: _some,',
      "          hint: 'some fruit',",
      for (final l in extra) '          $l',
      '          onChanged: (values) => setState(() => _some = values),',
      '        ),',
      '      ],',
      '    ),',
      "    // opens the fruit's list, the focus in its field",
      "    Button('Choose a fruit', onPressed: _popup.open),",
      '  ],',
      ');',
    ].join('\n');
  },
);

const List<Choice<String>> _fruits = [
  Choice('apple', 'apple'),
  Choice('apricot', 'apricot'),
  Choice('banana', 'banana'),
  Choice('blueberry', 'blueberry'),
  Choice('cherry', 'cherry'),
  Choice('durian', 'durian', enabled: false),
  Choice('fig', 'fig'),
  Choice('grape', 'grape'),
  Choice('lemon', 'lemon'),
];

/// The Code's line of [c].
String _choiceLine(Choice<String> c) {
  final enabled = c.enabled ? '' : ', enabled: false';
  return "  Choice('${c.value}', '${c.label}'$enabled),";
}

/// A fruit chosen in a Select, some in a MultiSelect.
final class _Selects extends StatefulWidget {
  const _Selects({
    required this.inline,
    required this.rows,
    required this.popupLook,
  });

  final bool inline;
  final int rows;
  final PanelLook popupLook;

  @override
  State<_Selects> createState() => _SelectsState();
}

final class _SelectsState extends State<_Selects> with KeptState {
  final _popup = PopupController();

  @override
  void dispose() {
    _popup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 1,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Select<String>(
            choices: _fruits,
            value: keptOr<String?>('one', null),
            hint: 'a fruit',
            inline: widget.inline,
            rows: widget.rows,
            popupLook: widget.popupLook,
            controller: _popup,
            onChanged: (value) => keep('one', value),
          ),
          MultiSelect<String>(
            choices: _fruits,
            values: keptOr('some', const <String>{}),
            hint: 'some fruit',
            inline: widget.inline,
            rows: widget.rows,
            popupLook: widget.popupLook,
            onChanged: (values) => keep('some', values),
          ),
        ],
      ),
      Button('Choose a fruit', onPressed: _popup.open),
    ],
  );
}
