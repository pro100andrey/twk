/// Text selected with the mouse: a [SelectionArea] lets the [Text]s below
/// it, and the [Selectable]s, be selected across, by characters, words and
/// lines, and copies what is selected to the clipboard (OSC 52).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;

import 'package:twk_core/twk_core.dart'
    show
        Axis,
        HitTestBehavior,
        RenderObject,
        RenderParagraph,
        clipboardSequence;

import '../binding/app_binding.dart';
import '../editing/text_editing.dart' show TextBoundaries;
import '../focus/focus.dart' show KeyBindings, KeyCombo;
import '../foundation/change_notifier.dart';
import '../foundation/controller_host.dart';
import '../framework/framework.dart';
import '../scroll/scrollable.dart' show ScrollPosition, Scrollable;
import '../style/style.dart';
import '../text/widgets.dart' show Text;
import 'gesture_detector.dart';
import 'mouse.dart';
import 'selectable.dart';

export 'selectable.dart' hide selectInSelectable;

/// Lets the [Text]s below it be selected with the left button, as in a
/// terminal, and copies what is selected to the clipboard.
///
/// Dragging from one cell to another selects the characters between them,
/// those of both cells too, across the Texts in the order of the tree (each
/// one's text in order, whatever rows it wraps to); a double click selects
/// the word under the mouse (or the run of blanks), a triple click the
/// line, between the line breaks of its Text, and a drag after either goes
/// on by words or by lines. The first press of a click clears the
/// selection, and so does [clearKey]; a click is the next of a double or
/// triple one when it comes in the same cell within [multiClickInterval] of
/// the release before it. A render object of an app's own that is a
/// [Selectable] (a painted log, a code view) is selected in as a Text is,
/// in its place in the order of the tree.
///
/// A drag past the top or bottom of the vertical [Scrollable] the mouse
/// selects in scrolls it on, every 50 ms while it stays there, by the rows
/// it is past (3 at most), the selection going on to what comes under the
/// mouse; past those of a [Selectable] that scrolls itself
/// ([Selectable.scrollSelectionBy]), that one first. Past the left or
/// right edge, the horizontal one scrolls sideways so, by the columns
/// ([Selectable.scrollSelectionAcross]), and past a corner both do. The
/// Scrollable is the nearest one of that axis around the Text or
/// Selectable nearest the mouse, inside the area or around it. Where the
/// view starts at the screen's first row or column or ends at its last,
/// the mouse going no further, that one counts as past it, as the edge of
/// a terminal's window does. What scrolls under the mouse while it stays
/// (the wheel turned with the button held) is selected on to as well, as
/// a terminal's selection goes on.
///
/// What is selected is drawn in [style] merged onto the style of the text,
/// by default the [ThemeData.selection] of the [Theme] above. It is copied
/// to the system clipboard (`clipboardSequence`, OSC 52, wrapped for tmux
/// or GNU screen when the app runs inside one) on the release that selected
/// it with [copyOnRelease], and by [copyKey]; [onCopy] is told what was
/// copied. The Texts are joined by line breaks; with [trimTrailingBlanks],
/// the blanks that end a line are left out, as a terminal leaves them out,
/// and [copyTransform] makes of that what is copied. While something is
/// selected, [copyKey] and [clearKey] are among the keys a `KeyHintsBar`
/// shows (`copy`, `clear`). A [controller] tells whether something is
/// selected and what, and clears it, from outside.
///
/// It gets every press over it, anywhere in its bounds, as a [Listener]
/// does, and the drags no `GestureDetector` inside it takes: one that
/// drags, inside, keeps its own. A press in a `TextField` or a `TextArea`
/// is the field's: it clears the selection here and selects nothing,
/// double and triple ones too, the field selecting in its own text. A
/// drag that leaves it goes on selecting to the Text nearest the mouse.
/// While mounted, it has the terminal report presses and drags, which
/// keeps the terminal's own selection from working over the app; in the
/// inline mode the mouse stays the terminal's, and nothing is selected
/// here.
///
/// A transcript whose lines are selected across and copied on the
/// release, Alt+C copying again:
///
/// ```dart
/// SelectionArea(
///   copyKey: 'alt+c',
///   child: ListView(
///     children: const [
///       Text('> make'),
///       Text('build ok'),
///       Text('3 tests passed'),
///     ],
///   ),
/// )
/// ```
///
/// See also:
///
///  * [SelectionAreaController], what is selected, read from outside.
///  * [Selectable], a render object of an app's own selected in.
final class SelectionArea extends StatefulWidget {
  /// Lets the Texts and Selectables below [child] be selected.
  const SelectionArea({
    required this.child,
    this.style,
    this.copyOnRelease = true,
    this.copyKey,
    this.clearKey = 'escape',
    this.trimTrailingBlanks = true,
    this.onCopy,
    this.copyTransform,
    this.controller,
    this.multiClickInterval = const Duration(milliseconds: 300),
    super.key,
  });

