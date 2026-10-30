// The Layout group of the gallery.
import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';
import 'common.dart';

/// The pages of the Layout group that draw.
final layoutPages = <GalleryPage>[
  _box,
  _decoratedBox,
  _container,
  _divider,
  _shadow,
  _padding,
  _alignCenter,
  _sizedBox,
  _constrainedBox,
  _limitedBox,
  _fractionallySizedBox,
  _intrinsic,
  _flex,
  _expanded,
  _stack,
  _transform,
  _visibility,
  _expansion,
  _grid,
  _wrap,
  _customPaint,
  _splitView,
  _dockArea,
  _scaffold,
];

// ------------------------------------------------------------ shared

/// The lines of the call [head]([args]) at [indent], then [tail], as the
/// layout pages write them: on one line where it fits in 80
/// columns, else an argument a line with a comma after each.
List<String> _call(int indent, String head, List<String> args, String tail) {
  final pad = ' ' * indent;
  final one = '$pad$head(${args.join(', ')})$tail';
  if (one.length <= 80) {
    return [one];
  }
  return [
    '$pad$head(',
    for (final a in args) '$pad  $a,',
    '$pad)$tail',
  ];
}

/// A rounded border in the theme's border style.
Border _rounded(ThemeData theme, {bool merge = false}) =>
    Border.all(type: BorderType.rounded, style: theme.border, merge: merge);

/// [key] of the page's state, made by [create] the first time: what
/// outlives a visit to another page.
T _kept<T>(BuildContext context, String key, T Function() create) =>
    PageControl.of(context).state.putIfAbsent(key, create) as T;

// twk's Alignment by name, and an Alignment's x and y as two choices
const _alignments = [
  'topLeft',
  'topCenter',
  'topRight',
  'centerLeft',
  'center',
  'centerRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
];
const Map<String, Alignment> _byName = {
  'topLeft': Alignment.topLeft,
  'topCenter': Alignment.topCenter,
  'topRight': Alignment.topRight,
  'centerLeft': Alignment.centerLeft,
  'center': Alignment.center,
  'centerRight': Alignment.centerRight,
  'bottomLeft': Alignment.bottomLeft,
  'bottomCenter': Alignment.bottomCenter,
  'bottomRight': Alignment.bottomRight,
};

List<PageOption> _alignOptions(int x, int y) => [
  ChoiceOption(
    'ax',
    'alignment x',
    values: const [-1, 0, 1],
    labels: const ['left', 'center', 'right'],
    initial: x,
  ),
  ChoiceOption(
    'ay',
    'alignment y',
    values: const [-1, 0, 1],
    labels: const ['top', 'center', 'bottom'],
    initial: y,
  ),
];

/// The name of the alignment options' Alignment.
String _alignmentOf(Options o) =>
    _alignments[(o.choice<int>('ay') + 1) * 3 + o.choice<int>('ax') + 1];

// ------------------------------------------------------------ Box

const _u = 1;
const _r = 2;
const _d = 4;
const _l = 8;
const Map<String, int> _sides = {
  'all': _u | _r | _d | _l,
  'top bottom': _u | _d,
  'top left': _u | _l,
  'left': _l,
};
const List<(int, String)> _sideNames = [
  (_u, 'top'),
  (_r, 'right'),
  (_d, 'bottom'),
  (_l, 'left'),
];
const _build =
    'Compiling 14 libraries…\n'
    'lib/src/layout    0.4 s\n'
    'lib/src/render    0.9 s';

final _box = GalleryPage(
  group: 'Layout',
  title: 'Box',
  options: [
    const ChoiceOption(
      'border',
      'border',
      values: ['single', 'rounded', 'double', 'heavy', 'ascii', 'none'],
      initial: 'rounded',
    ),
    ChoiceOption('sides', 'sides', values: _sides.keys.toList()),
    const SwitchOption('titles', 'titles', initial: true),
    ChoiceOption(
      'at',
      'title at',
      values: const [
        'topLeft',
        'topCenter',
        'topRight',
        'bottomLeft',
        'bottomCenter',
      ],
      disabled: (o) => !o.flag('titles'),
    ),
    const ChoiceOption('padding', 'padding', values: [0, 1, 2], initial: 1),
    const SwitchOption('surface', 'surface'),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final type = BorderType.values.byName(o.choice('border'));
    final sides = _sides[o.choice<String>('sides')]!;
    Style? side(int bit) => sides & bit != 0 ? theme.border : null;
    return SizedBox(
      width: 36,
      height: 8,
      child: Box(
        style: o.flag('surface') ? theme.surface : null,
        border: sides == _sides['all']
            ? Border.all(type: type, style: theme.border)
            : Border(
                type: type,
                top: side(_u),
                right: side(_r),
                bottom: side(_d),
                left: side(_l),
              ),
        titles: [
          if (o.flag('titles')) ...[
            BorderTitle(
              ' build ',
              style: theme.text.merge(const Style(attrs: Attr.bold)),
              alignment: _byName[o.choice<String>('at')]!,
            ),
            BorderTitle(
              ' 2 warnings ',
              style: theme.warning,
              alignment: Alignment.bottomRight,
            ),
          ],
        ],
        padding: EdgeInsets.all(o.choice<int>('padding')),
        child: const Text(_build),
      ),
    );
  },
  code: (o) {
    final border = o.label('border');
    final type = border == 'single' ? <String>[] : ['type: .$border'];
    final sides = _sides[o.choice<String>('sides')]!;
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 36,',
      '  height: 8,',
      '  child: Box(',
      if (o.flag('surface')) '    style: theme.surface,',
      if (sides == _sides['all'])
        '    border: .all(${[...type, 'style: theme.border'].join(', ')}),'
      else
        ..._call(4, 'border: Border', [
          ...type,
          for (final (bit, name) in _sideNames)
            if (sides & bit != 0) '$name: theme.border',
        ], ','),
      if (o.flag('titles')) ...[
        '    titles: [',
        '      BorderTitle(',
        "        ' build ',",
        '        style: theme.text.merge(const .new(attrs: Attr.bold)),',
        if (o['at'] != 'topLeft') '        alignment: .${o.label('at')},',
        '      ),',
        '      BorderTitle(',
        "        ' 2 warnings ',",
        '        style: theme.warning,',
        '        alignment: .bottomRight,',
        '      ),',
        '    ],',
      ],
      if (o['padding'] != 0) '    padding: const .all(${o.label('padding')}),',
      '    child: const Text(',
      r"      'Compiling 14 libraries…\n'",
      r"      'lib/src/layout    0.4 s\n'",
      "      'lib/src/render    0.9 s',",
      '    ),',
      '  ),',
      ');',
    ].join('\n');
  },
);

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

// ------------------------------------------------------------ Container

const Map<String, Alignment> _containerAlignments = {
  'topLeft': Alignment.topLeft,
  'center': Alignment.center,
  'bottomRight': Alignment.bottomRight,
};

