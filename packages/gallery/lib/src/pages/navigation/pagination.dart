// The Pagination page.
part of 'navigation.dart';

// ------------------------------------------------------------ Pagination

const _pages = 42;

const _pageSize = 20;

final _pagination = GalleryPage(
  group: 'Navigation',
  title: 'Pagination',
  options: [
    SliderOption(
      'width',
      'width',
      min: 16,
      max: 56,
      initial: 56,
      format: (v) => '$v cells',
    ),
    const ChoiceOption('siblings', 'siblings', values: [1, 0, 2]),
    const SwitchOption('firstLast', 'first and last', initial: true),
    const SwitchOption('prevNext', 'previous and next', initial: true),
    const SwitchOption('range', 'range'),
  ],
  build: (context, o) => _Pages(
    width: o.number('width').toInt(),
    siblings: o.choice('siblings'),
    firstLast: o.flag('firstLast'),
    prevNext: o.flag('prevNext'),
    range: o.flag('range'),
  ),
  code: (o) => [
    'var _page = 1;',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      SizedBox(',
    '        width: ${o.label('width')},',
    '        child: Pagination(',
    '          page: _page,',
    '          pageCount: $_pages,',
    if (o.flag('range')) ...[
      '          itemCount: ${_pages * _pageSize},',
      '          pageSize: $_pageSize,',
    ],
    if (o.choice<int>('siblings') != 1)
      '          siblings: ${o.choice<int>('siblings')},',
    if (!o.flag('firstLast')) '          showFirstLast: false,',
    if (!o.flag('prevNext')) '          showPrevNext: false,',
    '          onChanged: (page) => setState(() => _page = page),',
    '        ),',
    '      ),',
    '      Text.rich([',
    "        Span('page: ', theme.muted),",
    "        Span('\${_page + 1} of $_pages'),",
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// The pages of a list of 840 rows in a row [width] cells wide, the rows
/// of the page with [range], and the page shown.
final class _Pages extends StatefulWidget {
  const _Pages({
    required this.width,
    required this.siblings,
    required this.firstLast,
    required this.prevNext,
    required this.range,
  });

  final int width;
  final int siblings;
  final bool firstLast;
  final bool prevNext;
  final bool range;

  @override
  State<_Pages> createState() => _PagesState();
}

final class _PagesState extends State<_Pages> with KeptState {
  int get _page => kept['page'] as int? ?? 1;
  int get _serial => kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      SizedBox(
        width: widget.width,
        child: Pagination(
          page: _page,
          pageCount: _pages,
          itemCount: widget.range ? _pages * _pageSize : null,
          pageSize: widget.range ? _pageSize : null,
          siblings: widget.siblings,
          showFirstLast: widget.firstLast,
          showPrevNext: widget.prevNext,
          onChanged: (page) => setState(() {
            kept['page'] = page;
            kept['serial'] = _serial + 1;
          }),
        ),
      ),
      LitLine([
        ('page: ', true),
        ('${_page + 1} of $_pages', false),
      ], serial: _serial),
    ],
  );
}
