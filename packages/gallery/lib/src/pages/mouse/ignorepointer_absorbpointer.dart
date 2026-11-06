// The IgnorePointer, AbsorbPointer page.
part of 'mouse.dart';

/// The IgnorePointer, AbsorbPointer page's `gate` option.
const _ignorepointerAbsorbpointerGate = ChoiceOption<String>(
  'gate',
  'around the button',
  values: ['none', 'ignore', 'absorb'],
  labels: ['none', 'IgnorePointer', 'AbsorbPointer'],
  initial: 'ignore',
);

final _ignorepointerAbsorbpointerPage = GalleryPage(
  group: _group,
  title: 'IgnorePointer, AbsorbPointer',
  options: const [
    _ignorepointerAbsorbpointerGate,
  ],
  build: (context, o) => _Gated(gate: o(_ignorepointerAbsorbpointerGate)),
  code: _gatedCode,
);

/// The backdrop: its width and rows.
const _backdropW = 36;

const _backdropH = 7;

const _backdropTap =
    "            onTap: () => setState(() => _heard = 'the backdrop'),";

const _backdropTitle =
    "                titles: [BorderTitle(' backdrop ', style: theme.muted)],";

const _heardLine =
    "        if (_heard.isEmpty) Span('nothing', theme.muted) else "
    'Span(_heard),';

/// A button over a backdrop, in a Stack, the button inside an
/// IgnorePointer or an AbsorbPointer as [gate] says (`none`, `ignore`,
/// `absorb`): what heard a click says so under them.
final class _Gated extends StatefulWidget {
  const _Gated({required this.gate});

  final String gate;

  @override
  State<_Gated> createState() => _GatedState();
}

final class _GatedState extends State<_Gated> {
  var _over = false;
  var _heard = '';
  var _serial = 0;

  void _hear(String what) => setState(() {
    _heard = what;
    _serial++;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget button = MouseRegion(
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: GestureDetector(
        onTap: () => _hear('the button'),
        child: Box(
          border: Border.all(
            type: BorderType.rounded,
            style: _over ? theme.primary : theme.border,
          ),
          padding: const EdgeInsets.x(2),
          child: const Text('click me'),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: () => _hear('the backdrop'),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: _backdropW,
                height: _backdropH,
                child: Box(
                  border: _roundedBorder(theme),
                  titles: [BorderTitle(' backdrop ', style: theme.muted)],
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: switch (widget.gate) {
                  'ignore' => IgnorePointer(child: button),
                  'absorb' => AbsorbPointer(child: button),
                  _ => button,
                },
              ),
            ),
          ],
        ),
        LitLine([
          ('heard: ', true),
          if (_heard.isEmpty) ('nothing', true) else (_heard, false),
        ], serial: _serial),
      ],
    );
  }
}

Border _roundedBorder(ThemeData theme) =>
    Border.all(type: BorderType.rounded, style: theme.border);

String _gatedCode(Options o) {
  final gate = switch (o(_ignorepointerAbsorbpointerGate)) {
    'ignore' => 'IgnorePointer',
    'absorb' => 'AbsorbPointer',
    _ => null,
  };
  const button = [
    'MouseRegion(',
    '  onEnter: (_) => setState(() => _over = true),',
    '  onExit: (_) => setState(() => _over = false),',
    '  child: GestureDetector(',
    "    onTap: () => setState(() => _heard = 'the button'),",
    '    child: Box(',
    '      border: .all(',
    '        type: .rounded,',
    '        style: _over ? theme.primary : theme.border,',
    '      ),',
    '      padding: const .x(2),',
    "      child: const Text('click me'),",
    '    ),',
    '  ),',
    '),',
  ];
  List<String> pad(int n, Iterable<String> lines) => [
    for (final l in lines) '${' ' * n}$l',
  ];
  final child = gate != null
      ? [
          '              child: $gate(',
          '                child: ${button.first}',
          ...pad(16, button.sublist(1, button.length - 1)),
          '                ),',
          '              ),',
        ]
      : [
          '              child: ${button.first}',
          ...pad(14, button.sublist(1)),
        ];
  return [
    'var _over = false;',
    "var _heard = '';",
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    spacing: 1,',
    '    children: [',
    '      Stack(',
    '        children: [',
    '          GestureDetector(',
    _backdropTap,
    '            behavior: .opaque,',
    '            child: SizedBox(',
    '              width: $_backdropW,',
    '              height: $_backdropH,',
    '              child: Box(',
    '                border: .all(type: .rounded, style: theme.border),',
    _backdropTitle,
    '              ),',
    '            ),',
    '          ),',
    '          Positioned.fill(',
    '            child: Center(',
    ...child,
    '            ),',
    '          ),',
    '        ],',
    '      ),',
    '      Text.rich([',
    "        Span('heard: ', theme.muted),",
    _heardLine,
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n');
}
