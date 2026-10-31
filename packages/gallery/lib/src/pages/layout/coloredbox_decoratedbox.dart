// The ColoredBox, DecoratedBox page.
part of 'layout.dart';

// ------------------------------------------------------------ DecoratedBox

const _notes = 'release 0.4.0\n3 commits, 2 fixes';

/// The ColoredBox, DecoratedBox page's `position` option.
const _decoratedBoxPosition = ChoiceOption<String>(
  'position',
  'position',
  values: ['background', 'foreground'],
);

/// The ColoredBox, DecoratedBox page's `fill` option.
const _decoratedBoxFill = ChoiceOption<String>(
  'fill',
  'fill',
  values: ['color', 'gradient'],
  labels: ['ColoredBox', 'gradient'],
);

/// The ColoredBox, DecoratedBox page's `border` option.
const _decoratedBoxBorder = ChoiceOption<String>(
  'border',
  'border',
  values: ['single', 'rounded', 'double', 'heavy', 'ascii'],
  initial: 'rounded',
);

/// The ColoredBox, DecoratedBox page's `titles` option.
const _decoratedBoxTitles = SwitchOption(
  'titles',
  'titles',
  initial: true,
);

final _decoratedBox = GalleryPage(
  group: _group,
  title: 'ColoredBox, DecoratedBox',
  options: const [
    _decoratedBoxPosition,
    _decoratedBoxFill,
    _decoratedBoxBorder,
    _decoratedBoxTitles,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final gradient = o(_decoratedBoxFill) == 'gradient';
    const notes = Padding(padding: EdgeInsets.all(1), child: Text(_notes));
    return DecoratedBox(
      position: o(_decoratedBoxPosition) == 'foreground'
          ? DecorationPosition.foreground
          : DecorationPosition.background,
      decoration: BoxDecoration(
        border: Border.all(
          type: BorderType.values.byName(o(_decoratedBoxBorder)),
          style: theme.border,
        ),
        titles: [
          if (o(_decoratedBoxTitles))
            BorderTitle(' notes ', style: theme.muted),
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
    final type = o(_decoratedBoxBorder) == 'single'
        ? ''
        : 'type: .${o(_decoratedBoxBorder)}, ';
    final gradient = o(_decoratedBoxFill) == 'gradient';
    const notes = [
      'const Padding(',
      '  padding: .all(1),',
      r"  child: Text('release 0.4.0\n3 commits, 2 fixes'),",
      '),',
    ];
    return [
      'final theme = Theme.of(context);',
      'return DecoratedBox(',
      if (o(_decoratedBoxPosition) == 'foreground') '  position: .foreground,',
      '  decoration: BoxDecoration(',
      '    border: .all(${type}style: theme.border),',
      if (o(_decoratedBoxTitles))
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
