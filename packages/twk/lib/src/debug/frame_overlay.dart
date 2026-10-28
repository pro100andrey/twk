/// The frame overlay the binding shows over an app (`DebugAids.overlay`):
/// the numbers of its frames as the binding and the core measured them,
/// those of the overlay's own frames left out.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        Canvas,
        DiagnosticPropertiesBuilder,
        PaintContext,
        RenderObject,
        Screen,
        TwkApp;

import '../data/chart_glyphs.dart' show opaque;
import '../style/style.dart';

/// What the overlay shows of each frame, a row each.
enum _Metric {
  build('build µs'),
  layout('layout µs'),
  paint('paint µs'),
  present('present µs'),
  bytes('bytes'),
  written('cells written'),
  compared('cells compared'),
  scrolled('rows scrolled'),
  repaints('repaints'),
  rebuilds('rebuilds');

  const _Metric(this.label);

  final String label;
}

/// The numbers of the frames an overlay counts: the last frame's and the
/// median of the last [window], and when frames were written.
final class _Meter {
  static const window = 128;

  // frame n's numbers at (n % window) * metrics
  final _values = Int64List(window * _Metric.values.length);
  var _frames = 0;
  final _sorted = Int64List(window);

  // when the last frames were written, in microseconds
  final _writtenAt = Int64List(1024);
  var _written = 0;

  bool get isEmpty => _frames == 0;

  void add(List<int> values) {
    final at = (_frames % window) * values.length;
    for (var i = 0; i < values.length; i++) {
      _values[at + i] = values[i];
    }
    _frames++;
  }

  int last(_Metric m) =>
      _values[((_frames - 1) % window) * _Metric.values.length + m.index];

  int median(_Metric m) {
    final k = _frames < window ? _frames : window;
    for (var i = 0; i < k; i++) {
      _sorted[i] = _values[i * _Metric.values.length + m.index];
    }
    final sorted = Int64List.sublistView(_sorted, 0, k)..sort();
    return sorted[k ~/ 2];
  }

  /// A frame was written at [micros].
  void wrote(int micros) => _writtenAt[_written++ % _writtenAt.length] = micros;

  /// The frames written in the second up to [micros], at most as many as
  /// it remembers.
  int perSecond(int micros) {
    final kept = _written < _writtenAt.length ? _written : _writtenAt.length;
    var n = 0;
    while (n < kept &&
        _writtenAt[(_written - 1 - n) % _writtenAt.length] > micros - 1000000) {
      n++;
    }
    return n;
  }

  /// When the last frame was written; null before the first.
  int? get lastWritten =>
      _written == 0 ? null : _writtenAt[(_written - 1) % _writtenAt.length];
}

/// The frame overlay of an app run by [app]: its panel ([panel]) and the
/// frames it counts, which [afterFrame] is told of.
///
/// Each frame the app did anything in counts, those the panel showed new
/// numbers in too: the panel's own share is taken off the frame's numbers
/// wherever it was laid out or painted — its layout and paint as it timed
/// them, and the bytes, the cells written and compared and the time it
/// takes to present its cells on their own, on a screen of the app's
/// terminal that shows the panel alone — and its own mark off the repaint
/// boundaries. A frame the panel was all of (it showed new numbers and the
/// app did nothing) is not counted. The panel shows new numbers at most
/// every [refreshGap], so that they can be read, and once more a second
/// after the last frame of the app written, for the frames a second; it
/// asks for no frame otherwise.
final class FrameOverlay {
  /// The overlay of [app]'s frames, its panel in [theme].
  FrameOverlay(this.app, ThemeData theme) {
    panel = RenderFrameOverlay(this, theme);
  }

  /// The least time between two refreshes of the panel's numbers.
  static const refreshGap = Duration(milliseconds: 250);

  /// The app whose frames are counted, and whose clock times them.
  final TwkApp app;

  /// What shows the numbers, which the binding paints over the app.
  late final RenderFrameOverlay panel;
  final _meter = _Meter();
  final _values = List<int>.filled(_Metric.values.length, 0);

  // the panel is marked to show new numbers in the next frame; when it
  // last was; numbers counted since; the refresh that waits, and when it
  // is due
  var _refreshing = false;
  int? _refreshedAt;
  var _stale = false;
  Timer? _timer;
  var _timerDue = 0;

  int get _now => app.clock.elapsedMicroseconds;

  /// Counts the frames from the last one written on, in which [rebuilt]
  /// elements were built, and marks the panel to show its numbers.
  void start(int rebuilt) {
    final stats = app.stats;
    _record(
      stats.lastBuildMicros,
      stats.lastLayoutMicros,
      stats.lastPaintMicros,
      rebuilt,
    );
    refresh();
  }

  // what the panel shows: the frames a second, then each number's last
  // and median, as of the last refresh
  var _fps = '0 fps';
  final _shown = List<String>.filled(2 * _Metric.values.length, '–');

