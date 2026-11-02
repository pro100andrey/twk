// The IntrinsicWidth/Height page.
part of 'layout.dart';

// ---------------------------------------------------- IntrinsicWidth/Height

const _iw = 44;

const _ih = 7;

/// The IntrinsicWidth/Height page's `iw` option.
const _intrinsicIw = SwitchOption(
  'iw',
  'IntrinsicWidth',
  initial: true,
);

/// The IntrinsicWidth/Height page's `ih` option.
const _intrinsicIh = SwitchOption(
  'ih',
  'IntrinsicHeight',
  initial: true,
);

final _intrinsic = GalleryPage(
  group: _group,
  title: 'IntrinsicWidth/Height',
  options: const [
    _intrinsicIw,
    _intrinsicIh,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final menu = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, label) in ['Open…', 'Save as…', 'Close window'].indexed)
          Box(
            style: i == 0 ? theme.selection : theme.surface,
            padding: const EdgeInsets.x(1),
            child: Text(label),
          ),
      ],
    );
    final cards = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      gap: 1,
      children: [
        for (final text in ['one', 'three lines here'])
          SizedBox(
            width: 10,
            child: Box(border: _rounded(theme), child: Text(text)),
          ),
      ],
    );
    return SizedBox(
      width: _iw,
      height: _ih,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 4,
        children: [
          if (o(_intrinsicIw)) IntrinsicWidth(child: menu) else menu,
          if (o(_intrinsicIh)) IntrinsicHeight(child: cards) else cards,
        ],
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'final menu = Column(',
    '  crossAxisAlignment: .stretch,',
    '  children: [',
    codeLine([
      '    for (final (i, label) in ',
      "['Open…', 'Save as…', 'Close window'].indexed)",
    ]),
    '      Box(',
    '        style: i == 0 ? theme.selection : theme.surface,',
    '        padding: const .x(1),',
    '        child: Text(label),',
    '      ),',
    '  ],',
    ');',
    'final cards = Row(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .stretch,',
    '  gap: 1,',
    '  children: [',
    "    for (final text in ['one', 'three lines here'])",
    '      SizedBox(',
    '        width: 10,',
    '        child: Box(',
    '          border: .all(type: .rounded, style: theme.border),',
    '          child: Text(text),',
    '        ),',
    '      ),',
    '  ],',
    ');',
    'return SizedBox(',
    '  width: $_iw,',
    '  height: $_ih,',
    '  child: Row(',
    '    crossAxisAlignment: .start,',
    '    gap: 4,',
    '    children: [',
    '      ${o(_intrinsicIw) ? 'IntrinsicWidth(child: menu)' : 'menu'},',
    '      ${o(_intrinsicIh) ? 'IntrinsicHeight(child: cards)' : 'cards'},',
    '    ],',
    '  ),',
    ');',
  ].join('\n'),
);
