/// Floating windows: a [WindowLayer] shows [Window]s over its child, each
/// in a frame whose title bar drags it, whose edges resize it and whose
/// buttons minimise, maximise and close it; the window the focus goes to
/// comes to the front. A [WindowController] holds where a window is, a
/// [WindowFrame] how the layer draws its windows.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        Attr,
        BoxConstraints,
        Brightness,
        Color,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        EdgeInsets,
        HitTestBehavior,
        HitTestResult,
        PaintContext,
        ParentData,
        RenderObject,
        stringWidth;

import '../animation/ticker.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/mouse.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/child_list.dart';
import '../layout/flex.dart';
import '../layout/shadow.dart';
import '../layout/stack.dart';
import '../semantics/semantics.dart';
import '../style/color_mix.dart';
import '../style/style.dart';
import '../text/widgets.dart';

// Examples can assume:
// var showLog = true;
// late Widget notes;
// late Widget log;
// void setState(void Function() change) {}
// void closeAbout() {}

/// Where a [Window] is and how it shows: the cells it asks for, [left]
/// columns and [top] rows from the top left of its [WindowLayer], [width]
/// by [height] with its frame, and whether it is [minimised] or
/// [maximised]. The window sets them as it is dragged and moved by the
/// keys; its layer shows it inside its room, whatever they ask. It
/// notifies its listeners of each change, which an app listens to to keep
/// where its windows are.
///
/// A window the app puts in the middle of an 80 by 24 screen, and later
/// maximises:
///
/// ```dart
/// final where = WindowController(left: 20, top: 6, width: 40, height: 12);
/// final window = Window(title: 'Log', controller: where, child: Text('…'));
/// // later:
/// where.maximised = true;
/// ```
final class WindowController with ChangeNotifier {
  /// A window [width] by [height] cells, 40 by 12 by default, its top left
  /// [left] columns and [top] rows from the layer's; asserts that the size
  /// is 0 or more.
  WindowController({
    this._left = 0,
    this._top = 0,
    this._width = 40,
    this._height = 12,
    this._minimised = false,
    this._maximised = false,
  }) : assert(_width >= 0 && _height >= 0, 'a size of 0 or more');

  int _left;
  int _top;
  int _width;
  int _height;
  bool _minimised;
  bool _maximised;

  /// The columns between the layer's left edge and the window's, as asked
  /// for: [moveTo] sets it.
  int get left => _left;

  /// The rows between the layer's top edge and the window's, as asked for:
  /// [moveTo] sets it.
  int get top => _top;

  /// The window's columns, its frame with them, as asked for: [resizeTo]
  /// sets it.
  int get width => _width;

  /// The window's rows, its frame with them, as asked for: [resizeTo] sets
  /// it.
  int get height => _height;

  /// Whether the window is hidden, a chip in its layer's strip standing
  /// for it.
  bool get minimised => _minimised;

  set minimised(bool value) {
    if (value != _minimised) {
      _minimised = value;
      notifyListeners();
    }
  }

  /// Whether the window fills its layer's room, its cells kept for when
  /// it is not.
  bool get maximised => _maximised;

  set maximised(bool value) {
    if (value != _maximised) {
      _maximised = value;
      notifyListeners();
    }
  }

  /// Puts the top left of the window at [left], [top].
  void moveTo(int left, int top) => _place(left, top, _width, _height);

  /// Makes the window [width] by [height] cells, its frame with them.
  void resizeTo(int width, int height) {
    assert(width >= 0 && height >= 0, 'a size of 0 or more');
    _place(_left, _top, width, height);
  }

  void _place(int left, int top, int width, int height) {
    if (left == _left && top == _top && width == _width && height == _height) {
      return;
    }
    _left = left;
    _top = top;
    _width = width;
    _height = height;
    notifyListeners();
  }
}

/// A window of a [WindowLayer]: [child] in a frame, [title] on its top
/// edge, the title bar, with the buttons that minimise and maximise it
/// (while [minimisable] and [maximisable]) and close it (while there is
/// an [onClose]), casting [shadow]; where it is and how it shows is its
/// [controller]'s. With [pointerShapes], the pointer shows what a press
/// would do there (see [WindowLayer]).
///
/// A window that cannot be resized, with a close button and a shadow:
///
/// ```dart
/// Window(
///   title: 'About',
///   resizable: false,
///   onClose: closeAbout,
///   shadow: const BoxShadow(opacity: 0.5),
///   child: Text('twk'),
/// )
/// ```
///
/// See [WindowLayer] for windows in use.
@immutable
final class Window {
  /// A window of [child] titled [title]; asserts that [minWidth] and
  /// [minHeight] leave room for the frame, 2 at least.
  const Window({
    required this.title,
    required this.child,
    this.key,
    this.controller,
    this.onClose,
    this.resizable = true,
    this.minimisable = true,
    this.maximisable = true,
    this.minWidth = 12,
    this.minHeight = 3,
    this.shadow,
    this.pointerShapes = true,
  }) : assert(minWidth >= 2 && minHeight >= 2, 'room for the frame');

  /// What the title bar says.
  final String title;

  /// What the window shows inside its frame. Its state is kept as the
  /// window moves, comes to the front, is minimised or maximised; a
  /// [GlobalKey] on it keeps it as it moves to another part of the tree.
  final Widget child;

  /// Tells the window apart from the others of its layer, as a key tells
  /// a widget apart from its siblings: its state and its place in the
  /// layer's order go with it. Null for its index among them: windows
  /// added to or taken from the middle of the list need keys to keep
  /// theirs.
  final Key? key;

  /// Where the window is and how it shows; null for one of the layer's
  /// own, which puts it at the top left, 40 by 12 cells.
  final WindowController? controller;

  /// Called by the close button and by `x` on the title bar; null for a
  /// window without one. The window stays until the layer is built
  /// without it.
  final VoidCallback? onClose;

  /// Whether its edges and Shift and the arrows resize it.
  final bool resizable;

  /// Whether it has a button that minimises it.
  final bool minimisable;

  /// Whether it has a button that maximises it and restores it.
  final bool maximisable;

  /// The fewest columns it shows in and is resized to, its frame with
  /// them, unless the layer is narrower: 12 by default.
  final int minWidth;

  /// The fewest rows it shows in and is resized to, its frame with them,
  /// unless the layer is shorter: 3 by default.
  final int minHeight;

  /// The shadow the window casts on what is under it, outside its cells
  /// and painted with it ([Shadow]); null for none.
  final BoxShadow? shadow;

  /// Whether its title bar and its edges set the pointer's shape, as a
  /// [MouseRegion.cursor] does where the terminal shows it: grab over the
  /// title bar, grabbing while it moves the window, the resize shapes
  /// over the edges and the corners; none while the window is maximised.
  /// False leaves the pointer to the regions around it.
  final bool pointerShapes;
}