  /// Marks the panel to show the numbers counted so far: what it shows
  /// until the next refresh, also painted again.
  void refresh() {
    final now = _now;
    _refreshing = true;
    _refreshedAt = now;
    _stale = false;
    _fps = '${_meter.perSecond(now)} fps';
    if (!_meter.isEmpty) {
      for (final m in _Metric.values) {
        _shown[2 * m.index] = '${_meter.last(m)}';
        _shown[2 * m.index + 1] = '${_meter.median(m)}';
      }
    }
    panel.markNeedsPaint();
  }

  /// Counts the frame that has just been written, less the panel's own
  /// share of it, unless the panel was all of it; [rebuilt] elements were
  /// built in it.
  void afterFrame(int rebuilt) {
    final stats = app.stats;
    final marked = _refreshing;
    _refreshing = false;
    final layout = panel._takeLayoutMicros();
    final paint = panel._takePaintMicros();
    final painted = panel._takePainted();
    // the panel's own share: as it was painted, presented alone
    final alone = painted ? _presentAlone() : null;
    final repaints = stats.lastRepaints - (marked ? 1 : 0);
    // the bytes of a frame the panel was painted in are not all the app's
    if (rebuilt > 0 || repaints > 0 || !painted && stats.lastBytes > 0) {
      final present = app.screen.presenter.stats;
      _values
        ..[_Metric.build.index] = stats.lastBuildMicros
        ..[_Metric.layout.index] = _less(stats.lastLayoutMicros, layout)
        ..[_Metric.paint.index] = _less(stats.lastPaintMicros, paint)
        ..[_Metric.present.index] = _less(
          stats.lastPresentMicros,
          alone?.micros ?? 0,
        )
        ..[_Metric.bytes.index] = _less(stats.lastBytes, alone?.bytes ?? 0)
        ..[_Metric.written.index] = _less(
          present.cellsWritten,
          alone?.written ?? 0,
        )
        ..[_Metric.compared.index] = _less(
          present.cellsCompared,
          alone?.compared ?? 0,
        )
        ..[_Metric.scrolled.index] = present.scrolledRows
        ..[_Metric.repaints.index] = repaints
        ..[_Metric.rebuilds.index] = rebuilt;
      _meter.add(_values);
      _stale = true;
      if (_values[_Metric.bytes.index] > 0) {
        _meter.wrote(_now);
      }
    } else if (!marked) {
      return;
    }
    _schedule();
  }

  static int _less(int n, int own) => n > own ? n - own : 0;

  void _record(int build, int layout, int paint, int rebuilt) {
    final stats = app.stats;
    final present = app.screen.presenter.stats;
    _values
      ..[_Metric.build.index] = build
      ..[_Metric.layout.index] = layout
      ..[_Metric.paint.index] = paint
      ..[_Metric.present.index] = stats.lastPresentMicros
      ..[_Metric.bytes.index] = stats.lastBytes
      ..[_Metric.written.index] = present.cellsWritten
      ..[_Metric.compared.index] = present.cellsCompared
      ..[_Metric.scrolled.index] = present.scrolledRows
      ..[_Metric.repaints.index] = stats.lastRepaints
      ..[_Metric.rebuilds.index] = rebuilt;
    _meter.add(_values);
    _stale = true;
  }

  // the panel alone on a screen of the app's terminal, at its place: what
  // that screen was made for (the app's screen's size, the panel's place
  // and size), which a change of makes it again
  Screen? _alone;
  var _aloneFor = (0, 0, 0, 0, 0, 0);
  final _aloneWatch = Stopwatch();

  /// The panel as it was painted in the last frame, presented on its own
  /// screen: the bytes, the cells written and compared and the time that
  /// takes. Its screen shows the panel alone, at its place on the app's,
  /// and is made again blank when the app's screen or the panel's place
  /// changes, as the app's presenter then writes it whole.
  ({int bytes, int written, int compared, int micros}) _presentAlone() {
    final screen = app.screen;
    final (left, top) = panel.globalOffset;
    final w = panel.width;
    final h = panel.height;
    final key = (screen.width, screen.height, left, top, w, h);
    var alone = _alone;
    if (alone == null || key != _aloneFor) {
      _aloneFor = key;
      final segmenter = screen.canvas.segmenter;
      alone = _alone = Screen(
        left + w,
        top + h,
        caps: screen.presenter.caps,
        textMode: segmenter.mode,
        ambiguousWidth: segmenter.ambiguousWidth,
        colorMode: screen.styles.colorMode,
      );
      alone.styles.defaultBackgroundRgb = screen.styles.defaultBackgroundRgb;
      // what the presenter writes first, as it knows nothing of the
      // terminal, is the blank screen's
      alone.render();
    }
    final canvas = alone.canvas
      ..save()
      ..translate(left, top)
      ..clipRect(0, 0, w, h);
    panel._paintPanel(canvas);
    canvas.restore();
    _aloneWatch
      ..reset()
      ..start();
    final bytes = alone.render()?.length ?? 0;
    _aloneWatch.stop();
    final stats = alone.presenter.stats;
    return (
      bytes: bytes,
      written: stats.cellsWritten,
      compared: stats.cellsCompared,
      micros: _aloneWatch.elapsedMicroseconds,
    );
  }

