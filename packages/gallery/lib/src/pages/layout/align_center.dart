// The Align, Center page.
part of 'layout.dart';

// ------------------------------------------------------------ Align, Center

const List<int?> _alignFactors = [null, 1, 2, 3];

/// The Align, Center page's `wf` option.
const _alignCenterWf = ChoiceOption<int?>(
  'wf',
  'width factor',
  values: _alignFactors,
);

/// The Align, Center page's `hf` option.
const _alignCenterHf = ChoiceOption<int?>(
  'hf',
  'height factor',
  values: _alignFactors,
);

final _alignCenter = GalleryPage(
  group: _group,
  title: 'Align, Center',
  options: [
    ..._alignOptions(1, 1),
    _alignCenterWf,
    _alignCenterHf,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final wf = o(_alignCenterWf);
    final hf = o(_alignCenterHf);
    // a factor sizes the box along its axis, so the room does not
    Widget room(String title, Widget child) => SizedBox(
      width: wf == null ? 30 : null,
      height: hf == null ? 5 : null,
      child: Box(
        border: _rounded(theme),
        titles: [BorderTitle(' $title ', style: theme.muted)],
        child: child,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 1,
      children: [
        room(
          '.${_alignmentOf(o)}',
          Align(
            alignment: Alignment(o(_alignX), o(_alignY)),
            widthFactor: wf,
            heightFactor: hf,
            child: const Text('aligned'),
          ),
        ),
        room(
          'Center',
          Center(
            widthFactor: wf,
            heightFactor: hf,
            child: const Text('centred'),
          ),
        ),
      ],
    );
  },
  code: (o) {
    final wf = o(_alignCenterWf);
    final hf = o(_alignCenterHf);
    final factors = [
      if (wf != null) 'widthFactor: $wf',
      if (hf != null) 'heightFactor: $hf',
    ];
    final box = [
      'Box(',
      '  border: .all(type: .rounded, style: theme.border),',
      r"  titles: [BorderTitle(' $title ', style: theme.muted)],",
      '  child: child,',
      ');',
    ];
    return [
      'final theme = Theme.of(context);',
      if (wf != null && hf != null)
        'Widget room(String title, Widget child) => ${box.join('\n')}'
      else ...[
        if (factors.isNotEmpty)
          '// a factor sizes the box along its axis, so the room does not',
        'Widget room(String title, Widget child) => SizedBox(',
        if (wf == null) '  width: 30,',
        if (hf == null) '  height: 5,',
        '  child: ${box.first}',
        for (final l in box.sublist(1, box.length - 1)) '  $l',
        '  ),',
        ');',
      ],
      'return Column(',
      '  mainAxisSize: .min,',
      '  spacing: 1,',
      '  children: [',
      "    room('.${_alignmentOf(o)}', const Align(",
      '      alignment: .${_alignmentOf(o)},',
      for (final f in factors) '      $f,',
      "      child: Text('aligned'),",
      '    )),',
      ..._call(4, "room('Center', const Center", [
        ...factors,
        "child: Text('centred')",
      ], '),'),
      '  ],',
      ');',
    ].join('\n');
  },
);