/// How a [WindowLayer] draws its windows.
enum WindowFrame {
  /// Without an outline: a panel of the theme's surface, its top row the
  /// title bar a step lighter (towards the text color), the title in bold,
  /// the buttons `─ □ ×`, the child a cell in from the other edges. An
  /// edge is lit while the mouse is over it or drags it, a button while
  /// the mouse is over it. It needs RGB colors in the theme to raise the
  /// title bar.
  raised,

  /// In a box of the theme's border color, the title on its top edge with
  /// the buttons `_ □ ×`, the child inside the box.
  bordered,
}

/// Shows [windows] over [child], each in a frame ([frame]) with its title
/// on top, the title bar; laid out as [child] is, as big as it is.
///
/// A window shows inside the layer, whatever its [WindowController] asks:
/// as big as it asks, within its least size and the layer's, moved in
/// from the right and bottom edges as far as that takes; maximised, as big
/// as the layer. The layer getting smaller, as the terminal does, moves
/// and shrinks the windows into it, and getting bigger again shows them
/// where they were.
///
/// The windows are painted one over another in their order, the one in
/// front last: the one the focus goes to, or the mouse is pressed in,
/// comes to the front, as does one that is restored and one that the layer
/// is built with anew. Their nodes are in the focus tree in the order of
/// [windows], after [child]'s, so Tab and Shift+Tab go through all of them
/// in that order, whatever is in front: the title bar first, a node of its
/// own, then the nodes of the window's child. A press in a window the
/// focus is not in, which no node in it takes the focus on, gives it to
/// its title bar.
///
/// The left button dragging the title bar moves the window, and dragging
/// an edge or a corner resizes it, the top corners too, the title bar
/// itself moving it; a double click on the title bar maximises it, and
/// another restores it. Its buttons, at the right of the title bar,
/// minimise it (`─`, `_` in a [WindowFrame.bordered] frame), maximise and
/// restore it (`□` and `▣`) and close it (`×`, [Window.onClose]). While
/// the title bar has the focus, the arrows move the window a cell, Shift
/// and the arrows resize it by its right and bottom edges, Enter
/// maximises and restores it, `m` minimises it and `x` closes it; a
/// layer of the focus tree whose keys a `KeyHintsBar` shows.
/// A maximised window does not move nor resize.
///
/// With [Window.pointerShapes] the pointer shows what a press does, as
/// [MouseRegion.cursor] sets it where the terminal shows it:
/// [PointerShape.grab] over the title bar and [PointerShape.grabbing]
/// while it moves the window, [PointerShape.ewResize] over the left and
/// right edges, [PointerShape.nsResize] over the bottom one,
/// [PointerShape.nwseResize] and [PointerShape.neswResize] over the
/// corners; none of them over a maximised window. The terminal then
/// reports all motion of the mouse.
///
/// A minimised window is not shown, hit by the mouse nor focusable; its
/// state is kept. A chip with its title stands for it on the bottom row of
/// the layer, in the strip, with the others in the order they were
/// minimised, after the windows in the focus tree: a click on it, or Enter
/// or Space while it has the focus, restores the window and gives its
/// title bar the focus. Minimising the window the focus is in gives its
/// chip the focus. While the strip shows, the windows show in the rows
/// above it.
///
/// Maximising, restoring and minimising a window take [duration] to show:
/// the window grows or shrinks from where it was to where it goes, easing
/// out, minimised into its chip and restored out of it; while it moves,
/// the mouse goes through it. [Duration.zero] shows each change at once.
///
/// [frame] says how a window is drawn; null for [WindowFrame.raised] where
/// the theme's surface and text are RGB colors, [WindowFrame.bordered]
/// where they are not (as in [ThemeData.terminal]), where a raised title
/// bar would not stand out. Either is the theme's surface and text.
/// Raised, the title bar is the surface a step towards the text color
/// (0.08 of the way on a dark theme, 0.07 on a light one), the title in
/// bold [ThemeData.muted], merged with [focusedStyle] (the theme's primary
/// when null) while the focus is in the window; while the title bar has
/// the focus, the bar is the theme's selection with a primary `▎` at its
/// left. The buttons are muted, the text color while the focus is in the
/// window; the one the mouse is over in bold on a cell either side a step
/// towards the text color, `×` in the theme's error color. An edge or a
/// corner that resizes the window is lit in primary (`▏ ▕ ▁`, `▛ ▜` at the
/// top corners) while the mouse is over it or drags it. Bordered, the
/// border is in the theme's border color, merged with [focusedStyle] for
/// the window the focus is in, and the title of one whose title bar has
/// the focus is merged with the theme's selection. A window's
/// [Window.shadow] falls on the cells beside it, outside the cells it
/// asks for, and is painted with it, under the windows in front of it;
/// the mouse goes through it. [decorate] builds what each window is shown
/// in, its shadow with it, laid out over their cells and [margin] around
/// them, the window [margin] in from its edges: what it paints around the
/// window is painted with the window too; the mouse goes through the
/// margin where the decoration is not hit.
///
/// A screen reader reads a window as a [SemanticsRole.dialog] of its title,
/// `maximised` as its value while it is, then what is in it; its title bar
/// is the dialog's node for the focus. A minimised window is read as its
/// chip, a [SemanticsRole.button] of its title, `minimised`.
///
/// A desktop of two windows over a background, the second closed by its
/// `×`:
///
/// ```dart
/// WindowLayer(
///   windows: [
///     Window(title: 'Notes', key: const ValueKey('notes'), child: notes),
///     if (showLog)
///       Window(
///         title: 'Log',
///         key: const ValueKey('log'),
///         onClose: () => setState(() => showLog = false),
///         child: log,
///       ),
///   ],
///   child: Text('desktop'),
/// )
/// ```
final class WindowLayer extends StatefulWidget {
  /// Shows [windows] over [child], each maximised, restored and minimised
  /// over [duration], 160 ms by default.
  const WindowLayer({
    required this.windows,
    required this.child,
    super.key,
    this.focusedStyle,
    this.decorate,
    this.margin = EdgeInsets.zero,
    this.frame,
    this.duration = const Duration(milliseconds: 160),
  });

  /// The windows, in the order of the focus tree; a window taken out of the
  /// list is gone.
  final List<Window> windows;

  /// What the windows are shown over.
  final Widget child;

  /// For the window the focus is in, merged over its title in a
  /// [WindowFrame.raised] frame, over the theme's border in a
  /// [WindowFrame.bordered] one; the theme's primary when null.
  final Style? focusedStyle;

  /// How the windows are drawn; null for [WindowFrame.raised] where the
  /// theme's surface and text are RGB colors, else [WindowFrame.bordered].
  final WindowFrame? frame;

  /// How long a window takes to maximise, restore and minimise;
  /// [Duration.zero] for at once.
  final Duration duration;

