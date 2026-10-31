// The LimitedBox, OverflowBox page.
part of 'layout.dart';

// ----------------------------------------------------- LimitedBox, OverflowBox

const _wider = 'a line wider than the box, cut off at its edges';

const _limited = 'as tall as LimitedBox lets it be';

const Map<String, Alignment> _across = {
  'centerLeft': Alignment.centerLeft,
  'center': Alignment.center,
  'centerRight': Alignment.centerRight,
};

final _limitedBox = GalleryPage(
  group: 'Layout',
  title: 'LimitedBox, OverflowBox',
  options: [
    const ChoiceOption(
      'box',
      'widget',
      values: ['OverflowBox', 'SizedOverflowBox', 'LimitedBox'],
    ),
    ChoiceOption(
      'alignment',
      'alignment',
      values: _across.keys.toList(),
      initial: 'center',
      disabled: (o) => o['box'] == 'LimitedBox',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final alignment = _across[o['alignment']]!;
    return SizedBox(
      width: 30,
      height: 5,
      child: Box(
        border: _rounded(theme),
        titles: [BorderTitle(' 28 × 3 ', style: theme.muted)],
        child: switch (o['box']) {
          'OverflowBox' => OverflowBox(
            maxWidth: 48,
            alignment: alignment,
            child: Text(_wider, style: theme.selection),
          ),
          'SizedOverflowBox' => Center(
            child: SizedOverflowBox(
              size: (16, 1),
              alignment: alignment,
              child: Text(_wider, style: theme.selection),
            ),
          ),
          _ => SingleChildScrollView(
            child: LimitedBox(
              maxHeight: 2,
              child: SizedBox.expand(
                child: ColoredBox(
                  color: theme.selection.bg!,
                  child: const Text(_limited),
                ),
              ),
            ),
          ),
        },
      ),
    );
  },
  code: (o) {
    final align = [
      if (o['alignment'] != 'center') '      alignment: .${o['alignment']},',
    ];
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 30,',
      '  height: 5,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      "    titles: [BorderTitle(' 28 × 3 ', style: theme.muted)],",
      ...switch (o['box']) {
        'OverflowBox' => [
          '    child: OverflowBox(',
          '      maxWidth: 48,',
          ...align,
          '      child: Text(',
          "        '$_wider',",
          '        style: theme.selection,',
          '      ),',
          '    ),',
        ],
        'SizedOverflowBox' => [
          '    child: Center(',
          '      child: SizedOverflowBox(',
          '        size: (16, 1),',
          for (final l in align) '  $l',
          '        child: Text(',
          "          '$_wider',",
          '          style: theme.selection,',
          '        ),',
          '      ),',
          '    ),',
        ],
        _ => [
          '    child: SingleChildScrollView(',
          '      child: LimitedBox(',
          '        maxHeight: 2,',
          '        child: SizedBox.expand(',
          '          child: ColoredBox(',
          '            color: theme.selection.bg!,',
          "            child: const Text('$_limited'),",
          '          ),',
          '        ),',
          '      ),',
          '    ),',
        ],
      },
      '  ),',
      ');',
    ].join('\n');
  },
);
