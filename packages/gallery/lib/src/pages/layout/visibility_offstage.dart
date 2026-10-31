// The Visibility, Offstage page.
part of 'layout.dart';

// -------------------------------------------------------- Visibility, Offstage

final _visibility = GalleryPage(
  group: 'Layout',
  title: 'Visibility, Offstage',
  options: [
    const ChoiceOption('widget', 'widget', values: ['Visibility', 'Offstage']),
    const SwitchOption('hidden', 'hidden', initial: true),
    ChoiceOption(
      'keep',
      'keeps',
      values: const ['nothing', 'state', 'size'],
      disabled: (o) => o['widget'] != 'Visibility',
    ),
    SwitchOption(
      'replacement',
      'replacement',
      disabled: (o) => !_replaces(o),
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final hidden = o.flag('hidden');
    final keep = o['keep'];
    final child = Box(
      border: _rounded(theme),
      padding: const EdgeInsets.x(1),
      child: const Text('the child'),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('above the child'),
        if (o['widget'] == 'Offstage')
          Offstage(offstage: hidden, child: child)
        else
          Visibility(
            visible: !hidden,
            maintainState: keep != 'nothing',
            maintainSize: keep == 'size',
            replacement: o.flag('replacement') && _replaces(o)
                ? Text('in its place', style: theme.muted)
                : const SizedBox.shrink(),
            child: child,
          ),
        const Text('below the child'),
      ],
    );
  },
  code: (o) {
    final hidden = o.flag('hidden');
    const child = [
      '      child: Box(',
      '        border: .all(type: .rounded, style: theme.border),',
      '        padding: const .x(1),',
      "        child: const Text('the child'),",
      '      ),',
    ];
    return [
      'final theme = Theme.of(context);',
      'return Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  children: [',
      "    const Text('above the child'),",
      if (o['widget'] == 'Offstage') ...[
        '    Offstage(',
        '      offstage: $hidden,',
        ...child,
        '    ),',
      ] else ...[
        '    Visibility(',
        '      visible: ${!hidden},',
        if (o['keep'] != 'nothing') '      maintainState: true,',
        if (o['keep'] == 'size') '      maintainSize: true,',
        if (o.flag('replacement') && _replaces(o))
          "      replacement: Text('in its place', style: theme.muted),",
        ...child,
        '    ),',
      ],
      "    const Text('below the child'),",
      '  ],',
      ');',
    ].join('\n');
  },
);

/// Whether the Visibility page's child has a replacement to show: in a
/// Visibility that keeps nothing of it.
bool _replaces(Options o) =>
    o['widget'] == 'Visibility' && o['keep'] == 'nothing';