  /// Merged onto the style of the text selected; the theme's selection by
  /// default.
  final Style? style;

  /// Copies what a press selected when it is released.
  final bool copyOnRelease;

  /// A key that copies what is selected, named as [KeyCombo.parse] reads
  /// it (`'alt+c'`), bound around [child] as [KeyBindings] binds keys:
  /// with nothing selected it passes on. Null for none. `'ctrl+shift+c'`
  /// fires only with the kitty keyboard protocol: other terminals send it
  /// as Ctrl+C.
  final String? copyKey;

  /// A key that clears the selection, named as [copyKey] is: Escape by
  /// default. With nothing selected it passes on (a dialog's Escape still
  /// closes it). Null for none.
  final String? clearKey;

  /// Whether what is copied leaves out the blanks that end each line: those
  /// before a line break, and at the end of what is selected those only
  /// blanks follow up to the end of its line. True by default, as
  /// terminals copy (xterm, VTE, kitty, Alacritty, WezTerm, tmux's copy
  /// mode): the blanks a line ends in are padding more often than text, and
  /// copied they trail every line pasted.
  final bool trimTrailingBlanks;

  /// Told the text copied.
  final void Function(String text)? onCopy;

  /// Turns what is selected, joined and trimmed as [trimTrailingBlanks]
  /// says, into what is copied, on a release, by [copyKey] and as
  /// [SelectionAreaController.text] gives it: a prompt's marker left out,
  /// the blanks that end what is selected dropped too. What it makes empty
  /// is not copied. Null copies what is selected as it is.
  final String Function(String text)? copyTransform;

  /// Tells whether something is selected and what, and clears it, from
  /// outside the area: when what it shows changes, or by a key bound
  /// elsewhere. One area at a time.
  final SelectionAreaController? controller;

  /// How long after a release a press in the same cell is the next click
  /// of a double or triple click.
  final Duration multiClickInterval;

  /// What holds the Texts selected in.
  final Widget child;

  @override
  State<SelectionArea> createState() => _SelectionAreaState();
}

/// What a [SelectionArea] it is given to has selected, read and cleared
/// from outside the area: a view that shows other text clears it, and so
/// may a key bound wherever the focus is.
///
/// Its listeners are called when something comes to be selected and when
/// nothing is any more ([hasSelection]), not as a drag changes what is.
/// Given to no area, or to one no longer mounted, nothing is selected.
/// Given to an area built in place of its area (a key changed), it reads
/// what the new one selects.
///
/// A key bound around the app that clears what is selected, wherever the
/// focus is:
///
/// ```dart
/// final selection = SelectionAreaController();
/// final app = KeyBindings(
///   {'ctrl+l': selection.clear},
///   child: SelectionArea(
///     controller: selection,
///     child: const Text('select me'),
///   ),
/// );
/// ```
final class SelectionAreaController with ChangeNotifier {
  final _hosts = ControllerHost<_SelectionAreaState>();

