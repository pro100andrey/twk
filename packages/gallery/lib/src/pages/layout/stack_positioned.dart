// The Stack, Positioned page.
part of 'layout.dart';

// -------------------------------------------------------- Stack, Positioned

const _sw = 38;

const _sh = 9;

final _stack = GalleryPage(
  group: 'Layout',
  title: 'Stack, Positioned',
  options: [
    ..._alignOptions(0, 0),
    const ChoiceOption(
      'fit',
      'fit',
      values: ['loose', 'expand', 'passthrough'],
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      // tight across, loose down: each fit lays the child out otherwise
      constraints: const BoxConstraints(_sw, _sw, 0, _sh),
      child: Box(
        border: _rounded(theme),
        child: Stack(
          alignment: Alignment(o.choice('ax'), o.choice('ay')),
          fit: StackFit.values.byName(o.choice('fit')),
          children: [
            // the room the others are placed in: the stack as big as it may
            // be
            const SizedBox.expand(),
            Box(
              style: theme.selection,
              padding: const EdgeInsets.x(1),
              child: const Text('not positioned'),
            ),
            const Positioned(right: 0, top: 0, child: Badge('top right')),
            Positioned(
              left: 0,
              bottom: 0,
              child: Text('bottom left', style: theme.muted),
            ),
          ],
        ),
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'return ConstrainedBox(',
    '  // tight across, loose down: each fit lays the child out otherwise',
    '  constraints: const BoxConstraints($_sw, $_sw, 0, $_sh),',
    '  child: Box(',
    '    border: .all(type: .rounded, style: theme.border),',
    '    child: Stack(',
    if (_alignmentOf(o) != 'topLeft') '      alignment: .${_alignmentOf(o)},',
    if (o['fit'] != 'loose') '      fit: .${o.label('fit')},',
    '      children: [',
    '        // the room the others are placed in: the stack as big as it may be',
    '        const SizedBox.expand(),',
    '        Box(',
    '          style: theme.selection,',
    '          padding: const .x(1),',
    "          child: const Text('not positioned'),",
    '        ),',
    "        const Positioned(right: 0, top: 0, child: Badge('top right')),",
    '        Positioned(',
    '          left: 0,',
    '          bottom: 0,',
    "          child: Text('bottom left', style: theme.muted),",
    '        ),',
    '      ],',
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);
