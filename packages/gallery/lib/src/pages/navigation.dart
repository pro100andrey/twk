// The Navigation group of the gallery.
import 'dart:async';

import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';
import 'common.dart';

/// The pages of the Navigation group that draw.
final List<GalleryPage> navigationPages = [
  GalleryPage(
    group: 'Navigation',
    title: 'Navigator',
    options: const [
      ChoiceOption(
        'backKey',
        'back key',
        values: ['escape', 'backspace', null],
        labels: ['escape', 'backspace', 'none'],
      ),
    ],
    build: (context, o) => SizedBox(
      width: 44,
      height: 9,
      child: Box(
        border: Border.all(
          type: BorderType.rounded,
          style: Theme.of(context).border,
        ),
        padding: const EdgeInsets.x(1),
        child: Navigator(
          backKey: o.choice('backKey'),
          home: const _Home(),
          onGenerateRoute: (settings) => settings.name == '/settings'
              ? _slide(context, (_) => const _Settings(), settings)
              : null,
        ),
      ),
    ),
    code: _code,
  ),
  GalleryPage(
    group: 'Navigation',
    title: 'PopScope, NavigatorObserver',
    options: [
      const SwitchOption('scope', 'PopScope', initial: true),
      // the dialog's own pop: Escape and the barrier close it, or a
      // PopScope in it keeps it
      ChoiceOption(
        'dialog',
        'esc in the dialog',
        values: const ['close', 'keep'],
        labels: const ['closes it', 'is kept'],
        disabled: (o) => !o.flag('scope'),
      ),
    ],
    build: (context, o) => _Asks(
      scope: o.flag('scope'),
      keep: o.flag('scope') && o.choice<String>('dialog') == 'keep',
    ),
    code: _popScopeCode,
  ),
  _breadcrumbs,
  _pagination,
  _stepper,
];

/// The Navigator page's Code.
String _code(Options o) {
  final backKey = o.choice<String?>('backKey');
  final back = switch (backKey) {
    'escape' => '',
    null => '      backKey: null,\n',
    final key => "      backKey: '$key',\n",
  };
  return '''
@override
Widget build(BuildContext context) => SizedBox(
  width: 44,
  height: 9,
  child: Box(
    border: .all(type: .rounded, style: Theme.of(context).border),
    padding: const .x(1),
    child: Navigator(
$back      home: const _Home(),
      onGenerateRoute: (settings) => settings.name == '/settings'
          ? _Slide.route((_) => const _Settings(), settings)
          : null,
    ),
  ),
);

/// The routes of the screens: each slides in from the right over the one
/// under it, which dims, and out again as it is popped.
abstract final class _Slide {
  static PageRoute<void> route(
    Widget Function(BuildContext context) builder, [
    RouteSettings settings = const RouteSettings(),
  ]) => PageRoute(
    builder: builder,
    settings: settings,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
  );
}

/// The first route: buttons that push the others.
final class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      const Text('Home'),
      Button(
        'Open item 7',
        onPressed: () =>
            Navigator.push(context, _Slide.route((_) => const _Item(7))),
      ),
      Button(
        'Open /settings',
        onPressed: () => Navigator.pushNamed<void>(context, '/settings'),
      ),
    ],
  );
}

/// Item [n], with a button that pops it and one that pushes the next.
final class _Item extends StatelessWidget {
  const _Item(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      Text('Item \$n', style: Theme.of(context).primary),
      Row(
        gap: 2,
        children: [
          Button(
            'Back',
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          ),
          Button(
            'Open item \${n + 1}',
            onPressed: () =>
                Navigator.push(context, _Slide.route((_) => _Item(n + 1))),
          ),
        ],
      ),
    ],
  );
}

/// The route named /settings, with a button that pops it.
final class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      Text('Settings', style: Theme.of(context).primary),
      Button(
        'Back',
        autofocus: true,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}''';
}

