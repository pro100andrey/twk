// The LogView page.
part of 'scrolling.dart';

/// The LogView page's `level` option.
const _logviewLevel = ChoiceOption<String>(
  'level',
  'level',
  values: _logLevels,
);

/// The LogView page's `filter` option.
const _logviewFilter = ChoiceOption<String>(
  'filter',
  'filter',
  values: ['none', 'GET', 'slow'],
);

/// The LogView page's `query` option.
const _logviewQuery = ChoiceOption<String>(
  'query',
  'search',
  values: ['none', 'items', 'timeout'],
);

/// The LogView page's `time` option.
const _logviewTime = SwitchOption('time', 'time', initial: true);

/// The LogView page's `showLevel` option.
const _logviewShowLevel = SwitchOption(
  'showLevel',
  'show level',
  initial: true,
);

/// The LogView page's `wrap` option.
const _logviewWrap = SwitchOption('wrap', 'wrap');

/// The LogView page's `live` option.
const _logviewLive = SwitchOption('live', 'live', initial: true);

/// The LogView page's `scrollbar` option.
const _logviewScrollbar = ChoiceOption<String>(
  'scrollbar',
  'scrollbar',
  values: ['always', 'onScroll', 'never'],
);

final _logviewPage = GalleryPage(
  group: _group,
  title: 'LogView',
  options: const [
    _logviewLevel,
    _logviewFilter,
    _logviewQuery,
    _logviewTime,
    _logviewShowLevel,
    _logviewWrap,
    _logviewLive,
    _logviewScrollbar,
  ],
  build: (context, o) => _Log(
    level: LogLevel.values.byName(o(_logviewLevel)),
    filter: o(_logviewFilter) == 'none' ? '' : o(_logviewFilter),
    query: o(_logviewQuery) == 'none' ? '' : o(_logviewQuery),
    time: o(_logviewTime),
    showLevel: o(_logviewShowLevel),
    wrap: o(_logviewWrap),
    live: o(_logviewLive),
    scrollbar: ScrollbarVisibility.values.byName(o(_logviewScrollbar)),
  ),
  // the box, from the first frame: a LayoutBuilder asks for no rows
  heightIn: (o, room) => _logRows(room.height),
  codeIn: _logCode,
);

/// The LogView's box; its lines a column narrower than inside it.
const _logW = 50;

/// A line this often while live.
const _logMs = 400;

/// The lines logged before the page opens.
const _logFrom = 30;

const _logLevels = ['debug', 'info', 'warning', 'error'];

/// The box's rows in [room]: 12, or the room's where it is lower, 6 at
/// least.
int _logRows(int room) => room < 6 ? 6 : (room > 12 ? 12 : room);

/// Line [i] of the log: its level and text, as the Code's `_add` makes it.
(LogLevel, String) _logEntry(int i) => switch (i) {
  _ when i % 13 == 5 => (
    LogLevel.error,
    'POST /api/orders 500 upstream timeout after 5000 ms',
  ),
  _ when i % 7 == 3 => (
    LogLevel.warning,
    'slow query: SELECT * FROM items took ${300 + i * 29 % 900} ms',
  ),
  _ when i % 5 == 1 => (LogLevel.debug, 'cache hit items/${i * 37 % 500}'),
  _ => (
    LogLevel.info,
    'GET /api/items/${i * 37 % 500} 200 ${3 + i * 13 % 90} ms',
  ),
};

/// The LogView page's stage: a log the gallery's clock adds a line to
/// every [_logMs] while [live], kept while the gallery runs.
final class _Log extends StatefulWidget {
  const _Log({
    required this.level,
    required this.filter,
    required this.query,
    required this.time,
    required this.showLevel,
    required this.wrap,
    required this.live,
    required this.scrollbar,
  });

  final LogLevel level;
  final String filter;
  final String query;
  final bool time;
  final bool showLevel;
  final bool wrap;
  final bool live;
  final ScrollbarVisibility scrollbar;

  @override
  State<_Log> createState() => _LogState();
}

