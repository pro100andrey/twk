// The Button page.
part of 'controls.dart';

/// The Button page's `look` option.
const _buttonLook = ChoiceOption<String>(
  'look',
  'look',
  values: ['chip', 'outlined', 'filled', 'plain'],
);

/// The Button page's `tall` option.
const _buttonTall = SwitchOption('tall', 'tall');

final _buttonPage = GalleryPage(
  group: _group,
  title: 'Button',
  options: const [
    pageColorOption,
    _buttonLook,
    _buttonTall,
  ],
  build: (context, o) => _Buttons(
    color: o(pageColorOption),
    look: o(_buttonLook),
    tall: o(_buttonTall),
  ),
  code: (o) {
    final c = o(pageColorOption);
    final styled = c != 'primary';
    final look = o(_buttonLook);
    final plain = look == 'plain';
    final chip = look == 'chip' || plain;
    final button = chip ? 'Button' : 'Button.$look';
    final args = [
      if (plain) ...['canRequestFocus: false', 'style: style'],
      if (styled && chip && !plain) ...[
        'style: style',
        'focusedStyle: focused',
      ],
      if (styled && !chip) 'style: theme.$c',
      if (!chip && o(_buttonTall)) 'tall: true',
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
      if (plain)
        '  final style = theme.$c.merge(const .new(attrs: Attr.underline));'
      else if (styled && chip) ...[
        '  final style = theme.$c.merge(const .new(attrs: Attr.bold));',
        '  final focused = style.merge(const .new(attrs: Attr.reverse));',
      ],
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    spacing: 1,',
      '    children: [',
      '      Row(',
      '        mainAxisSize: .min,',
      '        spacing: 2,',
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
      ...call(10, '${styled || plain ? '' : 'const '}$button', [
        "'Disabled'",
        ...args,
        'onPressed: null',
      ], ','),
      '        ],',
      '      ),',
      '      // a key and its caption, each in its own style',
      '      // on the one chip',
      '      Button.rich(',
      "        ['Enter'.bold.fg(Color.yellow), const Span(' send')],",
      '        onPressed: () => setState(() => _sent++),',
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

  /// `chip`, `outlined`, `filled` or `plain`: Button, Button.outlined,
  /// Button.filled, or a flat clickable word that takes no focus.
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
    final flat = themeColor(theme, widget.color).merge(
      const Style(attrs: Attr.underline),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
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
                'plain' => Button(
                  label,
                  canRequestFocus: false,
                  style: flat,
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
        Button.rich([
          'Enter'.bold.fg(Color.yellow),
          const Span(' send'),
        ], onPressed: () => setState(() => _sent++)),
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