/// A screen that slides in from the right over the one under it, which
/// dims, and out again as it is popped; there at once while the gallery's
/// clock stands still, as its other motion is.
PageRoute<void> _slide(
  BuildContext context,
  Widget Function(BuildContext context) builder, [
  RouteSettings settings = const RouteSettings(),
]) {
  final still = Clock.of(context).frozen;
  return PageRoute(
    builder: builder,
    settings: settings,
    transitionDuration: still
        ? Duration.zero
        : const Duration(milliseconds: 220),
    reverseTransitionDuration: still
        ? Duration.zero
        : const Duration(milliseconds: 180),
  );
}

/// The first route: buttons that push the others.
final class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      const Text('Home'),
      Button(
        'Open item 7',
        onPressed: () =>
            Navigator.push(context, _slide(context, (_) => const _Item(7))),
      ),
      Button(
        'Open /settings',
        onPressed: () => Navigator.pushNamed<void>(context, '/settings'),
      ),
    ],
  );
}

/// Item [n], with a button that pops it and one that pushes the next.
final class _Item extends StatelessWidget {
  const _Item(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Text('Item $n', style: Theme.of(context).primary),
      Row(
        gap: 2,
        children: [
          Button(
            'Back',
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          ),
          Button(
            'Open item ${n + 1}',
            onPressed: () =>
                Navigator.push(context, _slide(context, (_) => _Item(n + 1))),
          ),
        ],
      ),
    ],
  );
}

/// The route named /settings, with a button that pops it.
final class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Text('Settings', style: Theme.of(context).primary),
      Button(
        'Back',
        autofocus: true,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}

// ------------------------------------------------ PopScope, NavigatorObserver

/// [lines], each [n] blanks in.
List<String> _pad(int n, List<String> lines) => [
  for (final l in lines) '${' ' * n}$l',
];

/// [lines] as the value of `child:`: the first after it, a comma after
/// the last.
List<String> _child(List<String> lines) => [
  'child: ${lines.first}',
  ...lines.sublist(1, lines.length - 1),
  '${lines.last},',
];