  /// Builds what a window, given in its frame, is shown in; null for the
  /// window alone.
  final Widget Function(BuildContext context, Widget window)? decorate;

  /// The cells around each window that what [decorate] builds takes.
  final EdgeInsets margin;

  @override
  State<WindowLayer> createState() => _WindowLayerState();
}

/// What tells a [Window] without a key apart: its index.
@immutable
final class _Index {
  const _Index(this.index);

  final int index;

  @override
  bool operator ==(Object other) => other is _Index && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// The edges of a window that a drag moves: none for the whole window.
const _leftEdge = 1;
const _topEdge = 2;
const _rightEdge = 4;
const _bottomEdge = 8;

/// The window and the cells of the screen as a drag's press found them:
/// what each drag of it moves the window from.
final class _Grip {
  _Grip(this.edges, this.x, this.y, this.rect);

  /// The edges dragged: none to move the window.
  final int edges;

  /// The cell of the screen pressed.
  final int x;
  final int y;

  /// Where the window showed.
  final _Rect rect;
}

/// Cells of a layer: the left and top ones, the width and the height. A
/// top of [_chipRow] is the layer's bottom row, the strip's.
typedef _Rect = ({int left, int top, int width, int height});

/// The top of a [_Rect] on the layer's bottom row, the strip's.
const _chipRow = -1;

/// A window on its way: from [from] to where it shows, or minimised to
/// its chip at [toChip]; [t] of the way there, eased.
final class _Motion {
  _Motion(this.from, this.toChip);

  final _Rect from;
  final _Rect? toChip;

  /// The ticker's time when it started; null before its first tick.
  Duration? start;
  var t = 0.0;
}

/// What a layer keeps for each of its windows: the window, its
/// controller, the nodes of its frame, the title bar's and the chip's, and
/// the drag under way.
final class _Slot {
  _Slot(this.id, this.window);

  final Object id;
  Window window;
  WindowController? _own;

  /// The node of the whole window, which cannot take the focus itself:
  /// the focus is in the window while it is in this one.
  final group = FocusNode(canRequestFocus: false);

  /// The node of the title bar.
  final title = FocusNode(debugLabel: 'window title');

  /// The node of the chip that stands for the window while it is
  /// minimised.
  final chip = FocusNode(debugLabel: 'window chip');

  _Grip? grip;

  /// Told when the controller changes.
  late final VoidCallback changed;

  // the controller's flags as the layer last saw them
  var maximised = false;
  var minimised = false;

  /// Where the window moves from while it is maximised, restored or
  /// minimised.
  _Motion? motion;

  /// The button of the title bar the mouse is over, by its index; -1 for
  /// none.
  var hoveredButton = -1;

  /// The edges whose grip the mouse is over.
  var hoveredEdges = 0;

  WindowController get controller =>
      window.controller ?? (_own ??= WindowController());

  void dispose() {
    group.dispose();
    title.dispose();
    chip.dispose();
    _own?.dispose();
  }
}

final class _WindowLayerState extends State<WindowLayer>
    with TickerProviderStateMixin {
  final _slots = <Object, _Slot>{};

  // what moves the windows on their way; made for the first
  Ticker? _ticker;

  /// The slot whose chip takes the focus as it is built: its window was
  /// minimised with the focus in it.
  _Slot? _focusChip;

  // the windows back to front, and those minimised in the order they were
  final _order = <Object>[];
  final _strip = <Object>[];

  final GlobalKey _layout = GlobalKey();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WindowLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    for (final slot in _slots.values) {
      slot.controller.removeListener(slot.changed);
      slot.dispose();
    }
    super.dispose();
  }

  static Object _idOf(Window window, int index) => window.key ?? _Index(index);

  /// A slot for each window, those of windows no longer there gone, a new
  /// window in front.
  void _sync() {
    final windows = widget.windows;
    final ids = <Object>{};
    for (var i = 0; i < windows.length; i++) {
      final window = windows[i];
      final id = _idOf(window, i);
      // added outside the assert, which a VM without asserts skips
      final added = ids.add(id);
      assert(added, 'two windows are both $id');
      final slot = _slots[id];
      if (slot == null) {
        _add(id, window);
        continue;
      }
      final old = slot.controller;
      slot.window = window;
      if (!identical(old, slot.controller)) {
        old.removeListener(slot.changed);
        slot.controller.addListener(slot.changed);
        _controllerChanged(slot, rebuild: false);
      }
    }
    for (final id in [..._slots.keys]) {
      if (!ids.contains(id)) {
        final slot = _slots.remove(id)!;
        if (identical(_focusChip, slot)) {
          _focusChip = null;
        }
        _order.remove(id);
        _strip.remove(id);
        slot.controller.removeListener(slot.changed);
        slot.dispose();
      }
    }
  }

  void _add(Object id, Window window) {
    final slot = _Slot(id, window);
    void focusChanged() {
      if (slot.group.hasFocus) {
        _front(slot);
      }
      setState(() {});
    }

    slot.changed = () => _controllerChanged(slot);
    slot.group.addListener(focusChanged);
    slot.title.addListener(_rebuild);
    slot.chip.addListener(_rebuild);
    slot.controller.addListener(slot.changed);
    _slots[id] = slot;
    _order.add(id);
    _controllerChanged(slot, rebuild: false);
  }

  void _rebuild() => setState(() {});

  /// Keeps [slot]'s window out of the focus while it is minimised, its
  /// chip in the strip, and brings it to the front as it is restored.
  /// Minimised with the focus in it, its chip takes the focus as it is
  /// built, the window keeping it until then. A change of [rebuild]'s
  /// starts the window on its way from where it shows.
  void _controllerChanged(_Slot slot, {bool rebuild = true}) {
    final c = slot.controller;
    final minimised = c.minimised;
    final maximised = c.maximised;
    final from =
        rebuild && (minimised != slot.minimised || maximised != slot.maximised)
        ? _shownNow(slot)
        : null;
    slot
      ..minimised = minimised
      ..maximised = maximised;
    if (minimised) {
      if (!_strip.contains(slot.id)) {
        _strip.add(slot.id);
        if (rebuild && slot.group.hasFocus) {
          _focusChip = slot;
        }
      }
    } else {
      if (identical(_focusChip, slot)) {
        _focusChip = null;
      }
      if (_strip.remove(slot.id)) {
        _order
          ..remove(slot.id)
          ..add(slot.id);
      }
    }
    slot.group.descendantsAreFocusable =
        !minimised || identical(_focusChip, slot);
    if (from != null) {
      _move(slot, from);
    }
    if (rebuild) {
      setState(() {});
    }
  }

  /// Gives [slot]'s chip the focus, as it is built, if it is to take it.
  void _chipBuilt(_Slot slot) {
    if (identical(_focusChip, slot)) {
      _focusChip = null;
      slot.chip.requestFocus();
      slot.group.descendantsAreFocusable = false;
    }
  }

