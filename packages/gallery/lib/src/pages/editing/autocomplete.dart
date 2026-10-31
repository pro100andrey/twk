// The Autocomplete page.
part of 'editing.dart';

/// The Autocomplete page's `trigger` option.
const _autocompleteTrigger = ChoiceOption<String>(
  'trigger',
  'trigger',
  values: ['/', 'none'],
);

/// The Autocomplete page's `rows` option.
const _autocompleteRows = ChoiceOption<int>(
  'rows',
  'rows',
  values: [8, 4],
);

final _autocompletePage = GalleryPage(
  group: _group,
  title: 'Autocomplete',
  options: [
    _autocompleteTrigger,
    _autocompleteRows,
    popupLookOption(),
  ],
  build: (context, o) => _Complete(
    fruit: o(_autocompleteTrigger) == 'none',
    rows: o(_autocompleteRows),
    popupLook: popupLookOf(o),
  ),
  code: (o) {
    final fruit = o(_autocompleteTrigger) == 'none';
    final placeholder = fruit ? 'a fruit' : '/ and a command';
    return [
      'final _controller = TextEditingController();',
      'String? _chosen;',
      '',
      if (fruit) ...[
        'static const _fruit = [',
        for (var k = 0; k < 15; k += 5)
          '  ${_fruit.sublist(k, k + 5).map((f) => "'$f'").join(', ')},',
        '];',
      ] else ...[
        'static const _commands = {',
        for (final MapEntry(:key, :value) in _commands.entries)
          "  '$key': '$value',",
        '};',
      ],
      '',
      '@override',
      'void dispose() {',
      '  _controller.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      // the suggestions show under the box, from its left edge',
      '      Autocomplete(',
      '        controller: _controller,',
      if (!fruit) "        trigger: '/',",
      if (o(_autocompleteRows) != 8)
        '        rows: ${o.nameOf(_autocompleteRows)},',
      ...popupLookArg(o, '        '),
      '        suggestions: (query) => [',
      if (fruit) ...[
        '          for (final fruit in _fruit)',
        _fruitLine,
      ] else ...[
        _commandsLine,
        '            if (fuzzyMatch(query, command) != null)',
        '              Suggestion(command, detail: detail),',
      ],
      '        ],',
      _selectedLine,
      '        child: SizedBox(',
      '          width: 30,',
      ..._focusBox('          ', 'field'),
      '            child: TextField(',
      '              controller: _controller,',
      "              placeholder: '$placeholder',",
      '            ),',
      '          ),',
      '        ),',
      '      ),',
      '      Text.rich([',
      "        Span('chosen: ', theme.muted),",
      '        if (_chosen case final chosen?)',
      '          Span(chosen)',
      '        else',
      "          Span('nothing', theme.muted),",
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

const _commands = {
  'help': 'the keys',
  'open': 'a file',
  'quit': 'the app',
  'save': 'the file',
  'search': 'in the files',
  'settings': 'of the app',
  'share': 'a link',
  'sort': 'the lines',
};

const _fruit = [
  'apple', 'apricot', 'avocado', 'banana', 'blackberry', //
  'blueberry', 'cherry', 'grape', 'lemon', 'lime',
  'mango', 'orange', 'peach', 'pear', 'plum',
];

const _fruitLine =
    '            if (fuzzyMatch(query, fruit) != null) Suggestion(fruit),';

const _commandsLine =
    '          for (final MapEntry(key: command, value: detail) in '
    '_commands.entries)';

const _selectedLine =
    '        onSelected: (suggestion) => '
    'setState(() => _chosen = suggestion.text),';

/// A field that suggests commands after `/`, or fruit, and what was
/// chosen.
final class _Complete extends StatefulWidget {
  const _Complete({
    required this.fruit,
    required this.rows,
    required this.popupLook,
  });

  final bool fruit;
  final int rows;
  final PanelLook popupLook;

  @override
  State<_Complete> createState() => _CompleteState();
}

final class _CompleteState extends State<_Complete> with KeptState {
  late final TextEditingController _controller = keptAt(
    context,
    'controller',
    TextEditingController.new,
  );
  String? get _chosen => kept['chosen'] as String?;
  int get _serial => kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Autocomplete(
          controller: _controller,
          trigger: widget.fruit ? null : '/',
          rows: widget.rows,
          popupLook: widget.popupLook,
          suggestions: (query) => widget.fruit
              ? [
                  for (final fruit in _fruit)
                    if (fuzzyMatch(query, fruit) != null) Suggestion(fruit),
                ]
              : [
                  for (final MapEntry(key: command, value: detail)
                      in _commands.entries)
                    if (fuzzyMatch(query, command) != null)
                      Suggestion(command, detail: detail),
                ],
          onSelected: (suggestion) => setState(() {
            kept['chosen'] = suggestion.text;
            kept['serial'] = _serial + 1;
          }),
          child: SizedBox(
            width: 30,
            child: _focusBoxed(
              TextField(
                controller: _controller,
                placeholder: widget.fruit ? 'a fruit' : '/ and a command',
              ),
            ),
          ),
        ),
        LitLine([
          ('chosen: ', true),
          if (chosen == null) ('nothing', true) else (chosen, false),
        ], serial: _serial),
      ],
    );
  }
}