/// The PopScope page's Code.
String _popScopeCode(Options o) {
  final scope = o.flag('scope');
  final keep = o.choice<String>('dialog') == 'keep';
  const dialog = [
    'Dialog(',
    "  title: 'Discard the changes?',",
    '  child: Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    "      const Text('The note was changed.'),",
    '      Row(',
    '        mainAxisSize: .min,',
    '        gap: 2,',
    '        children: [',
    '          Button(',
    "            'Discard',",
    '            autofocus: true,',
    '            onPressed: () => closeDialog(context, true),',
    '          ),',
    "          Button('Keep', onPressed: () => closeDialog(context, false)),",
    '        ],',
    '      ),',
    '    ],',
    '  ),',
    ')',
  ];
  final shown = keep
      ? [
          '    // Escape and the barrier ask to pop the dialog too: kept',
          '    (context) => PopScope<bool>(',
          '      canPop: false,',
          ..._pad(6, _child(dialog)),
          '    ),',
        ]
      : [
          '    (context) => ${dialog.first}',
          ..._pad(4, dialog.sublist(1, dialog.length - 1)),
          '    ${dialog.last},',
        ];
  const column = [
    'Column(',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    "    Text('Edit the note', style: Theme.of(context).primary),",
    '    Checkbox(',
    '      value: _changed,',
    "      label: 'changed',",
    '      onChanged: (v) => setState(() => _changed = v),',
    '    ),',
    '    Button(',
    "      'Back',",
    '      autofocus: true,',
    '      onPressed: () => Navigator.maybePop(context),',
    '    ),',
    '  ],',
    ')',
  ];
  final edit = scope
      ? [
          'Future<void> _ask() async {',
          '  final discard = await showDialog<bool>(',
          '    context,',
          ...shown,
          '  );',
          '  if ((discard ?? false) && mounted) {',
          '    Navigator.pop(context);',
          '  }',
          '}',
          '',
          '@override',
          'Widget build(BuildContext context) => PopScope<void>(',
          '  canPop: !_changed,',
          '  // a pop it kept: Back or the back key while the note is changed',
          '  onPopInvokedWithResult: (didPop, _) {',
          '    if (!didPop) {',
          '      unawaited(_ask());',
          '    }',
          '  },',
          ..._pad(2, _child(column)),
          ');',
        ]
      : [
          '@override',
          'Widget build(BuildContext context) => ${column.first}',
          ...column.sublist(1, column.length - 1),
          '${column.last};',
        ];
  return [
    'final _heard = _Heard();',
    '',
    '@override',
    'void dispose() {',
    '  _heard.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  gap: 1,',
    '  children: [',
    '    SizedBox(',
    '      width: 44,',
    '      height: 9,',
    '      child: Box(',
    '        border: .all(type: .rounded, style: Theme.of(context).border),',
    '        padding: const .x(1),',
    '        child: Navigator(',
    '          observers: [_heard],',
    '          home: const _Notes(),',
    "          routes: {'/edit': (_) => const _Edit()},",
    '        ),',
    '      ),',
    '    ),',
    '    ListenableBuilder(',
    '      listenable: _heard,',
    '      builder: (context, _) => Text.rich([',
    "        Span('heard: ', Theme.of(context).muted),",
    '        Span(_heard.last),',
    '      ]),',
    '    ),',
    '  ],',
    ');',
    '',
    '/// Hears of each route pushed, popped and removed, the last of them',
    '/// [last].',
    'final class _Heard extends NavigatorObserver with ChangeNotifier {',
    "  var last = '';",
    '',
    [
      '  String _name(Route<Object?> route) => ',
      "route.settings.name ?? 'a dialog';",
    ].join(),
    '',
    '  @override',
    '  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {',
    r"    last = 'pushed ${_name(route)}';",
    '    notifyListeners();',
    '  }',
    '',
    '  @override',
    '  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {',
    r"    last = 'popped ${_name(route)}';",
    '    notifyListeners();',
    '  }',
    '',
    '  // a dialog closeDialog closes',
    '  @override',
    '  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {',
    r"    last = 'removed ${_name(route)}';",
    '    notifyListeners();',
    '  }',
    '}',
    '',
    '/// The first route: a button that pushes the editor.',
    'final class _Notes extends StatelessWidget {',
    '  const _Notes();',
    '',
    '  @override',
    '  Widget build(BuildContext context) => Column(',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    "      const Text('Notes'),",
    '      Button(',
    "        'Edit the note',",
    "        onPressed: () => Navigator.pushNamed<void>(context, '/edit'),",
    '      ),',
    '    ],',
    '  );',
    '}',
    '',
    if (scope)
      "/// The note's editor: Back pops it, asking first while it is changed."
    else
      "/// The note's editor: Back pops it.",
    'final class _Edit extends StatefulWidget {',
    '  const _Edit();',
    '',
    '  @override',
    '  State<_Edit> createState() => _EditState();',
    '}',
    '',
    'final class _EditState extends State<_Edit> {',
    '  var _changed = false;',
    '',
    for (final l in _pad(2, edit))
      if (l.trim().isEmpty) '' else l,
    '}',
  ].join('\n');
}

/// Hears of each route pushed, popped and removed, the last of them [last], and
/// counts them, so that the line under the box lights at each.
final class _Heard extends NavigatorObserver with ChangeNotifier {
  var last = '';
  var heard = 0;

  String _name(Route<Object?> route) => route.settings.name ?? 'a dialog';

  void _hear(String what) {
    last = what;
    heard++;
    notifyListeners();
  }

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      _hear('pushed ${_name(route)}');

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) =>
      _hear('popped ${_name(route)}');

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) =>
      _hear('removed ${_name(route)}');
}

/// The Code's widget: a navigator whose editor route asks before it is
/// popped while it is changed ([scope]), in a dialog that a PopScope of
/// its own keeps open against Escape with [keep], and the line of what the
/// navigator's observer heard last.
final class _Asks extends StatefulWidget {
  const _Asks({required this.scope, required this.keep});

  final bool scope;
  final bool keep;

  @override
  State<_Asks> createState() => _AsksState();
}

final class _AsksState extends State<_Asks> {
  final _heard = _Heard();

  @override
  void dispose() {
    _heard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      SizedBox(
        width: 44,
        height: 9,
        child: Box(
          border: .all(type: .rounded, style: Theme.of(context).border),
          padding: const .x(1),
          child: _Asking(
            scope: widget.scope,
            keep: widget.keep,
            child: Navigator(
              observers: [_heard],
              home: const _Notes(),
              routes: {'/edit': (_) => const _Edit()},
            ),
          ),
        ),
      ),
      ListenableBuilder(
        listenable: _heard,
        builder: (context, _) => LitLine([
          ('heard: ', true),
          (_heard.last, false),
        ], serial: _heard.heard),
      ),
    ],
  );
}

