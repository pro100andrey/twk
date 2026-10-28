/// Something is going on: [Spinner], its [SpinnerFrames] and its
/// [RenderSpinner].
///
/// @docImport 'progress_bar.dart';
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        Color,
        PaintContext,
        RenderDecoratedBox,
        RenderObject,
        TextSegmenter;

import '../binding/app_binding.dart';
import '../data/chart_glyphs.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../layout/box.dart' show Box;
import '../style/style.dart';
import 'steps.dart';

/// The frames a [Spinner] shows in turn, each for [interval]: [dots],
/// [line] and [arc], or frames of one's own.
///
/// Two equal frames are the same frames: a spinner given equal ones shows
/// what it showed.
///
/// A moon that waxes and wanes, a quarter of a second each:
///
/// ```dart
/// Spinner(
///   frames: SpinnerFrames(
///     ['🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘'],
///     interval: Duration(milliseconds: 250),
///   ),
/// )
/// ```
@immutable
final class SpinnerFrames {
  /// The [frames] shown in turn, each for [interval].
  const SpinnerFrames(this.frames, {required this.interval});

  /// What it shows, in order, then from the first again: one at least.
  final List<String> frames;

  /// How long each frame shows.
  final Duration interval;

  /// Braille dots going round: `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`, 80 ms each.
  static const dots = SpinnerFrames([
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
  ], interval: Duration(milliseconds: 80));

  /// A line turning, in ASCII: `-\|/`, 130 ms each.
  static const line = SpinnerFrames([
    '-',
    r'\',
    '|',
    '/',
  ], interval: Duration(milliseconds: 130));

  /// An arc going round: `◜◠◝◞◡◟`, 100 ms each.
  static const arc = SpinnerFrames([
    '◜',
    '◠',
    '◝',
    '◞',
    '◡',
    '◟',
  ], interval: Duration(milliseconds: 100));

  @override
  bool operator ==(Object other) =>
      other is SpinnerFrames &&
      other.interval == interval &&
      sameList(other.frames, frames);

  @override
  int get hashCode => Object.hash(interval, Object.hashAll(frames));
}

/// The frames of [frames] in turn, as long as it is in an app: the frame
/// of the step of the app's clock the frame is in, so that spinners of
/// the same frames show the same one and step in the same frames, on one
/// timer. As wide as its widest frame and a row tall; a repaint boundary,
/// so a step repaints nothing else, and builds nothing. Outside an app it
/// shows the first frame. Its cells take the background of the [Box] it
/// sits in, where its style sets none.
///
/// A spinner before what is going on:
///
/// ```dart
/// Row(
///   children: [
///     Spinner(),
///     Text(' Loading…'),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [ProgressBar], for work whose progress is known.
final class Spinner extends LeafRenderObjectWidget {
  /// A spinner of [frames], [SpinnerFrames.dots] by default, in [style].
  const Spinner({super.key, this.frames = SpinnerFrames.dots, this.style});

  /// What it shows in turn, and how long each frame shows.
  final SpinnerFrames frames;

  /// The frames' color ([Style.fg]) and background ([Style.bg]), over the
  /// theme's text; null for the theme's [ThemeData.primary]. Without a
  /// background, the background of the nearest [Box] above it that has
  /// one ([RenderSpinner.background]), else the theme's.
  final Style? style;

  @override
  RenderSpinner createRenderObject(BuildContext context) {
    final theme = Theme.of(context);
    return RenderSpinner(
      frames: frames,
      style: _style(theme),
      background: theme.background.bg,
      binding: AppBinding.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSpinner renderObject) {
    final theme = Theme.of(context);
    renderObject
      ..frames = frames
      ..style = _style(theme)
      ..background = theme.background.bg;
  }

  Style _style(ThemeData theme) => theme.text.merge(style ?? theme.primary);
}

/// What a [Spinner] lays out and paints: it steps through its frames on
/// [binding]'s clock from its first paint until it is detached. In the
/// style given; where that has no background, on the opaque background of
/// the nearest [RenderDecoratedBox] above it (a `Box`), else on
/// [background]; the terminal's default colors where none of them sets
/// one: none of it the theme's.
final class RenderSpinner extends RenderObject {
  /// A spinner of [frames] in [style] on [background], stepping on
  /// [binding]'s clock; without a binding, one that shows the first frame.
  RenderSpinner({
    this._frames = SpinnerFrames.dots,
    this._style = const Style(),
    this._background,
    this.binding,
  });

  /// The app whose clock it steps by.
  final AppBinding? binding;

  late final _steps = Steps(_frames.interval, markNeedsPaint, binding: binding);

  SpinnerFrames _frames;

  /// What it shows in turn; set to other frames, it lays out again for
  /// their width and steps by their interval.
  SpinnerFrames get frames => _frames;
  set frames(SpinnerFrames f) {
    if (f != _frames) {
      _frames = f;
      _steps.interval = f.interval;
      markNeedsLayout();
    }
  }

  Style _style;

  /// The frames' color and background; where it has no background, the
  /// box's above it or [background].
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  Color? _background;

  /// What it paints on where neither its style nor a box above it has a
  /// background; the terminal's default background when null.
  Color? get background => _background;
  set background(Color? c) {
    if (c != _background) {
      _background = c;
      markNeedsPaint();
    }
  }

  /// The opaque background of the nearest [RenderDecoratedBox] above it
  /// that has one: what its cells show under its frames. Read as it
  /// paints, since a box above that repaints paints it again.
  Color? get _boxBackground {
    for (var p = parent; p != null; p = p.parent) {
      if (p is RenderDecoratedBox) {
        final pen = p.background;
        final bg = pen?.bg;
        if (bg != null && pen!.bgAlpha == 255) {
          return bg;
        }
      }
    }
    return null;
  }

  /// The frame it shows.
  String get frame => _frames.frames[_steps.current % _frames.frames.length];

  @override
  bool get isRepaintBoundary => true;

  @override
  void detach() {
    _steps.stop();
    super.detach();
  }

  static final _detached = TextSegmenter();

  int _width() {
    final segmenter = owner?.segmenter ?? _detached;
    var most = 0;
    for (final f in _frames.frames) {
      final w = segmenter.width(f);
      most = w > most ? w : most;
    }
    return most;
  }

  @override
  int computeMinIntrinsicWidth(int height) => _width();

  @override
  int computeMaxIntrinsicWidth(int height) => _width();

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_width());
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    _steps.start();
    final canvas = ctx.canvas;
    var style = _style;
    if (style.bg == null) {
      final bg = _boxBackground ?? _background;
      if (bg != null) {
        style = style.merge(Style(bg: bg));
      }
    }
    final pen = opaque(style).penIn(canvas.styles);
    canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, frame, pen);
  }
}