final class _LogState extends State<_Log> with MotionState {
  @override
  Widget build(BuildContext context) {
    final kept = PageControl.of(context).state;
    final log = (kept['log'] ??= LogController()) as LogController;
    motion.begin(context);
    final now = motion.now.inMilliseconds;
    // the lines logged by now: _logFrom, then one every _logMs while live;
    // the count stands while it is not
    var base = (kept['base'] ??= _logFrom) as int;
    var since = (kept['since'] ??= 0) as int;
    final was = (kept['live'] ??= widget.live) as bool;
    if (was != widget.live) {
      if (was) {
        base += (now - since) ~/ _logMs;
      }
      since = now;
      kept
        ..['base'] = base
        ..['since'] = since
        ..['live'] = widget.live;
    }
    var count = base;
    if (widget.live) {
      final k = (now - since) ~/ _logMs;
      motion.wakeAt(Duration(milliseconds: since + (k + 1) * _logMs));
      count += k;
    }
    motion.end();
    final added = (kept['added'] ??= 0) as int;
    if (count > added) {
      for (var i = added; i < count; i++) {
        final (level, text) = _logEntry(i);
        log.add(
          text,
          level: level,
          time: DateTime(2026, 10, 19, 12).add(
            Duration(milliseconds: _logMs * i),
          ),
        );
      }
      kept['added'] = count;
    }
    log
      ..level = widget.level
      ..filter = widget.filter
      ..query = widget.query;
    return LayoutBuilder(
      builder: (context, c) => _boxed(
        _logW,
        _logRows(c.maxH < BoxConstraints.unbounded ? c.maxH : 1 << 20),
        LogView(
          controller: log,
          wrap: widget.wrap,
          showTime: widget.time,
          showLevel: widget.showLevel,
          scrollbar: widget.scrollbar,
        ),
      ),
    );
  }
}

String _logCode(Options o, StageRoom room) {
  final level = o(_logviewLevel);
  final filter = o(_logviewFilter);
  final query = o(_logviewQuery);
  final live = o(_logviewLive);
  final args = [
    if (level != 'debug') 'level: .$level',
    if (filter != 'none') "filter: '$filter'",
    if (query != 'none') "query: '$query'",
  ];
  final view = [
    if (o(_logviewWrap)) 'wrap: true,',
    if (!o(_logviewTime)) 'showTime: false,',
    if (!o(_logviewShowLevel)) 'showLevel: false,',
    if (o(_logviewScrollbar) != 'always')
      'scrollbar: .${o.nameOf(_logviewScrollbar)},',
  ];
  return [
    if (args.isNotEmpty) ...[
      'final _log = LogController(',
      for (final a in args) '  $a,',
      ');',
    ] else
      'final _log = LogController();',
    if (live) ...['var _lines = $_logFrom;', 'late final Timer _timer;'],
    '',
    '@override',
    'void initState() {',
    '  super.initState();',
    '  // the lines logged before it opens',
    '  for (var i = 0; i < $_logFrom; i++) {',
    '    _add(i);',
    '  }',
    if (live) ...[
      '  // then one every $_logMs ms',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_logMs),',
      '    (_) => _add(_lines++),',
      '  );',
    ],
    '}',
    '',
    '@override',
    'void dispose() {',
    if (live) '  _timer.cancel();',
    '  _log.dispose();',
    '  super.dispose();',
    '}',
    '',
    '/// Line [i]: what it says, at what level, and when.',
    'void _add(int i) {',
    '  final (level, text) = switch (i) {',
    _logErrorLine,
    '    _ when i % 7 == 3 => (',
    '      LogLevel.warning,',
    r"      'slow query: SELECT * FROM items took ${300 + i * 29 % 900} ms',",
    '    ),',
    _logDebugLine,
    _logInfoLine,
    '  };',
    '  _log.add(',
    '    text,',
    '    level: level,',
    _logTimeLine,
    '  );',
    '}',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return SizedBox(',
    '    width: $_logW,',
    '    height: ${_logRows(room.height)},',
    ..._focusBox('    '),
    if (view.isEmpty)
      '      child: LogView(controller: _log),'
    else ...[
      '      child: LogView(',
      '        controller: _log,',
      for (final v in view) '        $v',
      '      ),',
    ],
    '    ),',
    '  );',
    '}',
  ].join('\n');
}

/// The Code's lines too long for a line of Dart.
const _logErrorLine =
    "    _ when i % 13 == 5 => (LogLevel.error, 'POST /api/orders 500 "
    "upstream timeout after 5000 ms'),";

const _logDebugLine =
    r"    _ when i % 5 == 1 => (LogLevel.debug, 'cache hit items/${i * 37 % 500}'),";

const _logInfoLine =
    r"    _ => (LogLevel.info, 'GET /api/items/${i * 37 % 500} 200 "
    r"${3 + i * 13 % 90} ms'),";

const _logTimeLine =
    '    time: DateTime(2026, 10, 19, 12).add(Duration(milliseconds: '
    '$_logMs * i)),';
