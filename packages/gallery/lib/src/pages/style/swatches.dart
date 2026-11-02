// The swatches of a theme's colours, which the Theme and the
// TerminalBrightness pages show.
part of 'style.dart';

const _cardWidth = 46;

/// twk's _Swatches of the Code: each style of the theme, named in it, on
/// its background, a panel on its surface; with a [name], the name on its
/// border and a Button, a Checkbox and a Switch, live, in it too, their
/// values kept in the page's state.
final class _Swatches extends StatefulWidget {
  const _Swatches([this.name]);

  final String? name;

  @override
  State<_Swatches> createState() => _SwatchesState();
}

final class _SwatchesState extends State<_Swatches> with KeptState {
  bool get _checked => kept['check'] as bool? ?? true;
  set _checked(bool v) => kept['check'] = v;
  bool get _on => kept['on'] as bool? ?? true;
  set _on(bool v) => kept['on'] = v;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.name;
    final text = [
      ('text', theme.text),
      ('muted', theme.muted),
      ('primary', theme.primary),
      ('accent', theme.accent),
      ('border', theme.border),
    ];
    final status = [
      ('error', theme.error),
      ('warning', theme.warning),
      ('success', theme.success),
      ('info', theme.info),
    ];
    return SizedBox(
      width: _cardWidth,
      child: Box(
        style: theme.background.merge(theme.text),
        border: Border.all(type: BorderType.rounded, style: theme.border),
        titles: [
          if (name != null)
            BorderTitle(' $name ', style: theme.text.merge(bold)),
        ],
        padding: const EdgeInsets.x(2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich([for (final (n, style) in text) Span('$n  ', style)]),
            Text.rich([for (final (n, style) in status) Span('$n  ', style)]),
            const SizedBox(height: 1),
            Box(
              style: theme.surface,
              border: Border.all(type: BorderType.rounded, style: theme.border),
              titles: [BorderTitle(' surface ', style: theme.muted)],
              padding: const EdgeInsets.x(1),
              child: Text.rich([
                const Span('a panel, with '),
                Span(' selection ', theme.selection),
                const Span(' in it'),
              ]),
            ),
            if (name != null) ...[
              const SizedBox(height: 1),
              Row(
                gap: 3,
                children: [
                  Button('Button', onPressed: () {}),
                  Checkbox(
                    value: _checked,
                    label: 'Checkbox',
                    onChanged: (value) => setState(() => _checked = value),
                  ),
                  Switch(
                    value: _on,
                    label: 'Switch',
                    onChanged: (value) => setState(() => _on = value),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              const Row(
                gap: 2,
                children: [
                  StatusMessage('Saved', kind: StatusKind.success),
                  Expanded(
                    child: LineGauge(
                      ratio: 0.6,
                      unfilledStyle: Style(attrs: Attr.dim),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Code's line of the name on the border of _Swatches.
const _titleLine =
    r"          BorderTitle(' ${widget.name} ', "
    'style: theme.text.merge(bold)),';

/// The Dart of _Swatches: with [named], its name and controls.
List<String> _swatchesCode({required bool named}) => [
  '/// Each style of the theme, named in it, on its background.',
  if (named) ...[
    'final class _Swatches extends StatefulWidget {',
    '  const _Swatches(this.name);',
    '',
    '  final String name;',
    '',
    '  @override',
    '  State<_Swatches> createState() => _SwatchesState();',
    '}',
    '',
    'final class _SwatchesState extends State<_Swatches> {',
    '  var _checked = true;',
    '  var _on = true;',
    '',
  ] else ...[
    'final class _Swatches extends StatelessWidget {',
    '  const _Swatches();',
    '',
  ],
  '  @override',
  '  Widget build(BuildContext context) {',
  '    final theme = Theme.of(context);',
  '    final text = [',
  "      ('text', theme.text),",
  "      ('muted', theme.muted),",
  "      ('primary', theme.primary),",
  "      ('accent', theme.accent),",
  "      ('border', theme.border),",
  '    ];',
  '    final status = [',
  "      ('error', theme.error),",
  "      ('warning', theme.warning),",
  "      ('success', theme.success),",
  "      ('info', theme.info),",
  '    ];',
  '    return SizedBox(',
  '      width: $_cardWidth,',
  '      child: Box(',
  '        style: theme.background.merge(theme.text),',
  '        border: .all(type: .rounded, style: theme.border),',
  if (named) ...[
    '        titles: [',
    _titleLine,
    '        ],',
  ],
  '        padding: const .x(2),',
  '        child: Column(',
  '          mainAxisSize: .min,',
  '          crossAxisAlignment: .stretch,',
  '          children: [',
  '            Text.rich([',
  r"              for (final (name, style) in text) Span('$name  ', style),",
  '            ]),',
  '            Text.rich([',
  r"              for (final (name, style) in status) Span('$name  ', style),",
  '            ]),',
  '            const SizedBox(height: 1),',
  '            Box(',
  '              style: theme.surface,',
  '              border: .all(type: .rounded, style: theme.border),',
  "              titles: [BorderTitle(' surface ', style: theme.muted)],",
  '              padding: const .x(1),',
  '              child: Text.rich([',
  "                const Span('a panel, with '),",
  "                Span(' selection ', theme.selection),",
  "                const Span(' in it'),",
  '              ]),',
  '            ),',
  if (named) ...[
    '            const SizedBox(height: 1),',
    '            Row(',
    '              gap: 3,',
    '              children: [',
    "                Button('Button', onPressed: () {}),",
    '                Checkbox(',
    '                  value: _checked,',
    "                  label: 'Checkbox',",
    '                  onChanged: (value) => setState(() => _checked = value),',
    '                ),',
    '                Switch(',
    '                  value: _on,',
    "                  label: 'Switch',",
    '                  onChanged: (value) => setState(() => _on = value),',
    '                ),',
    '              ],',
    '            ),',
    '            const SizedBox(height: 1),',
    '            const Row(',
    '              gap: 2,',
    '              children: [',
    "                StatusMessage('Saved', kind: StatusKind.success),",
    '                Expanded(',
    '                  child: LineGauge(',
    '                    ratio: 0.6,',
    '                    unfilledStyle: Style(attrs: Attr.dim),',
    '                  ),',
    '                ),',
    '              ],',
    '            ),',
  ],
  '          ],',
  '        ),',
  '      ),',
  '    );',
  '  }',
  '}',
  if (named) ...['', 'const bold = Style(attrs: Attr.bold);'],
];
