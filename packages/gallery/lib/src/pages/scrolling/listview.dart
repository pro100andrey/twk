// The ListView page.
part of 'scrolling.dart';

/// The ListView page's `items` option.
const _listviewItems = ChoiceOption<Object>(
  'items',
  'items',
  values: [100, 10000, 1000000, 'growing', 'chat', 'feed'],
  labels: ['100', '10 000', '1 000 000', 'growing', 'chat', 'feed'],
);

/// The ListView page's `heights` option.
final _listviewHeights = ChoiceOption<String>(
  'heights',
  'heights',
  values: const ['one row', 'different'],
  disabled: (o) => o(_listviewItems) == 'chat' || o(_listviewItems) == 'feed',
);

/// The ListView page's `separated` option.
const _listviewSeparated = SwitchOption('separated', 'separated');

/// The ListView page's `stick` option.
final _listviewStick = ChoiceOption<String>(
  'stick',
  'stuck by',
  values: const ['stickToBottom', 'stickToEnd'],
  disabled: (o) => o(_listviewItems) != 'growing',
);

final _listviewPage = GalleryPage(
  group: _group,
  title: 'ListView',
  options: [
    _listviewItems,
    _listviewHeights,
    _listviewSeparated,
    // what keeps the log at its end: the list, or its controller
    _listviewStick,
  ],
  build: (context, o) {
    final items = o(_listviewItems);
    final chat = items == 'chat';
    final feed = items == 'feed';
    final different = !chat && !feed && o(_listviewHeights) == 'different';
    final separated = o(_listviewSeparated);
    final byEnd = items == 'growing' && o(_listviewStick) == 'stickToEnd';
    return _List(
      key: ValueKey('$items/$different/$separated/$byEnd'),
      count: items is int ? items : null,
      chat: chat,
      feed: feed,
      different: different,
      separated: separated,
      stickToEnd: byEnd,
    );
  },
  code: _listCode,
);

/// The ListView's box: a window of six rows.
const _listH = 8;

/// A line of the log this often.
const _growMs = 600;

/// The lines the log starts with.
const _growFrom = 12;

/// The item a button scrolls into view.
const _show = 40;

const _showLine =
    "          Button('item $_show', onPressed: () => "
    '_list.ensureIndexVisible(${_show - 1})),';

const _middleLine =
    "          Button('middle', onPressed: () => "
    '_list.jumpToIndex(_count ~/ 2)),';

/// The time of line [i] of the log: a line every 0.6 s from noon.
String _clock(int i) {
  final t = 12 * 3600 + i * _growMs ~/ 1000;
  String two(int v) => '$v'.padLeft(2, '0');
  return '${two(t ~/ 3600)}:${two(t ~/ 60 % 60)}:${two(t % 60)}';
}

/// The answer to line [i]: mostly 200.
Span _status(int i) => switch ((i % 11, i % 17)) {
  (7, _) => '404'.fg(Color.yellow),
  (_, 5) => '500'.fg(Color.red),
  _ => '200'.fg(Color.green),
};

/// Why line [i] failed; null for a 200.
String? _reason(int i) => switch ((i % 11, i % 17)) {
  (7, _) => 'not found',
  (_, 5) => 'server error',
  _ => null,
};

/// The rows of item [i] of the list of different heights: one to four.
int _itemRows(int i) => 1 + i * 7 % 9 % 4;

/// The chat: who says what, a message every [_growMs], the newest item 0.
const _said = [
  'you: is the build green?',
  'twk: 412 tests, all passed',
  'you: and the bench?',
  'twk: no scenario slower',
  'you: then tag it',
  'twk: tagged 0.4.0',
  'you: the changelog?',
  'twk: written, 9 entries',
];

/// Message [k]: its number and who says what.
String _message(int k) => '${'${k + 1}'.padLeft(3)} ${_said[k % _said.length]}';

/// A list of [count] items, or of a log that grows ([count] null), of
/// one row each or [different] heights, or a [chat] that grows at its
/// bottom; [separated] by lines; and the buttons that move it.
final class _List extends StatefulWidget {
  const _List({
    required this.count,
    required this.chat,
    required this.feed,
    required this.different,
    required this.separated,
    required this.stickToEnd,
    super.key,
  });

  final int? count;
  final bool chat;
  final bool feed;
  final bool different;
  final bool separated;
  final bool stickToEnd;

