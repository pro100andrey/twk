// The PopScope, NavigatorObserver page.
part of 'navigation.dart';

/// The PopScope, NavigatorObserver page's `scope` option.
const _popscopeNavigatorobserverScope = SwitchOption(
  'scope',
  'PopScope',
  initial: true,
);

/// The PopScope, NavigatorObserver page's `dialog` option.
final _popscopeNavigatorobserverDialog = ChoiceOption<String>(
  'dialog',
  'esc in the dialog',
  values: const ['close', 'keep'],
  labels: const ['closes it', 'is kept'],
  disabled: (o) => !o(_popscopeNavigatorobserverScope),
);

final _popscopeNavigatorobserverPage = GalleryPage(
  group: _group,
  title: 'PopScope, NavigatorObserver',
  options: [
    _popscopeNavigatorobserverScope,
    // the dialog's own pop: Escape and the barrier close it, or a
    // PopScope in it keeps it
    _popscopeNavigatorobserverDialog,
  ],
  build: (context, o) => _Asks(
    scope: o(_popscopeNavigatorobserverScope),
    keep:
        o(_popscopeNavigatorobserverScope) &&
        o(_popscopeNavigatorobserverDialog) == 'keep',
  ),
  code: _popScopeCode,
);

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
  final scope = o(_popscopeNavigatorobserverScope);
  final keep = o(_popscopeNavigatorobserverDialog) == 'keep';
  const dialog = [
    'Dialog(',
    "  title: 'Discard the changes?',",
    '  child: Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    spacing: 1,',
    '    children: [',
    "      const Text('The note was changed.'),",
    '      Row(',
    '        mainAxisSize: .min,',
    '        spacing: 2,',
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
          '    builder: (context) => PopScope<bool>(',
          '      canPop: false,',
          ..._pad(6, _child(dialog)),
          '    ),',
        ]
      : [
          '    builder: (context) => ${dialog.first}',
          ..._pad(4, dialog.sublist(1, dialog.length - 1)),
          '    ${dialog.last},',
        ];
  const column = [
    'Column(',
    '  crossAxisAlignment: .start,',
    '  spacing: 1,',
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
          '    context: context,',
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
    '  spacing: 1,',
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
    '    spacing: 1,',
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
    spacing: 1,
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
    spacing: 1,
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
        spacing: 1,
        children: [
          const Text('The note was changed.'),
          Row(
            mainAxisSize: .min,
            spacing: 2,
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
      context: context,
      builder: keep
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
      spacing: 1,
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