/// How the editor below asks: the page's options, for the routes, which
/// the navigator builds apart from the page.
final class _Asking extends InheritedWidget {
  const _Asking({
    required this.scope,
    required this.keep,
    required super.child,
  });

  final bool scope;
  final bool keep;

  static _Asking of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Asking>()!;

  @override
  bool updateShouldNotify(_Asking oldWidget) =>
      scope != oldWidget.scope || keep != oldWidget.keep;
}

/// The first route: a button that pushes the editor.
final class _Notes extends StatelessWidget {
  const _Notes();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      const Text('Notes'),
      Button(
        'Edit the note',
        onPressed: () => Navigator.pushNamed<void>(context, '/edit'),
      ),
    ],
  );
}

/// The note's editor: Back pops it, asking first while it is changed.
final class _Edit extends StatefulWidget {
  const _Edit();

  @override
  State<_Edit> createState() => _EditState();
}

final class _EditState extends State<_Edit> {
  var _changed = false;

  Future<void> _ask() async {
    final keep = _Asking.of(context).keep;
    Widget dialog(BuildContext context) => Dialog(
      title: 'Discard the changes?',
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        gap: 1,
        children: [
          const Text('The note was changed.'),
          Row(
            mainAxisSize: .min,
            gap: 2,
            children: [
              Button(
                'Discard',
                autofocus: true,
                onPressed: () => closeDialog(context, true),
              ),
              Button('Keep', onPressed: () => closeDialog(context, false)),
            ],
          ),
        ],
      ),
    );
    final discard = await showDialog<bool>(
      context,
      keep
          ? (context) => PopScope<bool>(canPop: false, child: dialog(context))
          : dialog,
    );
    if ((discard ?? false) && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: .start,
      gap: 1,
      children: [
        Text('Edit the note', style: Theme.of(context).primary),
        Checkbox(
          value: _changed,
          label: 'changed',
          onChanged: (v) => setState(() => _changed = v),
        ),
        Button(
          'Back',
          autofocus: true,
          onPressed: () => Navigator.maybePop(context),
        ),
      ],
    );
    if (!_Asking.of(context).scope) {
      return column;
    }
    return PopScope<void>(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_ask());
        }
      },
      child: column,
    );
  }
}

// ------------------------------------------------------------ Breadcrumbs

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

final class _CrumbsState extends State<_Crumbs> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;

  int get _at => _kept['at'] as int? ?? _path.length - 1;
  int get _serial => _kept['serial'] as int? ?? 0;

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
            _kept['at'] = index;
            _kept['serial'] = _serial + 1;
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

final class _PagesState extends State<_Pages> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;

  int get _page => _kept['page'] as int? ?? 1;
  int get _serial => _kept['serial'] as int? ?? 0;

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
            _kept['page'] = page;
            _kept['serial'] = _serial + 1;
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

// ------------------------------------------------------------ Stepper

/// The packages the wizard offers.
const _offered = ['args', 'http', 'path'];