final _container = GalleryPage(
  group: 'Layout',
  title: 'Container',
  options: const [
    ChoiceOption('fill', 'fill', values: ['decoration', 'color']),
    ChoiceOption(
      'alignment',
      'alignment',
      values: [null, 'topLeft', 'center', 'bottomRight'],
      labels: ['none', 'topLeft', 'center', 'bottomRight'],
      initial: 'center',
    ),
    ChoiceOption('width', 'width', values: [null, 24, 30, 36], initial: 30),
    ChoiceOption('height', 'height', values: [null, 5, 7, 9], initial: 7),
    ChoiceOption('padding', 'padding', values: [0, 1, 2], initial: 1),
    ChoiceOption('margin', 'margin', values: [0, 1, 2], initial: 1),
    SwitchOption('foreground', 'foreground'),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final margin = o.choice<int>('margin');
    final padding = o.choice<int>('padding');
    final decorated = o['fill'] == 'decoration';
    return Container(
      width: o.choice('width'),
      height: o.choice('height'),
      margin: margin > 0 ? EdgeInsets.all(margin) : null,
      padding: padding > 0 ? EdgeInsets.all(padding) : null,
      alignment: _containerAlignments[o['alignment']],
      decoration: decorated
          ? BoxDecoration(style: theme.surface, border: _rounded(theme))
          : null,
      color: decorated ? null : theme.surface.bg,
      foregroundDecoration: o.flag('foreground')
          ? BoxDecoration(
              border: Border(type: BorderType.heavy, left: theme.warning),
            )
          : null,
      child: const Text('deploy to staging'),
    );
  },
  code: (o) {
    final margin = o.choice<int>('margin');
    final padding = o.choice<int>('padding');
    final alignment = o['alignment'];
    return [
      'final theme = Theme.of(context);',
      'return Container(',
      if (o.choice<int?>('width') case final w?) '  width: $w,',
      if (o.choice<int?>('height') case final h?) '  height: $h,',
      if (margin > 0) '  margin: const .all($margin),',
      if (padding > 0) '  padding: const .all($padding),',
      if (alignment != null) '  alignment: .$alignment,',
      if (o['fill'] == 'decoration') ...[
        '  decoration: BoxDecoration(',
        '    style: theme.surface,',
        '    border: .all(type: .rounded, style: theme.border),',
        '  ),',
      ] else
        '  color: theme.surface.bg,',
      if (o.flag('foreground')) ...[
        '  foregroundDecoration: BoxDecoration(',
        '    border: Border(type: .heavy, left: theme.warning),',
        '  ),',
      ],
      "  child: const Text('deploy to staging'),",
      ');',
    ].join('\n');
  },
);

// ------------------------------------------------------------ Divider

final _divider = GalleryPage(
  group: 'Layout',
  title: 'Divider',
  options: const [
    ChoiceOption(
      'type',
      'type',
      values: ['single', 'rounded', 'double', 'heavy', 'ascii'],
    ),
    SwitchOption('merge', 'merge', initial: true),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final type = BorderType.values.byName(o.choice('type'));
    final merge = o.flag('merge');
    return SizedBox(
      width: 36,
      height: 7,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Box(
            border: Border.all(type: type, style: theme.border),
          ),
          const Positioned(
            left: 2,
            top: 1,
            child: Text('release 0.4.0', style: Style(attrs: Attr.bold)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 2,
            child: Divider(type: type, style: theme.border, merge: merge),
          ),
          Positioned(
            left: 17,
            top: 2,
            bottom: 0,
            child: VerticalDivider(
              type: type,
              style: theme.border,
              merge: merge,
            ),
          ),
          Positioned(
            left: 2,
            top: 3,
            child: Text('added', style: theme.muted),
          ),
          const Positioned(
            left: 2,
            top: 4,
            child: Text('Grid tracks\nDockArea'),
          ),
          Positioned(
            left: 19,
            top: 3,
            child: Text('fixed', style: theme.muted),
          ),
          const Positioned(
            left: 19,
            top: 4,
            child: Text('wide glyphs\nwheel scroll'),
          ),
        ],
      ),
    );
  },
  code: (o) {
    final type = o['type'] == 'single' ? '' : 'type: .${o.label('type')}, ';
    final args = [
      if (type.isNotEmpty) type.substring(0, type.length - 2),
      'style: theme.border',
      if (o.flag('merge')) 'merge: true',
    ];
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 36,',
      '  height: 7,',
      '  child: Stack(',
      '    fit: .expand,',
      '    children: [',
      '      Box(border: .all(${type}style: theme.border)),',
      '      const Positioned(',
      '        left: 2,',
      '        top: 1,',
      "        child: Text('release 0.4.0', style: .new(attrs: Attr.bold)),",
      '      ),',
      '      Positioned(',
      '        left: 0,',
      '        right: 0,',
      '        top: 2,',
      ..._call(8, 'child: Divider', args, ','),
      '      ),',
      '      Positioned(',
      '        left: 17,',
      '        top: 2,',
      '        bottom: 0,',
      ..._call(8, 'child: VerticalDivider', args, ','),
      '      ),',
      codeLine([
        '      Positioned(left: 2, top: 3, ',
        "child: Text('added', style: theme.muted)),",
      ]),
      r"      const Positioned(left: 2, top: 4, child: Text('Grid tracks\nDockArea')),",
      codeLine([
        '      Positioned(left: 19, top: 3, ',
        "child: Text('fixed', style: theme.muted)),",
      ]),
      '      const Positioned(',
      '        left: 19,',
      '        top: 4,',
      r"        child: Text('wide glyphs\nwheel scroll'),",
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);

// ------------------------------------------------------------ Shadow

const _offsets = {'2, 1': (2, 1), '1, 1': (1, 1), '-2, -1': (-2, -1)};
const _shadowed = 'a box with a shadow';
const _wall = 'what is under a shadow keeps its glyphs; their colours darken. ';

final _shadow = GalleryPage(
  group: 'Layout',
  title: 'Shadow',
  options: [
    ChoiceOption('offset', 'offset', values: _offsets.keys.toList()),
    const ChoiceOption(
      'alpha',
      'alpha',
      values: [0x40, 0x80, 0xc0],
      labels: ['¼', '½', '¾'],
      initial: 0x80,
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final (dx, dy) = _offsets[o.choice<String>('offset')]!;
    return SizedBox(
      width: 36,
      height: 8,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Text(_wall * 5, style: theme.muted),
          Positioned(
            left: 5,
            top: 2,
            child: Shadow(
              shadow: BoxShadow(dx: dx, dy: dy, alpha: o.choice('alpha')),
              child: Box(
                style: theme.surface.merge(theme.text),
                border: _rounded(theme),
                padding: const EdgeInsets.x(1),
                child: const Text(_shadowed),
              ),
            ),
          ),
        ],
      ),
    );
  },
  code: (o) {
    final (dx, dy) = _offsets[o.choice<String>('offset')]!;
    final alpha = o.choice<int>('alpha');
    final args = [
      if (dx != 2) 'dx: $dx',
      if (dy != 1) 'dy: $dy',
      if (alpha != 0x80) 'alpha: 0x${alpha.toRadixString(16)}',
    ];
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 36,',
      '  height: 8,',
      '  child: Stack(',
      '    fit: .expand,',
      '    children: [',
      '      Text(',
      "        '$_wall' * 5,",
      '        style: theme.muted,',
      '      ),',
      '      Positioned(',
      '        left: 5,',
      '        top: 2,',
      '        child: Shadow(',
      '          shadow: const BoxShadow(${args.join(', ')}),',
      '          child: Box(',
      '            style: theme.surface.merge(theme.text),',
      '            border: .all(type: .rounded, style: theme.border),',
      '            padding: const .x(1),',
      "            child: const Text('$_shadowed'),",
      '          ),',
      '        ),',
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);

// ------------------------------------------------------------ Padding

// the Dart, and the insets
const _insets = {
  'all 1': ('.all(1)', EdgeInsets.all(1)),
  'x 4': ('.x(4)', EdgeInsets.x(4)),
  'y 2': ('.y(2)', EdgeInsets.y(2)),
  'left 8': ('.only(left: 8)', EdgeInsets.only(left: 8)),
  'left 3, top 1': ('.only(left: 3, top: 1)', EdgeInsets.only(left: 3, top: 1)),
};