  /// Whether anything is selected.
  bool get hasSelection => _hosts.host?._selected.isNotEmpty ?? false;

  /// What is selected as the area copies it ([SelectionArea.copyTransform]
  /// included); empty while nothing is.
  String get text => _hosts.host?._text ?? '';

  /// Clears the selection, a drag under way selecting nothing more.
  void clear() => _hosts.host?._clear();

  /// [area] serves the controller, in place of the area that did, if any:
  /// where one of them has something selected and the other not, the
  /// listeners are told after the build.
  void _attach(_SelectionAreaState area) {
    final old = _hosts.attach(area);
    if ((old?._selected.isNotEmpty ?? false) != area._selected.isNotEmpty) {
      _hosts.afterBuild(_changed);
    }
  }

  /// [area] lets go of the controller: where no area takes it over and
  /// something was selected, the listeners are told after the build.
  void _detach(_SelectionAreaState area) =>
      _hosts.detach(area, area._selected.isNotEmpty ? _changed : null);

  void _changed() => notifyListeners();

  @override
  void dispose() {
    _hosts.dispose();
    super.dispose();
  }
}

/// What is selected in below the area (the paragraph of a [Text], a
/// [Selectable]), and the cell of the area its top left is at.
typedef _Placed = ({RenderObject object, int x, int y});

/// Where a selection starts or ends: a paragraph or a [Selectable], which
/// one it is in the order of the tree, and the range of its text a click
/// there selects (a character, a word, a line).
typedef _Edge = ({RenderObject object, int index, int start, int end});

/// A scrollable view: its position, and the render object it shows its
/// content in.
typedef _Scroller = ({ScrollPosition position, RenderObject viewport});

/// The nearest vertical and the nearest horizontal scrollable view around
/// what is selected in, if any.
typedef _Scrollers = ({_Scroller? vertical, _Scroller? horizontal});

/// How often a drag past the edge of a view scrolls it.
const _edgeInterval = Duration(milliseconds: 50);

final class _SelectionAreaState extends State<SelectionArea> {
  // the paragraphs of the Texts that registered with this area
  final _mine = Expando<bool>();

  // what is selected of each paragraph or Selectable, in the order of the
  // tree; those whose selection changed since the version before; and the
  // style it is drawn in
  var _selected = <RenderObject, (int, int)>{};
  var _changed = <RenderObject>{};
  var _version = 0;
  // the version the last build told the Texts of: those changed by later
  // selections are told together by the next
  var _built = 0;
  Style? _style;

  // the clicks of a double or triple click so far, where the last press
  // was, and a timer from its release while the next can be one more
  var _clicks = 0;
  (int, int)? _clickedAt;
  Timer? _interval;

  // where the press under way started its selection, by characters (1),
  // words (2) or lines (3); and whether it selected anything
  _Edge? _anchor;
  var _unit = 1;
  var _selectedByPress = false;

  // the cell of the screen the mouse is at in the press under way (the area
  // may move under it, scrolled); the timer scrolling a view while it is
  // past its edge, and the one looking again at what is under the mouse
  // while a drag stays; the view around the object last asked for
  (int, int)? _at;
  Timer? _edge;
  Timer? _watch;
  (RenderObject, _Scrollers)? _scroller;

