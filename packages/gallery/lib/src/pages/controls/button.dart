// The Button page.
part of 'controls.dart';

final _buttonPage = GalleryPage(
  group: 'Controls',
  title: 'Button',
  options: const [
    pageColorOption,
    ChoiceOption('look', 'look', values: ['chip', 'outlined', 'filled']),
    SwitchOption('tall', 'tall'),
  ],
  build: (context, o) => _Buttons(
    color: o.color('color'),
    look: o.choice('look'),
    tall: o.flag('tall'),
  ),
  code: (o) {
    final c = o.color('color');
    final styled = c != 'primary';
    final look = o.choice<String>('look');
    final chip = look == 'chip';
    final button = chip ? 'Button' : 'Button.$look';
    final args = [
      if (styled && chip) ...['style: style', 'focusedStyle: focused'],
      if (styled && !chip) 'style: theme.$c',
      if (!chip && o.flag('tall')) 'tall: true',
    ];
    return [
      'var _saved = 0;',
      'var _sent = 0;',
      '',
      '// Button, as each control here, stands on',
      '// Pressable: a node that Tab stops at unless it',
      '// is disabled, the keys it binds while it has',
      '// the focus (Enter, Space), a press that focuses',
      '// it and a click.',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      if (styled && chip) ...[
        '  final style = theme.$c.merge(const .new(attrs: Attr.bold));',
        '  final focused = style.merge(const .new(attrs: Attr.reverse));',
      ],
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      Row(',
      '        mainAxisSize: .min,',
      '        gap: 2,',
      '        children: [',
      ...call(10, button, [
        "'Save'",
        ...args,
        'onPressed: () => setState(() => _saved++)',
      ], ','),
      ...call(10, button, [
        "'Send'",
        ...args,
        'onPressed: () => setState(() => _sent++)',
      ], ','),
      ...call(10, '${styled ? '' : 'const '}$button', [
        "'Disabled'",
        ...args,
        'onPressed: null',
      ], ','),
      '        ],',
      '      ),',
      '      Text.rich([',
      "        Span('saved: ', theme.muted),",
      r"        Span('$_saved'),",
      "        Span('  sent: ', theme.muted),",
      r"        Span('$_sent'),",
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// Save, Send and a disabled button, and how often each was pressed.
final class _Buttons extends StatefulWidget {
  const _Buttons({required this.color, this.look = 'chip', this.tall = false});

  final String color;

  /// `chip`, `outlined` or `filled`: Button, Button.outlined, Button.filled.
  final String look;

  /// Whether an outlined or a filled one is three rows.
  final bool tall;

  @override
  State<_Buttons> createState() => _ButtonsState();
}

final class _ButtonsState extends State<_Buttons> with KeptState {
  // kept in the page's state while the gallery runs
  int get _saved => kept['saved'] as int? ?? 0;
  set _saved(int n) => kept['saved'] = n;
  int get _sent => kept['sent'] as int? ?? 0;
  set _sent(int n) => kept['sent'] = n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styled = widget.color != 'primary';
    final style = styled
        ? themeColor(theme, widget.color).merge(const Style(attrs: Attr.bold))
        : null;
    final focused = style?.merge(const Style(attrs: Attr.reverse));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 2,
          children: [
            for (final (label, onPressed) in [
              ('Save', () => setState(() => _saved++)),
              ('Send', () => setState(() => _sent++)),
              ('Disabled', null),
            ])
              switch (widget.look) {
                'outlined' => Button.outlined(
                  label,
                  tall: widget.tall,
                  style: styled ? themeColor(theme, widget.color) : null,
                  onPressed: onPressed,
                ),
                'filled' => Button.filled(
                  label,
                  tall: widget.tall,
                  style: styled ? themeColor(theme, widget.color) : null,
                  onPressed: onPressed,
                ),
                _ => Button(
                  label,
                  style: style,
                  focusedStyle: focused,
                  onPressed: onPressed,
                ),
              },
          ],
        ),
        LitLine([
          ('saved: ', true),
          ('$_saved', false),
          ('  sent: ', true),
          ('$_sent', false),
        ], serial: _saved + _sent),
      ],
    );
  }
}