  /// Shows the numbers counted now, or when [refreshGap] has passed since
  /// the panel last showed new ones; then once more a second after the
  /// last frame written.
  void _schedule() {
    final now = _now;
    final gap = refreshGap.inMicroseconds;
    final shown = _refreshedAt;
    int due;
    if (_stale) {
      if (shown == null || now - shown >= gap) {
        refresh();
        _wait(null);
        return;
      }
      due = shown + gap;
    } else {
      final written = _meter.lastWritten;
      if (written == null || shown == null || shown >= written + 1000000) {
        _wait(null);
        return;
      }
      due = written + 1000000;
    }
    _wait(due);
  }

  /// Refreshes the panel at [due] on the app's clock, never when null, in
  /// place of the refresh that waited.
  void _wait(int? due) {
    if (_timer != null && due == _timerDue) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    if (due != null) {
      _timerDue = due;
      _timer = Timer(Duration(microseconds: due - _now), () {
        _timer = null;
        refresh();
      });
    }
  }

  /// Stops refreshing.
  void dispose() => _wait(null);
}

/// The panel of a [FrameOverlay]: a row for each number of the frames it
/// counts, the last frame's and the median of the last 128, and a header
/// with the frames written in the last second, as of the last refresh, in
/// [theme]'s colors. A repaint boundary that times its own paint.
final class RenderFrameOverlay extends RenderObject {
  /// The panel of [_overlay], in [theme].
  RenderFrameOverlay(this._overlay, this.theme);

  final FrameOverlay _overlay;

  /// Its width: the columns of its rows.
  static const columns = 31;

  /// Its height: a header, the names of the columns and a row per number.
  static const rows = 12;

  /// What it is painted in: its surface, text, muted and primary colors.
  final ThemeData theme;

  final _layoutWatch = Stopwatch();
  final _paintWatch = Stopwatch();
  var _painted = false;

  /// Its layouts since this was last asked, in microseconds.
  int _takeLayoutMicros() {
    final micros = _layoutWatch.elapsedMicroseconds;
    _layoutWatch.reset();
    return micros;
  }

  /// Its paints since this was last asked, in microseconds.
  int _takePaintMicros() {
    final micros = _paintWatch.elapsedMicroseconds;
    _paintWatch.reset();
    return micros;
  }

  /// Whether it was painted since this was last asked.
  bool _takePainted() {
    final painted = _painted;
    _painted = false;
    return painted;
  }

  @override
  bool get isRepaintBoundary => true;

  /// Adds how many frames it counted.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('frames', _overlay._meter._frames);
  }

  @override
  int computeMaxIntrinsicWidth(int height) => columns;

  @override
  int computeMaxIntrinsicHeight(int width) => rows;

  @override
  void performLayout(BoxConstraints c) {
    _layoutWatch.start();
    width = c.constrainW(columns);
    height = c.constrainH(rows);
    _layoutWatch.stop();
  }

  @override
  void paint(PaintContext ctx) {
    _painted = true;
    _paintWatch.start();
    try {
      _paintPanel(ctx.canvas);
    } finally {
      _paintWatch.stop();
    }
  }

  void _paintPanel(Canvas canvas) {
    final styles = canvas.styles;
    final base = opaque(theme.surface.merge(theme.text));
    canvas.fill(0, 0, width, height, base.penIn(styles));
    final header = base.merge(const Style(attrs: Attr.underline));
    final muted = header.merge(theme.muted).penIn(styles);
    canvas
      ..fill(0, 0, width, 1, header.penIn(styles))
      ..text(
        1,
        0,
        'frames',
        header
            .merge(theme.primary)
            .merge(const Style(attrs: Attr.bold))
            .penIn(styles),
      );
    final fps = _overlay._fps;
    canvas.text(columns - 1 - fps.length, 0, fps, muted);
    final label = base.merge(theme.muted).penIn(styles);
    _right(canvas, 1, 'last', 'median', label);
    final plain = base.penIn(styles);
    final shown = _overlay._shown;
    for (final m in _Metric.values) {
      final y = 2 + m.index;
      canvas.text(1, y, m.label, label);
      _right(canvas, y, shown[2 * m.index], shown[2 * m.index + 1], plain);
    }
  }

  /// [last] ending at column 22 of row [y], [median] at column 30.
  static void _right(Canvas canvas, int y, String last, String median, int p) {
    canvas
      ..text(22 - last.length, y, last, p)
      ..text(columns - 1 - median.length, y, median, p);
  }
}
