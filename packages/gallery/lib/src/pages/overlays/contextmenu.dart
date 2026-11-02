// The ContextMenu page.
part of 'overlays.dart';

final _contextmenuPage = GalleryPage(
  group: _group,
  title: 'ContextMenu',
  // an open menu (or palette) takes Tab itself
  modalTab: false,
  options: [_lookOption],
  build: (context, o) => _Context(look: _lookOf(o)),
  code: _contextCode,
);

/// The ContextMenu page's Code.
String _contextCode(Options o) =>
    '''
final _menu = MenuController();
String? _chosen;
var _copied = false;

@override
void dispose() {
  _menu.dispose();
  super.dispose();
}

void _choose(String what) => setState(() {
  _chosen = what;
  _copied |= what == 'Cut' || what == 'Copy';
});

@override
Widget build(BuildContext context) => ContextMenu(
  controller: _menu,
${_lookLine(o, '  ').map((l) => '$l\n').join()}  items: [
    MenuItem('Cu&t', onSelected: () => _choose('Cut')),
    MenuItem('&Copy', onSelected: () => _choose('Copy')),
    MenuItem('&Paste', onSelected: _copied ? () => _choose('Paste') : null),
    const MenuDivider(),
    MenuItem('Select &all', onSelected: () => _choose('Select all')),
  ],
  child: SizedBox(
    width: 40,
    height: 5,
    child: Box(
      border: .all(type: .rounded, style: Theme.of(context).border),
      padding: const .x(1),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          const Text('Right click in here.'),
          Row(
            gap: 2,
            children: [
              Button('Or focus me', onPressed: () {}),
              // at a cell of the child, as a right click there
              Button(
                'Open the menu',
                onPressed: () => _menu.open(null, (22, 1)),
              ),
            ],
          ),
          Text.rich([
            Span('chosen: ', Theme.of(context).muted),
            switch (_chosen) {
              null => Span('nothing', Theme.of(context).muted),
              final chosen => Span(chosen),
            },
          ]),
        ],
      ),
    ),
  ),
);''';

/// A box a right click opens a menu in, or Shift+F10 on its button.
final class _Context extends StatefulWidget {
  const _Context({required this.look});

  final PanelLook look;

  @override
  State<_Context> createState() => _ContextState();
}

final class _ContextState extends State<_Context> with KeptState {
  String? get _chosen => kept['chosen'] as String?;
  bool get _copied => kept['copied'] as bool? ?? false;
  int get _serial => kept['serial'] as int? ?? 0;

  void _choose(String what) => setState(() {
    kept
      ..['chosen'] = what
      ..['copied'] = _copied || what == 'Cut' || what == 'Copy'
      ..['serial'] = _serial + 1;
  });

  final _menu = MenuController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContextMenu(
    controller: _menu,
    look: widget.look,
    items: [
      MenuItem('Cu&t', onSelected: () => _choose('Cut')),
      MenuItem('&Copy', onSelected: () => _choose('Copy')),
      MenuItem('&Paste', onSelected: _copied ? () => _choose('Paste') : null),
      const MenuDivider(),
      MenuItem('Select &all', onSelected: () => _choose('Select all')),
    ],
    child: SizedBox(
      width: 40,
      height: 5,
      child: Box(
        border: Border.all(
          type: BorderType.rounded,
          style: Theme.of(context).border,
        ),
        padding: const EdgeInsets.x(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Right click in here.'),
            Row(
              gap: 2,
              children: [
                Button('Or focus me', onPressed: () {}),
                Button(
                  'Open the menu',
                  onPressed: () => _menu.open(null, (22, 1)),
                ),
              ],
            ),
            LitLine([
              ('chosen: ', true),
              (_chosen ?? 'nothing', _chosen == null),
            ], serial: _serial),
          ],
        ),
      ),
    ),
  );
}
