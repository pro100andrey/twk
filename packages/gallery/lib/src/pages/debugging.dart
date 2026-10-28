// The Debugging group of the gallery.
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';
import '../paint.dart';
import '../shell/tokens.dart';

/// The pages of the Debugging group that draw.
final List<GalleryPage> debuggingPages = [
  _console,
  _frameOverlay,
  _repaintRainbow,
  _repaintBoundary,
];

/// [parts] as one line of the Code, a line too long for this file.
String _line(List<String> parts) => parts.join();

/// A State that builds with a [Motion] begun on the gallery's clock, and
/// the page's kept state.
abstract base class _TimedState<W extends StatefulWidget> extends State<W> {
  late final motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });
  late final Map<String, Object?> kept = PageControl.of(context).state;

  /// The time of this build, in ms.
  int get now => motion.now.inMilliseconds;

  /// The time on the gallery's clock, in ms, outside a build.
  int get clockNow => Clock.of(context).now(context).inMilliseconds;

  /// A build at [at] ms on the gallery's clock.
  void wake(int at) => motion.wakeAt(Duration(milliseconds: at));

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  Widget buildTimed(BuildContext context);

  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final built = buildTimed(context);
    motion.end();
    return built;
  }
}

// ------------------------------------------------------------ Console

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

final _console = GalleryPage(
  group: 'Debugging',
  title: 'Console',
  options: const [
    ChoiceOption(
      'level',
      'level',
      values: [LogLevel.debug, LogLevel.info, LogLevel.warning, LogLevel.error],
      labels: ['debug', 'info', 'warning', 'error'],
    ),
    ChoiceOption('rows', 'rows', values: [4, 6, 8], initial: 6),
    SwitchOption('live', 'traffic', initial: true),
    SwitchOption('openOnError', 'open on error'),
  ],
  build: (context, o) => _Logged(
    level: o.choice('level'),
    rows: o.choice('rows'),
    live: o.flag('live'),
    openOnError: o.flag('openOnError'),
  ),
  code: (o) {
    final args = [
      if (o.label('level') != 'debug') 'level: .${o.label('level')}',
      if (o.flag('openOnError')) 'openOnError: true',
    ];
    final live = o.flag('live');
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
      _line([
        '      hints: const ',
        "{'up': 'select', 'down': 'select', 'end': 'newest'},",
      ]),
      '      child: Console(',
      '        controller: _console,',
      '        rows: ${o.label('rows')},',
      '        child: Column(',
      '          crossAxisAlignment: .start,',
      '          gap: 1,',
      '          children: [',
      '            Row(',
      '              gap: 1,',
      '              children: [',
      _line([
        '                ',
        "Button('Info', onPressed: () => _log(.info, 'all is well')),",
      ]),
      '                Button(',
      "                  'Warn',",
      "                  onPressed: () => _log(.warning, 'disk nearly full'),",
      '                ),',
      _line([
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

final class _LoggedState extends _TimedState<_Logged> {
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

// ============================================================ the debug aids

// The app both pages run, the Code's Sync: a spinner stepping each 80 ms,
// a bar a step each 300 ms, a sparkline a sample each second; space
// pauses the copy, the spinner then gone. Its terminal is the stage, 56
// by 14 where there is room. The binding's aids act on the whole app, the
// gallery's too, so the pages draw them over the Sync as twk does: what
// each frame repaints and lays out, and what the frame overlay counts,
// worked out frame by frame from what runs of the Code's app showed.

const _aw = 56;
const _ah = 14;
const _spinMs = 80;
const _copyMs = 300;
const _sampleMs = 1000;
const _loads = <double>[3, 5, 4, 6, 8, 7, 5, 6, 9, 7, 4, 5];
const _barX = 6;
const _barW = 16;

/// PipelineOwner's tints: twelve hues round the colour wheel; how much of
/// one a repaint's cells take, and an outline's.
const _tints = [
  0xff0000, 0xff8000, 0xffff00, 0x80ff00, 0x00ff00, 0x00ff80, //
  0x00ffff, 0x0080ff, 0x0000ff, 0x8000ff, 0xff00ff, 0xff0080,
];
const double _rainbow = 0x50 / 255;
const double _outline = 0xa0 / 255;

/// RenderFrameOverlay: 31 columns, a header, the columns' names, a row a
/// number, the last frame's ending at column 21, the median at 29.
const _panelW = 31;
const _panelH = 12;
const _metrics = [
  'build µs',
  'layout µs',
  'paint µs',
  'present µs',
  'bytes',
  'cells written',
  'cells compared',
  'rows scrolled',
  'repaints',
  'rebuilds',
];

/// FrameOverlay.refreshGap.
const _refreshGap = 250;

/// The binding's console, rows tall, and RenderKeyHint's commands.
const _consoleRows = 10;
const _commands = [
  ('o', 'overlay'),
  ('r', 'rainbow'),
  ('c', 'console'),
  ('l', 'relayout'),
  ('f', 'level'),
  ('y', 'copy'),
  ('s', 'save'),
  ('h', 'reload'),
  ('H', 'restart'),
  ('ctrl+g', 'to the app'),
];

/// A rectangle: x, y, w, h.
typedef _Rect = (int, int, int, int);

/// What a frame of each kind measured, in the order of [_metrics], in runs
/// of the Code's app at 56 × 14 (a frame's cells compared: [w], [h] the
/// terminal's); the times vary from frame to frame around these.
List<int> _measured(String kind, int w, int h) => switch (kind) {
  'first' => [117, 92, 121, 17, 140, 32, w * h, 0, 4, 13],
  'spin' => [24, 1, 9, 8, 6, 1, 1, 0, 1, 0],
  'copy' => [58, 1, 7, 9, 14, 1, 16, 0, 1, 6],
  'sample' => [51, 1, 8, 14, 59, 14, 16, 0, 1, 6],
  'pause' => [40, 6, 15, 10, 22, 9, w, 0, 1, 6],
  'hint' => [21, 3, 14, 12, 150, 51, w, 0, 1, 0],
  _ => [30, 2, 40, 14, 60, 40, w * 2, 0, 1, 0],
};

/// A frame's numbers of [kinds] together, the times jittered by the
/// frame's [serial].
List<int> _numbers(List<String> kinds, int serial, int w, int h) {
  final parts = [for (final k in kinds) _measured(k, w, h)];
  final out = [...parts[0]];
  for (final q in parts.skip(1)) {
    out[0] = math.max(out[0], q[0]) + 6;
    out[1] = math.max(out[1], q[1]);
    out[2] += q[2];
    out[3] = math.max(out[3], q[3]) + 3;
    for (var i = 4; i < 9; i++) {
      out[i] += q[i];
    }
    out[9] = math.max(out[9], q[9]);
  }
  for (var i = 0; i < 4; i++) {
    final r = math.sin(serial * 12.9898 + i * 78.233) * 43758.5453;
    out[i] = (out[i] * (0.8 + 0.4 * (r - r.floorToDouble()))).round();
  }
  return out;
}

/// The render objects of the app at [w] × [h] that a frame lays out: all
/// of them at first, the first row's when the copy pauses or goes on.
List<_Rect> _laidOut(String kind, int w, int h, {required bool paused}) {
  final column = (1, 1, w - 2, h - 2);
  final row1 = (1, 1, w - 2, 1);
  final first = paused
      ? const [(1, 1, 6, 1)]
      : const [(1, 1, 1, 1), (3, 1, 7, 1)];
  if (kind == 'pause') {
    return [column, row1, ...first];
  }
  return [
    (0, 0, w, h),
    (0, 0, w, h),
    column,
    row1,
    ...first,
    (1, 3, w - 2, 1),
    (1, 3, 4, 1),
    (_barX, 3, _barW, 1),
    (_barX, 3, _barW, 1),
    (1, 5, w - 2, 1),
    (1, 5, 4, 1),
    (_barX, 5, _barW, 1),
    (_barX, 5, _barW, 1),
  ];
}

/// The panels' rectangles in the app's terminal.
_Rect _panelRect(int w, int h) => (
  math.max(0, w - _panelW),
  0,
  math.min(w, _panelW),
  math.min(h, _panelH),
);
_Rect _consoleRect(int w, int h) => (
  0,
  math.max(0, h - _consoleRows),
  w,
  math.min(h, _consoleRows),
);
_Rect _hintRect(int w, int h) => (0, h - 1, w, 1);

/// A cell of the app's terminal: the tint it was last repainted with, the
/// outline's and how many outlines it took since.
final class _Cell {
  var r = -1;
  var o = -1;
  var n = 0;
}

/// What the frame overlay shows: the frames written in the last second,
/// the last frame's numbers and the median of those counted.
typedef _Display = (int fps, List<int>? last, List<int>? median);

/// The app and the binding's debug aids, from when the app started (u =
/// 0) to [u], frame by frame: what each cell's background was last
/// painted with (a repaint's tint, an outline's), and what the frame
/// overlay counted and shows.
final class _AidsApp {
  _AidsApp(this.aids);

  var u = -1;
  var paused = false;
  var done = 0;
  final Map<String, bool> aids;
  var console = false;
  var prefix = false;
  final List<_Cell> cells = [for (var i = 0; i < _aw * _ah; i++) _Cell()];
  var rainbowAt = 0;
  var relayoutAt = 0;
  int? outlinedIn;
  // the overlay: its frames, those written, when it last showed new
  // numbers, whether it counted one since, the refresh that waits, the
  // frame that paints it, what it shows, and how many frames ran
  var meter = <List<int>>[];
  var written = <int>[];
  int? shown;
  var stale = false;
  int? due;
  int? panelAt;
  _Display? display;
  var panel = false;
  List<int>? last;
  var serial = 0;

  bool aid(String k) => aids[k] ?? false;

  /// Paints [rect] of the app's cells anew, tinted when the rainbow is on,
  /// then outlines in it the objects [laid] out since.
  void paint(_Rect rect, List<_Rect> laid, int w, int h) {
    final (x0, y0, rw, rh) = rect;
    final x1 = math.min(w, x0 + rw);
    final y1 = math.min(h, y0 + rh);
    final r = aid('rainbow') ? rainbowAt : -1;
    if (aid('rainbow')) {
      rainbowAt = (rainbowAt + 1) % _tints.length;
    }
    for (var y = y0; y < y1; y++) {
      for (var x = math.max(0, x0); x < x1; x++) {
        cells[y * _aw + x]
          ..r = r
          ..o = -1
          ..n = 0;
      }
    }
    if (!aid('relayout') || laid.isEmpty) {
      return;
    }
    if (outlinedIn != serial) {
      outlinedIn = serial;
      relayoutAt = (relayoutAt + 5) % _tints.length;
    }
    void mark(int x, int y) {
      if (x < x0 || x >= x1 || y < y0 || y >= y1) {
        return;
      }
      cells[y * _aw + x]
        ..o = relayoutAt
        ..n += 1;
    }

    for (final (ox, oy, ow, oh) in laid) {
      for (var x = ox; x < ox + ow; x++) {
        mark(x, oy);
        if (oh > 1) {
          mark(x, oy + oh - 1);
        }
      }
      for (var y = oy + 1; y < oy + oh - 1; y++) {
        if (ow <= 2) {
          for (var x = ox; x < ox + ow; x++) {
            mark(x, y);
          }
        } else {
          mark(ox, y);
          mark(ox + ow - 1, y);
        }
      }
    }
  }

  /// The frame overlay shows the numbers counted until [at]
  /// (FrameOverlay.refresh), and paints them in the frame after.
  void refresh(int at, int now) {
    shown = at;
    stale = false;
    written = [
      for (final x in written)
        if (x > at - 1000) x,
    ];
    final k = meter.length;
    display = (
      written.length,
      k > 0 ? meter[k - 1] : null,
      k > 0
          ? [
              for (var i = 0; i < _metrics.length; i++)
                ([for (final m in meter) m[i]]..sort())[k >> 1],
            ]
          : null,
    );
    panelAt = now;
  }

  /// What the overlay does after a frame at [now]
  /// (FrameOverlay._schedule): new numbers now, or when 250 ms have gone
  /// since the last ones; once more a second after the last frame written.
  void schedule(int now) {
    final s = shown;
    if (stale) {
      if (s == null || now - s >= _refreshGap) {
        refresh(now, now + 17);
        due = null;
      } else {
        due = s + _refreshGap;
      }
      return;
    }
    final last = written.isEmpty ? null : written.last;
    due = last == null || s == null || s >= last + 1000 ? null : last + 1000;
  }

  /// A frame at [e] of the app's [kinds] of work (none for one that paints
  /// the binding's panels alone): [root] repaints all of it, else each of
  /// [rects] on its own; [laid], what it laid out.
  void frame(
    int e,
    int w,
    int h, {
    bool root = false,
    List<_Rect> laid = const [],
    List<String> kinds = const [],
    List<_Rect> rects = const [],
    List<_Rect> laidRects = const [],
    bool laidPanel = false,
  }) {
    serial++;
    final at = panelAt;
    final repaintPanel = at != null && at <= e;
    if (repaintPanel) {
      panelAt = null;
    }
    // what repaints, the outermost first: the root covers everything
    if (root) {
      paint((0, 0, w, h), laid, w, h);
    } else {
      if (repaintPanel && panel) {
        paint(
          _panelRect(w, h),
          laidPanel ? [_panelRect(w, h)] : const [],
          w,
          h,
        );
      }
      for (final rect in rects) {
        paint(rect, laidRects, w, h);
      }
    }
    if (kinds.isEmpty) {
      if (panel && repaintPanel) {
        schedule(e);
      }
      return;
    }
    final nums = _numbers(kinds, serial, w, h);
    last = nums;
    if (!panel) {
      return;
    }
    if (repaintPanel) {
      // the panel showed new numbers in it: not counted
      written.add(e);
      schedule(e);
      return;
    }
    meter.add(nums);
    if (meter.length > 128) {
      meter.removeAt(0);
    }
    stale = true;
    written.add(e);
    schedule(e);
  }

  /// Turns the overlay on or off in a frame at [e]: shown, it is laid out
  /// and painted on its own, the last frame's numbers in it; hidden, what
  /// was under it repaints, the root here. With [root] the frame repaints
  /// everything anyway.
  void setOverlay(bool on, int e, int w, int h, {required bool root}) {
    aids['overlay'] = on;
    if (on == panel) {
      if (root) {
        frame(e, w, h, root: true);
      }
      return;
    }
    panel = on;
    meter = [];
    written = [];
    shown = null;
    stale = false;
    due = null;
    display = null;
    panelAt = null;
    if (on) {
      final l = last;
      if (l != null) {
        meter.add(l);
      }
      refresh(e, e);
      if (root) {
        frame(e, w, h, root: true, laid: [_panelRect(w, h)]);
      } else {
        frame(e, w, h, laidPanel: true);
      }
    } else {
      frame(e, w, h, root: true);
    }
  }

  /// Turns aid [k] on or off at [e]: the rainbow and the relayout
  /// highlight repaint everything, the latter outlining nothing laid out
  /// before.
  void setAid(String k, bool on, int e, int w, int h, {required bool root}) {
    if (k == 'overlay') {
      setOverlay(on, e, w, h, root: root);
      return;
    }
    aids[k] = on;
    frame(e, w, h, root: true);
  }

  /// Runs the app on to [to]: the steps of its timers, the overlay's
  /// refreshes, in order of time.
  void advance(int to, int w, int h) {
    if (u < 0) {
      // the first frame lays out and paints everything; the overlay, on
      // from the start, shows its numbers in the frame after
      u = 0;
      frame(
        0,
        w,
        h,
        root: true,
        laid: _laidOut('first', w, h, paused: false),
        kinds: const ['first'],
      );
      if (aid('overlay')) {
        aids['overlay'] = false;
        setOverlay(true, 0, w, h, root: false);
      }
    }
    int next(int period, int from) => (from ~/ period + 1) * period;
    const never = 1 << 62;
    for (;;) {
      final from = u;
      final spin = paused ? never : next(_spinMs, from);
      final copy = next(_copyMs, from);
      final sample = next(_sampleMs, from);
      final e = [
        spin,
        copy,
        sample,
        due ?? never,
        panelAt ?? never,
      ].reduce(math.min);
      if (e > to) {
        break;
      }
      u = e;
      if (due == e) {
        due = null;
        refresh(e, e);
      }
      final kinds = <String>[];
      final rects = <_Rect>[];
      if (spin == e) {
        kinds.add('spin');
        rects.add((1, 1, 1, 1));
      }
      if (copy == e && !paused) {
        done = (done + 1) % 101;
        kinds.add('copy');
        rects.add((_barX, 3, _barW, 1));
      }
      if (sample == e) {
        kinds.add('sample');
        rects.add((_barX, 5, _barW, 1));
      }
      frame(e, w, h, kinds: kinds, rects: rects);
    }
    u = math.max(u, to);
  }

  /// When it next changes, from [u]: its timers, the overlay's refresh.
  int nextAt() => [
    (u ~/ _copyMs + 1) * _copyMs,
    (u ~/ _sampleMs + 1) * _sampleMs,
    ?due,
    ?panelAt,
    if (!paused) (u ~/ _spinMs + 1) * _spinMs,
  ].reduce(math.min);
}

/// A page of the app with the debug aids its [aids] (switch options:
/// key, label, initial) turn on.
GalleryPage _aidsPage(String title, List<(String, String, bool)> aids) =>
    GalleryPage(
      group: 'Debugging',
      title: title,
      options: [
        for (final (key, label, initial) in aids)
          SwitchOption(key, label, initial: initial),
      ],
      build: (context, o) => _Aids(
        aids: {for (final (key, _, _) in aids) key: o.flag(key)},
      ),
      code: (o) => _syncCode(o, title),
      codeInTerminalColors: true,
    );

final GalleryPage _frameOverlay = _aidsPage('FrameOverlay', const [
  ('overlay', 'overlay', true),
]);

final GalleryPage _repaintRainbow = _aidsPage('Repaint rainbow', const [
  ('rainbow', 'rainbow', true),
  ('relayout', 'relayout highlight', false),
]);

/// The Code of the pages: the app, the debug aids on as an app turns
/// them on.
String _syncCode(Options o, String title) {
  final overlay = title == 'FrameOverlay';
  final on = overlay
      ? [if (o.flag('overlay')) 'overlay']
      : [if (o.flag('rainbow')) 'rainbow', if (o.flag('relayout')) 'relayout'];
  final how = overlay
      ? [
          '    // the debug keys, Ctrl+G then o showing and hiding the frame',
          '    // overlay',
        ]
      : [
          _line([
            '    // the debug keys, Ctrl+G then r ',
            'turning the rainbow on and off,',
          ]),
          '    // and l the relayout highlight',
        ];
  return [
    "import 'dart:async';",
    '',
    "import 'package:twk/twk.dart';",
    '',
    if (on.isNotEmpty)
      '// TWK_DEBUG=${on.join(',')} turns '
          '${on.length > 1 ? 'them' : 'it'} on in any app as well'
    else
      '// TWK_DEBUG=keys gives any app the debug keys as well',
    'void main() => runApp(const Sync());',
    '',
    _line([
      '/// A small app whose parts change at rates of their own: ',
      'the spinner each',
    ]),
    '/// 80 ms, the bar each 300 ms, the sparkline each second. Space pauses',
    '/// the copy.',
    'final class Sync extends StatefulWidget {',
    '  const Sync({super.key});',
    '',
    '  @override',
    '  State<Sync> createState() => _SyncState();',
    '}',
    '',
    'final class _SyncState extends State<Sync> {',
    _line([
      '  static const _loads = <double>[',
      "${_loads.map((v) => v.round()).join(', ')}];",
    ]),
    '',
    '  var _done = 0;',
    '  var _samples = 0;',
    '  var _paused = false;',
    '  late final Timer _copy;',
    '  late final Timer _sample;',
    '',
    '  @override',
    '  void initState() {',
    '    super.initState();',
    ...how,
    if (on.isNotEmpty) ...[
      '    AppBinding.of(context).debug',
      '      ..keys = true',
      for (var i = 0; i < on.length; i++)
        '      ..${on[i]} = true${i == on.length - 1 ? ';' : ''}',
    ] else
      '    AppBinding.of(context).debug.keys = true;',
    _line([
      '    _copy = Timer.periodic(',
      'const Duration(milliseconds: $_copyMs), (_) {',
    ]),
    '      if (!_paused) {',
    '        setState(() => _done = (_done + 1) % 101);',
    '      }',
    '    });',
    '    _sample = Timer.periodic(',
    '      const Duration(seconds: 1),',
    '      (_) => setState(() => _samples++),',
    '    );',
    '  }',
    '',
    '  @override',
    '  void dispose() {',
    '    _copy.cancel();',
    '    _sample.cancel();',
    '    super.dispose();',
    '  }',
    '',
    '  @override',
    '  Widget build(BuildContext context) {',
    '    final theme = Theme.of(context);',
    '    return KeyBindings(',
    "      {'space': () => setState(() => _paused = !_paused)},",
    "      hints: const {'space': 'pause'},",
    '      child: Padding(',
    '        padding: const .all(1),',
    '        child: Column(',
    '          crossAxisAlignment: .start,',
    '          gap: 1,',
    '          children: [',
    '            Row(',
    '              gap: 1,',
    '              children: [',
    '                if (!_paused) const Spinner(),',
    "                Text(_paused ? 'paused' : 'syncing'),",
    '              ],',
    '            ),',
    '            Row(',
    '              gap: 1,',
    '              children: [',
    "                Text('copy', style: theme.muted),",
    _line([
      '                SizedBox(width: $_barW, ',
      'child: ProgressBar(value: _done / 100)),',
    ]),
    '              ],',
    '            ),',
    '            Row(',
    '              gap: 1,',
    '              children: [',
    "                Text('load', style: theme.muted),",
    '                SizedBox(',
    '                  width: $_barW,',
    '                  child: Sparkline(',
    '                    data: [',
    '                      for (var i = 0; i < $_barW; i++)',
    '                        _loads[(_samples + i) % _loads.length],',
    '                    ],',
    '                    style: theme.info,',
    '                  ),',
    '                ),',
    '              ],',
    '            ),',
    '          ],',
    '        ),',
    '      ),',
    '    );',
    '  }',
    '}',
  ].join('\n');
}

/// The name of [key] as the debug keys read it: `ctrl+g`, `space`, `o`.
String _keyName(KeyEvent key) => [
  if (key.ctrl) 'ctrl',
  if (key.alt) 'alt',
  switch (key) {
    KeyEvent(code: KeyCode.char, char: ' ') => 'space',
    KeyEvent(code: KeyCode.char, :final char) =>
      key.ctrl ? char.toLowerCase() : char,
    KeyEvent(:final code) => code.name.toLowerCase(),
  },
].join('+');

/// The Code's Sync with the binding's debug aids drawn over it, the
/// switches [aids] on or off; Tab to it, then its keys and the debug keys
/// (Ctrl+G and a command).
final class _Aids extends StatefulWidget {
  const _Aids({required this.aids});

  final Map<String, bool> aids;

  @override
  State<_Aids> createState() => _AidsState();
}

final class _AidsState extends _TimedState<_Aids> {
  final _node = FocusNode(debugLabel: 'the app');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// The app of the page, run on to [ms] in a terminal [w] × [h].
  (_AidsApp, int) _appAt(int ms, int w, int h) {
    final app =
        (kept['app'] ??= () {
              kept['born'] = motion.frozen ? 0 : ms;
              return _AidsApp(Map.of(widget.aids));
            }())
            as _AidsApp;
    final u = math.max(0, ms - (kept['born']! as int));
    app.advance(u, w, h);
    // an option set: the aid turned on or off now, as the key does
    for (final MapEntry(:key, :value) in widget.aids.entries) {
      if (value != app.aid(key)) {
        app.setAid(key, value, u, w, h, root: false);
      }
    }
    return (app, u);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.kind == KeyKind.release) {
      return KeyEventResult.ignored;
    }
    final (w, h) = (kept['w'] as int? ?? _aw, kept['h'] as int? ?? _ah);
    final (app, u) = _appAt(clockNow, w, h);
    final name = _keyName(event);
    var took = true;
    if (app.prefix) {
      // the command after Ctrl+G, in the frame the line of the commands
      // goes in, which repaints what was under it; any other key is
      // dropped
      app.prefix = false;
      final aid = const {'o': 'overlay', 'r': 'rainbow', 'l': 'relayout'}[name];
      if (aid != null) {
        app.setAid(aid, !app.aid(aid), u, w, h, root: true);
        if (widget.aids.containsKey(aid)) {
          PageControl.of(context).setOption(aid, app.aid(aid));
        }
      } else if (name == 'c') {
        app
          ..console = !app.console
          ..frame(
            u,
            w,
            h,
            root: true,
            laid: app.console ? [_consoleRect(w, h)] : const [],
          );
      } else {
        app.frame(u, w, h, root: true);
      }
    } else if (app.console &&
        const [
          'up',
          'down',
          'pageup',
          'pagedown',
          'end',
          'escape',
        ].contains(name)) {
      // the console's keys; with nothing logged, Escape closes it
      if (name == 'escape') {
        app
          ..console = false
          ..frame(u, w, h, root: true);
      }
    } else {
      // space and Ctrl+G: the app's KeyBindings and the binding's
      took = false;
    }
    if (app.prefix) {
      _node.holdKeys();
    } else {
      _node.releaseKeys();
    }
    if (took) {
      setState(() {});
    }
    return took ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// Ctrl+G: the binding waits for a command, the line of them shown.
  void _prefix() {
    final (w, h) = (kept['w'] as int? ?? _aw, kept['h'] as int? ?? _ah);
    final (app, u) = _appAt(clockNow, w, h);
    setState(() {
      app
        ..prefix = true
        ..frame(
          u,
          w,
          h,
          kinds: const ['hint'],
          rects: [_hintRect(w, h)],
          laidRects: [_hintRect(w, h)],
        );
    });
    _node.holdKeys();
  }

  /// Space: the Code's KeyBindings pause the copy or go on with it.
  void _pause() {
    final (w, h) = (kept['w'] as int? ?? _aw, kept['h'] as int? ?? _ah);
    final (app, u) = _appAt(clockNow, w, h);
    setState(() {
      app
        ..paused = !app.paused
        ..frame(
          u,
          w,
          h,
          root: true,
          laid: _laidOut('pause', w, h, paused: app.paused),
          kinds: const ['pause'],
        );
    });
  }

  @override
  Widget buildTimed(BuildContext context) {
    final ms = now;
    return LayoutBuilder(
      builder: (context, c) {
        final w = math.min(_aw, c.maxW);
        final h = math.min(_ah, c.maxH);
        kept
          ..['w'] = w
          ..['h'] = h;
        final (app, u) = _appAt(ms, w, h);
        wake((kept['born']! as int) + app.nextAt());
        final t = Tokens(Theme.of(context));
        final brightness = Theme.of(context).brightness;
        return SizedBox(
          width: w,
          height: h,
          // the app's space and the binding's Ctrl+G; while Ctrl+G waits,
          // the commands that may follow it, which the node takes
          child: KeyBindings(
            app.prefix
                ? {for (final (k, _) in _commands.take(4)) k: () {}}
                : {'space': _pause, 'ctrl+g': _prefix},
            hints: app.prefix
                ? {for (final (k, d) in _commands.take(4)) k: d}
                : const {'space': 'pause'},
            child: Focus(
              focusNode: _node,
              onKeyEvent: _onKey,
              child: Stack(
                children: [
                  // the app, in the terminal's own colours
                  Theme(
                    data: ThemeData.terminal(brightness),
                    child: _Sync(app: app, u: u),
                  ),
                  CellPaint(
                    (p) => _drawAids(p, t, app, w, h),
                    width: w,
                    height: h,
                    hit: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Code's Sync at [u] ms into its run, as [app] has it: paused or
/// syncing, the copy done so far, the samples taken.
final class _Sync extends StatelessWidget {
  const _Sync({required this.app, required this.u});

  final _AidsApp app;
  final int u;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final samples = u ~/ _sampleMs;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          Row(
            gap: 1,
            children: [
              if (!app.paused) const Spinner(),
              Text(app.paused ? 'paused' : 'syncing'),
            ],
          ),
          Row(
            gap: 1,
            children: [
              Text('copy', style: theme.muted),
              SizedBox(
                width: _barW,
                child: ProgressBar(value: app.done / 100),
              ),
            ],
          ),
          Row(
            gap: 1,
            children: [
              Text('load', style: theme.muted),
              SizedBox(
                width: _barW,
                child: Sparkline(
                  data: [
                    for (var i = 0; i < _barW; i++)
                      _loads[(samples + i) % _loads.length],
                  ],
                  style: theme.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The binding's panels over the app, in the terminal's colours, and each
/// cell's background as the last paint of it left it.
void _drawAids(Painter p, Tokens t, _AidsApp app, int w, int h) {
  const blue = Color.blue;
  final text = Style(fg: t.text);
  final muted = Style(fg: t.text, attrs: Attr.dim);
  final display = app.display;
  // the frame overlay at the top right, once it has painted
  if (app.panel && display != null) {
    final (px, py, pw, ph) = _panelRect(w, h);
    final canvas = p.canvas
      ..save()
      ..translate(px, py)
      ..clipRect(0, 0, pw, ph);
    final q = Painter(canvas, pw, ph)
      ..fill(0, 0, _panelW, ph, Style(bg: t.background))
      // the header underlined, dimmed after its title
      ..fill(0, 0, _panelW, 1, Style(fg: t.text, attrs: Attr.underline))
      ..fill(
        7,
        0,
        _panelW - 7,
        1,
        Style(fg: t.text, attrs: Attr.dim | Attr.underline),
      )
      ..text(
        1,
        0,
        'frames',
        const Style(fg: blue, attrs: Attr.bold | Attr.underline),
      );
    final (fps, last, median) = display;
    final f = '$fps fps';
    q.text(
      _panelW - 1 - f.length,
      0,
      f,
      Style(fg: t.text, attrs: Attr.dim | Attr.underline),
    );
    void right(int y, String a, String b, Style st) => q
      ..text(22 - widthOf(a), y, a, st)
      ..text(_panelW - 1 - widthOf(b), y, b, st);
    right(1, 'last', 'median', muted);
    for (var i = 0; i < _metrics.length; i++) {
      q.text(1, 2 + i, _metrics[i], muted);
      right(
        2 + i,
        last == null ? '–' : '${last[i]}',
        median == null ? '–' : '${median[i]}',
        text,
      );
    }
    canvas.restore();
  }
  // the binding's console over the bottom rows: the app logs nothing
  if (app.console) {
    final (_, cy, _, chh) = _consoleRect(w, h);
    p
      ..fill(0, cy, w, chh, Style(bg: t.background))
      ..fill(0, cy, w, 1, Style(fg: t.text, attrs: Attr.underline))
      ..fill(
        8,
        cy,
        w - 8,
        1,
        Style(fg: t.text, attrs: Attr.dim | Attr.underline),
      )
      ..text(
        1,
        cy,
        'console',
        const Style(fg: blue, attrs: Attr.bold | Attr.underline),
      )
      ..text(
        10,
        cy,
        'debug+  0 of 0',
        Style(fg: t.text, attrs: Attr.dim | Attr.underline),
      );
  }
  // while Ctrl+G waits: the commands, as many as fit
  if (app.prefix) {
    p
      ..fill(0, h - 1, w, 1, Style(bg: t.background))
      ..text(
        0,
        h - 1,
        ' ctrl+g ',
        const Style(fg: blue, attrs: Attr.bold | Attr.reverse),
      );
    var x = 9;
    for (final (k, d) in _commands) {
      final end = x + widthOf(k) + 1 + widthOf(d);
      if (end > w) {
        break;
      }
      p
        ..text(x, h - 1, k, const Style(fg: blue, attrs: Attr.bold))
        ..text(x + widthOf(k) + 1, h - 1, d, muted);
      x = end + 2;
    }
  }
  // the backgrounds, as the last paint of each cell left it
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = app.cells[y * _aw + x];
      var bg = t.background;
      if (c.r >= 0) {
        bg = mix(bg, _tint(c.r), _rainbow);
      }
      for (var k = 0; k < c.n; k++) {
        bg = mix(bg, _tint(c.o), _outline);
      }
      if (bg != t.background) {
        p.bg(x, y, 1, 1, bg);
      }
    }
  }
}

/// Tint [i] as a colour.
Color _tint(int i) {
  final v = _tints[i];
  return Color.rgb(v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF);
}

// ------------------------------------------------------------ RepaintBoundary

/// The dots' cells: the marker goes round them.
const _strip = 20;

/// How often the dots under the marker had been painted when the Code's
/// count was built: in the frame of the [k]th step, before it paints. The
/// first frame paints them; without the boundary, each step of the marker
/// over them paints them again, with it the marker alone. The page draws
/// what the Code counts: the gallery's own repaints would count too.
int _paintsAt(int k, {required bool boundary}) =>
    k == 0 ? 0 : (boundary ? 1 : k);

final _repaintBoundary = GalleryPage(
  group: 'Debugging',
  title: 'RepaintBoundary',
  options: const [
    SwitchOption('boundary', 'RepaintBoundary', initial: true),
    ChoiceOption(
      'every',
      'a step every',
      values: [300, 1000],
      labels: ['300 ms', '1 s'],
    ),
  ],
  build: (context, o) =>
      _Paints(boundary: o.flag('boundary'), every: o.choice<int>('every')),
  code: _paintsCode,
);

String _paintsCode(Options o) {
  final ms = o.choice<int>('every');
  final every = ms == 1000 ? 'seconds: 1' : 'milliseconds: $ms';
  final marker = o.flag('boundary')
      ? [
          '    // painted on its own, over what is under it: the dots are not',
          '    final marker = RepaintBoundary(',
          '      child: CustomPaint(painter: _Marker(_at, theme.primary)),',
          '    );',
        ]
      : [
          '    // painted with what is under it: the dots too',
          _line([
            '    final marker = ',
            'CustomPaint(painter: _Marker(_at, theme.primary));',
          ]),
        ];
  return [
    "import 'dart:async';",
    '',
    "import 'package:twk/twk.dart';",
    '',
    'void main() => runApp(const Paints());',
    '',
    '/// Dots across its cells, counting how often it paints them.',
    'final class _Dots extends CellPainter {',
    '  _Dots(this.style);',
    '',
    '  final Style style;',
    '  var paints = 0;',
    '',
    '  @override',
    '  void paint(Canvas canvas, int width, int height) {',
    '    paints++;',
    "    canvas.text(0, 0, '·' * width, style.penIn(canvas.styles));",
    '  }',
    '',
    '  @override',
    '  bool shouldRepaint(_Dots oldDelegate) => false;',
    '}',
    '',
    '/// A dot in the column [at] says, painted again as it moves.',
    'final class _Marker extends CellPainter {',
    '  _Marker(this.at, this.style) : super(repaint: at);',
    '',
    '  final ValueNotifier<int> at;',
    '  final Style style;',
    '',
    '  @override',
    '  void paint(Canvas canvas, int width, int height) =>',
    "      canvas.text(at.value, 0, '●', style.penIn(canvas.styles));",
    '',
    '  @override',
    '  bool shouldRepaint(_Marker oldDelegate) => false;',
    '}',
    '',
    'final class Paints extends StatefulWidget {',
    '  const Paints({super.key});',
    '',
    '  @override',
    '  State<Paints> createState() => _PaintsState();',
    '}',
    '',
    'final class _PaintsState extends State<Paints> {',
    '  final _at = ValueNotifier(0);',
    '  late final Timer _timer;',
    '  late final _dots = _Dots(Theme.of(context).border);',
    '',
    '  @override',
    '  void initState() {',
    '    super.initState();',
    '    // the marker a cell on: its painter repaints, no widget is built',
    '    _timer = Timer.periodic(',
    '      const Duration($every),',
    '      (_) => _at.value = (_at.value + 1) % $_strip,',
    '    );',
    '  }',
    '',
    '  @override',
    '  void dispose() {',
    '    _timer.cancel();',
    '    _at.dispose();',
    '    super.dispose();',
    '  }',
    '',
    '  @override',
    '  Widget build(BuildContext context) {',
    '    final theme = Theme.of(context);',
    ...marker,
    '    return Column(',
    '      mainAxisSize: .min,',
    '      crossAxisAlignment: .start,',
    '      gap: 1,',
    '      children: [',
    '        CustomPaint(',
    '          painter: _dots,',
    '          child: SizedBox(width: $_strip, height: 1, child: marker),',
    '        ),',
    '        // the count on its own too: in a box of its size, a new one',
    '        // lays nothing else out; in a boundary, repaints nothing else',
    '        RepaintBoundary(',
    '          child: SizedBox(',
    '            width: $_strip,',
    '            height: 1,',
    '            child: ListenableBuilder(',
    '              listenable: _at,',
    '              builder: (context, _) => Text.rich([',
    "                Span('painted: ', theme.muted),",
    r"                Span('${_dots.paints}'),",
    '              ]),',
    '            ),',
    '          ),',
    '        ),',
    '      ],',
    '    );',
    '  }',
    '}',
  ].join('\n');
}

/// Dots across the cells of a [CustomPaint].
final class _DotsPainter extends CellPainter {
  const _DotsPainter(this.style);

  final Style style;

  @override
  void paint(Canvas canvas, int width, int height) =>
      canvas.text(0, 0, '·' * width, style.penIn(canvas.styles));

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.style != style;
}

/// A dot in column [at].
final class _MarkerPainter extends CellPainter {
  const _MarkerPainter(this.at, this.style);

  final int at;
  final Style style;

  @override
  void paint(Canvas canvas, int width, int height) =>
      canvas.text(at, 0, '●', style.penIn(canvas.styles));

  @override
  bool shouldRepaint(_MarkerPainter oldDelegate) =>
      oldDelegate.at != at || oldDelegate.style != style;
}

/// The Code's `Paints`: dots under a marker that a timer moves a cell on
/// every [every] ms, the marker in a RepaintBoundary with [boundary], and
/// how often the dots were painted. The steps on the gallery's clock, from
/// when the page was first built (0 while it stands still) or [every] was
/// chosen; the count as the Code's would be.
final class _Paints extends StatefulWidget {
  const _Paints({required this.boundary, required this.every});

  final bool boundary;
  final int every;

  @override
  State<_Paints> createState() => _PaintsState();
}

final class _PaintsState extends _TimedState<_Paints> {
  @override
  Widget buildTimed(BuildContext context) {
    final theme = Theme.of(context);
    final every = widget.every;
    if (kept['born'] == null || kept['every'] != every) {
      // a step every [every] from now: the timer started again
      kept['born'] = kept['born'] == null && motion.frozen ? 0 : now;
      kept['every'] = every;
    }
    final born = kept['born']! as int;
    final k = math.max(0, (now - born) ~/ every);
    wake(born + (k + 1) * every);
    final marker = CustomPaint(
      painter: _MarkerPainter(k % _strip, theme.primary),
    );
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      gap: 1,
      children: [
        CustomPaint(
          painter: _DotsPainter(theme.border),
          child: SizedBox(
            width: _strip,
            height: 1,
            child: widget.boundary ? RepaintBoundary(child: marker) : marker,
          ),
        ),
        RepaintBoundary(
          child: SizedBox(
            width: _strip,
            height: 1,
            child: Text.rich([
              Span('painted: ', theme.muted),
              Span('${_paintsAt(k, boundary: widget.boundary)}'),
            ]),
          ),
        ),
      ],
    );
  }
}
