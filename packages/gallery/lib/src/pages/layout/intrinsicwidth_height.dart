// The IntrinsicWidth/Height page.
part of 'layout.dart';

// ---------------------------------------------------- IntrinsicWidth/Height

const _iw = 44;

const _ih = 7;

final _intrinsic = GalleryPage(
  group: 'Layout',
  title: 'IntrinsicWidth/Height',
  options: const [
    SwitchOption('iw', 'IntrinsicWidth', initial: true),
    SwitchOption('ih', 'IntrinsicHeight', initial: true),
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
          if (o.flag('iw')) IntrinsicWidth(child: menu) else menu,
          if (o.flag('ih')) IntrinsicHeight(child: cards) else cards,
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
    '      ${o.flag('iw') ? 'IntrinsicWidth(child: menu)' : 'menu'},',
    '      ${o.flag('ih') ? 'IntrinsicHeight(child: cards)' : 'cards'},',
    '    ],',
    '  ),',
    ');',
  ].join('\n'),
);