final _padding = GalleryPage(
  group: 'Layout',
  title: 'Padding',
  options: [
    ChoiceOption(
      'insets',
      'padding',
      values: _insets.keys.toList(),
      initial: 'x 4',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    return Box(
      border: _rounded(theme),
      child: Padding(
        padding: _insets[o.choice<String>('insets')]!.$2,
        child: Box(
          style: theme.selection,
          child: const Text('the child,\npadded from the box'),
        ),
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'return Box(',
    '  border: .all(type: .rounded, style: theme.border),',
    '  child: Padding(',
    '    padding: const ${_insets[o.choice<String>('insets')]!.$1},',
    '    child: Box(',
    '      style: theme.selection,',
    r"      child: const Text('the child,\npadded from the box'),",
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);

// ------------------------------------------------------------ Align, Center

const List<int?> _alignFactors = [null, 1, 2, 3];

final _alignCenter = GalleryPage(
  group: 'Layout',
  title: 'Align, Center',
  options: [
    ..._alignOptions(1, 1),
    const ChoiceOption('wf', 'width factor', values: _alignFactors),
    const ChoiceOption('hf', 'height factor', values: _alignFactors),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final wf = o.choice<int?>('wf');
    final hf = o.choice<int?>('hf');
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
      gap: 1,
      children: [
        room(
          '.${_alignmentOf(o)}',
          Align(
            alignment: Alignment(o.choice('ax'), o.choice('ay')),
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
    final wf = o.choice<int?>('wf');
    final hf = o.choice<int?>('hf');
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
      '  gap: 1,',
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

// ------------------------------------------------------------ SizedBox

final _sizedBox = GalleryPage(
  group: 'Layout',
  title: 'SizedBox',
  options: [
    const ChoiceOption(
      'kind',
      'constructor',
      values: ['sized', 'expand', 'shrink'],
      labels: ['width, height', '.expand', '.shrink'],
    ),
    SliderOption(
      'width',
      'width',
      min: 0,
      max: 44,
      initial: 16,
      format: (v) => '$v cells',
      disabled: (o) => o['kind'] != 'sized',
    ),
    SliderOption(
      'height',
      'height',
      min: 0,
      max: 9,
      initial: 3,
      format: (v) => '$v rows',
      disabled: (o) => o['kind'] != 'sized',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    Widget child(String label) =>
        Box(style: theme.selection, child: Text(label));
    final w = o.number('width').toInt();
    final h = o.number('height').toInt();
    return SizedBox(
      width: 40,
      height: 9,
      child: Box(
        border: _rounded(theme),
        child: Center(
          child: switch (o['kind']) {
            'expand' => SizedBox.expand(child: child('SizedBox.expand')),
            'shrink' => SizedBox.shrink(child: child('none of it shows')),
            _ => SizedBox(width: w, height: h, child: child('$w × $h')),
          },
        ),
      ),
    );
  },
  code: (o) {
    List<String> child(String label) => _call(8, 'child: Box', [
      'style: theme.selection',
      "child: const Text('$label')",
    ], ',');
    final w = o.label('width');
    final h = o.label('height');
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 40,',
      '  height: 9,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: Center(',
      ...switch (o['kind']) {
        'expand' => [
          '      child: SizedBox.expand(',
          ...child('SizedBox.expand'),
          '      ),',
        ],
        'shrink' => [
          '      child: SizedBox.shrink(',
          ...child('none of it shows'),
          '      ),',
        ],
        _ => [
          '      child: SizedBox(',
          '        width: $w,',
          '        height: $h,',
          ...child('$w × $h'),
          '      ),',
        ],
      },
      '    ),',
      '  ),',
      ');',
    ].join('\n');
  },
);

// ------------------------------------------------------------ ConstrainedBox

final _constrainedBox = GalleryPage(
  group: 'Layout',
  title: 'ConstrainedBox',
  options: const [
    ChoiceOption('min', 'min width', values: [0, 12, 20], initial: 12),
    ChoiceOption('max', 'max width', values: [20, 32, 48], initial: 32),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    Widget bounded(String text) => ConstrainedBox(
      constraints: BoxConstraints(o.choice('min'), o.choice('max'), 1, 3),
      child: Box(
        style: theme.selection,
        padding: const EdgeInsets.x(1),
        child: Text(text),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        bounded('short'),
        bounded('A child as wide as its text, within the bounds.'),
      ],
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'Widget bounded(String text) => ConstrainedBox(',
    codeLine([
      '  constraints: const BoxConstraints(',
      "${o.label('min')}, ${o.label('max')}, 1, 3),",
    ]),
    '  child: Box(',
    '    style: theme.selection,',
    '    padding: const .x(1),',
    '    child: Text(text),',
    '  ),',
    ');',
    'return Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    "    bounded('short'),",
    "    bounded('A child as wide as its text, within the bounds.'),",
    '  ],',
    ');',
  ].join('\n'),
);

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

// ----------------------------------------------------- FractionallySizedBox

const _factors = [0.25, 0.5, 0.75, 1.0];
const _factorLabels = ['¼', '½', '¾', '1'];

final _fractionallySizedBox = GalleryPage(
  group: 'Layout',
  title: 'FractionallySizedBox',
  options: [
    const ChoiceOption(
      'wf',
      'width factor',
      values: _factors,
      labels: _factorLabels,
      initial: 0.5,
    ),
    const ChoiceOption(
      'hf',
      'height factor',
      values: _factors,
      labels: _factorLabels,
      initial: 0.5,
    ),
    const ChoiceOption(
      'alignment',
      'alignment',
      values: ['center', 'topLeft', 'bottomRight'],
    ),
    SliderOption(
      'room',
      'room',
      min: 16,
      max: 48,
      initial: 40,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final wf = o.choice<double>('wf');
    final hf = o.choice<double>('hf');
    return SizedBox(
      width: o.number('room').toInt(),
      height: 9,
      child: Box(
        border: _rounded(theme),
        child: FractionallySizedBox(
          alignment: _byName[o.choice<String>('alignment')]!,
          widthFactor: wf,
          heightFactor: hf,
          child: Box(
            style: theme.selection,
            child: Center(child: Text('$wf × $hf')),
          ),
        ),
      ),
    );
  },
  code: (o) {
    final wf = o.choice<double>('wf');
    final hf = o.choice<double>('hf');
    return [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: ${o.label('room')},',
      '  height: 9,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: FractionallySizedBox(',
      if (o['alignment'] != 'center')
        '      alignment: .${o.label('alignment')},',
      '      widthFactor: $wf,',
      '      heightFactor: $hf,',
      '      child: Box(',
      '        style: theme.selection,',
      "        child: const Center(child: Text('$wf × $hf')),",
      '      ),',
      '    ),',
      '  ),',
      ');',
    ].join('\n');
  },
);

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

// -------------------------------------------------------- Row, Column, Flex

const _fw = 44;
const _fh = 11;
const _main = [
  'start',
  'end',
  'center',
  'spaceBetween',
  'spaceAround',
  'spaceEvenly',
];

final _flex = GalleryPage(
  group: 'Layout',
  title: 'Row, Column, Flex',
  options: const [
    ChoiceOption('dir', 'direction', values: ['row', 'column']),
    ChoiceOption(
      'main',
      'main axis',
      values: _main,
      initial: 'spaceBetween',
    ),
    ChoiceOption(
      'cross',
      'cross axis',
      values: ['start', 'end', 'center', 'stretch'],
      initial: 'center',
    ),
    ChoiceOption('gap', 'gap', values: [0, 1, 2], initial: 1),
    ChoiceOption('size', 'main axis size', values: ['max', 'min']),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    // the text reversed too, as Badge has it: a Box gives its child its
    // colours, not its attributes
    Widget chip(
      String label,
      Style color, [
      EdgeInsets padding = const EdgeInsets.x(1),
    ]) {
      final reversed = color.merge(const Style(attrs: Attr.reverse));
      return Box(
        style: reversed,
        padding: padding,
        child: Text(label, style: reversed),
      );
    }

    final children = [
      chip('one', theme.primary),
      chip('two', theme.accent, const EdgeInsets.all(1)),
      chip('three', theme.success),
    ];
    final main = MainAxisAlignment.values.byName(o.choice('main'));
    final cross = CrossAxisAlignment.values.byName(o.choice('cross'));
    final gap = o.choice<int>('gap');
    final size = MainAxisSize.values.byName(o.choice('size'));
    final Widget flex = o['dir'] == 'row'
        ? Row(
            mainAxisAlignment: main,
            mainAxisSize: size,
            crossAxisAlignment: cross,
            gap: gap,
            children: children,
          )
        : Column(
            mainAxisAlignment: main,
            mainAxisSize: size,
            crossAxisAlignment: cross,
            gap: gap,
            children: children,
          );
    return SizedBox(
      width: _fw,
      height: _fh,
      child: Box(
        border: _rounded(theme),
        // in the box's tight constraints a flex is as long as the box,
        // whatever its size: a Center loosens them
        child: size == MainAxisSize.min ? Center(child: flex) : flex,
      ),
    );
  },
  code: (o) {
    final min = o['size'] == 'min';
    final flex = [
      '${o['dir'] == 'row' ? 'Row' : 'Column'}(',
      if (o['main'] != 'start') '  mainAxisAlignment: .${o.label('main')},',
      if (min) '  mainAxisSize: .min,',
      if (o['cross'] != 'center') '  crossAxisAlignment: .${o.label('cross')},',
      if (o['gap'] != 0) '  gap: ${o.label('gap')},',
      '  children: [',
      "    chip('one', theme.primary),",
      "    chip('two', theme.accent, const .all(1)),",
      "    chip('three', theme.success),",
      '  ],',
      '),',
    ];
    return [
      'final theme = Theme.of(context);',
      '// the text reversed too, as Badge has it: a Box gives its child its',
      '// colours, not its attributes',
      codeLine([
        'Widget chip(String label, Style color, ',
        '[EdgeInsets padding = const .x(1)]) {',
      ]),
      '  final reversed = color.merge(const .new(attrs: Attr.reverse));',
      '  return Box(',
      '    style: reversed,',
      '    padding: padding,',
      '    child: Text(label, style: reversed),',
      '  );',
      '}',
      'return SizedBox(',
      '  width: $_fw,',
      '  height: $_fh,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      if (min) ...[
        "    // in the box's tight constraints a flex is as long as the box,",
        '    // whatever its size: a Center loosens them',
        '    child: Center(',
        '      child: ${flex.first}',
        for (final l in flex.skip(1)) '      $l',
        '    ),',
      ] else ...[
        '    child: ${flex.first}',
        for (final l in flex.skip(1)) '    $l',
      ],
      '  ),',
      ');',
    ].join('\n');
  },
);

// ------------------------------------------------------------ Expanded, Spacer

final _expanded = GalleryPage(
  group: 'Layout',
  title: 'Expanded, Spacer',
  options: [
    const ChoiceOption('flex', 'Expanded flex', values: [1, 2, 3]),
    const ChoiceOption('fit', 'Flexible fit', values: ['loose', 'tight']),
    SliderOption(
      'width',
      'width',
      min: 20,
      max: 50,
      initial: 48,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final flex = o.choice<int>('flex');
    return SizedBox(
      width: o.number('width').toInt(),
      height: 3,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: flex,
            child: Box(
              border: Border.all(
                type: BorderType.rounded,
                style: theme.accent,
              ),
              child: Text('Expanded $flex', wrap: TextWrap.none),
            ),
          ),
          Flexible(
            fit: FlexFit.values.byName(o.choice('fit')),
            child: Box(border: _rounded(theme), child: const Text('Flexible')),
          ),
          const Spacer(),
          Box(border: _rounded(theme), child: const Text('end')),
        ],
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'return SizedBox(',
    '  width: ${o.label('width')},',
    '  height: 3,',
    '  child: Row(',
    '    crossAxisAlignment: .stretch,',
    '    children: [',
    '      Expanded(',
    if (o['flex'] != 1) '        flex: ${o.label('flex')},',
    '        child: Box(',
    '          border: .all(type: .rounded, style: theme.accent),',
    "          child: const Text('Expanded ${o.label('flex')}', wrap: .none),",
    '        ),',
    '      ),',
    '      Flexible(',
    if (o['fit'] != 'loose') '        fit: .${o.label('fit')},',
    '        child: Box(',
    '          border: .all(type: .rounded, style: theme.border),',
    "          child: const Text('Flexible'),",
    '        ),',
    '      ),',
    '      const Spacer(),',
    '      Box(',
    '        border: .all(type: .rounded, style: theme.border),',
    "        child: const Text('end'),",
    '      ),',
    '    ],',
    '  ),',
    ');',
  ].join('\n'),
);

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

// ------------------------------------------------------------ Transform

/// The offsets the chip goes round, a step every [_move] ms.
const _round = [
  (0, -2), (5, -2), (9, -1), (10, 0), //
  (9, 1), (5, 2), (0, 2), (-5, 2), //
  (-9, 1), (-10, 0), (-9, -1), (-5, -2),
];
const _move = 200;

/// The steps a timer of [ms] started with the page has ticked, on the
/// gallery's clock (0 while it stands still, as the design's born):
/// [builder] given them, built again at the next.
final class _Ticks extends StatefulWidget {
  const _Ticks({required this.ms, required this.builder});

  final int ms;
  final Widget Function(BuildContext context, int steps) builder;

  @override
  State<_Ticks> createState() => _TicksState();
}

final class _TicksState extends State<_Ticks> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final now = _motion.now.inMilliseconds;
    final born = _kept<int>(context, 'born', () => _motion.frozen ? 0 : now);
    final steps = math.max(0, (now - born) ~/ widget.ms);
    _motion
      ..wakeAt(Duration(milliseconds: born + (steps + 1) * widget.ms))
      ..end();
    return widget.builder(context, steps);
  }
}

final _transform = GalleryPage(
  group: 'Layout',
  title: 'Transform',
  options: [
    const ChoiceOption('move', 'offset', values: ['round', 'fixed']),
    SliderOption(
      'dx',
      'dx',
      min: -12,
      max: 12,
      initial: 6,
      format: (v) => '$v cells',
      disabled: (o) => o['move'] != 'fixed',
    ),
    SliderOption(
      'dy',
      'dy',
      min: -2,
      max: 2,
      initial: 1,
      format: (v) => '$v rows',
      disabled: (o) => o['move'] != 'fixed',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    Widget moved((int, int) offset) => SizedBox(
      width: 32,
      height: 7,
      child: Box(
        border: _rounded(theme),
        child: Transform.translate(
          offset: offset,
          child: Center(
            child: Box(
              style: theme.selection,
              padding: const EdgeInsets.x(1),
              child: const Text('moved'),
            ),
          ),
        ),
      ),
    );
    if (o['move'] == 'fixed') {
      return moved((o.number('dx').toInt(), o.number('dy').toInt()));
    }
    return _Ticks(
      ms: _move,
      builder: (context, steps) => moved(_round[steps % _round.length]),
    );
  },
  code: (o) {
    List<String> build(String offset) => [
      'final theme = Theme.of(context);',
      'return SizedBox(',
      '  width: 32,',
      '  height: 7,',
      '  child: Box(',
      '    border: .all(type: .rounded, style: theme.border),',
      '    child: Transform.translate(',
      '      offset: $offset,',
      '      child: Center(',
      '        child: Box(',
      '          style: theme.selection,',
      '          padding: const .x(1),',
      "          child: const Text('moved'),",
      '        ),',
      '      ),',
      '    ),',
      '  ),',
      ');',
    ];
    if (o['move'] == 'fixed') {
      return build('(${o.label('dx')}, ${o.label('dy')})').join('\n');
    }
    final path = [for (final (x, y) in _round) '($x, $y)'];
    return [
      'const _round = [',
      for (final i in const [0, 4, 8])
        '  ${path.sublist(i, i + 4).join(', ')},',
      '];',
      '',
      'var _step = 0;',
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_move),',
      '    (_) => setState(() => _step++),',
      '  );',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _timer.cancel();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      for (final l in build('_round[_step % _round.length]')) '  $l',
      '}',
    ].join('\n');
  },
);

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

// ------------------------------------------------------ Grid, GridPlacement

// the third column: its track, the Dart and the label of its cell
const _third = {
  'content': (GridTrack.content(), '.content()', 'content()'),
  'fixed': (GridTrack.fixed(14), '.fixed(14)', 'fixed(14)'),
  'fr': (GridTrack.fr(1), '.fr(1)', 'fr(1)'),
};
const _gh = 12;

final _grid = GalleryPage(
  group: 'Layout',
  title: 'Grid, GridPlacement',
  options: [
    ChoiceOption(
      'third',
      'third column',
      values: _third.keys.toList(),
      labels: [for (final t in _third.values) t.$2],
    ),
    const ChoiceOption('cg', 'column gap', values: [0, 1, 2], initial: 1),
    const ChoiceOption('rg', 'row gap', values: [0, 1]),
    SliderOption(
      'width',
      'width',
      min: 32,
      max: 50,
      initial: 44,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final third = _third[o.choice<String>('third')]!;
    Widget cell(String label) =>
        Box(border: _rounded(theme), child: Text(label));
    return SizedBox(
      width: o.number('width').toInt(),
      height: _gh,
      child: Grid(
        columns: [const GridTrack.fixed(12), const GridTrack.fr(1), third.$1],
        rows: const [GridTrack.content(), GridTrack.fr(1), GridTrack.content()],
        columnGap: o.choice('cg'),
        rowGap: o.choice('rg'),
        children: [
          GridPlacement(
            columnSpan: 3,
            child: cell('header · columnSpan: 3'),
          ),
          cell('fixed(12)'),
          cell('fr(1)'),
          cell(third.$3),
          GridPlacement(
            row: 2,
            column: 1,
            columnSpan: 2,
            child: cell('columnSpan: 2'),
          ),
        ],
      ),
    );
  },
  code: (o) {
    final third = _third[o.choice<String>('third')]!;
    return [
      'final theme = Theme.of(context);',
      'Widget cell(String label) => Box(',
      '  border: .all(type: .rounded, style: theme.border),',
      '  child: Text(label),',
      ');',
      'return SizedBox(',
      '  width: ${o.label('width')},',
      '  height: $_gh,',
      '  child: Grid(',
      '    columns: const [.fixed(12), .fr(1), ${third.$2}],',
      '    rows: const [.content(), .fr(1), .content()],',
      if (o['cg'] != 0) '    columnGap: ${o.label('cg')},',
      if (o['rg'] != 0) '    rowGap: ${o.label('rg')},',
      '    children: [',
      codeLine([
        '      GridPlacement(columnSpan: 3, ',
        "child: cell('header · columnSpan: 3')),",
      ]),
      "      cell('fixed(12)'),",
      "      cell('fr(1)'),",
      "      cell('${third.$3}'),",
      '      GridPlacement(',
      '        row: 2,',
      '        column: 1,',
      '        columnSpan: 2,',
      "        child: cell('columnSpan: 2'),",
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);

// ------------------------------------------------------------ Wrap

// the label and the kind of each badge, null for the box
const List<(String, StatusKind?, bool)> _tags = [
  ('dart', null, true),
  ('terminal', StatusKind.info, true),
  ('a box', null, false),
  ('twk', StatusKind.success, true),
  ('日本語', StatusKind.warning, true),
  ('layout', null, true),
  ('runs', StatusKind.info, true),
];
const List<String> _wrapAlign = _main;
const _wh = 11;

/// The room narrows a cell this often while live.
const _narrow = 120;

final _wrap = GalleryPage(
  group: 'Layout',
  title: 'Wrap',
  options: [
    SliderOption(
      'width',
      'width',
      min: 20,
      max: 48,
      initial: 36,
      format: (v) => '$v cells',
    ),
    const SwitchOption('live', 'narrowing'),
    const ChoiceOption(
      'direction',
      'direction',
      values: ['horizontal', 'vertical'],
    ),
    const ChoiceOption('alignment', 'alignment', values: _wrapAlign),
    const ChoiceOption('runAlignment', 'run alignment', values: _wrapAlign),
    const ChoiceOption(
      'cross',
      'cross axis',
      values: ['start', 'end', 'center'],
      initial: 'center',
    ),
    const ChoiceOption('gap', 'gap', values: [0, 1, 2], initial: 1),
    const ChoiceOption('runGap', 'run gap', values: [0, 1]),
  ],
  build: (context, o) => Timed((context, ms, wake) {
    var width = o.number('width').toInt();
    if (o.flag('live')) {
      // a cell narrower every 120 ms from 48 to 20 and back, the slider
      // following it
      final step = ms ~/ _narrow;
      wake((step + 1) * _narrow);
      final w = 20 + (step % 56 - 28).abs();
      if (w != width) {
        final control = PageControl.of(context);
        scheduleMicrotask(() => control.setOption('width', w));
      }
      width = w;
    }
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      height: _wh,
      child: Box(
        border: _rounded(theme),
        child: Wrap(
          direction: Axis.values.byName(o.choice('direction')),
          alignment: WrapAlignment.values.byName(o.choice('alignment')),
          runAlignment: WrapAlignment.values.byName(o.choice('runAlignment')),
          crossAxisAlignment: WrapCrossAlignment.values.byName(
            o.choice('cross'),
          ),
          gap: o.choice('gap'),
          runGap: o.choice('runGap'),
          children: [
            for (final (label, kind, badge) in _tags)
              if (badge)
                Badge(label, kind: kind)
              else
                Box(border: _rounded(theme), child: Text(label)),
          ],
        ),
      ),
    );
  }),
  code: (o) {
    final wrap = [
      '    child: Wrap(',
      if (o['direction'] != 'horizontal') '      direction: .vertical,',
      if (o['alignment'] != 'start')
        '      alignment: .${o.label('alignment')},',
      if (o['runAlignment'] != 'start')
        '      runAlignment: .${o.label('runAlignment')},',
      if (o['cross'] != 'start')
        '      crossAxisAlignment: .${o.label('cross')},',
      if (o['gap'] != 0) '      gap: ${o.label('gap')},',
      if (o['runGap'] != 0) '      runGap: ${o.label('runGap')},',
      '      children: [',
      for (final (label, kind, badge) in _tags)
        if (!badge) ...[
          '        Box(',
          '          border: .all(type: .rounded, style: theme.border),',
          "          child: const Text('a box'),",
          '        ),',
        ] else if (kind == null)
          "        const Badge('$label'),"
        else
          "        const Badge('$label', kind: .${kind.name}),",
      '      ],',
      '    ),',
    ];
    if (!o.flag('live')) {
      return [
        'final theme = Theme.of(context);',
        'return SizedBox(',
        '  width: ${o.label('width')},',
        '  height: $_wh,',
        '  child: Box(',
        '    border: .all(type: .rounded, style: theme.border),',
        ...wrap,
        '  ),',
        ');',
      ].join('\n');
    }
    return [
      '// the room narrows a cell at a time, from 48 to 20 and back',
      'late final Timer _timer;',
      'var _step = 0;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_narrow),',
      '    (_) => setState(() => _step++),',
      '  );',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _timer.cancel();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return SizedBox(',
      '    width: 20 + (_step % 56 - 28).abs(),',
      '    height: $_wh,',
      '    child: Box(',
      '      border: .all(type: .rounded, style: theme.border),',
      for (final l in wrap) '  $l',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

// ------------------------------------------------------------ CustomPaint

const _blocks = ' ▁▂▃▄▅▆▇█';
const _waveStep = 100;

/// Blocks as high as a wave 24 columns long at [phase], as the Code's
/// WavePainter paints them; the gallery's clock gives the phase.
final class _Wave extends CellPainter {
  const _Wave(this.phase, this.style);

  final int phase;
  final Style style;

  @override
  void paint(Canvas canvas, int width, int height) {
    final pen = style.penIn(canvas.styles);
    for (var x = 0; x < width; x++) {
      final u = (x + phase) % 24;
      final eighths = 4 + 3 * (u < 12 ? u : 24 - u);
      for (var row = 0; row < height; row++) {
        final left = eighths - 8 * row;
        if (left > 0) {
          canvas.text(x, height - 1 - row, _blocks[math.min(left, 8)], pen);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Wave oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.style != style;
}

final _customPaint = GalleryPage(
  group: 'Layout',
  title: 'CustomPaint',
  options: const [
    ChoiceOption(
      'paints',
      'painter',
      values: ['under', 'over'],
      labels: ['painter', 'foregroundPainter'],
    ),
    SwitchOption('moving', 'moving', initial: true),
    ColorOption(
      'color',
      'style',
      values: ['primary', 'accent', 'success'],
      initial: 'primary',
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final style = o.colorStyle(context, 'color');
    final under = o['paints'] == 'under';
    Widget painted(int phase) => CustomPaint(
      painter: under ? _Wave(phase, style) : null,
      foregroundPainter: under ? null : _Wave(phase, style),
      child: SizedBox(
        width: 36,
        height: 6,
        child: Center(
          child: Text(
            'cells of its own',
            style: theme.text.merge(const Style(attrs: Attr.bold)),
          ),
        ),
      ),
    );
    if (!o.flag('moving')) {
      return painted(0);
    }
    return _Ticks(
      ms: _waveStep,
      builder: (context, steps) => painted(steps),
    );
  },
  code: (o) {
    final which = o['paints'] == 'under' ? 'painter' : 'foregroundPainter';
    return [
      if (o.flag('moving')) ...[
        'final _phase = ValueNotifier(0);',
        'late final Timer _timer;',
        '',
        '@override',
        'void initState() {',
        '  super.initState();',
        '  _timer = Timer.periodic(',
        '    const Duration(milliseconds: $_waveStep),',
        '    (_) => _phase.value++,',
        '  );',
        '}',
        '',
        '@override',
        'void dispose() {',
        '  _timer.cancel();',
        '  _phase.dispose();',
        '  super.dispose();',
        '}',
      ] else ...[
        'final _phase = ValueNotifier(0);',
        '',
        '@override',
        'void dispose() {',
        '  _phase.dispose();',
        '  super.dispose();',
        '}',
      ],
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return CustomPaint(',
      '    $which: WavePainter(_phase, theme.${o['color']}),',
      '    child: SizedBox(',
      '      width: 36,',
      '      height: 6,',
      '      child: Center(',
      '        child: Text(',
      "          'cells of its own',",
      '          style: theme.text.merge(const .new(attrs: Attr.bold)),',
      '        ),',
      '      ),',
      '    ),',
      '  );',
      '}',
      '',
      '/// Blocks as high as a wave 24 columns long, moved along by [phase]',
      '/// with no widget built again.',
      'final class WavePainter extends CellPainter {',
      '  WavePainter(this.phase, this.style) : super(repaint: phase);',
      '',
      '  final ValueNotifier<int> phase;',
      '  final Style style;',
      '',
      '  @override',
      '  void paint(Canvas canvas, int width, int height) {',
      '    final pen = style.penIn(canvas.styles);',
      '    for (var x = 0; x < width; x++) {',
      '      final u = (x + phase.value) % 24;',
      '      final eighths = 4 + 3 * (u < 12 ? u : 24 - u);',
      '      for (var row = 0; row < height; row++) {',
      '        final left = eighths - 8 * row;',
      '        if (left > 0) {',
      codeLine([
        '          canvas.text(x, height - 1 - row, ',
        "'$_blocks'[min(left, 8)], pen);",
      ]),
      '        }',
      '      }',
      '    }',
      '  }',
      '',
      '  @override',
      '  bool shouldRepaint(WavePainter oldDelegate) =>',
      '      oldDelegate.phase != phase || oldDelegate.style != style;',
      '}',
    ].join('\n');
  },
);

// ------------------------------------------------------------ SplitView

const _panes = [
  ('files', 'box.dart\nflex.dart\ngrid.dart\nwrap.dart'),
  ('editor', 'Drag a divider, or Tab to one and press the arrows.'),
  ('outline', 'Drag its divider to the edge.'),
];
// room for three panes of three rows and the two dividers between them,
// edges shared or not
const _spw = 48;
const _sph = 11;

final _splitView = GalleryPage(
  group: 'Layout',
  title: 'SplitView',
  options: const [
    ChoiceOption('dir', 'direction', values: ['horizontal', 'vertical']),
    SwitchOption('share', 'share edges', initial: true),
    ChoiceOption(
      'type',
      'dividers',
      values: ['single', 'rounded', 'double', 'heavy', 'ascii'],
    ),
  ],
  build: (context, o) => _Split(
    vertical: o['dir'] == 'vertical',
    share: o.flag('share'),
    type: BorderType.values.byName(o.choice('type')),
  ),
  code: (o) {
    final min = o['dir'] == 'horizontal' ? 8 : 3;
    List<String> pane((String, String) p, {required bool last}) => [
      '              SplitPane(',
      '                minSize: $min,',
      if (last) '                collapsible: true,',
      ..._call(16, 'child: pane', [
        "'${p.$1}'",
        "'${p.$2.replaceAll('\n', r'\n')}'",
      ], ','),
      '              ),',
    ];
    final share = o.flag('share');
    return [
      'final _split = SplitController(fractions: [1, 2, 1]);',
      '',
      '@override',
      'void dispose() {',
      '  _split.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  Widget pane(String title, String text) => Box(',
      codeLine([
        '    border: .all(type: .rounded, style: theme.border',
        "${share ? ', merge: true' : ''}),",
      ]),
      '    // no blanks around the title: a divider over the edge would',
      '    // draw its line in them',
      '    titles: [BorderTitle(title, style: theme.muted)],',
      '    padding: const .only(left: 1),',
      '    child: Text(text),',
      '  );',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      // as tall as the room leaves it, at most $_sph',
      '      Flexible(',
      '        child: SizedBox(',
      '          width: $_spw,',
      '          height: $_sph,',
      '          child: SplitView(',
      '            controller: _split,',
      if (o['dir'] != 'horizontal') '            direction: .vertical,',
      if (share) '            shareEdges: true,',
      if (o['type'] != 'single') '            type: .${o['type']},',
      '            style: theme.border,',
      '            panes: [',
      for (final (i, p) in _panes.indexed)
        ...pane(p, last: i == _panes.length - 1),
      '            ],',
      '          ),',
      '        ),',
      '      ),',
      '      ListenableBuilder(',
      '        listenable: _split,',
      '        builder: (context, _) {',
      codeLine([
        '          final fractions = ',
        '_split.fractions.map((f) => f.toStringAsFixed(2));',
      ]),
      '          final collapsed = _split.collapsed;',
      '          return Text.rich([',
      "            Span('fractions: ', theme.muted),",
      "            Span(fractions.join('  ')),",
      '            if (collapsed.isNotEmpty) ...[',
      "              Span('  collapsed: ', theme.muted),",
      r"              Span('$collapsed'),",
      '            ],',
      '          ]);',
      '        },',
      '      ),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The SplitView page's widget: its controller kept in the page's state,
/// so that the panes keep their sizes over a visit to another page.
final class _Split extends StatelessWidget {
  const _Split({
    required this.vertical,
    required this.share,
    required this.type,
  });

  final bool vertical;
  final bool share;
  final BorderType type;

  @override
  Widget build(BuildContext context) {
    final split = _kept(
      context,
      'split',
      () => SplitController(fractions: [1, 2, 1]),
    );
    final theme = Theme.of(context);
    Widget pane(String title, String text) => Box(
      border: _rounded(theme, merge: share),
      // no blanks around the title: a divider over the edge would draw its
      // line in them
      titles: [BorderTitle(title, style: theme.muted)],
      padding: const EdgeInsets.only(left: 1),
      child: Text(text),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        // as tall as the room leaves it, at most 11
        Flexible(
          child: SizedBox(
            width: _spw,
            height: _sph,
            child: SplitView(
              controller: split,
              direction: vertical ? Axis.vertical : Axis.horizontal,
              shareEdges: share,
              type: type,
              style: theme.border,
              panes: [
                for (final (i, (title, text)) in _panes.indexed)
                  SplitPane(
                    minSize: vertical ? 3 : 8,
                    collapsible: i == _panes.length - 1,
                    child: pane(title, text),
                  ),
              ],
            ),
          ),
        ),
        ListenableBuilder(
          listenable: split,
          builder: (context, _) {
            final fractions = split.fractions.map(
              (f) => f.toStringAsFixed(2),
            );
            final collapsed = split.collapsed;
            return Text.rich([
              Span('fractions: ', theme.muted),
              Span(fractions.join('  ')),
              if (collapsed.isNotEmpty) ...[
                Span('  collapsed: ', theme.muted),
                Span('$collapsed'),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ DockArea

const _daw = 50;
const _dah = 10;

DockLayout _docked() => DockLayout(
  root: DockSplit(
    Axis.horizontal,
    [
      DockTabs(['files', 'find']),
      DockTabs(['editor']),
    ],
    fractions: [1, 2],
  ),
  windows: const [DockWindow('log', left: 23, top: 4, width: 26, height: 6)],
);

final _dockArea = GalleryPage(
  group: 'Layout',
  title: 'DockArea',
  options: const [
    SwitchOption('strip', 'tab strip', initial: true),
    ChoiceOption(
      'frame',
      'window frame',
      values: [null, 'raised', 'bordered'],
      labels: ['by the theme', 'raised', 'bordered'],
    ),
  ],
  build: (context, o) => _Dock(
    tabStrip: o.flag('strip'),
    windowFrame: switch (o.choice<String?>('frame')) {
      final frame? => WindowFrame.values.byName(frame),
      null => null,
    },
  ),
  code: (o) => [
    _dockHead,
    if (!o.flag('strip')) '        tabStrip: false,',
    if (o.choice<String?>('frame') case final frame?)
      '        windowFrame: .$frame,',
    _dockTail,
  ].join('\n'),
);

/// The DockArea page's widget: its controller kept in the page's state,
/// so that the panels stay where they were put over a visit to another
/// page.
final class _Dock extends StatelessWidget {
  const _Dock({required this.tabStrip, required this.windowFrame});

  final bool tabStrip;
  final WindowFrame? windowFrame;

  @override
  Widget build(BuildContext context) {
    final dock = _kept(context, 'dock', () => DockController(_docked()));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: _daw,
          height: _dah,
          child: DockArea(
            controller: dock,
            tabStrip: tabStrip,
            windowFrame: windowFrame,
            panels: const [
              DockPanel(
                id: 'files',
                title: 'Files',
                child: Padding(
                  padding: EdgeInsets.x(1),
                  child: Text('Drag a tab onto a target to dock it there.'),
                ),
              ),
              DockPanel(
                id: 'find',
                title: 'Find',
                child: Padding(
                  padding: EdgeInsets.x(1),
                  child: Text('Find in files.'),
                ),
              ),
              DockPanel(
                id: 'editor',
                title: 'Editor',
                child: Padding(padding: EdgeInsets.x(1), child: _Clicks()),
              ),
              DockPanel(
                id: 'log',
                title: 'Log',
                child: Padding(
                  padding: EdgeInsets.x(1),
                  child: Text('Drop a tab off the targets to float it.'),
                ),
              ),
            ],
          ),
        ),
        Button(
          'Dock them as they were',
          onPressed: () => dock.layout = _docked(),
        ),
      ],
    );
  }
}

/// A count and a button that adds to it: kept as its panel moves, and in
/// the page's state over a visit to another page.
final class _Clicks extends StatefulWidget {
  const _Clicks();

  @override
  State<_Clicks> createState() => _ClicksState();
}

final class _ClicksState extends State<_Clicks> {
  late final Map<String, Object?> _state = PageControl.of(context).state;
  int get _count => _state['count'] as int? ?? 0;
  set _count(int n) => _state['count'] = n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich([Span('count: ', theme.muted), Span('$_count')]),
        Button('Add one', onPressed: () => setState(() => _count++)),
      ],
    );
  }
}

const _dockHead = '''
final _dock = DockController(_docked());

static DockLayout _docked() => DockLayout(
  root: DockSplit(
    .horizontal,
    [
      DockTabs(['files', 'find']),
      DockTabs(['editor']),
    ],
    fractions: [1, 2],
  ),
  windows: const [DockWindow('log', left: 23, top: 4, width: 26, height: 6)],
);

@override
void dispose() {
  _dock.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  gap: 1,
  children: [
    SizedBox(
      width: 50,
      height: 10,
      child: DockArea(
        controller: _dock,''';

const _dockTail = r'''
        panels: const [
          DockPanel(
            id: 'files',
            title: 'Files',
            child: Padding(
              padding: .x(1),
              child: Text('Drag a tab onto a target to dock it there.'),
            ),
          ),
          DockPanel(
            id: 'find',
            title: 'Find',
            child: Padding(padding: .x(1), child: Text('Find in files.')),
          ),
          DockPanel(
            id: 'editor',
            title: 'Editor',
            child: Padding(padding: .x(1), child: _Clicks()),
          ),
          DockPanel(
            id: 'log',
            title: 'Log',
            child: Padding(
              padding: .x(1),
              child: Text('Drop a tab off the targets to float it.'),
            ),
          ),
        ],
      ),
    ),
    Button(
      'Dock them as they were',
      onPressed: () => _dock.layout = _docked(),
    ),
  ],
);

/// A count and a button that adds to it: kept as its panel moves.
final class _Clicks extends StatefulWidget {
  const _Clicks();

  @override
  State<_Clicks> createState() => _ClicksState();
}

final class _ClicksState extends State<_Clicks> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text.rich([Span('count: ', theme.muted), Span('$_count')]),
        Button('Add one', onPressed: () => setState(() => _count++)),
      ],
    );
  }
}''';

// ------------------------------------------------------------ Scaffold

/// What the Scaffold page keeps while the gallery runs: the controller,
/// whose sidebar width and choice outlive a visit elsewhere, and the
/// checkboxes and the count.
final class _NotesState {
  final controller = ScaffoldController(sidebarWidth: 14);
  var inbox = true;
  var archive = false;
  var notes = 3;
}

final class _Notes extends StatefulWidget {
  const _Notes(this.o);

  final Options o;

  @override
  State<_Notes> createState() => _NotesPageState();
}

final class _NotesPageState extends State<_Notes> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.o;
    final k = _kept(context, 'notes', _NotesState.new);
    return SizedBox(
      width: o.number('width').toInt(),
      height: 12,
      child: Scaffold(
        controller: k.controller,
        collapsedBelow: o.choice('collapsed'),
        sidebarSide: o['side'] == 'right'
            ? SidebarSide.right
            : SidebarSide.left,
        resizableSidebar: o.flag('resizable'),
        keyHints: o.flag('hints'),
        header: o.flag('header') ? const Text('notes') : null,
        sidebar: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: k.inbox,
                label: 'inbox',
                onChanged: (v) => setState(() => k.inbox = v),
              ),
              Checkbox(
                value: k.archive,
                label: 'archive',
                onChanged: (v) => setState(() => k.archive = v),
              ),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            gap: 1,
            children: [
              Button('New note', onPressed: () => setState(() => k.notes++)),
              Text.rich([Span('notes: ', theme.muted), Span('${k.notes}')]),
            ],
          ),
        ),
        statusBar: o.flag('status')
            ? StatusBar(
                left: Text('${k.notes} notes'),
                right: const Text('saved'),
              )
            : null,
      ),
    );
  }
}

final _scaffold = GalleryPage(
  group: 'Layout',
  title: 'Scaffold',
  options: [
    SliderOption(
      'width',
      'width',
      min: 30,
      max: 48,
      initial: 48,
      format: (v) => '$v cells',
    ),
    const ChoiceOption('side', 'sidebar side', values: ['left', 'right']),
    const SwitchOption('resizable', 'resizable', initial: true),
    const SwitchOption('hints', 'key hints', initial: true),
    const SwitchOption('header', 'header', initial: true),
    const SwitchOption('status', 'status bar', initial: true),
    const ChoiceOption(
      'collapsed',
      'collapsed below',
      values: [null, 36, 40, 44],
      initial: 40,
    ),
  ],
  build: (context, o) => _Notes(o),
  code: (o) => [
    'final _controller = ScaffoldController(sidebarWidth: 14);',
    'var _inbox = true;',
    'var _archive = false;',
    'var _notes = 3;',
    '',
    '@override',
    'void dispose() {',
    '  _controller.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return SizedBox(',
    '    width: ${o.label('width')},',
    '    height: 12,',
    '    child: Scaffold(',
    '      controller: _controller,',
    if (o.choice<int?>('collapsed') case final w?) '      collapsedBelow: $w,',
    if (o['side'] == 'right') '      sidebarSide: .right,',
    if (o.flag('resizable')) '      resizableSidebar: true,',
    if (!o.flag('hints')) '      keyHints: false,',
    if (o.flag('header')) "      header: const Text('notes'),",
    '      sidebar: Padding(',
    '        padding: const .all(1),',
    '        child: Column(',
    '          crossAxisAlignment: .start,',
    '          children: [',
    '            Checkbox(',
    '              value: _inbox,',
    "              label: 'inbox',",
    '              onChanged: (v) => setState(() => _inbox = v),',
    '            ),',
    '            Checkbox(',
    '              value: _archive,',
    "              label: 'archive',",
    '              onChanged: (v) => setState(() => _archive = v),',
    '            ),',
    '          ],',
    '        ),',
    '      ),',
    '      body: Padding(',
    '        padding: const .all(1),',
    '        child: Column(',
    '          crossAxisAlignment: .start,',
    '          gap: 1,',
    '          children: [',
    codeLine([
      "            Button('New note', ",
      'onPressed: () => setState(() => _notes++)),',
    ]),
    r"            Text.rich([Span('notes: ', theme.muted), Span('$_notes')]),",
    '          ],',
    '        ),',
    '      ),',
    if (o.flag('status')) ...[
      '      statusBar: StatusBar(',
      r"        left: Text('$_notes notes'),",
      "        right: const Text('saved'),",
      '      ),',
    ],
    '    ),',
    '  );',
    '}',
  ].join('\n'),
);

// ---------------------------------------------------- ExpansionTile, Accordion

/// The sections: a title, a subtitle, and what each holds as the Code
/// writes it, but the last, which holds a checkbox.
const _sections = [
  ('General', 'Name and theme', r'Name: twk\nTheme: dark'),
  ('Network', 'Proxy and timeouts', r'Proxy: none\nTimeout: 30 s'),
  ('Security', 'TLS and certificates', ''),
];

const _sectionsW = 40;

final _expansion = GalleryPage(
  group: 'Layout',
  title: 'ExpansionTile, Accordion',
  options: [
    const SwitchOption('accordion', 'in an accordion', initial: true),
    SwitchOption(
      'multiple',
      'several open',
      disabled: (o) => !o.flag('accordion'),
    ),
    const SwitchOption('subtitle', 'subtitles', initial: true),
    const ChoiceOption(
      'duration',
      'duration',
      values: [150, 400, 0],
      labels: ['150 ms', '400 ms', 'none'],
    ),
  ],
  build: (context, o) => _Sections(
    accordion: o.flag('accordion'),
    multiple: o.flag('multiple'),
    subtitle: o.flag('subtitle'),
    duration: Duration(milliseconds: o.choice<int>('duration')),
  ),
  code: (o) {
    final accordion = o.flag('accordion');
    final subtitle = o.flag('subtitle');
    final ms = o.choice<int>('duration');
    final [general, network, security] = [
      for (final (title, sub, _) in _sections)
        ["'$title'", if (subtitle) "'$sub'"].join(', '),
    ];
    return [
      'var _verify = true;',
      "var _did = '';",
      '',
      '/// A section of [title] that holds [child], and says when it opens or',
      '/// closes.',
      'ExpansionTile _section(',
      '  String title,',
      if (subtitle) '  String subtitle,',
      '  Widget child, {',
      '  bool open = false,',
      '}) => ExpansionTile(',
      '  title: Text(title),',
      if (subtitle) '  subtitle: Text(subtitle),',
      '  initiallyExpanded: open,',
      if (ms == 0)
        '  duration: Duration.zero,'
      else if (ms != 150)
        '  duration: const Duration(milliseconds: $ms),',
      '  onExpansionChanged: (expanded) => setState(',
      r"    () => _did = '${expanded ? 'opened' : 'closed'} $title',",
      '  ),',
      '  child: child,',
      ');',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  final sections = [',
      '    _section(',
      '      $general,',
      "      const Text('${_sections[0].$3}'),",
      '      open: true,',
      '    ),',
      "    _section($network, const Text('${_sections[1].$3}')),",
      '    _section(',
      '      $security,',
      '      Column(',
      '        mainAxisSize: .min,',
      '        crossAxisAlignment: .start,',
      '        children: [',
      "          const Text('TLS: 1.3'),",
      '          Checkbox(',
      '            value: _verify,',
      "            label: 'verify certificates',",
      '            onChanged: (value) => setState(() => _verify = value),',
      '          ),',
      '        ],',
      '      ),',
      '    ),',
      '  ];',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: $_sectionsW,',
      if (!accordion) ...[
        '        child: Column(',
        '          mainAxisSize: .min,',
        '          crossAxisAlignment: .start,',
        '          children: sections,',
        '        ),',
      ] else if (o.flag('multiple'))
        '        child: Accordion(allowMultiple: true, children: sections),'
      else
        '        child: Accordion(children: sections),',
      '      ),',
      '      Text.rich([',
      "        Span('did: ', theme.muted),",
      '        if (_did.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      '          Span(_did),',
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// Three sections of settings, in an accordion or apart, and what was
/// done to them last.
final class _Sections extends StatefulWidget {
  const _Sections({
    required this.accordion,
    required this.multiple,
    required this.subtitle,
    required this.duration,
  });

  final bool accordion;
  final bool multiple;
  final bool subtitle;
  final Duration duration;

  @override
  State<_Sections> createState() => _SectionsState();
}

final class _SectionsState extends State<_Sections> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;

  bool get _verify => _kept['verify'] as bool? ?? true;
  String get _did => _kept['did'] as String? ?? '';
  int get _serial => _kept['serial'] as int? ?? 0;

  ExpansionTile _section(
    String title,
    String subtitle,
    Widget child, {
    bool open = false,
  }) => ExpansionTile(
    title: Text(title),
    subtitle: widget.subtitle ? Text(subtitle) : null,
    initiallyExpanded: open,
    duration: widget.duration,
    onExpansionChanged: (expanded) => setState(() {
      _kept['did'] = '${expanded ? 'opened' : 'closed'} $title';
      _kept['serial'] = _serial + 1;
    }),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final [(g, gs, _), (n, ns, _), (s, ss, _)] = _sections;
    final sections = [
      _section(g, gs, const Text('Name: twk\nTheme: dark'), open: true),
      _section(n, ns, const Text('Proxy: none\nTimeout: 30 s')),
      _section(
        s,
        ss,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TLS: 1.3'),
            Checkbox(
              value: _verify,
              label: 'verify certificates',
              onChanged: (value) => setState(() => _kept['verify'] = value),
            ),
          ],
        ),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: _sectionsW,
          child: widget.accordion
              ? Accordion(allowMultiple: widget.multiple, children: sections)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sections,
                ),
        ),
        LitLine([
          ('did: ', true),
          if (_did.isEmpty) ('nothing', true) else (_did, false),
        ], serial: _serial),
      ],
    );
  }
}
