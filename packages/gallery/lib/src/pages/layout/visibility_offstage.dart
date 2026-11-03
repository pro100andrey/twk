// The Visibility, Offstage page.
part of 'layout.dart';

/// The Visibility, Offstage page's `widget` option.
const _visibilityWidget = ChoiceOption<String>(
  'widget',
  'widget',
  values: ['Visibility', 'Offstage'],
);

/// The Visibility, Offstage page's `hidden` option.
const _visibilityHidden = SwitchOption(
  'hidden',
  'hidden',
  initial: true,
);

/// The Visibility, Offstage page's `keep` option.
final _visibilityKeep = ChoiceOption<String>(
  'keep',
  'keeps',
  values: const ['nothing', 'state', 'size'],
  disabled: (o) => o(_visibilityWidget) != 'Visibility',
);

/// The Visibility, Offstage page's `replacement` option.
final _visibilityReplacement = SwitchOption(
  'replacement',
  'replacement',
  disabled: (o) => !_replaces(o),
);

// -------------------------------------------------------- Visibility, Offstage

final _visibility = GalleryPage(
  group: _group,
  title: 'Visibility, Offstage',
  options: [
    _visibilityWidget,
    _visibilityHidden,
    _visibilityKeep,
    _visibilityReplacement,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final hidden = o(_visibilityHidden);
    final keep = o(_visibilityKeep);
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
        if (o(_visibilityWidget) == 'Offstage')
          Offstage(offstage: hidden, child: child)
        else
          Visibility(
            visible: !hidden,
            maintainState: keep != 'nothing',
            maintainSize: keep == 'size',
            replacement: o(_visibilityReplacement) && _replaces(o)
                ? Text('in its place', style: theme.muted)
                : const SizedBox.shrink(),
            child: child,
          ),
        const Text('below the child'),
      ],
    );
  },
  code: (o) {
    final hidden = o(_visibilityHidden);
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
      if (o(_visibilityWidget) == 'Offstage') ...[
        '    Offstage(',
        '      offstage: $hidden,',
        ...child,
        '    ),',
      ] else ...[
        '    Visibility(',
        '      visible: ${!hidden},',
        if (o(_visibilityKeep) != 'nothing') '      maintainState: true,',
        if (o(_visibilityKeep) == 'size') '      maintainSize: true,',
        if (o(_visibilityReplacement) && _replaces(o))
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
    o(_visibilityWidget) == 'Visibility' && o(_visibilityKeep) == 'nothing';
