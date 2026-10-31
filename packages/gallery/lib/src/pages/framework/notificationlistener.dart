// The NotificationListener page.
part of 'framework.dart';

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
          codeLine([
            "    _heard = 'scrolled ",
            r"${notification.scrollDelta} to $offset of $maxOffset';",
          ]),
        ],
        _ => [
          '    _heard =',
          codeLine([
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
      codeLine([
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
      codeLine([
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
      codeLine([
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
      codeLine([
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

final class _BubblingState extends State<_Bubbling> with KeptState {
  late final _trace = (kept['trace'] ??= <_Sent>[]) as List<_Sent>;
  late final _controller = ScrollController(
    initialOffset: (kept['offset'] ?? 0) as int,
  );

  // the list's, so that its box shows where the focus is
  final _list = FocusNode();

  @override
  void dispose() {
    _list.dispose();
    _controller.dispose();
    super.dispose();
  }

  String? get _heard => kept['heard'] as String?;

  int get _serial => (kept['serial'] ?? 0) as int;

  // nearest the list: hears each one first, and lets it go on up
  bool _onSent(ScrollNotification notification) {
    setState(() {
      _trace.add(_Sent(notification));
      if (_trace.length > 20) {
        _trace.removeAt(0);
      }
      kept['offset'] = notification.metrics.offset;
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
      kept
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