  @override
  State<_List> createState() => _ListState();
}

final class _ListState extends State<_List> with MotionState {
  late final _list = ListController(stickToEnd: widget.stickToEnd);
  Duration? _grownFrom;

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  /// The lines of the log now: one every [_growMs] on the gallery's clock
  /// from when it was chosen.
  int _grown() {
    final from = _grownFrom ??= motion.now;
    final k = (motion.now - from).inMilliseconds ~/ _growMs;
    motion.wakeAt(from + Duration(milliseconds: (k + 1) * _growMs));
    return _growFrom + k;
  }

  Widget _item(BuildContext context, int i, int count) {
    final theme = Theme.of(context);
    if (widget.chat) {
      return Text(_message(count - 1 - i));
    }
    if (widget.feed) {
      return Text(_message(count - 1 - i), key: ValueKey(count - 1 - i));
    }
    if (widget.count == null) {
      return Text.rich([
        _clock(i).dim,
        Span("  GET /items/${'${i + 1}'.padRight(4)}  "),
        _status(i),
        if (widget.different)
          if (_reason(i) case final reason?) Span('\n│ $reason', theme.muted),
      ]);
    }
    if (!widget.different) {
      return Text('item ${i + 1}');
    }
    return Text.rich([
      Span('item ${i + 1}'),
      for (var row = 2; row <= _itemRows(i); row++)
        Span('\n│ row $row of ${_itemRows(i)}', theme.muted),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final count = widget.count ?? _grown();
    motion.end();
    final chat = widget.chat;
    Widget item(BuildContext context, int i) => _item(context, i, count);
    final sticks =
        widget.count == null && !chat && !widget.feed && !widget.stickToEnd;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        _boxed(
          _boxW,
          _listH,
          widget.separated
              ? ListView.separated(
                  itemCount: count,
                  controller: _list,
                  stickToBottom: sticks,
                  reverse: chat,
                  itemBuilder: item,
                  separatorBuilder: (context, i) =>
                      Divider(style: Theme.of(context).border),
                )
              : ListView.builder(
                  itemCount: count,
                  controller: _list,
                  stickToBottom: sticks,
                  reverse: chat,
                  itemBuilder: item,
                ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 1,
          children: chat || widget.feed
              ? [
                  Button('newest', onPressed: () => _list.jumpTo(0)),
                  Button(
                    'oldest',
                    onPressed: () => _list.ensureIndexVisible(count - 1),
                  ),
                  Button(
                    'middle',
                    onPressed: () => _list.jumpToIndex(count ~/ 2),
                  ),
                ]
              : [
                  Button('top', onPressed: () => _list.jumpTo(0)),
                  Button(
                    'item $_show',
                    onPressed: () => _list.ensureIndexVisible(_show - 1),
                  ),
                  Button(
                    'middle',
                    onPressed: () => _list.jumpToIndex(count ~/ 2),
                  ),
                ],
        ),
        _offsetLine(_list),
      ],
    );
  }
}

String _listCode(Options o) {
  final chat = o(_listviewItems) == 'chat';
  final feed = o(_listviewItems) == 'feed';
  final growing = o(_listviewItems) == 'growing';
  final grows = growing || chat || feed;
  final different = !chat && !feed && o(_listviewHeights) == 'different';
  final separated = o(_listviewSeparated);
  final byEnd = growing && o(_listviewStick) == 'stickToEnd';
  final item = feed
      ? [
          '            // keyed by the message, as its index is not: scrolled down,',
          '            // what the window shows stays on its rows as messages come',
          '            itemBuilder: (context, i) => Text(',
          '              _message(_count - 1 - i),',
          '              key: ValueKey(_count - 1 - i),',
          '            ),',
        ]
      : chat
      ? [_chatItemLine]
      : growing
      ? [
          '            itemBuilder: (context, i) => Text.rich([',
          '              _clock(i).dim,',
          r'''              Span("  GET /items/${'${i + 1}'.padRight(4)}  "),''',
          '              _status(i),',
          if (different) ...[
            '              // a request that failed: why, on a row of its own',
            '              if (_reason(i) case final reason?)',
            r"                Span('\n│ $reason', theme.muted),",
          ],
          '            ]),',
        ]
      : different
      ? [
          '            // an item of one to four rows',
          '            itemBuilder: (context, i) => Text.rich([',
          r"              Span('item ${i + 1}'),",
          '              for (var row = 2; row <= _rows(i); row++)',
          r"                Span('\n│ row $row of ${_rows(i)}', theme.muted),",
          '            ]),',
        ]
      : [r"            itemBuilder: (context, i) => Text('item ${i + 1}'),"];
  final buttons = chat || feed
      ? [
          "          Button('newest', onPressed: () => _list.jumpTo(0)),",
          '          // the least move that shows it',
          _oldestLine,
          if (feed)
            '          // at the top, built or not'
          else
            '          // at the bottom, the edge a reverse list reads from',
          _middleLine,
        ]
      : [
          "          Button('top', onPressed: () => _list.jumpTo(0)),",
          '          // the least move that shows it',
          _showLine,
          '          // at the top, built or not: where the estimate puts it',
          _middleLine,
        ];
  return [
    if (grows) ...[
      'var _count = $_growFrom;',
      '',
      if (chat)
        '// a message every $_growMs ms, the newest item 0 at the bottom'
      else if (feed)
        '// a message every $_growMs ms, the newest item 0 at the top'
      else
        '// a line of the log every $_growMs ms',
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_growMs),',
      '    (_) => setState(() => _count++),',
      '  );',
      '}',
      '',
    ] else ...[
      'const _count = ${o(_listviewItems)};',
      '',
    ],
    if (byEnd)
      'final _list = ListController(stickToEnd: true);'
    else
      'final _list = ListController();',
    '',
    '@override',
    'void dispose() {',
    if (grows) '  _timer.cancel();',
    '  _list.dispose();',
    '  super.dispose();',
    '}',
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
    '        width: $_boxW,',
    '        height: $_listH,',
    ..._focusBox('        '),
    '          child: ListView.${separated ? 'separated' : 'builder'}(',
    '            itemCount: _count,',
    '            controller: _list,',
    if (growing && !byEnd) '            stickToBottom: true,',
    if (chat) '            reverse: true,',
    ...item,
    if (separated) _separatorLine,
    '          ),',
    '        ),',
    '      ),',
    '      Row(',
    '        mainAxisSize: .min,',
    '        gap: 1,',
    '        children: [',
    ...buttons,
    '        ],',
    '      ),',
    ..._offsetCode('_list'),
    '    ],',
    '  );',
    '}',
    if (chat || feed) ...[
      '',
      '/// Message [k]: its number and who says what.',
      _messageLine,
      '',
      'const _said = [',
      for (final m in _said) "  '$m',",
      '];',
    ] else if (growing) ...[
      '',
      '/// The time of line [i]: a line every 0.6 s from noon.',
      'String _clock(int i) {',
      '  final t = 12 * 3600 + i * $_growMs ~/ 1000;',
      r"  String two(int v) => '$v'.padLeft(2, '0');",
      r"  return '${two(t ~/ 3600)}:${two(t ~/ 60 % 60)}:${two(t % 60)}';",
      '}',
      '',
      '/// The answer to line [i]: mostly 200.',
      'Span _status(int i) => switch ((i % 11, i % 17)) {',
      "  (7, _) => '404'.fg(.yellow),",
      "  (_, 5) => '500'.fg(.red),",
      "  _ => '200'.fg(.green),",
      '};',
      if (different) ...[
        '',
        '/// Why line [i] failed; null for a 200.',
        'String? _reason(int i) => switch ((i % 11, i % 17)) {',
        "  (7, _) => 'not found',",
        "  (_, 5) => 'server error',",
        '  _ => null,',
        '};',
      ],
    ] else if (different) ...[
      '',
      '/// The rows of item [i]: one to four.',
      'int _rows(int i) => 1 + i * 7 % 9 % 4;',
    ],
  ].join('\n');
}

/// The ListView Code's lines too long for a line of Dart.
const _oldestLine =
    "          Button('oldest', onPressed: () => "
    '_list.ensureIndexVisible(_count - 1)),';

const _chatItemLine =
    '            itemBuilder: (context, i) => '
    'Text(_message(_count - 1 - i)),';

const _separatorLine =
    '            separatorBuilder: (context, i) => '
    'Divider(style: theme.border),';

const _messageLine =
    r"String _message(int k) => '${'${k + 1}'.padLeft(3)} "
    r"${_said[k % _said.length]}';";
