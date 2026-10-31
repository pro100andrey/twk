// The OptionList page.
part of 'overlays.dart';

final _optionlistPage = GalleryPage(
  group: 'Overlays',
  title: 'OptionList',
  options: const [
    ChoiceOption(
      'query',
      'marks of',
      values: ['', 'o', 'sa'],
      labels: ['none', 'o', 'sa'],
    ),
    ChoiceOption('rows', 'rows', values: [3, 5, 8], initial: 5),
    SwitchOption('details', 'details', initial: true),
    SwitchOption('bar', 'bar', initial: true),
    SwitchOption('thumb', 'thumb', initial: true),
  ],
  build: (context, o) => _Options(
    query: o.choice('query'),
    rows: o.choice('rows'),
    details: o.flag('details'),
    bar: o.flag('bar'),
    thumb: o.flag('thumb'),
  ),
  code: _optionListCode,
);

/// What the Notes window says.
/// The commands of the OptionList page: a label and its keys.
const _commands = [
  ('Open file', 'ctrl+o'),
  ('Save', 'ctrl+s'),
  ('Save as…', 'ctrl+shift+s'),
  ('Close tab', 'ctrl+w'),
  ('Find', 'ctrl+f'),
  ('Replace', 'ctrl+h'),
  ('Go to line', 'ctrl+g'),
  ('Toggle theme', 'ctrl+t'),
  ('Quit', 'ctrl+q'),
];

/// The Dart of the OptionList page.
String _optionListCode(Options o) {
  final q = o.choice<String>('query');
  final details = o.flag('details');
  final detail = details ? ', detail: keys' : '';
  return [
    'const _commands = [',
    for (final (l, k) in _commands) "  ('$l', '$k'),",
    '];',
    '',
    'var _highlighted = 0;',
    'String? _ran;',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    if (q.isNotEmpty) ...[
      "  // the commands '$q' matches, its characters marked",
      '  final options = [',
      '    for (final (label, ${details ? 'keys' : '_'}) in _commands)',
      "      if (fuzzyMatch('$q', label) case final match?)",
      '        Option(label, marks: match.positions$detail),',
      '  ];',
    ] else if (details) ...[
      '  final options = [',
      '    for (final (label, keys) in _commands) Option(label, detail: keys),',
      '  ];',
    ] else
      '  final options = [for (final (label, _) in _commands) Option(label)];',
    '  final highlighted = _highlighted.clamp(0, options.length - 1);',
    '  void highlight(int i) => setState(() => _highlighted = i);',
    '  void move(int by) =>',
    '      highlight((highlighted + by).clamp(0, options.length - 1));',
    '  void run(int i) => setState(() => _ran = options[i].label);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      // the list takes no keys: a Pressable around it',
    '      // does, its border primary while it has the focus',
    '      Pressable(',
    '        bindings: {',
    "          'up': () => move(-1),",
    "          'down': () => move(1),",
    "          'enter': () => run(highlighted),",
    '        },',
    "        hints: const {'up': 'select', 'down': 'select', 'enter': 'run'},",
    '        builder: (context, focused) => Box(',
    '          border: .all(',
    '            type: .rounded,',
    '            style: focused ? theme.primary : theme.border,',
    '          ),',
    '          child: OptionList(',
    '            options: options,',
    '            highlighted: highlighted,',
    '            rows: ${o.label('rows')},',
    if (!o.flag('bar')) '            bar: false,',
    if (!o.flag('thumb')) '            thumb: false,',
    '            onHighlight: highlight,',
    '            onSelected: run,',
    '          ),',
    '        ),',
    '      ),',
    '      Text.rich([',
    "        Span('ran: ', theme.muted),",
    '        if (_ran case final ran?)',
    '          Span(ran)',
    '        else',
    "          Span('nothing', theme.muted),",
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n');
}

/// The OptionList page's widget: the commands [query] matches in an
/// OptionList of [rows] rows, the keys a Pressable's around it, and what
/// ran.
final class _Options extends StatefulWidget {
  const _Options({
    required this.query,
    required this.rows,
    required this.details,
    required this.bar,
    required this.thumb,
  });

  final String query;
  final int rows;
  final bool details;
  final bool bar;
  final bool thumb;

  @override
  State<_Options> createState() => _OptionsState();
}

final class _OptionsState extends State<_Options> with KeptState {
  // kept in the page's state while the gallery runs
  int get _highlighted => kept['highlighted'] as int? ?? 0;
  set _highlighted(int i) => kept['highlighted'] = i;
  String? get _ran => kept['ran'] as String?;
  int get _serial => kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.query;
    final options = [
      for (final (label, keys) in _commands)
        if (fuzzyMatch(q, label) case final match?)
          Option(
            label,
            marks: match.positions,
            detail: widget.details ? keys : null,
          ),
    ];
    final highlighted = _highlighted.clamp(0, options.length - 1);
    void highlight(int i) => setState(() => _highlighted = i);
    void move(int by) =>
        highlight((highlighted + by).clamp(0, options.length - 1));
    void run(int i) => setState(() {
      kept['ran'] = options[i].label;
      kept['serial'] = _serial + 1;
    });
    final ran = _ran;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Pressable(
          bindings: {
            'up': () => move(-1),
            'down': () => move(1),
            'enter': () => run(highlighted),
          },
          hints: const {'up': 'select', 'down': 'select', 'enter': 'run'},
          builder: (context, focused) => Box(
            border: Border.all(
              type: BorderType.rounded,
              style: focused ? theme.primary : theme.border,
            ),
            child: OptionList(
              options: options,
              highlighted: highlighted,
              rows: widget.rows,
              bar: widget.bar,
              thumb: widget.thumb,
              onHighlight: highlight,
              onSelected: run,
            ),
          ),
        ),
        LitLine([
          ('ran: ', true),
          if (ran == null) ('nothing', true) else (ran, false),
        ], serial: _serial),
      ],
    );
  }
}
