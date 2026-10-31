// The Breadcrumbs page.
part of 'navigation.dart';

/// The path the crumbs show, from the project down.
const _path = ['twk', 'packages', 'gallery', 'lib', 'src', 'pages'];

final _breadcrumbs = GalleryPage(
  group: 'Navigation',
  title: 'Breadcrumbs',
  options: [
    SliderOption(
      'width',
      'width',
      min: 12,
      max: 50,
      initial: 36,
      format: (v) => '$v cells',
    ),
    const ChoiceOption('keep', 'leading kept', values: [1, 0, 2]),
    const ChoiceOption(
      'separator',
      'separator',
      values: [' › ', ' / '],
      labels: ['›', '/'],
    ),
  ],
  build: (context, o) => _Crumbs(
    width: o.number('width').toInt(),
    keepLeading: o.choice('keep'),
    separator: o.choice('separator'),
  ),
  code: (o) => [
    'static const _path = [${_path.map((p) => "'$p'").join(', ')}];',
    'var _at = _path.length - 1;',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    '    SizedBox(',
    '      width: ${o.label('width')},',
    '      child: Breadcrumbs(',
    '        items: _path,',
    '        current: _at,',
    if (o.choice<int>('keep') != 1)
      '        keepLeading: ${o.choice<int>('keep')},',
    if (o.choice<String>('separator') != ' › ')
      "        separator: '${o.choice<String>('separator')}',",
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
    gap: 1,
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
