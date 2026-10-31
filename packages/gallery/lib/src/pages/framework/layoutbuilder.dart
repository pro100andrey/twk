// The LayoutBuilder page.
part of 'framework.dart';

/// The SizedBox's height.
const _lh = 8;

/// The LayoutBuilder page's `width` option.
final _layoutWidth = SliderOption(
  'width',
  'width',
  min: 12,
  max: 50,
  initial: 40,
  format: (v) => '$v cells',
);

/// The LayoutBuilder page's `at` option.
const _layoutAt = ChoiceOption<int>(
  'at',
  'wide from',
  values: [24, 30, 36],
  initial: 30,
  labels: ['24', '30', '36'],
);

final _layout = GalleryPage(
  group: _group,
  title: 'LayoutBuilder',
  options: [
    _layoutWidth,
    _layoutAt,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final at = o(_layoutAt);
    return SizedBox(
      width: o(_layoutWidth).toInt(),
      height: _lh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxW >= at;
          final panes = [
            for (final name in const ['one', 'two'])
              Expanded(
                child: Box(
                  border: Border.all(
                    type: BorderType.rounded,
                    style: theme.border,
                  ),
                  titles: [BorderTitle(' $name ')],
                  child: LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: Text(
                        describeConstraints(constraints),
                        style: theme.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich([
                Span('${describeConstraints(constraints)}: '),
                Span(wide ? 'wide' : 'narrow', theme.primary),
              ]),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: panes,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: panes,
                      ),
              ),
            ],
          );
        },
      ),
    );
  },
  code: (o) => [
    'final theme = Theme.of(context);',
    'return SizedBox(',
    '  width: ${o.nameOf(_layoutWidth)},',
    '  height: $_lh,',
    '  // a render object widget: its builder runs in the layout, with the',
    '  // constraints the SizedBox gives, and again when they change',
    '  child: LayoutBuilder(',
    '    builder: (context, constraints) {',
    '      final wide = constraints.maxW >= ${o.nameOf(_layoutAt)};',
    '      final panes = [',
    "        for (final name in const ['one', 'two'])",
    '          Expanded(',
    '            child: Box(',
    '              border: .all(type: .rounded, style: theme.border),',
    r"              titles: [BorderTitle(' $name ')],",
    '              // what each pane is given in turn',
    '              child: LayoutBuilder(',
    '                builder: (context, constraints) => Center(',
    '                  child: Text(',
    '                    describeConstraints(constraints),',
    '                    style: theme.muted,',
    '                  ),',
    '                ),',
    '              ),',
    '            ),',
    '          ),',
    '      ];',
    '      return Column(',
    '        crossAxisAlignment: .stretch,',
    '        children: [',
    '          Text.rich([',
    r"            Span('${describeConstraints(constraints)}: '),",
    "            Span(wide ? 'wide' : 'narrow', theme.primary),",
    '          ]),',
    '          Expanded(',
    '            child: wide',
    '                ? Row(crossAxisAlignment: .stretch, children: panes)',
    codeLine([
      '                : ',
      'Column(crossAxisAlignment: .stretch, children: panes),',
    ]),
    '          ),',
    '        ],',
    '      );',
    '    },',
    '  ),',
    ');',
  ].join('\n'),
);
