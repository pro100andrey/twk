// The Console page.
part of 'debugging.dart';

/// The stage.
const _cw = 48;

const _ch = 10;

/// A record of the traffic this often while it is live.
const _every = 700;

const List<(LogLevel, String)> _traffic = [
  (LogLevel.info, 'GET /api/items 200 in 12 ms'),
  (LogLevel.debug, 'cache hit: items?page=2'),
  (LogLevel.info, 'GET /api/user/42 200 in 8 ms'),
  (LogLevel.debug, 'pool: 3 of 8 connections busy'),
  (LogLevel.warning, 'slow query: 412 ms on orders'),
  (LogLevel.info, 'POST /api/orders 201 in 31 ms'),
  (LogLevel.debug, 'cache miss: user:42:prefs'),
  (LogLevel.error, 'upstream timed out after 5 s'),
  (LogLevel.info, 'GET /api/items 200 in 15 ms'),
  (LogLevel.warning, 'retrying upload (2 of 3)'),
];

/// The time a record logged at [ms] on the gallery's clock has: from
/// 09:05:07.042 at its start, as the design's.
DateTime _timeAt(int ms) =>
    DateTime(2026, 10, 20, 9, 5, 7, 42).add(Duration(milliseconds: ms));

/// The Console page's `level` option.
const _consoleLevel = ChoiceOption<LogLevel>(
  'level',
  'level',
  values: [LogLevel.debug, LogLevel.info, LogLevel.warning, LogLevel.error],
  labels: ['debug', 'info', 'warning', 'error'],
);

/// The Console page's `rows` option.
const _consoleRowsOption = ChoiceOption<int>(
  'rows',
  'rows',
  values: [4, 6, 8],
  initial: 6,
);

/// The Console page's `live` option.
const _consoleLive = SwitchOption(
  'live',
  'traffic',
  initial: true,
);

/// The Console page's `openOnError` option.
const _consoleOpenOnError = SwitchOption(
  'openOnError',
  'open on error',
);

