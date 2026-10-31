// The Row, Column, Flex page.
part of 'layout.dart';

// -------------------------------------------------------- Row, Column, Flex

const _fw = 44;

const _fh = 11;

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