  /// What is selected as it is copied: the Texts joined by line breaks,
  /// trimmed, and transformed ([SelectionArea.copyTransform]).
  String get _text {
    final text = [
      for (final MapEntry(key: p, value: (s, e)) in _selected.entries)
        if (p.owner != null)
          _copied(_textOf(p), s, e, trim: widget.trimTrailingBlanks),
    ].join('\n');
    final transform = widget.copyTransform;
    return transform == null || text.isEmpty ? text : transform(text);
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(SelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _interval?.cancel();
    _stopDrag();
    for (final o in _selected.keys) {
      if (o is Selectable) {
        selectInSelectable(o, null, const Style());
      }
    }
    super.dispose();
  }

  /// The paragraphs of this area's Texts and the [Selectable]s below it, in
  /// the order of the tree, each where it is in the area.
  List<_Placed> _placed() {
    final placed = <_Placed>[];
    void visit(RenderObject o, int x, int y) {
      if (o is RenderParagraph && (_mine[o] ?? false)) {
        if (o.width > 0 && o.height > 0) {
          placed.add((object: o, x: x, y: y));
        }
        return;
      }
      if (o is Selectable &&
          o.width > 0 &&
          o.height > 0 &&
          o.selectableText.isNotEmpty) {
        placed.add((object: o, x: x, y: y));
      }
      o.visitChildren(
        (c) => visit(c, x + c.parentData.dx, y + c.parentData.dy),
      );
    }

    final root = context.findRenderObject();
    if (root != null) {
      visit(root, 0, 0);
    }
    return placed;
  }

  /// The edge a click at [x], [y] of the area makes by [_unit]: in the
  /// paragraph there, or else in the nearest one, by rows first.
  _Edge? _edgeAt(List<_Placed> placed, int x, int y) {
    var best = -1;
    var bestRows = 0;
    var bestColumns = 0;
    for (var i = 0; i < placed.length; i++) {
      final (:object, x: left, y: top) = placed[i];
      final rows = _outside(y, top, object.height);
      final columns = _outside(x, left, object.width);
      if (best < 0 ||
          rows < bestRows ||
          (rows == bestRows && columns < bestColumns)) {
        best = i;
        bestRows = rows;
        bestColumns = columns;
      }
    }
    if (best < 0) {
      return null;
    }
    final (:object, x: left, y: top) = placed[best];
    final lx = x - left;
    final ly = y - top;
    final text = _textOf(object);
    var (start, end) = _rangeAt(object, lx, ly);
    switch (_unit) {
      case 2 when start < end:
        (start, end) = _wordAt(text, start, end);
      case 3:
        final last = object.height - 1;
        final (s, _) = _rangeAt(object, -1, ly < 0 ? 0 : min(ly, last));
        (start, end) = _lineAt(text, s);
      case _:
    }
    return (object: object, index: best, start: start, end: end);
  }

  void _down(PointerEvent event) {
    if (event.button != 0) {
      return;
    }
    final tracker = MouseTracker.of(context);
    if (tracker != null && _taken[tracker] == tracker.presses) {
      // a text field's press: it selects in the field, nothing here
      _interval?.cancel();
      _clicks = 0;
      _clickedAt = null;
      _anchor = null;
      _selectedByPress = false;
      _select(const {});
      return;
    }
    final at = (event.screenX, event.screenY);
    final again = (_interval?.isActive ?? false) && _clickedAt == at;
    _interval?.cancel();
    _clicks = again ? _clicks % 3 + 1 : 1;
    _clickedAt = at;
    _unit = _clicks;
    _selectedByPress = false;
    _stopDrag();
    _at = (event.screenX, event.screenY);
    _scroller = null;
    final placed = _placed();
    final anchor = _anchor = _edgeAt(placed, event.x, event.y);
    if (_clicks == 1 || anchor == null) {
      _select(const {});
    } else {
      _selectTo(placed, anchor);
    }
  }

  void _drag(DragDetails details) {
    if (_anchor == null) {
      return;
    }
    _at = (details.event.screenX, details.event.screenY);
    _track();
    // what scrolls under the mouse while it stays (the wheel) is selected
    // on to, as a terminal's selection goes on
    _watch ??= Timer.periodic(_edgeInterval, (_) {
      if (_edge == null) {
        _track();
      }
    });
  }

  /// Selects on to what is under the mouse, scrolling on the view it is
  /// past the edge of while it stays there.
  void _track() {
    final focus = _follow();
    if (focus != null && _edge == null && _scrollPast(focus)) {
      _edge = Timer.periodic(_edgeInterval, (_) {
        // what the last step scrolled under the mouse is laid out by now
        final focus = _follow();
        if (focus == null || !_scrollPast(focus)) {
          _stopEdge();
        }
      });
    }
  }

  void _up(PointerEvent event) {
    if (event.button != 0) {
      return;
    }
    _stopDrag();
    if (_selectedByPress || _clicks > 1) {
      // what came under the mouse since it moved last (the view scrolled
      // under it)
      _follow();
    }
    _at = null;
    _scroller = null;
    _interval = Timer(widget.multiClickInterval, () {});
    if (widget.copyOnRelease && _selectedByPress) {
      _copy();
    }
  }

  /// Selects from the anchor to what is under the mouse now; what that is
  /// in, and where.
  _Placed? _follow() {
    final at = _mouse();
    if (_anchor == null || at == null) {
      return null;
    }
    final placed = _placed();
    final focus = _edgeAt(placed, at.$1, at.$2);
    if (focus == null) {
      return null;
    }
    _selectTo(placed, focus);
    return placed[focus.index];
  }

  /// The cell of the area the mouse is at, as the area was laid out last.
  (int, int)? _mouse() {
    final at = _at;
    final root = context.findRenderObject();
    if (at == null || root == null) {
      return null;
    }
    final (x, y) = _offsetOf(root);
    return (at.$1 - x, at.$2 - y);
  }

  void _stopEdge() {
    _edge?.cancel();
    _edge = null;
  }

  /// Stops the timers of a drag: the one scrolling past an edge, the one
  /// looking again at what is under the mouse.
  void _stopDrag() {
    _stopEdge();
    _watch?.cancel();
    _watch = null;
  }

  /// Scrolls on the views the mouse is past the edge of, if it is, for
  /// [focus], what it selects in: up or down [focus] itself when it is a
  /// [Selectable] that scrolls, else the vertical [Scrollable] around it,
  /// and sideways [focus] when it scrolls so, else the horizontal one.
  /// Whether anything scrolled.
  bool _scrollPast(_Placed focus) {
    final at = _mouse();
    final root = context.findRenderObject();
    if (at == null || root == null) {
      return false;
    }
    final (areaLeft, areaTop) = _offsetOf(root);
    var screen = root;
    for (var p = root.parent; p != null; p = p.parent) {
      screen = p;
    }
    int down(int top, int extent) =>
        _pastEdge(at.$2, top, extent, areaTop, screen.height);
    int across(int left, int extent) =>
        _pastEdge(at.$1, left, extent, areaLeft, screen.width);
    final o = focus.object;
    var rows = false;
    var columns = false;
    if (o is Selectable) {
      final dy = down(focus.y, o.height);
      rows = dy != 0 && o.scrollSelectionBy(dy);
      final dx = across(focus.x, o.width);
      columns = dx != 0 && o.scrollSelectionAcross(dx);
    }
    final (:vertical, :horizontal) = _scrollersOf(o);
    if (!rows && vertical != null) {
      final (:position, :viewport) = vertical;
      final top = _offsetOf(viewport).$2 - areaTop;
      rows = _scrollOn(position, down(top, viewport.height));
    }
    if (!columns && horizontal != null) {
      final (:position, :viewport) = horizontal;
      final left = _offsetOf(viewport).$1 - areaLeft;
      columns = _scrollOn(position, across(left, viewport.width));
    }
    return rows || columns;
  }

  /// The nearest vertical and horizontal [Scrollable]s around [o], one of
  /// the objects selected in: inside the area or around it.
  _Scrollers _scrollersOf(RenderObject o) {
    if (_scroller case (final of, final scrollers) when identical(of, o)) {
      return scrollers;
    }
    Element? found;
    void visit(Element e) {
      if (found != null) {
        return;
      }
      if (e is RenderObjectElement && identical(e.renderObject, o)) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    _Scroller? vertical;
    _Scroller? horizontal;
    // the position of the nearest Scrollable above `at`, and that one
    for (var at = found; at != null;) {
      final position = Scrollable.maybeOf(at);
      Element? scrollable;
      at.visitAncestorElements((a) {
        if (a.widget is! Scrollable) {
          return true;
        }
        scrollable = a;
        return false;
      });
      final viewport = scrollable?.findRenderObject();
      if (position == null || viewport == null) {
        break;
      }
      final scroller = (position: position, viewport: viewport);
      if (position.axis == Axis.vertical) {
        vertical ??= scroller;
      } else {
        horizontal ??= scroller;
      }
      if (vertical != null && horizontal != null) {
        break;
      }
      at = scrollable;
    }
    final scrollers = (vertical: vertical, horizontal: horizontal);
    _scroller = (o, scrollers);
    return scrollers;
  }

  /// Selects from the anchor to [focus], whichever comes first in the
  /// order of the tree, both included.
  void _selectTo(List<_Placed> placed, _Edge focus) {
    final anchor = _anchor!;
    final a = placed.indexWhere((p) => identical(p.object, anchor.object));
    if (a < 0) {
      _select(const {});
      return;
    }
    final aFirst =
        a < focus.index || (a == focus.index && anchor.start <= focus.start);
    final (from, start) = aFirst
        ? (a, anchor.start)
        : (focus.index, focus.start);
    final aLast =
        a > focus.index || (a == focus.index && anchor.end >= focus.end);
    final (to, end) = aLast ? (a, anchor.end) : (focus.index, focus.end);
    final selected = <RenderObject, (int, int)>{};
    for (var i = from; i <= to; i++) {
      final p = placed[i].object;
      final s = i == from ? start : 0;
      final e = i == to ? end : _textOf(p).length;
      if (s < e) {
        selected[p] = (s, e);
      }
    }
    _select(selected);
    _selectedByPress = _selected.isNotEmpty;
  }

  /// Selects [selected]: the Texts whose part changed are built again, the
  /// Selectables told.
  void _select(Map<RenderObject, (int, int)> selected) {
    final changed = <RenderObject>{
      for (final MapEntry(:key, :value) in selected.entries)
        if (_selected[key] != value) key,
      for (final p in _selected.keys)
        if (!selected.containsKey(p)) p,
    };
    if (changed.isEmpty) {
      return;
    }
    for (final o in changed) {
      if (o is Selectable) {
        selectInSelectable(o, selected[o], _style ?? const Style());
      }
    }
    final had = _selected.isNotEmpty;
    setState(() {
      _selected = Map.of(selected);
      _changed = _built == _version ? changed : {..._changed, ...changed};
      _version++;
    });
    if (widget.controller case final controller?
        when had != selected.isNotEmpty && controller._hosts.isHost(this)) {
      controller._changed();
    }
  }

  /// Clears the selection, a drag under way selecting nothing more.
  void _clear() {
    _stopDrag();
    _anchor = null;
    _selectedByPress = false;
    _select(const {});
  }

  /// Copies what is selected, if anything is, to the system clipboard.
  void _copy() {
    final text = _text;
    final terminal = AppBinding.maybeOf(context)?.twkApp.terminal;
    if (text.isEmpty || terminal == null) {
      return;
    }
    terminal.write(
      ascii.encode(
        clipboardSequence(text, multiplexer: terminal.info.multiplexer),
      ),
    );
    widget.onCopy?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? Theme.of(context).selection;
    if (style != _style) {
      _style = style;
      _changed = {if (_built != _version) ..._changed, ..._selected.keys};
      _version++;
      for (final MapEntry(:key, :value) in _selected.entries) {
        if (key is Selectable) {
          selectInSelectable(key, value, style);
        }
      }
    }
    _built = _version;
    final selected = _selected.isNotEmpty;
    final copy = widget.copyKey;
    final clear = widget.clearKey == copy ? null : widget.clearKey;
    return KeyBindings(
      {
        ?copy: selected ? _copy : null,
        ?clear: selected ? _clear : null,
      },
      hints: {
        if (selected && copy != null) copy: 'copy',
        if (selected && clear != null) clear: 'clear',
      },
      child: Listener(
        onDown: _down,
        onUp: _up,
        behavior: HitTestBehavior.translucent,
        child: GestureDetector(
          onDragUpdate: _drag,
          behavior: HitTestBehavior.translucent,
          child: _SelectionScope(
            this,
            version: _version,
            style: style,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The columns or rows [at] is outside [start, start + extent): 0 inside.
int _outside(int at, int start, int extent) => at < start
    ? start - at
    : (at >= start + extent ? at - (start + extent) + 1 : 0);

/// The rows (or columns) [at] is past the view whose rows are [start] to
/// [start] + [extent], in the area's rows: less than 0 above it (left of
/// it), more than 0 below (right), 3 at most. [areaStart] is the row of the
/// screen the area's first is, [screenExtent] the screen's rows: where the
/// view starts at the screen's first row, that row counts as past it, and
/// where it ends at its last, that one.
int _pastEdge(int at, int start, int extent, int areaStart, int screenExtent) {
  final first = areaStart + start <= 0 ? start + 1 : start;
  final last = areaStart + start + extent >= screenExtent
      ? start + extent - 2
      : start + extent - 1;
  final d = at < first ? at - first : (at > last ? at - last : 0);
  return d < -3 ? -3 : (d > 3 ? 3 : d);
}

/// Scrolls [position] on by [by]; whether it moved.
bool _scrollOn(ScrollPosition position, int by) {
  if (by == 0) {
    return false;
  }
  final from = position.offset;
  position.jumpTo(from + by);
  return position.offset != from;
}

/// Where [o] is from the top left of the screen, as last laid out.
(int, int) _offsetOf(RenderObject o) {
  var x = 0;
  var y = 0;
  for (RenderObject? p = o; p != null; p = p.parent) {
    x += p.parentData.dx;
    y += p.parentData.dy;
  }
  return (x, y);
}

/// The text of [o], a paragraph or a [Selectable]: the paragraph's spans
/// joined.
String _textOf(RenderObject o) => switch (o) {
  final Selectable s => s.selectableText,
  final RenderParagraph p => p.spans.map((s) => s.$1).join(),
  _ => '',
};

/// The range of the text of [o] the cell [x], [y] of it stands for.
(int, int) _rangeAt(RenderObject o, int x, int y) => switch (o) {
  final Selectable s => s.selectableRangeAt(x, y),
  final RenderParagraph p => p.textRangeAt(x, y),
  _ => (0, 0),
};

/// [text] from [start] to [end] as copied, as much of it as there is:
/// with [trim], the blanks that end a line left out, those before a line
/// break and at the end those only blanks follow to the end of the line.
String _copied(String text, int start, int end, {required bool trim}) {
  final s = min(start, text.length);
  final e = min(end, text.length);
  if (!trim) {
    return text.substring(s, e);
  }
  final out = StringBuffer();
  var from = s;
  for (var i = s; i <= e; i++) {
    final atBreak = i < e && _breaksLine(text.codeUnitAt(i));
    if (i < e && !atBreak) {
      continue;
    }
    var to = i;
    if (atBreak || _blanksToLineEnd(text, e)) {
      while (to > from && _blankAt(text, to - 1)) {
        to--;
      }
    }
    out.write(text.substring(from, to));
    if (atBreak) {
      out.writeCharCode(text.codeUnitAt(i));
      from = i + 1;
    }
  }
  return out.toString();
}

/// Whether only blanks follow [at] in [text] up to the end of its line.
bool _blanksToLineEnd(String text, int at) {
  for (var i = at; i < text.length; i++) {
    if (_breaksLine(text.codeUnitAt(i))) {
      return true;
    }
    if (!_blankAt(text, i)) {
      return false;
    }
  }
  return true;
}

/// The word of [text] the cluster [start, end) is in, or the run of blanks
/// it is in.
(int, int) _wordAt(String text, int start, int end) {
  if (!_blankAt(text, start)) {
    return (text.wordStartBefore(end), text.wordEndAfter(start));
  }
  var s = start;
  var e = end;
  while (s > 0 && _blankAt(text, s - 1)) {
    s--;
  }
  while (e < text.length && _blankAt(text, e)) {
    e++;
  }
  return (s, e);
}

/// Whether the code unit of [text] at [i] is a blank that breaks no line.
bool _blankAt(String text, int i) {
  final c = text.codeUnitAt(i);
  return c == 0x20 ||
      c == 0x09 ||
      c == 0xA0 ||
      c == 0x3000 ||
      (c >= 0x2000 && c <= 0x200A);
}

/// The line of [text] [offset] is in, between the line breaks around it.
(int, int) _lineAt(String text, int offset) {
  var s = offset;
  while (s > 0 && !_breaksLine(text.codeUnitAt(s - 1))) {
    s--;
  }
  var e = offset;
  while (e < text.length && !_breaksLine(text.codeUnitAt(e))) {
    e++;
  }
  return (s, e);
}

/// Whether [c] breaks a line (LF, CR, VT, FF, NEL, LS, PS).
bool _breaksLine(int c) =>
    (c >= 0x0A && c <= 0x0D) || c == 0x85 || c == 0x2028 || c == 0x2029;

/// What the [Text]s below a [SelectionArea] find it by.
final class _SelectionScope extends InheritedWidget {
  const _SelectionScope(
    this.area, {
    required this.version,
    required this.style,
    required super.child,
  });

  final _SelectionAreaState area;
  final int version;
  final Style style;

  @override
  InheritedElement createElement() => _SelectionScopeElement(this);

  @override
  bool updateShouldNotify(_SelectionScope oldWidget) =>
      version != oldWidget.version || !identical(area, oldWidget.area);
}

/// Tells only the Texts whose part selected changed.
final class _SelectionScopeElement extends InheritedElement {
  _SelectionScopeElement(_SelectionScope super.widget);

  @override
  void notifyDependent(_SelectionScope oldWidget, Element dependent) {
    final scope = widget as _SelectionScope;
    if (!identical(scope.area, oldWidget.area) ||
        scope.area._changed.contains(dependent.findRenderObject())) {
      super.notifyDependent(oldWidget, dependent);
    }
  }
}

// How a text field keeps its presses from the SelectionArea above it;
// hidden from the library's exports.

// the press of each app's mouse a field took, by its number
// (MouseTracker.presses)
final _taken = Expando<int>();

/// Takes the press under way of [tracker]'s app from the [SelectionArea]s
/// it was hit in: they clear their selection and select nothing by it.
/// Called by the press's [Listener] below them, which gets it first.
void takePressFromSelectionArea(MouseTracker tracker) =>
    _taken[tracker] = tracker.presses;

// How a Text takes part in the SelectionArea above it; hidden from the
// library's exports.

/// Makes [paragraph], the one of the [Text] at [context], selectable in the
/// [SelectionArea] above [context], if there is one, which [context] then
/// depends on.
void addToSelectionArea(BuildContext context, RenderParagraph paragraph) {
  final scope = context.dependOnInheritedWidgetOfExactType<_SelectionScope>();
  if (scope != null) {
    scope.area._mine[paragraph] = true;
  }
}

/// The part of the text of [paragraph] selected in the [SelectionArea]
/// above [context], offsets into its spans joined, and the style it is
/// merged with; null when none is.
(int, int, Style)? selectedInSelectionArea(
  BuildContext context,
  RenderParagraph paragraph,
) {
  final scope = context.dependOnInheritedWidgetOfExactType<_SelectionScope>();
  final range = scope?.area._selected[paragraph];
  if (scope == null || range == null) {
    return null;
  }
  final (start, end) = range;
  return (start, end, scope.style);
}