final _console = GalleryPage(
  group: _group,
  title: 'Console',
  options: const [
    _consoleLevel,
    _consoleRowsOption,
    _consoleLive,
    _consoleOpenOnError,
  ],
  build: (context, o) => _Logged(
    level: o(_consoleLevel),
    rows: o(_consoleRowsOption),
    live: o(_consoleLive),
    openOnError: o(_consoleOpenOnError),
  ),
  code: (o) {
    final args = [
      if (o.nameOf(_consoleLevel) != 'debug')
        'level: .${o.nameOf(_consoleLevel)}',
      if (o(_consoleOpenOnError)) 'openOnError: true',
    ];
    final live = o(_consoleLive);
    return [
      'final _sink = LogSink();',
      if (args.isNotEmpty) ...[
        'late final _console = ConsoleController(',
        '  _sink,',
        for (final a in args) '  $a,',
        ')..open();',
      ] else
        'late final _console = ConsoleController(_sink)..open();',
      if (live) ...[
        'static const _traffic = [',
        for (final (level, message) in _traffic)
          "  (LogLevel.${level.name}, '$message'),",
        '];',
        'var _i = 0;',
        'late final Timer _timer;',
        '',
        '@override',
        'void initState() {',
        '  super.initState();',
        "  // a small server's traffic, a record every 700 ms",
        '  _timer = Timer.periodic(',
        '    const Duration(milliseconds: $_every),',
        '    (_) {',
        '      final (level, message) = _traffic[_i++ % _traffic.length];',
        '      _log(level, message);',
        '    },',
        '  );',
        '}',
      ],
      '',
      'void _log(LogLevel level, String message) =>',
      '    _sink.add(LogRecord(DateTime.now(), level, message));',
      '',
      '@override',
      'void dispose() {',
      if (live) '  _timer.cancel();',
      '  _console.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return SizedBox(',
      '    width: $_cw,',
      '    height: $_ch,',
      '    child: KeyBindings(',
      '      {',
      "        'up': _console.selectPrevious,",
      "        'down': _console.selectNext,",
      "        'end': _console.scrollToEnd,",
      '      },',
      codeLine([
        '      hints: const ',
        "{'up': 'select', 'down': 'select', 'end': 'newest'},",
      ]),
      '      child: Console(',
      '        controller: _console,',
      '        rows: ${o.nameOf(_consoleRowsOption)},',
      '        child: Column(',
      '          crossAxisAlignment: .start,',
      '          gap: 1,',
      '          children: [',
      '            Row(',
      '              gap: 1,',
      '              children: [',
      codeLine([
        '                ',
        "Button('Info', onPressed: () => _log(.info, 'all is well')),",
      ]),
      '                Button(',
      "                  'Warn',",
      "                  onPressed: () => _log(.warning, 'disk nearly full'),",
      '                ),',
      codeLine([
        '                ',
        "Button('Fail', onPressed: () => _log(.error, 'could not save')),",
      ]),
      '                ListenableBuilder(',
      '                  listenable: _console,',
      '                  builder: (context, _) => Button(',
      "                    _console.isOpen ? 'Close' : 'Open',",
      '                    onPressed: _console.toggle,',
      '                  ),',
      '                ),',
      '              ],',
      '            ),',
      "            Text('The app, under its console.', style: theme.muted),",
      '          ],',
      '        ),',
      '      ),',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The Code's app under its console, the traffic of a small server
/// arriving on the gallery's clock while [live]. The sink and the console
/// are the page's, so that they outlive a visit to another page.
final class _Logged extends StatefulWidget {
  const _Logged({
    required this.level,
    required this.rows,
    required this.live,
    required this.openOnError,
  });

  final LogLevel level;
  final int rows;
  final bool live;
  final bool openOnError;

  @override
  State<_Logged> createState() => _LoggedState();
}

final class _LoggedState extends TimedState<_Logged> {
  LogSink get _sink => (kept['sink'] ??= LogSink()) as LogSink;

  ConsoleController get _console =>
      (kept['console'] ??= ConsoleController(_sink)..open())
          as ConsoleController;

  void _log(LogLevel level, String message) =>
      _sink.add(LogRecord(_timeAt(clockNow), level, message));

  /// The traffic up to now: a record every [_every] ms, the last few
  /// already there at first.
  void _arrive() {
    if (kept['seeded'] != true) {
      kept
        ..['seeded'] = true
        ..['next'] = now - 5 * _every;
    }
    if (!widget.live) {
      kept['next'] = null;
      return;
    }
    var next = (kept['next'] ??= now + _every) as int;
    var n = (kept['n'] ?? 0) as int;
    while (next <= now) {
      final (level, message) = _trafficOf(n++);
      _sink.add(LogRecord(_timeAt(next), level, message));
      next += _every;
    }
    kept
      ..['next'] = next
      ..['n'] = n;
    wake(next);
  }

  static (LogLevel, String) _trafficOf(int n) => _traffic[n % _traffic.length];

  @override
  Widget buildTimed(BuildContext context) {
    final theme = Theme.of(context);
    final console = _console
      ..level = widget.level
      ..openOnError = widget.openOnError;
    _arrive();
    return SizedBox(
      width: _cw,
      height: _ch,
      child: KeyBindings(
        {
          'up': console.selectPrevious,
          'down': console.selectNext,
          'end': console.scrollToEnd,
        },
        hints: const {'up': 'select', 'down': 'select', 'end': 'newest'},
        child: Console(
          controller: console,
          rows: widget.rows,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            gap: 1,
            children: [
              Row(
                gap: 1,
                children: [
                  Button(
                    'Info',
                    onPressed: () => _log(LogLevel.info, 'all is well'),
                  ),
                  Button(
                    'Warn',
                    onPressed: () => _log(LogLevel.warning, 'disk nearly full'),
                  ),
                  Button(
                    'Fail',
                    onPressed: () => _log(LogLevel.error, 'could not save'),
                  ),
                  ListenableBuilder(
                    listenable: console,
                    builder: (context, _) => Button(
                      console.isOpen ? 'Close' : 'Open',
                      onPressed: console.toggle,
                    ),
                  ),
                ],
              ),
              Text('The app, under its console.', style: theme.muted),
            ],
          ),
        ),
      ),
    );
  }
}
