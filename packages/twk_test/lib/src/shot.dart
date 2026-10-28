/// A tree shown without an app: [Shot], a widget tree or a render tree on
/// a screen of its own, each frame written to an emulator.
///
/// @docImport 'tester.dart';
library;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineOwner, Screen;

import '../vt.dart';
import 'screen_text.dart';

// Examples can assume:
// import 'package:test/test.dart';
// import 'package:twk/twk.dart';

/// A widget tree, or a render tree, on a screen of [width] × [height] cells
/// of its own: built, laid out and painted as an app's frame is, and the
/// bytes of each frame written to an emulator ([vt]), which the getters
/// read back. No binding, no clock and no input: a frame runs when [pump]
/// or [frame] is called, and only then.
///
/// It is for a widget or a render object tested on its own, frame by
/// frame; an app, with its input, time and log, is [testTwk]'s.
///
/// A text in red, and what the emulator shows of it:
///
/// ```dart
/// final shot = Shot(
///   const Text('hi', style: Style(fg: Color.red)),
///   4,
///   1,
/// );
/// expect(shot.rows, ['hi']);
/// expect(shot.vt.cell(0, 0).fgColor, Color.red);
/// ```
///
/// The screen's canvas takes the characters of ambiguous width as
/// `ambiguousWidth` columns (1 or 2), and so does the emulator.
///
/// The tree's own warnings, such as a `RenderFlex` whose children
/// overflow it, are kept in [logs] (the [pipeline]'s `onLog`), not
/// printed: a test reads them there.
///
/// See also:
///
///  * [testTwk], which runs a whole app on a terminal in memory.
///  * [rowText] and [describeScreen], the emulator's screen as text.
final class Shot {
  /// Shows [widget] on a screen of [width] × [height] cells and runs the
  /// first frame.
  Shot(Widget widget, this.width, this.height, {int ambiguousWidth = 1})
    : _widgets = true,
      screen = Screen(width, height, ambiguousWidth: ambiguousWidth),
      vt = Vt(
        width,
        height,
        segmenter: TextSegmenter(ambiguousWidth: ambiguousWidth),
      ) {
    pump(widget);
  }

  /// Shows [root], a render object no widget made, on a screen of
  /// [width] × [height] cells and runs the first frame. With [under], a
  /// character, the screen is filled with it first: what [root] leaves
  /// unpainted shows it, when it is a repaint boundary (a root that is
  /// not one starts each paint from blank cells), which tells whether it
  /// paints every cell. [pump] and [root] are for a widget tree, and
  /// throw a [StateError] here.
  ///
  /// ```dart
  /// final shot = Shot.render(RenderProgressBar(value: 0.5), 10, 1);
  /// expect(shot.rows, ['█████']);
  /// ```
  Shot.render(
    RenderObject root,
    this.width,
    this.height, {
    int ambiguousWidth = 1,
    String? under,
  }) : _widgets = false,
       screen = Screen(width, height, ambiguousWidth: ambiguousWidth),
       vt = Vt(
         width,
         height,
         segmenter: TextSegmenter(ambiguousWidth: ambiguousWidth),
       ) {
    if (under != null) {
      screen.canvas.fill(
        0,
        0,
        width,
        height,
        screen.styles.pen(const Pen(bg: Color.defaultColor)),
        under.codeUnitAt(0),
      );
    }
    pipeline.root = _top = root;
    frame();
  }

  /// The screen's width, in cells.
  final int width;

  /// The screen's height, in cells.
  final int height;

  /// The screen the tree paints on, whose frames go to [vt].
  final Screen screen;

  /// The emulator each frame is written to.
  final Vt vt;

  /// What builds the widgets: [frame] builds what is dirty in it.
  final owner = BuildOwner();

  /// What lays out and paints the render tree: [frame] flushes it.
  late final pipeline = PipelineOwner(
    () {},
    segmenter: screen.canvas.segmenter,
  )..onLog = logs.add;

  /// What the render tree logged of itself, oldest first: the warnings
  /// its render objects give in debug, such as an overflow.
  final logs = <LogRecord>[];

  final bool _widgets;
  RootElement? _root;
  RenderObject? _top;

  /// Shows [widget] in place of the widget shown before, its elements kept
  /// where the widgets match, as in any rebuild, and runs a frame.
  void pump(Widget widget) {
    if (!_widgets) {
      throw StateError('a Shot.render shows no widgets');
    }
    _root = RootWidget(child: widget).attach(owner, _root);
    frame();
  }

  /// Runs a frame: builds what is dirty, lays out and paints what changed,
  /// unmounts what was removed, and writes the frame to [vt]. A frame
  /// that changes nothing writes nothing.
  void frame() {
    if (_widgets) {
      owner.buildScope();
      final top = _root!.renderObject!;
      if (!identical(top, _top)) {
        pipeline.root = top;
        _top = top;
      }
    }
    pipeline
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    if (_widgets) {
      owner.finalizeTree();
    }
    final bytes = screen.render();
    if (bytes != null) {
      vt.feed(bytes);
    }
  }

  /// The element at the top of the widget tree.
  RootElement get root =>
      _widgets ? _root! : throw StateError('a Shot.render has no elements');

  /// The render object at the top of the render tree.
  RenderObject get top => _top!;

  /// The rows the emulator shows, every one of the screen's, each as
  /// [rowText] gives it: without the blanks that end it, a wide glyph
  /// once.
  List<String> get rows => [for (var y = 0; y < height; y++) rowText(vt, y)];

  /// The glyph, text color and background of each cell of row [y].
  List<(String, Color, Color)> colors(int y) => [
    for (var x = 0; x < width; x++)
      if (vt.cell(x, y) case final c) (c.text, c.fgColor, c.bgColor),
  ];

  /// The attributes of each cell of row [y], as [Attr]'s bits.
  List<int> attrs(int y) => [
    for (var x = 0; x < width; x++) vt.cell(x, y).attrs,
  ];

  /// Whether the emulator shows a glyph two columns wide anywhere.
  bool get anyWide => [
    for (var y = 0; y < height; y++)
      for (var x = 0; x < width; x++) vt.cell(x, y).role,
  ].any((role) => role != 0);
}