  _RenderWindows? get _render {
    final render = _layout.currentContext?.findRenderObject();
    return render is _RenderWindows ? render : null;
  }

  /// Where [slot]'s window shows at the last layout, on its way too; its
  /// chip while it is minimised; null for neither.
  _Rect? _shownNow(_Slot slot) =>
      _render?.rectOf(slot.id) ?? (slot.minimised ? _chipRect(slot) : null);

  /// The cells of [slot]'s chip in the strip; null for none.
  _Rect? _chipRect(_Slot slot) {
    var left = 0;
    for (final id in _strip) {
      final s = _slots[id];
      if (s == null) {
        continue;
      }
      final width = stringWidth(s.window.title) + 2;
      if (identical(s, slot)) {
        return (left: left, top: _chipRow, width: width, height: 1);
      }
      left += width + 1;
    }
    return null;
  }

  /// Starts [slot]'s window on its way from [from]; at once without a
  /// [WindowLayer.duration] or an app whose frames tick.
  void _move(_Slot slot, _Rect from) {
    if (widget.duration <= Duration.zero) {
      slot.motion = null;
      return;
    }
    final ticker = _ticker ??= createTicker(_tick);
    if (ticker.binding == null) {
      return;
    }
    slot.motion = _Motion(from, slot.minimised ? _chipRect(slot) : null);
    if (!ticker.isActive) {
      ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final total = widget.duration.inMicroseconds;
    var moving = false;
    for (final slot in _slots.values) {
      final m = slot.motion;
      if (m == null) {
        continue;
      }
      final start = m.start ??= elapsed;
      final k = total <= 0 ? 1.0 : (elapsed - start).inMicroseconds / total;
      if (k >= 1) {
        slot.motion = null;
      } else {
        // the cubic ease out
        final rest = 1 - k;
        m.t = 1 - rest * rest * rest;
        moving = true;
      }
    }
    if (!moving) {
      _ticker?.stop();
    }
    setState(() {});
  }

  /// Puts [slot]'s window in front.
  void _front(_Slot slot) {
    if (_order.last != slot.id) {
      setState(
        () => _order
          ..remove(slot.id)
          ..add(slot.id),
      );
    }
  }

  /// A button pressed in [slot]'s window: it comes to the front, and its
  /// title bar gets the focus unless the focus is in it.
  void _pressed(_Slot slot) {
    _front(slot);
    if (!slot.group.hasFocus) {
      slot.title.requestFocus();
    }
  }

  /// Restores [slot]'s minimised window and gives its title bar the
  /// focus.
  void _restore(_Slot slot) {
    slot.controller.minimised = false;
    slot.title.requestFocus();
  }

  /// The room the windows show in at the last layout: the layer's, less
  /// the strip's row; none before the first.
  (int, int) get _room => _render?.room ?? (0, 0);

  /// Where [slot]'s window shows in the room of the last layout, as its
  /// controller asks now.
  _Rect _shown(_Slot slot) {
    final (width, height) = _room;
    return _fit(slot.controller, slot.window, width, height);
  }

  void _dragStart(_Slot slot, int edges, PointerEvent event) {
    if (slot.controller.maximised) {
      return;
    }
    // rebuilt for the pointer's shape
    setState(
      () =>
          slot.grip = _Grip(edges, event.screenX, event.screenY, _shown(slot)),
    );
  }

  void _dragUpdate(_Slot slot, PointerEvent event) {
    final grip = slot.grip;
    if (grip == null) {
      return;
    }
    final (width, height) = _room;
    final dx = event.screenX - grip.x;
    final dy = event.screenY - grip.y;
    final r = grip.rect;
    final c = slot.controller;
    if (grip.edges == 0) {
      c.moveTo(
        _clamp(r.left + dx, 0, width - r.width),
        _clamp(r.top + dy, 0, height - r.height),
      );
      return;
    }
    final window = slot.window;
    final minW = _less(window.minWidth, width);
    final minH = _less(window.minHeight, height);
    var left = r.left;
    var top = r.top;
    var right = r.left + r.width;
    var bottom = r.top + r.height;
    if (grip.edges & _leftEdge != 0) {
      left = _clamp(left + dx, 0, right - minW);
    }
    if (grip.edges & _rightEdge != 0) {
      right = _clamp(right + dx, left + minW, width);
    }
    if (grip.edges & _topEdge != 0) {
      top = _clamp(top + dy, 0, bottom - minH);
    }
    if (grip.edges & _bottomEdge != 0) {
      bottom = _clamp(bottom + dy, top + minH, height);
    }
    c._place(left, top, right - left, bottom - top);
  }

  void _dragEnd(_Slot slot) => setState(() => slot.grip = null);

  /// The mouse came over [slot]'s button [index], or left the one [from]
  /// for none (-1).
  void _hoverButton(_Slot slot, int index, {int? from}) {
    if (from != null && slot.hoveredButton != from) {
      return;
    }
    if (slot.hoveredButton != index) {
      setState(() => slot.hoveredButton = index);
    }
  }

  /// The mouse came over the grip of [slot]'s [edges], or left the one of
  /// those [from] for none (0).
  void _hoverEdges(_Slot slot, int edges, {int? from}) {
    if (from != null && slot.hoveredEdges != from) {
      return;
    }
    if (slot.hoveredEdges != edges) {
      setState(() => slot.hoveredEdges = edges);
    }
  }

  /// Moves [slot]'s window [dx] columns and [dy] rows, inside the room.
  void _nudge(_Slot slot, int dx, int dy) {
    if (slot.controller.maximised) {
      return;
    }
    final (width, height) = _room;
    final r = _shown(slot);
    slot.controller.moveTo(
      _clamp(r.left + dx, 0, width - r.width),
      _clamp(r.top + dy, 0, height - r.height),
    );
  }

  /// Makes [slot]'s window [dw] columns wider and [dh] rows taller, by its
  /// right and bottom edges, within its least size and the room.
  void _stretch(_Slot slot, int dw, int dh) {
    if (slot.controller.maximised) {
      return;
    }
    final (width, height) = _room;
    final window = slot.window;
    final r = _shown(slot);
    slot.controller._place(
      r.left,
      r.top,
      _clamp(r.width + dw, _less(window.minWidth, width), width - r.left),
      _clamp(r.height + dh, _less(window.minHeight, height), height - r.top),
    );
  }

  void _toggleMaximised(_Slot slot) {
    if (slot.window.maximisable) {
      final c = slot.controller;
      c.maximised = !c.maximised;
    }
  }

  void _minimise(_Slot slot) {
    if (slot.window.minimisable) {
      slot.controller.minimised = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raised = switch (widget.frame) {
      WindowFrame.raised => true,
      WindowFrame.bordered => false,
      null => _isRgb(theme.surface.bg) && _isRgb(theme.text.fg),
    };
    final windows = widget.windows;
    final margin = widget.margin;
    return _WindowsLayout(
      key: _layout,
      margin: margin,
      children: [
        widget.child,
        for (var i = 0; i < windows.length; i++)
          _placed(context, _slots[_idOf(windows[i], i)]!, theme, raised),
        _Strip(this, [for (final id in _strip) _slots[id]!]),
      ],
    );
  }

  Widget _placed(
    BuildContext context,
    _Slot slot,
    ThemeData theme,
    bool raised,
  ) {
    final c = slot.controller;
    final window = slot.window;
    final shadow = window.shadow;
    final focused = widget.focusedStyle ?? theme.primary;
    final Widget framed = _Frame(
      this,
      slot,
      theme,
      raised ? focused : theme.border.merge(focused),
      raised: raised,
    );
    final motion = slot.motion;
    final Widget frame = Padding(
      padding: widget.margin,
      child: shadow == null ? framed : Shadow(shadow: shadow, child: framed),
    );
    return _Placed(
      key: ValueKey<Object>(slot.id),
      left: c.left,
      top: c.top,
      width: c.width,
      height: c.height,
      minWidth: window.minWidth,
      minHeight: window.minHeight,
      maximised: c.maximised,
      minimised: c.minimised,
      shadow: shadow?.insets ?? EdgeInsets.zero,
      z: _order.indexOf(slot.id),
      id: slot.id,
      from: motion?.from,
      toChip: motion?.toChip,
      progress: motion?.t ?? 1,
      child: widget.decorate?.call(context, frame) ?? frame,
    );
  }
}

bool _isRgb(Color? color) => color != null && color.isRgb;

/// A window in its frame: the title bar's node first, then the window's
/// child in its frame, then over the frame's edges what the mouse drags
/// and presses there. [raised] for a [WindowFrame.raised] frame, in which
/// [focused] is merged over the title of the window the focus is in; in a
/// bordered one it is the border of that window.
final class _Frame extends StatelessWidget {
  const _Frame(
    this.layer,
    this.slot,
    this.theme,
    this.focused, {
    required this.raised,
  });

  final _WindowLayerState layer;
  final _Slot slot;
  final ThemeData theme;
  final Style focused;
  final bool raised;

  static const _buttonsInset = 1;

  @override
  Widget build(BuildContext context) {
    final window = slot.window;
    final c = slot.controller;
    final onClose = window.onClose;
    final buttons = <(String, VoidCallback)>[
      if (window.minimisable) (raised ? '─' : '_', () => layer._minimise(slot)),
      if (window.maximisable)
        (c.maximised ? '▣' : '□', () => layer._toggleMaximised(slot)),
      if (onClose != null) ('×', onClose),
    ];
    final buttonsWidth = buttons.isEmpty ? 0 : 1 + 2 * buttons.length;
    final minimised = c.minimised;
    final within = slot.group.hasFocus;
    final onBar = slot.title.hasFocus;
    final Style title;
    final Widget body;
    final Widget? chrome;
    final Widget buttonRow;
    if (raised) {
      const bold = Style(attrs: Attr.bold);
      title = within
          ? theme.muted.merge(focused).merge(bold)
          : theme.muted.merge(bold);
      final bar = onBar ? theme.selection : _raisedBar(theme);
      body = Box(
        style: theme.surface.merge(theme.text),
        padding: const EdgeInsets.all(1),
        child: window.child,
      );
      final lit = c.maximised || !window.resizable
          ? 0
          : switch (slot.grip?.edges) {
              final edges? when edges != 0 => edges,
              _ => slot.hoveredEdges,
            };
      chrome = _Chrome(
        bar: bar,
        mark: onBar ? theme.primary : null,
        lit: lit,
        litStyle: theme.surface.merge(theme.primary),
      );
      buttonRow = _raisedButtons(buttons, bar, within, onClose);
    } else {
      final border = within ? focused : theme.border;
      title = onBar ? theme.text.merge(theme.selection) : theme.text;
      body = Box(
        style: theme.surface.merge(theme.text),
        border: Border.all(style: border),
        child: window.child,
      );
      chrome = null;
      buttonRow = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(' ', style: border, wrap: TextWrap.none),
          for (final (glyph, onTap) in buttons)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (_) => onTap(),
              child: Text('$glyph ', style: border, wrap: TextWrap.none),
            ),
        ],
      );
    }
    final frame = Focus(
      focusNode: slot.group,
      child: Listener(
        onDown: (_) => layer._pressed(slot),
        child: Stack(
          children: [
            Focus(
              focusNode: slot.title,
              child: KeyBindings(
                _keys(window, onClose),
                hints: _hints(window, onClose, c.maximised),
                child: const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(child: body),
            if (chrome != null) Positioned.fill(child: chrome),
            Positioned(
              left: 1,
              top: 0,
              right: _buttonsInset + buttonsWidth,
              height: 1,
              child: _shaped(
                slot.grip?.edges == 0
                    ? PointerShape.grabbing
                    : PointerShape.grab,
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDragStart: (d) => layer._dragStart(slot, 0, d.event),
                  onDragUpdate: (d) => layer._dragUpdate(slot, d.event),
                  onDragEnd: (_) => layer._dragEnd(slot),
                  onDoubleTap: window.maximisable
                      ? (_) => layer._toggleMaximised(slot)
                      : null,
                  // read as the window's label
                  child: Semantics(
                    nodes: const [],
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        raised ? ' ${window.title}' : ' ${window.title} ',
                        style: title,
                        wrap: TextWrap.none,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (buttons.isNotEmpty)
              Positioned(
                top: 0,
                right: _buttonsInset,
                // the title bar's keys stand for them
                child: Semantics(nodes: const [], child: buttonRow),
              ),
            if (window.resizable) ..._edges(),
          ],
        ),
      ),
    );
    // minimised, read as its chip
    return Semantics(
      role: minimised ? null : SemanticsRole.dialog,
      label: minimised ? null : window.title,
      value: c.maximised && !minimised ? 'maximised' : null,
      nodes: minimised ? const [] : null,
      child: frame,
    );
  }

  /// The buttons of a raised title bar on [bar]: a blank, then each glyph
  /// and a blank after it, the one the mouse is over lit with the blanks
  /// either side of it.
  Widget _raisedButtons(
    List<(String, VoidCallback)> buttons,
    Style bar,
    bool within,
    VoidCallback? onClose,
  ) {
    final hovered = slot.hoveredButton;
    final rest = within ? theme.text : theme.muted;
    // the fill of button i lit, null where none can be mixed
    Style lit(int i) {
      final closes = onClose != null && i == buttons.length - 1;
      final towards = closes ? theme.error.fg : theme.text.fg;
      // the colors not RGB: the close button filled with the error's
      // color, the others on the theme's hover
      final fill = mixRgb(bar.bg, towards, 0.16);
      if (fill == null) {
        return (closes
                ? theme.fill(theme.error.fg)
                : theme.text.merge(theme.hover))
            .merge(const Style(attrs: Attr.bold));
      }
      return (closes ? theme.error : theme.text).merge(
        Style(bg: fill, attrs: Attr.bold),
      );
    }

    Style blank(int after) =>
        hovered >= 0 && (after == hovered || after + 1 == hovered)
        ? Style(bg: lit(hovered).bg)
        : const Style();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(' ', style: blank(-1), wrap: TextWrap.none),
        for (final (i, (glyph, onTap)) in buttons.indexed)
          MouseRegion(
            onEnter: (_) => layer._hoverButton(slot, i),
            onExit: (_) => layer._hoverButton(slot, -1, from: i),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (_) => onTap(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    glyph,
                    style: i == hovered ? lit(i) : rest,
                    wrap: TextWrap.none,
                  ),
                  Text(' ', style: blank(i), wrap: TextWrap.none),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Map<String, VoidCallback> _keys(Window window, VoidCallback? onClose) => {
    'left': () => layer._nudge(slot, -1, 0),
    'right': () => layer._nudge(slot, 1, 0),
    'up': () => layer._nudge(slot, 0, -1),
    'down': () => layer._nudge(slot, 0, 1),
    if (window.resizable) ...{
      'shift+left': () => layer._stretch(slot, -1, 0),
      'shift+right': () => layer._stretch(slot, 1, 0),
      'shift+up': () => layer._stretch(slot, 0, -1),
      'shift+down': () => layer._stretch(slot, 0, 1),
    },
    if (window.maximisable) 'enter': () => layer._toggleMaximised(slot),
    if (window.minimisable) 'm': () => layer._minimise(slot),
    'x': ?onClose,
  };

  static Map<String, String> _hints(
    Window window,
    VoidCallback? onClose,
    bool maximised,
  ) => {
    'left': 'window left',
    'right': 'window right',
    'up': 'window up',
    'down': 'window down',
    if (window.resizable) ...{
      'shift+left': 'narrower',
      'shift+right': 'wider',
      'shift+up': 'shorter',
      'shift+down': 'taller',
    },
    if (window.maximisable) 'enter': maximised ? 'restore' : 'maximise',
    if (window.minimisable) 'm': 'minimise',
    if (onClose != null) 'x': 'close',
  };

  /// [child] in a region of the pointer in [shape], while the window
  /// sets the pointer's shape and is not maximised; hit where [child] is.
  /// With [edges], the mouse over it lights them in a raised frame.
  Widget _shaped(PointerShape shape, Widget child, {int edges = 0}) =>
      MouseRegion(
        cursor: slot.window.pointerShapes && !slot.controller.maximised
            ? shape
            : null,
        behavior: HitTestBehavior.deferToChild,
        onEnter: raised && edges != 0
            ? (_) => layer._hoverEdges(slot, edges)
            : null,
        onExit: raised && edges != 0
            ? (_) => layer._hoverEdges(slot, 0, from: edges)
            : null,
        child: child,
      );

  /// What drags the edges and the corners: the top edge between the
  /// corners is the title bar's.
  List<Widget> _edges() {
    Widget grip(int edges) => _shaped(
      switch (edges) {
        _leftEdge || _rightEdge => PointerShape.ewResize,
        _bottomEdge => PointerShape.nsResize,
        const (_leftEdge | _topEdge) ||
        const (_rightEdge | _bottomEdge) => PointerShape.nwseResize,
        _ => PointerShape.neswResize,
      },
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDragStart: (d) => layer._dragStart(slot, edges, d.event),
        onDragUpdate: (d) => layer._dragUpdate(slot, d.event),
        onDragEnd: (_) => layer._dragEnd(slot),
      ),
      edges: edges,
    );
    return [
      Positioned(left: 0, top: 1, bottom: 1, width: 1, child: grip(_leftEdge)),
      Positioned(
        right: 0,
        top: 1,
        bottom: 1,
        width: 1,
        child: grip(_rightEdge),
      ),
      Positioned(
        left: 1,
        right: 1,
        bottom: 0,
        height: 1,
        child: grip(_bottomEdge),
      ),
      Positioned(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        child: grip(_leftEdge | _topEdge),
      ),
      Positioned(
        right: 0,
        top: 0,
        width: 1,
        height: 1,
        child: grip(_rightEdge | _topEdge),
      ),
      Positioned(
        left: 0,
        bottom: 0,
        width: 1,
        height: 1,
        child: grip(_leftEdge | _bottomEdge),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        width: 1,
        height: 1,
        child: grip(_rightEdge | _bottomEdge),
      ),
    ];
  }
}

/// The title bar of a raised window, a step from the theme's surface
/// towards its text color: 0.08 of the way on a dark theme, 0.07 on a
/// light one; the surface where either is not RGB.
Style _raisedBar(ThemeData theme) {
  final bar = mixRgb(
    theme.surface.bg,
    theme.text.fg,
    theme.brightness == Brightness.dark ? 0.08 : 0.07,
  );
  return bar == null ? theme.surface : Style(bg: bar);
}

/// What a raised frame paints over the window's surface: the title bar,
/// [bar] across its top row, with [mark]'s `▎` at its left while it has
/// the focus; the [lit] edges in [litStyle], `▏ ▕ ▁` and `▛ ▜` at the top
/// corners.
final class _Chrome extends LeafRenderObjectWidget {
  const _Chrome({
    required this.bar,
    required this.mark,
    required this.lit,
    required this.litStyle,
  });

  final Style bar;
  final Style? mark;
  final int lit;
  final Style litStyle;

  @override
  _RenderChrome createRenderObject(BuildContext context) =>
      _RenderChrome().._configure(this);

  @override
  void updateRenderObject(BuildContext context, _RenderChrome renderObject) =>
      renderObject._configure(this);
}

final class _RenderChrome extends RenderObject {
  var _bar = const Style();
  Style? _mark;
  var _lit = 0;
  var _litStyle = const Style();

  void _configure(_Chrome w) {
    if (w.bar != _bar ||
        w.mark != _mark ||
        w.lit != _lit ||
        w.litStyle != _litStyle) {
      _bar = w.bar;
      _mark = w.mark;
      _lit = w.lit;
      _litStyle = w.litStyle;
      markNeedsPaint();
    }
  }

  // the mouse goes through it, to what is under it
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.deferToChild;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  int computeMinIntrinsicWidth(int height) => 0;

  @override
  int computeMaxIntrinsicWidth(int height) => 0;

  @override
  int computeMinIntrinsicHeight(int width) => 0;

  @override
  int computeMaxIntrinsicHeight(int width) => 0;

  @override
  void paint(PaintContext ctx) {
    final w = width;
    final h = height;
    if (w <= 0 || h <= 0) {
      return;
    }
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final bar = _bar.penIn(styles);
    canvas.fill(0, 0, w, 1, bar);
    if (_mark case final mark?) {
      canvas.fill(0, 0, 1, 1, _bar.merge(mark).penIn(styles), 0x258E);
    }
    final lit = _lit;
    if (lit == 0) {
      return;
    }
    final pen = _litStyle.penIn(styles);
    final left = lit & _leftEdge != 0;
    final right = lit & _rightEdge != 0;
    if (left && h > 1) {
      canvas.fill(0, 1, 1, h - 1, pen, 0x258F);
    }
    if (right && h > 1) {
      canvas.fill(w - 1, 1, 1, h - 1, pen, 0x2595);
    }
    if (lit & _bottomEdge != 0 && h > 1) {
      final from = left ? 1 : 0;
      final to = right ? w - 1 : w;
      if (to > from) {
        canvas.fill(from, h - 1, to - from, 1, pen, 0x2581);
      }
    }
    if (lit & _topEdge != 0) {
      final corner = _bar.merge(Style(fg: _litStyle.fg)).penIn(styles);
      canvas.fill(left ? 0 : w - 1, 0, 1, 1, corner, left ? 0x259B : 0x259C);
    }
  }
}

/// The chips of the minimised windows, side by side; nothing without any.
final class _Strip extends StatelessWidget {
  const _Strip(this.layer, this.slots);

  final _WindowLayerState layer;
  final List<_Slot> slots;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final style = theme.surface.merge(theme.text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      gap: 1,
      children: [
        for (final slot in slots)
          Semantics(
            key: ValueKey<Object>(slot.id),
            role: SemanticsRole.button,
            label: slot.window.title,
            value: 'minimised',
            child: Focus(
              focusNode: slot.chip,
              child: KeyBindings(
                {
                  'enter': () => layer._restore(slot),
                  'space': () => layer._restore(slot),
                },
                hints: const {'enter': 'restore', 'space': 'restore'},
                child: _ChipBuilt(
                  layer,
                  slot,
                  GestureDetector(
                    onTap: (_) => layer._restore(slot),
                    child: Text(
                      ' ${slot.window.title} ',
                      style: slot.chip.hasFocus
                          ? style.merge(theme.selection)
                          : style,
                      wrap: TextWrap.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// [child], telling [layer] as it is first built that [slot]'s chip is
/// in the focus tree, under it.
final class _ChipBuilt extends StatefulWidget {
  const _ChipBuilt(this.layer, this.slot, this.child);

  final _WindowLayerState layer;
  final _Slot slot;
  final Widget child;

  @override
  State<_ChipBuilt> createState() => _ChipBuiltState();
}

final class _ChipBuiltState extends State<_ChipBuilt> {
  @override
  void initState() {
    super.initState();
    widget.layer._chipBuilt(widget.slot);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// [v] within [low] and [high], [high] where [low] is past it.
int _clamp(int v, int low, int high) =>
    v > high ? (high > low ? high : low) : (v < low ? low : v);

/// The smaller of [a] and [b].
int _less(int a, int b) => a < b ? a : b;

/// Where a window shows in a room [width] by [height]: as [c] asks, within
/// [window]'s least size and the room's, moved in from its right and
/// bottom edges; all of it when maximised.
_Rect _fit(WindowController c, Window window, int width, int height) =>
    _fitCells(
      c.left,
      c.top,
      c.width,
      c.height,
      window.minWidth,
      window.minHeight,
      maximised: c.maximised,
      roomWidth: width,
      roomHeight: height,
    );

_Rect _fitCells(
  int left,
  int top,
  int width,
  int height,
  int minWidth,
  int minHeight, {
  required bool maximised,
  required int roomWidth,
  required int roomHeight,
}) {
  if (maximised) {
    return (left: 0, top: 0, width: roomWidth, height: roomHeight);
  }
  final w = _clamp(width, _less(minWidth, roomWidth), roomWidth);
  final h = _clamp(height, _less(minHeight, roomHeight), roomHeight);
  return (
    left: _clamp(left, 0, roomWidth - w),
    top: _clamp(top, 0, roomHeight - h),
    width: w,
    height: h,
  );
}

/// [r] with a top of [_chipRow] on the bottom row of a layer [height]
/// tall.
_Rect _onRow(_Rect r, int height) => r.top == _chipRow
    ? (left: r.left, top: height - 1, width: r.width, height: r.height)
    : r;

/// [k] of the way from [a] to [b], each rounded.
_Rect _lerp(_Rect a, _Rect b, double k) {
  int at(int x, int y) => (x + (y - x) * k).round();
  return (
    left: at(a.left, b.left),
    top: at(a.top, b.top),
    width: at(a.width, b.width),
    height: at(a.height, b.height),
  );
}

/// What a [_RenderWindows] lays out: the layer's child, its windows, its
/// strip.
final class _WindowsLayout extends MultiChildRenderObjectWidget {
  const _WindowsLayout({
    required this.margin,
    required super.children,
    super.key,
  });

  final EdgeInsets margin;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderWindows createRenderObject(BuildContext context) =>
      _RenderWindows(margin);

  @override
  void updateRenderObject(BuildContext context, _RenderWindows renderObject) =>
      renderObject.margin = margin;
}

/// Where a [_Placed] window is, what a [_RenderWindows] keeps on each
/// child: none for the layer's child and its strip.
final class _WindowData extends ParentData with ContainerParentDataMixin {
  var isWindow = false;
  var left = 0;
  var top = 0;
  var width = 0;
  var height = 0;
  var minWidth = 0;
  var minHeight = 0;
  var maximised = false;
  var minimised = false;

  /// What tells its window apart.
  Object? id;

  /// Where it moves from on its way, and to its chip; [progress] of the
  /// way there.
  _Rect? from;
  _Rect? toChip;
  var progress = 1.0;

  /// Where it showed at the last layout, on its way too; whether it was on
  /// its way, when the mouse goes through it.
  _Rect rect = (left: 0, top: 0, width: 0, height: 0);
  var moving = false;

  /// The cells its shadow takes beside it.
  EdgeInsets shadow = EdgeInsets.zero;

  /// Its place in the order the windows are painted in, the one in front
  /// the highest.
  var z = 0;
}

/// Puts where a window is on what shows it in a [_RenderWindows].
final class _Placed extends ParentDataWidget<_WindowData> {
  const _Placed({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.minWidth,
    required this.minHeight,
    required this.maximised,
    required this.minimised,
    required this.shadow,
    required this.z,
    required this.id,
    required this.from,
    required this.toChip,
    required this.progress,
    required super.child,
    super.key,
  });

  final int left;
  final int top;
  final int width;
  final int height;
  final int minWidth;
  final int minHeight;
  final bool maximised;
  final bool minimised;
  final EdgeInsets shadow;
  final int z;
  final Object id;
  final _Rect? from;
  final _Rect? toChip;
  final double progress;

  @override
  void applyParentData(RenderObject renderObject) {
    final at = renderObject.parentData as _WindowData;
    if (at.isWindow &&
        at.left == left &&
        at.top == top &&
        at.width == width &&
        at.height == height &&
        at.minWidth == minWidth &&
        at.minHeight == minHeight &&
        at.maximised == maximised &&
        at.minimised == minimised &&
        at.shadow == shadow &&
        at.z == z &&
        at.id == id &&
        at.from == from &&
        at.toChip == toChip &&
        at.progress == progress) {
      return;
    }
    at
      ..isWindow = true
      ..left = left
      ..top = top
      ..width = width
      ..height = height
      ..minWidth = minWidth
      ..minHeight = minHeight
      ..maximised = maximised
      ..minimised = minimised
      ..shadow = shadow
      ..z = z
      ..id = id
      ..from = from
      ..toChip = toChip
      ..progress = progress;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => WindowLayer;
}

/// Lays the layer's child out as the layer is laid out, the strip, its
/// last child, on its bottom row, and each window between them where it
/// shows in the room above the strip ([_fitCells]), the cells of its
/// shadow and [margin] around it; a minimised one is laid out where it
/// was, but outside the layer, cut off. Paints the child, the windows in
/// their order and the strip, and hits them the other way round; what a
/// repaint boundary repaints on its own has what is painted after it
/// painted over it again.
final class _RenderWindows extends RenderObject
    with ContainerRenderObjectMixin<_WindowData> {
  _RenderWindows(this._margin);

  EdgeInsets _margin;
  EdgeInsets get margin => _margin;
  set margin(EdgeInsets m) {
    if (m != _margin) {
      _margin = m;
      markNeedsLayout();
    }
  }

  /// The room the windows show in at the last layout.
  (int, int) get room => _room;

  /// Where the window [id] showed at the last layout, on its way too; null
  /// for one not shown.
  _Rect? rectOf(Object id) {
    for (final w in _shown) {
      final at = w.parentData as _WindowData;
      if (at.id == id) {
        return at.rect;
      }
    }
    return null;
  }

  var _room = (0, 0);

  // the windows shown, in the order they are painted
  final _shown = <RenderObject>[];

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _WindowData) {
      child.parentData = _WindowData();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = firstChild!;
    final strip = lastChild!;
    child.layout(c, parentUsesSize: true);
    width = c.constrainW(child.width);
    height = c.constrainH(child.height);
    strip.layout(BoxConstraints(0, width, 0, height), parentUsesSize: true);
    strip.parentData
      ..dx = 0
      ..dy = height - strip.height;
    final roomWidth = width;
    final roomHeight = height - strip.height;
    _room = (roomWidth, roomHeight);
    _shown.clear();
    final m = _margin;
    for (var w = childAfter(child); w != null && !identical(w, strip);) {
      final at = w.parentData as _WindowData;
      final fit = _fitCells(
        at.left,
        at.top,
        at.width,
        at.height,
        at.minWidth,
        at.minHeight,
        maximised: at.maximised,
        roomWidth: roomWidth,
        roomHeight: roomHeight,
      );
      final from = at.from;
      final toChip = at.toChip;
      final r = from == null
          ? fit
          : _lerp(
              _onRow(from, height),
              at.minimised && toChip != null ? _onRow(toChip, height) : fit,
              at.progress,
            );
      final shown = !at.minimised || from != null;
      at
        ..rect = r
        ..moving = from != null;
      final s = at.shadow;
      w.layout(
        BoxConstraints.tight(
          r.width + m.horizontal + s.horizontal,
          r.height + m.vertical + s.vertical,
        ),
      );
      at
        ..dx = shown ? r.left - m.left - s.left : width
        ..dy = r.top - m.top - s.top;
      if (shown) {
        _shown.add(w);
      }
      w = at.nextSibling;
    }
    _shown.sort(
      (a, b) => (a.parentData as _WindowData).z.compareTo(
        (b.parentData as _WindowData).z,
      ),
    );
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      firstChild!.getMinIntrinsicWidth(height);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      firstChild!.getMaxIntrinsicWidth(height);

  @override
  int computeMinIntrinsicHeight(int width) =>
      firstChild!.getMinIntrinsicHeight(width);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      firstChild!.getMaxIntrinsicHeight(width);

  @override
  void paint(PaintContext ctx) {
    paintChild(ctx, firstChild!);
    for (final w in _shown) {
      paintChild(ctx, w);
    }
    final strip = lastChild!;
    if (strip.height > 0) {
      paintChild(ctx, strip);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) {
    final strip = lastChild!;
    if (_hits(strip, result, x, y)) {
      return true;
    }
    for (var i = _shown.length - 1; i >= 0; i--) {
      final w = _shown[i];
      // the mouse goes through a window on its way
      if (!(w.parentData as _WindowData).moving && _hits(w, result, x, y)) {
        return true;
      }
    }
    return _hits(firstChild!, result, x, y);
  }

  static bool _hits(RenderObject child, HitTestResult result, int x, int y) {
    final at = child.parentData;
    return child.hitTest(result, x - at.dx, y - at.dy);
  }

  /// The children painted after [child], in order: for the layer's child
  /// the windows shown and the strip, for a window those in front of it
  /// and the strip; none for the strip and a minimised window.
  Iterable<RenderObject> _after(RenderObject child) sync* {
    final strip = lastChild!;
    if (identical(child, strip)) {
      return;
    }
    final from = identical(child, firstChild) ? 0 : _shown.indexOf(child) + 1;
    if (from == 0 && !identical(child, firstChild)) {
      return;
    }
    for (var i = from; i < _shown.length; i++) {
      yield _shown[i];
    }
    yield strip;
  }

  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) =>
      _after(child).any((c) => _reaches(c, x, y, w, h));

  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) {
    for (final c in _after(child)) {
      if (_reaches(c, x, y, w, h)) {
        paintChild(ctx, c);
        _forgetPaint(c);
      }
    }
  }

  /// Whether [c] reaches the cells [x], [y], [w] × [h] of this object.
  static bool _reaches(RenderObject c, int x, int y, int w, int h) {
    final at = c.parentData;
    return c.width > 0 &&
        c.height > 0 &&
        at.dx < x + w &&
        x < at.dx + c.width &&
        at.dy < y + h &&
        y < at.dy + c.height;
  }

  /// Has [o] and everything inside it forget what they painted before.
  static void _forgetPaint(RenderObject o) => o
    ..invalidatePaintCache()
    ..visitChildren(_forgetPaint);
}
