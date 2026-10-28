// The Framework group of the gallery.
import 'package:twk/twk.dart';

import '../page.dart';
import 'common.dart';

/// The pages of the Framework group that draw.
final List<GalleryPage> frameworkPages = [_layout, _notifications, _slots];

/// [parts] as one line of the Code, a line too long for this file.
String _line(List<String> parts) => parts.join();

// ----------------------------------------------------------- LayoutBuilder

/// The SizedBox's height.
const _lh = 8;

final _layout = GalleryPage(
  group: 'Framework',
  title: 'LayoutBuilder',
  options: [
    SliderOption(
      'width',
      'width',
      min: 12,
      max: 50,
      initial: 40,
      format: (v) => '$v cells',
    ),
    const ChoiceOption(
      'at',
      'wide from',
      values: [24, 30, 36],
      initial: 30,
      labels: ['24', '30', '36'],
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final at = o.choice<int>('at');
    return SizedBox(
      width: o.number('width').toInt(),
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
    '  width: ${o.label('width')},',
    '  height: $_lh,',
    '  // a render object widget: its builder runs in the layout, with the',
    '  // constraints the SizedBox gives, and again when they change',
    '  child: LayoutBuilder(',
    '    builder: (context, constraints) {',
    '      final wide = constraints.maxW >= ${o.label('at')};',
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
    _line([
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

// ---------------------------------------------------- NotificationListener

/// The list's items.
const _items = 100;

/// The list's box.
const _nw = 16;
const _nh = 8;

/// The rows of the trace.
const _shown = 4;

/// What each choice of the outer listener hears, by the Code's type.
const _types = [
  'ScrollNotification',
  'ScrollUpdateNotification',
  'OverscrollNotification',
];

final _notifications = GalleryPage(
  group: 'Framework',
  title: 'NotificationListener',
  options: const [
    ChoiceOption(
      'outer',
      'outer hears',
      values: _types,
      labels: ['Scroll', 'ScrollUpdate', 'Overscroll'],
    ),
    SwitchOption('stops', 'inner stops them'),
  ],
  build: (context, o) =>
      _Bubbling(outer: o.choice('outer'), stops: o.flag('stops')),
  code: (o) {
    final stops = o.flag('stops');
    final outer = o.choice<String>('outer');
    return [
      '/// What became of a notification on its way up the tree.',
      'final class _Sent {',
      '  _Sent(this.notification);',
      '',
      '  final ScrollNotification notification;',
      '',
      '  // what the inner and the outer listener did with it',
      "  var inner = 'past';",
      '  String? _outer;',
      '',
      "  String get outer => _outer ?? (inner == 'stops' ? '–' : 'past');",
      '  set outer(String what) => _outer = what;',
      '}',
      '',
      'final _trace = <_Sent>[];',
      'String? _heard;',
      '',
      "// the list's, so that its box shows where the focus is",
      'final _list = FocusNode();',
      '',
      '@override',
      'void dispose() {',
      '  _list.dispose();',
      '  super.dispose();',
      '}',
      '',
      '// nearest the list: hears each one first, and lets it go on up',
      'bool _onSent(ScrollNotification notification) {',
      '  setState(() => _trace.add(_Sent(notification)));',
      '  return false;',
      '}',
      '',
      'bool _onInner(ScrollUpdateNotification notification) {',
      "  _trace.last.inner = '${stops ? 'stops' : 'heard'}';",
      '  return $stops;${stops ? ' // stops it here' : ' // lets it go on up'}',
      '}',
      '',
      'bool _onOuter($outer notification) {',
      '  final ScrollMetrics(:offset, :maxOffset) = notification.metrics;',
      '  setState(() {',
      "    _trace.last.outer = 'heard';",
      ...switch (outer) {
        'ScrollNotification' => [
          '    _heard = switch (notification) {',
          '      ScrollUpdateNotification(:final scrollDelta) =>',
          r"        'scrolled $scrollDelta to $offset of $maxOffset',",
          '      OverscrollNotification(:final overscroll) =>',
          r"        'overscrolled $overscroll at $offset of $maxOffset',",
          r"      _ => '$notification',",
          '    };',
        ],
        'ScrollUpdateNotification' => [
          _line([
            "    _heard = 'scrolled ",
            r"${notification.scrollDelta} to $offset of $maxOffset';",
          ]),
        ],
        _ => [
          '    _heard =',
          _line([
            "        'overscrolled ",
            r"${notification.overscroll} at $offset of $maxOffset';",
          ]),
        ],
      },
      '  });',
      '  return false;',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return SizedBox(',
      '    width: 50,',
      '    child: Column(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .start,',
      '      gap: 1,',
      '      children: [',
      '        Row(',
      '          crossAxisAlignment: .start,',
      '          gap: 2,',
      '          children: [',
      '            SizedBox(',
      '              width: $_nw,',
      '              height: $_nh,',
      _line([
        '              // proxy widgets: they draw nothing, ',
        'and hear what bubbles up',
      ]),
      '              child: NotificationListener<$outer>(',
      '                onNotification: _onOuter,',
      '                child: NotificationListener<ScrollUpdateNotification>(',
      '                  onNotification: _onInner,',
      '                  child: ListenableBuilder(',
      '                    listenable: _list,',
      '                    builder: (context, list) => Box(',
      '                      border: .all(',
      '                        type: .rounded,',
      _line([
        '                        style: ',
        '_list.hasFocus ? theme.primary : theme.border,',
      ]),
      '                      ),',
      '                      padding: const .x(1),',
      '                      child: list,',
      '                    ),',
      '                    child: NotificationListener<ScrollNotification>(',
      '                      onNotification: _onSent,',
      '                      child: ListView.builder(',
      '                        focusNode: _list,',
      '                        itemCount: $_items,',
      _line([
        '                        itemBuilder: ',
        r"(context, i) => Text('item ${i + 1}'),",
      ]),
      '                      ),',
      '                    ),',
      '                  ),',
      '                ),',
      '              ),',
      '            ),',
      '            Expanded(',
      _line([
        '              child: ',
        '_Trace([..._trace.reversed.take($_shown)].reversed),',
      ]),
      '            ),',
      '          ],',
      '        ),',
      '        Text.rich([',
      "          Span('heard: ', theme.muted),",
      '          switch (_heard) {',
      "            null => Span('nothing', theme.muted),",
      '            final heard => Span(heard),',
      '          },',
      '        ]),',
      '      ],',
      '    ),',
      '  );',
      '}',
      '',
      '/// The notifications sent up, newest last: their kind, how far, and',
      '/// what the inner and the outer listener did with them.',
      'final class _Trace extends StatelessWidget {',
      '  const _Trace(this.sent);',
      '',
      '  final Iterable<_Sent> sent;',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    final theme = Theme.of(context);',
      '    Style mark(String what) => switch (what) {',
      "      'heard' => theme.success,",
      "      'stops' => theme.warning,",
      '      _ => theme.muted,',
      '    };',
      r"    String signed(int n) => (n > 0 ? '+$n' : '$n').padLeft(3);",
      '    return SizedBox(',
      '      height: $_nh,',
      '      child: Column(',
      '        crossAxisAlignment: .start,',
      '        children: [',
      "          Text('             Δ  inner  outer', style: theme.muted),",
      "          if (sent.isEmpty) Text('nothing yet', style: theme.muted),",
      '          for (final s in sent)',
      '            Text.rich([',
      '              Span(switch (s.notification) {',
      '                ScrollUpdateNotification(:final scrollDelta) =>',
      r"                  'update     ${signed(scrollDelta)}',",
      '                OverscrollNotification(:final overscroll) =>',
      r"                  'overscroll ${signed(overscroll)}',",
      "                _ => '',",
      '              }),',
      r"              Span('  ${s.inner.padRight(7)}', mark(s.inner)),",
      '              Span(s.outer, mark(s.outer)),',
      '            ]),',
      '          const Spacer(),',
      '          Text.rich([',
      "            Span('inner ', theme.muted),",
      "            const Span('ScrollUpdateNotification'),",
      '          ]),',
      '          Text.rich([',
      "            Span('outer ', theme.muted),",
      "            const Span('$outer'),",
      '          ]),',
      '        ],',
      '      ),',
      '    );',
      '  }',
      '}',
    ].join('\n');
  },
);

/// What became of a notification on its way up the tree.
final class _Sent {
  _Sent(this.notification);

  final ScrollNotification notification;

  // what the inner and the outer listener did with it
  var inner = 'past';
  String? _outer;

  String get outer => _outer ?? (inner == 'stops' ? '–' : 'past');
  set outer(String what) => _outer = what;
}

/// The Code's list in its two listeners, the outer one hearing [outer]
/// (a type's name), the inner one stopping them with [stops].
final class _Bubbling extends StatefulWidget {
  const _Bubbling({required this.outer, required this.stops});

  final String outer;
  final bool stops;

  @override
  State<_Bubbling> createState() => _BubblingState();
}

final class _BubblingState extends State<_Bubbling> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;
  late final _trace = (_kept['trace'] ??= <_Sent>[]) as List<_Sent>;
  late final _controller = ScrollController(
    initialOffset: (_kept['offset'] ?? 0) as int,
  );

  // the list's, so that its box shows where the focus is
  final _list = FocusNode();

  @override
  void dispose() {
    _list.dispose();
    _controller.dispose();
    super.dispose();
  }

  String? get _heard => _kept['heard'] as String?;

  int get _serial => (_kept['serial'] ?? 0) as int;

  // nearest the list: hears each one first, and lets it go on up
  bool _onSent(ScrollNotification notification) {
    setState(() {
      _trace.add(_Sent(notification));
      if (_trace.length > 20) {
        _trace.removeAt(0);
      }
      _kept['offset'] = notification.metrics.offset;
    });
    return false;
  }

  bool _onInner(ScrollUpdateNotification notification) {
    _trace.last.inner = widget.stops ? 'stops' : 'heard';
    return widget.stops;
  }

  bool _onOuter(ScrollNotification notification) {
    final hears = switch (widget.outer) {
      'ScrollUpdateNotification' => notification is ScrollUpdateNotification,
      'OverscrollNotification' => notification is OverscrollNotification,
      _ => true,
    };
    if (!hears) {
      return false;
    }
    final ScrollMetrics(:offset, :maxOffset) = notification.metrics;
    setState(() {
      _trace.last.outer = 'heard';
      _kept
        ..['heard'] = switch (notification) {
          ScrollUpdateNotification(:final scrollDelta) =>
            'scrolled $scrollDelta to $offset of $maxOffset',
          OverscrollNotification(:final overscroll) =>
            'overscrolled $overscroll at $offset of $maxOffset',
          _ => '$notification',
        }
        ..['serial'] = _serial + 1;
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heard = _heard;
    return SizedBox(
      width: 50,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            gap: 2,
            children: [
              SizedBox(
                width: _nw,
                height: _nh,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onOuter,
                  child: NotificationListener<ScrollUpdateNotification>(
                    onNotification: _onInner,
                    child: ListenableBuilder(
                      listenable: _list,
                      builder: (context, list) => Box(
                        border: Border.all(
                          type: BorderType.rounded,
                          style: _list.hasFocus ? theme.primary : theme.border,
                        ),
                        padding: const EdgeInsets.x(1),
                        child: list,
                      ),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onSent,
                        child: ListView.builder(
                          focusNode: _list,
                          controller: _controller,
                          itemCount: _items,
                          itemBuilder: (context, i) => Text('item ${i + 1}'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _Trace(
                  [..._trace.reversed.take(_shown)].reversed,
                  outer: widget.outer,
                ),
              ),
            ],
          ),
          LitLine([
            ('heard: ', true),
            (heard ?? 'nothing', heard == null),
          ], serial: _serial),
        ],
      ),
    );
  }
}

/// The notifications sent up, newest last: their kind, how far, and what
/// the inner and the outer listener did with them.
final class _Trace extends StatelessWidget {
  const _Trace(this.sent, {required this.outer});

  final Iterable<_Sent> sent;
  final String outer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Style mark(String what) => switch (what) {
      'heard' => theme.success,
      'stops' => theme.warning,
      _ => theme.muted,
    };
    String signed(int n) => (n > 0 ? '+$n' : '$n').padLeft(3);
    return SizedBox(
      height: _nh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('             Δ  inner  outer', style: theme.muted),
          if (sent.isEmpty) Text('nothing yet', style: theme.muted),
          for (final s in sent)
            Text.rich([
              Span(switch (s.notification) {
                ScrollUpdateNotification(:final scrollDelta) =>
                  'update     ${signed(scrollDelta)}',
                OverscrollNotification(:final overscroll) =>
                  'overscroll ${signed(overscroll)}',
                _ => '',
              }),
              Span('  ${s.inner.padRight(7)}', mark(s.inner)),
              Span(s.outer, mark(s.outer)),
            ]),
          const Spacer(),
          Text.rich([
            Span('inner ', theme.muted),
            const Span('ScrollUpdateNotification'),
          ]),
          Text.rich([Span('outer ', theme.muted), Span(outer)]),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- Slot, SlotScope

/// The status bar's box.
const _sw = 44;

/// A status bar item: its name muted, then its value.
Widget _item(BuildContext context, String name, String value) =>
    Text.rich([Span('$name ', Theme.of(context).muted), Span(value)]);

/// What the plugins put in the slots named 'status', in order, the lint's
/// at [lint].
List<SlotEntry> _plugins(int lint) => [
  SlotEntry(
    slot: 'status',
    id: 'git',
    builder: (context) => _item(context, 'git', 'main'),
  ),
  SlotEntry(
    slot: 'status',
    id: 'lint',
    order: lint,
    builder: (context) => _item(context, 'lint', '0 problems'),
  ),
  SlotEntry(
    slot: 'status',
    id: 'words',
    order: 2,
    builder: (context) => _item(context, 'words', '120'),
  ),
];

final _slots = GalleryPage(
  group: 'Framework',
  title: 'Slot, SlotScope',
  options: const [
    ChoiceOption(
      'lint',
      'lint order',
      values: [-1, 1, 3],
      initial: 1,
      labels: ['-1, first', '1, between', '3, last'],
    ),
    SwitchOption('placeholder', 'placeholder', initial: true),
  ],
  build: (context, o) =>
      _Plugins(lint: o.choice('lint'), placeholder: o.flag('placeholder')),
  code: (o) => [
    '/// A status bar item: its name muted, then its value.',
    _line([
      'static Widget _item(BuildContext context, String name, ',
      'String value) =>',
    ]),
    r"    Text.rich([Span('$name ', Theme.of(context).muted), Span(value)]);",
    '',
    "/// What the plugins put in the slots named 'status', in order.",
    'static final _plugins = [',
    '  SlotEntry(',
    "    slot: 'status',",
    "    id: 'git',",
    "    builder: (context) => _item(context, 'git', 'main'),",
    '  ),',
    '  SlotEntry(',
    "    slot: 'status',",
    "    id: 'lint',",
    '    order: ${o.choice<int>('lint')},',
    "    builder: (context) => _item(context, 'lint', '0 problems'),",
    '  ),',
    '  SlotEntry(',
    "    slot: 'status',",
    "    id: 'words',",
    '    order: 2,',
    "    builder: (context) => _item(context, 'words', '120'),",
    '  ),',
    '];',
    '',
    'final _registry = SlotRegistry()',
    '  ..register(_plugins[0])',
    '  ..register(_plugins[2]);',
    '',
    'void _turn(SlotEntry plugin, {required bool on}) => setState(() {',
    '  if (on) {',
    '    _registry.register(plugin);',
    '  } else {',
    '    _registry.unregister(plugin.slot, plugin.id);',
    '  }',
    '});',
    '',
    '@override',
    'void dispose() {',
    '  _registry.dispose();',
    '  super.dispose();',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  // an InheritedWidget: the Slots below find the registry through it',
    '  return SlotScope(',
    '    registry: _registry,',
    '    child: Column(',
    '      mainAxisSize: .min,',
    '      crossAxisAlignment: .start,',
    '      gap: 1,',
    '      children: [',
    '        Row(',
    '          mainAxisSize: .min,',
    '          gap: 2,',
    '          children: [',
    '            for (final plugin in _plugins)',
    '              Checkbox(',
    "                value: _registry.entriesOf('status').contains(plugin),",
    '                onChanged: (on) => _turn(plugin, on: on),',
    '                label: plugin.id,',
    '              ),',
    '          ],',
    '        ),',
    '        SizedBox(',
    '          width: $_sw,',
    '          child: Box(',
    '            border: .all(type: .rounded, style: theme.border),',
    "            titles: const [BorderTitle(' status ')],",
    '            padding: const .x(1),',
    _line([
      "            // built again when the entries of 'status' change, ",
      'and then only',
    ]),
    '            child: Slot(',
    "              'status',",
    _line([
      '              layout: (context, children) => ',
      'Row(gap: 2, children: children),',
    ]),
    if (o.flag('placeholder'))
      _line([
        '              placeholder: ',
        "Text('no plugins', style: theme.muted),",
      ]),
    '            ),',
    '          ),',
    '        ),',
    '      ],',
    '    ),',
    '  );',
    '}',
  ].join('\n'),
);

/// The Code's registry and its Slot: a Checkbox for each plugin, which
/// registers its entry or unregisters it, the lint's at order [lint].
final class _Plugins extends StatefulWidget {
  const _Plugins({required this.lint, required this.placeholder});

  final int lint;
  final bool placeholder;

  @override
  State<_Plugins> createState() => _PluginsState();
}

final class _PluginsState extends State<_Plugins> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;

  /// The ids registered, in the order they were.
  late final _on =
      (_kept['registered'] ??= <String>['git', 'words']) as List<String>;
  late List<SlotEntry> _entries = _plugins(widget.lint);
  final _registry = SlotRegistry();

  var _registered = false;

  @override
  void didUpdateWidget(_Plugins oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lint != widget.lint) {
      _entries = _plugins(widget.lint);
      if (_on.contains('lint')) {
        // a new order: registered again, as the Code's would be built
        _registry
          ..unregister('status', 'lint')
          ..register(_entries[1]);
      }
    }
  }

  @override
  void dispose() {
    _registry.dispose();
    super.dispose();
  }

  void _turn(SlotEntry plugin, {required bool on}) => setState(() {
    if (on) {
      _registry.register(plugin);
      _on.add(plugin.id);
    } else {
      _registry.unregister(plugin.slot, plugin.id);
      _on.remove(plugin.id);
    }
  });

  @override
  Widget build(BuildContext context) {
    if (!_registered) {
      // the page's kept plugins, once its state can be read
      _registered = true;
      for (final id in _on) {
        _registry.register(_entries.firstWhere((e) => e.id == id));
      }
    }
    final theme = Theme.of(context);
    return SlotScope(
      registry: _registry,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            gap: 2,
            children: [
              for (final plugin in _entries)
                Checkbox(
                  value: _on.contains(plugin.id),
                  onChanged: (on) => _turn(plugin, on: on),
                  label: plugin.id,
                ),
            ],
          ),
          SizedBox(
            width: _sw,
            child: Box(
              border: Border.all(type: BorderType.rounded, style: theme.border),
              titles: const [BorderTitle(' status ')],
              padding: const EdgeInsets.x(1),
              child: Slot(
                'status',
                layout: (context, children) => Row(gap: 2, children: children),
                placeholder: widget.placeholder
                    ? Text('no plugins', style: theme.muted)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
