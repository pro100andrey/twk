// The ColoredBox, DecoratedBox page.
part of 'layout.dart';

// ------------------------------------------------------------ DecoratedBox

const _notes = 'release 0.4.0\n3 commits, 2 fixes';

final _decoratedBox = GalleryPage(
  group: 'Layout',
  title: 'ColoredBox, DecoratedBox',
  options: const [
    ChoiceOption('position', 'position', values: ['background', 'foreground']),
    ChoiceOption(
      'fill',
      'fill',
      values: ['color', 'gradient'],
      labels: ['ColoredBox', 'gradient'],
    ),
    ChoiceOption(
      'border',
      'border',
      values: ['single', 'rounded', 'double', 'heavy', 'ascii'],
      initial: 'rounded',
    ),
    SwitchOption('titles', 'titles', initial: true),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final gradient = o['fill'] == 'gradient';
    const notes = Padding(padding: EdgeInsets.all(1), child: Text(_notes));
    return DecoratedBox(
      position: o['position'] == 'foreground'
          ? DecorationPosition.foreground
          : DecorationPosition.background,
      decoration: BoxDecoration(
        border: Border.all(
          type: BorderType.values.byName(o.choice('border')),
          style: theme.border,
        ),
        titles: [
          if (o.flag('titles')) BorderTitle(' notes ', style: theme.muted),
        ],
        gradient: gradient
            ? Gradient([theme.primary.fg!, theme.accent.fg!])
            : null,
      ),
      child: gradient
          ? notes
          : ColoredBox(color: theme.selection.bg!, child: notes),
    );
  },
  code: (o) {
    final type = o['border'] == 'single' ? '' : 'type: .${o['border']}, ';
    final gradient = o['fill'] == 'gradient';
    const notes = [
      'const Padding(',
      '  padding: .all(1),',
      r"  child: Text('release 0.4.0\n3 commits, 2 fixes'),",
      '),',
    ];
    return [
      'final theme = Theme.of(context);',
      'return DecoratedBox(',
      if (o['position'] == 'foreground') '  position: .foreground,',
      '  decoration: BoxDecoration(',
      '    border: .all(${type}style: theme.border),',
      if (o.flag('titles'))
        "    titles: [BorderTitle(' notes ', style: theme.muted)],",
      if (gradient)
        '    gradient: Gradient([theme.primary.fg!, theme.accent.fg!]),',
      '  ),',
      if (gradient) ...[
        '  child: ${notes.first}',
        for (final l in notes.skip(1)) '  $l',
      ] else ...[
        '  child: ColoredBox(',
        '    color: theme.selection.bg!,',
        '    child: ${notes.first}',
        for (final l in notes.skip(1)) '    $l',
        '  ),',
      ],
      ');',
    ].join('\n');
  },
);
