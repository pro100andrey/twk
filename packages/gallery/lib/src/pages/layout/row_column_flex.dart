// The Row, Column, Flex page.
part of 'layout.dart';

// -------------------------------------------------------- Row, Column, Flex

const _fw = 44;

const _fh = 11;

/// The Row, Column, Flex page's `dir` option.
const _flexDir = ChoiceOption<String>(
  'dir',
  'direction',
  values: ['row', 'column'],
);

/// The Row, Column, Flex page's `main` option.
const _flexMain = ChoiceOption<String>(
  'main',
  'main axis',
  values: _main,
  initial: 'spaceBetween',
);

/// The Row, Column, Flex page's `cross` option.
const _flexCross = ChoiceOption<String>(
  'cross',
  'cross axis',
  values: ['start', 'end', 'center', 'stretch'],
  initial: 'center',
);

/// The Row, Column, Flex page's `spacing` option.
const _flexSpacing = ChoiceOption<int>(
  'spacing',
  'spacing',
  values: [0, 1, 2],
  initial: 1,
);

/// The Row, Column, Flex page's `size` option.
const _flexSize = ChoiceOption<String>(
  'size',
  'main axis size',
  values: ['max', 'min'],
);

final _flex = GalleryPage(
  group: _group,
  title: 'Row, Column, Flex',
  options: const [
    _flexDir,
    _flexMain,
    _flexCross,
    _flexSpacing,
    _flexSize,
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
    final main = MainAxisAlignment.values.byName(o(_flexMain));
    final cross = CrossAxisAlignment.values.byName(o(_flexCross));
    final spacing = o(_flexSpacing);
    final size = MainAxisSize.values.byName(o(_flexSize));
    final Widget flex = o(_flexDir) == 'row'
        ? Row(
            mainAxisAlignment: main,
            mainAxisSize: size,
            crossAxisAlignment: cross,
            spacing: spacing,
            children: children,
          )
        : Column(
            mainAxisAlignment: main,
            mainAxisSize: size,
            crossAxisAlignment: cross,
            spacing: spacing,
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
    final min = o(_flexSize) == 'min';
    final flex = [
      '${o(_flexDir) == 'row' ? 'Row' : 'Column'}(',
      if (o(_flexMain) != 'start')
        '  mainAxisAlignment: .${o.nameOf(_flexMain)},',
      if (min) '  mainAxisSize: .min,',
      if (o(_flexCross) != 'center')
        '  crossAxisAlignment: .${o.nameOf(_flexCross)},',
      if (o(_flexSpacing) != 0) '  spacing: ${o.nameOf(_flexSpacing)},',
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