final _stepper = GalleryPage(
  group: 'Navigation',
  title: 'Stepper',
  options: const [
    ChoiceOption(
      'direction',
      'direction',
      values: ['horizontal', 'vertical'],
    ),
    SwitchOption('linear', 'linear', initial: true),
    // Back and Next under the content; without them PageDown and PageUp
    // still move it, and a click on a header
    SwitchOption('controls', 'back and next', initial: true),
    // the Packages step disabled: passed by, muted
    SwitchOption('disabled', 'packages disabled'),
  ],
  build: (context, o) => _Wizard(
    direction: Axis.values.byName(o.choice('direction')),
    linear: o.flag('linear'),
    showControls: o.flag('controls'),
    packagesDisabled: o.flag('disabled'),
  ),
  code: (o) => [
    "final _name = TextEditingController(text: 'my_app');",
    "final _packages = {'args'};",
    "var _created = '';",
    '',
    '@override',
    'void dispose() {',
    '  _name.dispose();',
    '  super.dispose();',
    '}',
    '',
    'Widget _package(String name) => Checkbox(',
    '  value: _packages.contains(name),',
    '  label: name,',
    '  onChanged: (on) => setState(() {',
    '    if (!on) {',
    '      _packages.remove(name);',
    '    } else {',
    '      _packages.add(name);',
    '    }',
    '  }),',
    ');',
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
    '        width: 50,',
    '        child: Stepper(',
    if (o.choice<String>('direction') == 'vertical')
      '          direction: .vertical,',
    if (!o.flag('linear')) '          linear: false,',
    if (!o.flag('controls')) '          showControls: false,',
    '          steps: [',
    '            Step(',
    "              title: 'Name',",
    "              subtitle: 'What the package is called',",
    '              content: TextField(',
    '                controller: _name,',
    "                semanticsLabel: 'Name',",
    '              ),',
    '              validate: () =>',
    "                  _name.text.isEmpty ? 'The package needs a name' : null,",
    '            ),',
    '            Step(',
    "              title: 'Packages',",
    "              subtitle: 'What it depends on',",
    if (o.flag('disabled')) '              state: .disabled,',
    '              content: Column(',
    '                mainAxisSize: .min,',
    '                crossAxisAlignment: .start,',
    '                children: [',
    for (final p in _offered) "                  _package('$p'),",
    '                ],',
    '              ),',
    '              // as a server that looks them up would',
    '              validate: () async {',
    '                await Future<void>.delayed(',
    '                  const Duration(milliseconds: 800),',
    '                );',
    "                return _packages.isEmpty ? 'Pick one at least' : null;",
    '              },',
    '            ),',
    '            Step(',
    "              title: 'Confirm',",
    '              content: Text(',
    r"                'Create ${_name.text} with ${_packages.join(', ')}?',",
    '              ),',
    '            ),',
    '          ],',
    '          onFinished: () => setState(() => _created = _name.text),',
    '        ),',
    '      ),',
    '      Text.rich([',
    "        Span('created: ', theme.muted),",
    '        if (_created.isEmpty)',
    "          Span('nothing', theme.muted)",
    '        else',
    '          Span(_created),',
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// A wizard that makes a package, and the package it made last.
final class _Wizard extends StatefulWidget {
  const _Wizard({
    required this.direction,
    required this.linear,
    required this.showControls,
    required this.packagesDisabled,
  });

  final Axis direction;
  final bool linear;
  final bool showControls;
  final bool packagesDisabled;

  @override
  State<_Wizard> createState() => _WizardState();
}

final class _WizardState extends State<_Wizard> {
  final _name = TextEditingController(text: 'my_app');
  final _packages = {'args'};
  var _created = '';
  var _serial = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _package(String name) => Checkbox(
    value: _packages.contains(name),
    label: name,
    onChanged: (on) => setState(() {
      if (!on) {
        _packages.remove(name);
      } else {
        _packages.add(name);
      }
    }),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      SizedBox(
        width: 50,
        child: Stepper(
          direction: widget.direction,
          linear: widget.linear,
          showControls: widget.showControls,
          steps: [
            Step(
              title: 'Name',
              subtitle: 'What the package is called',
              content: TextField(controller: _name, semanticsLabel: 'Name'),
              validate: () =>
                  _name.text.isEmpty ? 'The package needs a name' : null,
            ),
            Step(
              title: 'Packages',
              subtitle: 'What it depends on',
              state: widget.packagesDisabled ? StepState.disabled : null,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final p in _offered) _package(p)],
              ),
              validate: () async {
                await Future<void>.delayed(const Duration(milliseconds: 800));
                return _packages.isEmpty ? 'Pick one at least' : null;
              },
            ),
            Step(
              title: 'Confirm',
              content: Text(
                'Create ${_name.text} with ${_packages.join(', ')}?',
              ),
            ),
          ],
          onFinished: () => setState(() {
            _created = _name.text;
            _serial++;
          }),
        ),
      ),
      LitLine([
        ('created: ', true),
        if (_created.isEmpty) ('nothing', true) else (_created, false),
      ], serial: _serial),
    ],
  );
}
