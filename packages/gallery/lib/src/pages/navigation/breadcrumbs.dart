// The Breadcrumbs page.
part of 'navigation.dart';

/// The path the crumbs show, from the project down.
const _path = ['twk', 'packages', 'gallery', 'lib', 'src', 'pages'];

/// The Breadcrumbs page's `width` option.
final _breadcrumbsWidth = SliderOption(
  'width',
  'width',
  min: 12,
  max: 50,
  initial: 36,
  format: (v) => '$v cells',
);

/// The Breadcrumbs page's `keep` option.
const _breadcrumbsKeep = ChoiceOption<int>(
  'keep',
  'leading kept',
  values: [1, 0, 2],
);

/// The Breadcrumbs page's `separator` option.
const _breadcrumbsSeparator = ChoiceOption<String>(
  'separator',
  'separator',
  values: [' › ', ' / '],
  labels: ['›', '/'],
);

final _breadcrumbs = GalleryPage(
  group: _group,
  title: 'Breadcrumbs',
  options: [
    _breadcrumbsWidth,
    _breadcrumbsKeep,
    _breadcrumbsSeparator,
  ],
  build: (context, o) => _Crumbs(
    width: o(_breadcrumbsWidth).toInt(),
    keepLeading: o(_breadcrumbsKeep),
    separator: o(_breadcrumbsSeparator),
  ),
  code: (o) => [
    'static const _path = [${_path.map((p) => "'$p'").join(', ')}];',
    'var _at = _path.length - 1;',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  spacing: 1,',
    '  children: [',
    '    SizedBox(',
    '      width: ${o.nameOf(_breadcrumbsWidth)},',
    '      child: Breadcrumbs(',
    '        items: _path,',
    '        current: _at,',
    if (o(_breadcrumbsKeep) != 1)
      '        keepLeading: ${o(_breadcrumbsKeep)},',
    if (o(_breadcrumbsSeparator) != ' › ')
      "        separator: '${o(_breadcrumbsSeparator)}',",
    '        onSelected: (index) => setState(() => _at = index),',
    '      ),',
    '    ),',
    '    Text.rich([',
    "      Span('at: ', Theme.of(context).muted),",
    "      Span(_path.take(_at + 1).join('/')),",
    '    ]),',
    '  ],',
    ');',
  ].join('\n'),
);

/// The path in crumbs [width] cells wide, the level gone to last, and
/// where that is.
final class _Crumbs extends StatefulWidget {
  const _Crumbs({
    required this.width,
    required this.keepLeading,
    required this.separator,
  });

  final int width;
  final int keepLeading;
  final String separator;

  @override
  State<_Crumbs> createState() => _CrumbsState();
}

final class _CrumbsState extends State<_Crumbs> with KeptState {
  int get _at => kept['at'] as int? ?? _path.length - 1;
  int get _serial => kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 1,
    children: [
      SizedBox(
        width: widget.width,
        child: Breadcrumbs(
          items: _path,
          current: _at,
          keepLeading: widget.keepLeading,
          separator: widget.separator,
          onSelected: (index) => setState(() {
            kept['at'] = index;
            kept['serial'] = _serial + 1;
          }),
        ),
      ),
      LitLine([
        ('at: ', true),
        (_path.take(_at + 1).join('/'), false),
      ], serial: _serial),
    ],
  );
}
