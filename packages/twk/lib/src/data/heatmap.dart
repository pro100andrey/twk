/// Values over a grid of cells, each a shade or a color: [Heatmap], its
/// [HeatmapScale], [ActivityHeatmap] for counts by day, and the
/// [RenderHeatmap] that paints them.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        Canvas,
        Color,
        ColorMode,
        KeyCode,
        KeyEvent,
        KeyKind,
        PaintContext,
        RenderObject,
        TextSegmenter;

import '../editing/caret.dart' show clearRestCursor, restCursor;
import '../focus/focus_tree.dart';
import '../focus/hinted_keys.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/ignore_pointer.dart';
import '../gestures/mouse.dart';
import '../layout/basic.dart';
import '../layout/stack.dart';
import '../overlay/layer.dart';
import '../overlay/tooltip.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/hit_row.dart' show segmenterOf;
import 'chart_glyphs.dart';

// Examples can assume:
// late Map<DateTime, int> commits;
// late List<List<double?>> load;
// void open(DateTime day) {}

/// How a [Heatmap] shows a value between its smallest and its largest:
/// as a shade ([HeatmapScale.shades]) or as a color
/// ([HeatmapScale.colors]).
@immutable
sealed class HeatmapScale {
  const HeatmapScale._();

  /// [glyphs] from the smallest value to the largest, ` ░▒▓█` by default.
  /// The first is for a value at the smallest alone: one above it is at
  /// least the second.
  const factory HeatmapScale.shades([List<String> glyphs]) = HeatmapShades;

  /// [glyph], `■`, in the color of [gradient] at the value: its first
  /// color at the smallest value, its last at the largest. On a terminal
  /// that shows no RGB colors ([ColorMode.trueColor]), the default
  /// [HeatmapScale.shades] in its place. The gradient's direction is not
  /// read.
  const factory HeatmapScale.colors(Gradient gradient, {String glyph}) =
      HeatmapColors;
}

/// A [HeatmapScale] of glyphs: see [HeatmapScale.shades].
final class HeatmapShades extends HeatmapScale {
  /// [glyphs], at least two, from the smallest value to the largest.
  const HeatmapShades([this.glyphs = defaultGlyphs]) : super._();

  /// ` ░▒▓█`: a blank, three shades and a full block.
  static const defaultGlyphs = [' ', '░', '▒', '▓', '█'];

  /// The glyphs, from the smallest value to the largest; each a grapheme.
  final List<String> glyphs;

  @override
  bool operator ==(Object other) =>
      other is HeatmapShades && sameList(other.glyphs, glyphs);

  @override
  int get hashCode => Object.hashAll(glyphs);
}

/// A [HeatmapScale] of colors: see [HeatmapScale.colors].
final class HeatmapColors extends HeatmapScale {
  /// [glyph] in the colors of [gradient].
  const HeatmapColors(this.gradient, {this.glyph = '■'}) : super._();

  /// The colors, from the smallest value to the largest.
  final Gradient gradient;

  /// What a cell shows, in its color; a grapheme.
  final String glyph;

  @override
  bool operator ==(Object other) =>
      other is HeatmapColors &&
      other.gradient == gradient &&
      other.glyph == glyph;

  @override
  int get hashCode => Object.hash(gradient, glyph);
}

/// [rows] × [columns] cells, each the [value] there on the [scale]: from
/// [min], by default the smallest value, to [max], by default the largest;
/// those beyond them as they are. A cell whose value is null (or not
/// finite) is blank: no data.
///
/// A cell is [cellWidth] columns wide, its glyph over all of them but the
/// last, a blank between two cells; one column wide, the glyph alone. A
/// glyph two columns wide (`░` where ambiguous characters are) takes the
/// whole cell; one that does not fit in it is in `.:+#` instead. With
/// [rowLabels], each row starts with its label, the widest and a blank
/// before the cells; with [columnLabels], a row above the cells has the
/// label of a column at its first column, cut off a blank before the next
/// label (an empty label is none: `Oct` over the first week of October
/// runs on over the weeks after it). With [showLegend], a row below the
/// cells says `less ░▒▓█ more` at their right ([legendLabels]). As big as
/// all that, within the constraints.
///
/// With [tooltip] or [onSelected] it is interactive. While it has the
/// focus, a cell is marked in [cursorStyle], the top left one at first:
/// the arrows move it, Enter and Space call [onSelected] with its row and
/// column. Other keys go up to the nodes above its [Focus]. The mouse
/// over a cell shows its [tooltip], at once and while it stays, in a
/// [Tooltip] under the heatmap at the cell's column, where it covers no
/// cell (above it where there is no room below); while the focus is in
/// the heatmap and the mouse elsewhere, that of the marked cell shows. A
/// click on a cell focuses the heatmap, marks the cell and selects it as
/// Enter does. An empty tooltip shows nothing; without an [Overlay] above
/// the heatmap, none shows.
///
/// The styles, each merged over those before it: [style] for every cell,
/// over the theme's background and text; [labelStyle] for the labels and
/// the legend's words; the color of a cell ([HeatmapScale.colors]); and
/// [cursorStyle] for the marked cell while focused. One left null is the
/// theme's: [ThemeData.muted] and [ThemeData.selection].
///
/// A screen reader reads it as a table of the values: a node a row, of the
/// row's label, and in it a node a cell, of the cell's tooltip or else of
/// its column's label and its value (`no data` for none); the marked cell
/// is the focused one.
///
/// A repaint boundary: moving the marked cell repaints nothing else.
///
/// The load of each hour of a week, a row a day, in colors from dark to
/// light green, the hours in a tooltip:
///
/// ```dart
/// Heatmap(
///   rows: 7,
///   columns: 24,
///   value: (row, column) => load[row][column],
///   min: 0,
///   max: 1,
///   scale: const HeatmapScale.colors(
///     Gradient([Color.rgb(14, 68, 41), Color.rgb(57, 211, 83)]),
///   ),
///   rowLabels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
///   tooltip: (row, column) => '$column:00',
/// )
/// ```
///
/// See also:
///
///  * [ActivityHeatmap], counts by day, a column a week.
///  * `Sparkline`, values one after another as bars.
final class Heatmap extends StatefulWidget {
  /// Shows [value] of each of [rows] × [columns] cells on [scale]; asserts
  /// that there are as many [rowLabels] as [rows] and [columnLabels] as
  /// [columns], and that [cellWidth] is at least one.
  const Heatmap({
    required this.rows,
    required this.columns,
    required this.value,
    super.key,
    this.min,
    this.max,
    this.scale = const HeatmapScale.shades(),
    this.rowLabels,
    this.columnLabels,
    this.cellWidth = 2,
    this.showLegend = false,
    this.legendLabels = ('less', 'more'),
    this.tooltip,
    this.onSelected,
    this.focusNode,
    this.autofocus = false,
    this.keyHints = true,
    this.style,
    this.labelStyle,
    this.cursorStyle,
  }) : assert(rows >= 0 && columns >= 0, 'no fewer than no cells'),
       assert(cellWidth >= 1, 'a cell a column wide at least'),
       assert(
         rowLabels == null || rowLabels.length == rows,
         'a label for each row',
       ),
       assert(
         columnLabels == null || columnLabels.length == columns,
         'a label for each column',
       );

  /// How many rows of cells.
  final int rows;

  /// How many cells a row.
  final int columns;

  /// The value of the cell at a row and a column, each from 0; null for
  /// no data. Called for each cell on each paint; a new function repaints.
  final double? Function(int row, int column) value;

  /// The value of the first shade or color; null for the smallest value.
  final double? min;

  /// The value of the last shade or color; null for the largest value.
  final double? max;

  /// The shades or the colors.
  final HeatmapScale scale;

  /// A label at the start of each row; null for none. An empty one leaves
  /// its row unlabelled.
  final List<String>? rowLabels;

  /// A label above each column, running on to the next one that is not
  /// empty; null for none.
  final List<String>? columnLabels;

  /// The columns of a cell, its glyph on all but the last.
  final int cellWidth;

  /// Whether a row below the cells shows the scale between
  /// [legendLabels].
  final bool showLegend;

  /// The words either side of the legend: the smallest values', the
  /// largest values'.
  final (String, String) legendLabels;

  /// What the cell at a row and a column says while the mouse is on it, or
  /// it is marked; null for no tooltips, and an empty one for none there.
  final String Function(int row, int column)? tooltip;

  /// Called with the row and the column of the cell Enter, Space or a click
  /// selected.
  final void Function((int, int) cell)? onSelected;

  /// See [Focus.focusNode]; one of its own when null. It takes the focus
  /// with a [tooltip] or an [onSelected] alone.
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// Whether the keys it takes carry their hints, for a `KeyHintsBar`:
  /// `←↑↓→ move   enter select` while it has the focus.
  final bool keyHints;

  /// Every cell, the theme's background and text under it; its text color
  /// is that of the shades.
  final Style? style;

  /// The labels and the words of the legend; [ThemeData.muted] when null.
  final Style? labelStyle;

  /// The marked cell, while the heatmap has the focus;
  /// [ThemeData.selection] when null.
  final Style? cursorStyle;

  @override
  State<Heatmap> createState() => _HeatmapState();
}

final class _HeatmapState extends State<Heatmap> {
  FocusNode? _ownNode;
  FocusNode? _listened;
  final _tip = TooltipController();

  // what paints the cells, which tells the cell at a place
  RenderHeatmap? _grid;

  // the marked cell; the cell under the mouse, null for none
  var _cursor = (0, 0);
  (int, int)? _hovered;
  var _focused = false;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool get _interactive => widget.tooltip != null || widget.onSelected != null;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(Heatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
    _cursor = _clamp(_cursor);
    if (_hovered case final h? when _clamp(h) != h) {
      _hovered = null;
    }
    _syncLater();
  }

  @override
  void dispose() {
    _listened?.removeListener(_focusChanged);
    _ownNode?.dispose();
    _tip.dispose();
    super.dispose();
  }

  void _listen() {
    final node = _node;
    if (!identical(node, _listened)) {
      _listened?.removeListener(_focusChanged);
      _listened = node..addListener(_focusChanged);
      _focused = node.hasFocus;
    }
  }

  // out of the tree: what the focus and the mouse do there shows nothing
  var _active = true;

  @override
  void deactivate() {
    _active = false;
    _tip.hide();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  void _focusChanged() {
    final focused = _node.hasFocus;
    if (mounted && _active && focused != _focused) {
      setState(() => _focused = focused);
      _syncLater();
    }
  }

  (int, int) _clamp((int, int) cell) {
    int within(int v, int n) => v >= n ? n - 1 : (v < 0 ? 0 : v);
    return (within(cell.$1, widget.rows), within(cell.$2, widget.columns));
  }

  /// The cell whose tooltip shows: the one under the mouse, else the
  /// marked one while focused.
  (int, int)? get _shown {
    if (widget.rows == 0 || widget.columns == 0) {
      return null;
    }
    return _hovered ?? (_focused ? _cursor : null);
  }

  String _message((int, int)? cell) {
    final tooltip = widget.tooltip;
    if (cell == null || tooltip == null) {
      return '';
    }
    return tooltip(cell.$1, cell.$2);
  }

  /// [_sync] once the build under way is done: an overlay is not changed
  /// in a build, which a widget changed or the focus moved in.
  void _syncLater() => scheduleMicrotask(() {
    if (mounted) {
      _sync();
    }
  });

  /// Shows the tooltip of [_shown], or hides it.
  void _sync() {
    if (!_active || _message(_shown).isEmpty) {
      _tip.hide();
    } else {
      _tip.show();
    }
  }

  void _hover(PointerEvent event) {
    final cell = _grid?.cellAt(event.x, event.y);
    if (cell != _hovered) {
      setState(() => _hovered = cell);
      _sync();
    }
  }

  void _exit(PointerEvent event) {
    if (_hovered != null) {
      setState(() => _hovered = null);
      _sync();
    }
  }

  void _tapped(PointerEvent event) {
    final cell = _grid?.cellAt(event.x, event.y);
    if (cell == null || !_node.canRequestFocus) {
      return;
    }
    _node.requestFocus();
    setState(() => _cursor = cell);
    _sync();
    widget.onSelected?.call(cell);
  }

  void _move(int rows, int columns) {
    final cell = _clamp((_cursor.$1 + rows, _cursor.$2 + columns));
    if (cell != _cursor) {
      setState(() => _cursor = cell);
      _sync();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.kind == KeyKind.release ||
        !node.hasFocus ||
        widget.rows == 0 ||
        widget.columns == 0) {
      return KeyEventResult.ignored;
    }
    switch ((event.code, event.modifiers)) {
      case (KeyCode.left, 0):
        _move(0, -1);
      case (KeyCode.right, 0):
        _move(0, 1);
      case (KeyCode.up, 0):
        _move(-1, 0);
      case (KeyCode.down, 0):
        _move(1, 0);
      case (KeyCode.enter, 0):
        widget.onSelected?.call(_cursor);
      case (KeyCode.char, 0) when event.char == ' ':
        widget.onSelected?.call(_cursor);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static const _hints = {
    'left': 'move',
    'up': 'move',
    'down': 'move',
    'right': 'move',
    'enter': 'select',
  };

  static bool _takes(String key) => true;

  List<SemanticsNode> _semantics() {
    final w = widget;
    final rowLabels = w.rowLabels;
    final columnLabels = w.columnLabels;
    return [
      for (var r = 0; r < w.rows; r++)
        SemanticsNode(
          label: rowLabels?[r] ?? 'row ${r + 1}',
          children: [
            for (var c = 0; c < w.columns; c++)
              if (w.tooltip case final tooltip?)
                SemanticsNode(
                  label: tooltip(r, c),
                  focused: _focused && _cursor == (r, c),
                )
              else
                SemanticsNode(
                  label: columnLabels?[c] ?? 'column ${c + 1}',
                  value: switch (w.value(r, c)) {
                    final v? when v.isFinite => formatValue(v),
                    _ => 'no data',
                  },
                  focused: _focused && _cursor == (r, c),
                ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = Theme.of(context);
    final grid = _Grid(
      this,
      style: theme.background.merge(theme.text).merge(w.style ?? _plain),
      labelStyle: w.labelStyle ?? theme.muted,
      cursorStyle: w.cursorStyle ?? theme.selection,
    );
    Widget child = grid;
    final shown = _shown;
    if (_interactive) {
      final message = _message(shown);
      final at = shown ?? _cursor;
      child = MouseRegion(
        onEnter: _hover,
        onHover: _hover,
        onExit: _exit,
        child: GestureDetector(
          onTap: _tapped,
          child: Stack(
            children: [
              grid,
              if (w.tooltip != null && Overlay.maybeOf(context) != null)
                Positioned(
                  // the column of the cell, as tall as the heatmap shows
                  // anything: the tooltip under it, over none of its cells
                  left: _left + at.$2 * w.cellWidth,
                  top: 0,
                  height:
                      (w.columnLabels == null ? 0 : 1) +
                      w.rows +
                      (w.showLegend ? 1 : 0),
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Tooltip(
                        message: message,
                        controller: _tip,
                        showOnHover: false,
                        showOnFocus: false,
                        child: SizedBox(
                          width: w.cellWidth > 1 ? w.cellWidth - 1 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      final node = _node;
      child = HintedKeys(
        node: node,
        hints: w.keyHints ? _hints : const {},
        takes: _takes,
        child: Focus(
          focusNode: node,
          autofocus: w.autofocus,
          canRequestFocus: w.focusNode == null ? true : null,
          onKeyEvent: _onKey,
          child: child,
        ),
      );
    }
    return Semantics(nodes: _semantics(), child: child);
  }

  /// The column the cells start at, as the grid lays them out.
  int get _left => RenderHeatmap._leftOf(
    widget.rowLabels,
    _grid?.owner?.segmenter ?? RenderHeatmap._detached,
  );
}

/// The cells of a [Heatmap] as its state has them, with its theme's styles
/// where it has none, and its marked cell while it has the focus.
final class _Grid extends LeafRenderObjectWidget {
  const _Grid(
    this.state, {
    required this.style,
    required this.labelStyle,
    required this.cursorStyle,
  });

  final _HeatmapState state;
  final Style style;
  final Style labelStyle;
  final Style cursorStyle;

  @override
  RenderHeatmap createRenderObject(BuildContext context) {
    final w = state.widget;
    final grid = RenderHeatmap(
      rows: w.rows,
      columns: w.columns,
      value: w.value,
    );
    updateRenderObject(context, grid);
    return grid;
  }

  @override
  void updateRenderObject(BuildContext context, RenderHeatmap renderObject) {
    final w = state.widget;
    state._grid = renderObject
      ..rows = w.rows
      ..columns = w.columns
      ..value = w.value
      ..min = w.min
      ..max = w.max
      ..scale = w.scale
      ..rowLabels = w.rowLabels
      ..columnLabels = w.columnLabels
      ..cellWidth = w.cellWidth
      ..showLegend = w.showLegend
      ..legendLabels = w.legendLabels
      ..cursor = state._focused && state._interactive ? state._cursor : null
      ..style = style
      ..labelStyle = labelStyle
      ..cursorStyle = cursorStyle;
  }
}

const _plain = Style();

/// What a [Heatmap] lays out and paints: its cells, labels and legend, as
/// [Heatmap] shows them, in the styles given, none of them the theme's.
final class RenderHeatmap extends RenderObject {
  /// Lays out and paints [value] of [rows] × [columns] cells, with the
  /// settings a [Heatmap] has; the styles left out are plain.
  RenderHeatmap({
    required this._rows,
    required this._columns,
    required this._value,
    this._min,
    this._max,
    this._scale = const HeatmapScale.shades(),
    this._rowLabels,
    this._columnLabels,
    this._cellWidth = 2,
    this._showLegend = false,
    this._legendLabels = ('less', 'more'),
    this._cursor,
    this._style = const Style(),
    this._labelStyle = const Style(),
    this._cursorStyle = const Style(attrs: Attr.reverse),
  });

  int _rows;

  /// How many rows of cells, as [Heatmap.rows].
  int get rows => _rows;
  set rows(int n) {
    if (n != _rows) {
      _rows = n;
      markNeedsLayout();
    }
  }

  int _columns;

  /// How many cells a row, as [Heatmap.columns].
  int get columns => _columns;
  set columns(int n) {
    if (n != _columns) {
      _columns = n;
      markNeedsLayout();
    }
  }

  double? Function(int row, int column) _value;

  /// The value of a cell, as [Heatmap.value]; another function repaints.
  double? Function(int row, int column) get value => _value;
  set value(double? Function(int row, int column) f) {
    if (!identical(f, _value)) {
      _value = f;
      markNeedsPaint();
    }
  }

  double? _min;

  /// The value of the first shade, as [Heatmap.min].
  double? get min => _min;
  set min(double? m) {
    if (m != _min) {
      _min = m;
      markNeedsPaint();
    }
  }

  double? _max;

  /// The value of the last shade, as [Heatmap.max].
  double? get max => _max;
  set max(double? m) {
    if (m != _max) {
      _max = m;
      markNeedsPaint();
    }
  }

  HeatmapScale _scale;

  /// The shades or the colors, as [Heatmap.scale].
  HeatmapScale get scale => _scale;
  set scale(HeatmapScale s) {
    if (s != _scale) {
      _scale = s;
      markNeedsLayout();
    }
  }

  List<String>? _rowLabels;

  /// The labels of the rows, as [Heatmap.rowLabels].
  List<String>? get rowLabels => _rowLabels;
  set rowLabels(List<String>? labels) {
    if (!_sameLabels(labels, _rowLabels)) {
      _rowLabels = labels;
      markNeedsLayout();
    }
  }

  List<String>? _columnLabels;

  /// The labels of the columns, as [Heatmap.columnLabels].
  List<String>? get columnLabels => _columnLabels;
  set columnLabels(List<String>? labels) {
    if (!_sameLabels(labels, _columnLabels)) {
      _columnLabels = labels;
      markNeedsLayout();
    }
  }

  int _cellWidth;

  /// The columns of a cell, as [Heatmap.cellWidth].
  int get cellWidth => _cellWidth;
  set cellWidth(int w) {
    if (w != _cellWidth) {
      _cellWidth = w;
      markNeedsLayout();
    }
  }

  bool _showLegend;

  /// Whether a row below the cells shows the scale, as
  /// [Heatmap.showLegend].
  bool get showLegend => _showLegend;
  set showLegend(bool s) {
    if (s != _showLegend) {
      _showLegend = s;
      markNeedsLayout();
    }
  }

  (String, String) _legendLabels;

  /// The words either side of the legend, as [Heatmap.legendLabels].
  (String, String) get legendLabels => _legendLabels;
  set legendLabels((String, String) l) {
    if (l != _legendLabels) {
      _legendLabels = l;
      markNeedsLayout();
    }
  }

  (int, int)? _cursor;

  /// The row and the column of the cell in [cursorStyle]; null for none.
  (int, int)? get cursor => _cursor;
  set cursor((int, int)? c) {
    if (c != _cursor) {
      _cursor = c;
      markNeedsPaint();
    }
  }

  Style _style;

  /// Every cell, the others merged over it.
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  Style _labelStyle;

  /// The labels and the legend's words.
  Style get labelStyle => _labelStyle;
  set labelStyle(Style s) {
    if (s != _labelStyle) {
      _labelStyle = s;
      markNeedsPaint();
    }
  }

  Style _cursorStyle;

  /// The cell of [cursor].
  Style get cursorStyle => _cursorStyle;
  set cursorStyle(Style s) {
    if (s != _cursorStyle) {
      _cursorStyle = s;
      markNeedsPaint();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  static final _detached = TextSegmenter();

  TextSegmenter get _segmenter => owner?.segmenter ?? _detached;

  static bool _sameLabels(List<String>? a, List<String>? b) =>
      a == null || b == null ? identical(a, b) : sameList(a, b);

  /// The widest of [labels].
  static int _widest(List<String> labels, TextSegmenter segmenter) {
    var most = 0;
    for (final label in labels) {
      final w = segmenter.width(label);
      if (w > most) {
        most = w;
      }
    }
    return most;
  }

  // the column the cells start at and the row of the first of them
  int get _left => _leftOf(_rowLabels, _segmenter);

  /// The column the cells start at with [labels] before them: the widest
  /// and a blank.
  static int _leftOf(List<String>? labels, TextSegmenter segmenter) {
    if (labels == null) {
      return 0;
    }
    final widest = _widest(labels, segmenter);
    return widest == 0 ? 0 : widest + 1;
  }

  int get _top => _columnLabels == null ? 0 : 1;

  /// The columns of the cells, the blank after the last left out.
  int get _cellsWidth {
    if (_columns == 0) {
      return 0;
    }
    return _columns * _cellWidth - (_cellWidth > 1 && !_wideGlyphs ? 1 : 0);
  }

  /// Whether a glyph of the scale takes the whole of a cell, its last
  /// column too: then so does the last cell.
  bool get _wideGlyphs {
    if (_cellWidth < 2) {
      return false;
    }
    final seg = _segmenter;
    final glyphs = switch (_scale) {
      HeatmapShades(:final glyphs) => glyphs,
      HeatmapColors(:final glyph) => [glyph, ...HeatmapShades.defaultGlyphs],
    };
    return glyphs.any((g) => seg.width(g) > _cellWidth - 1);
  }

  /// The glyphs of the legend's scale.
  int get _legendSteps => switch (_scale) {
    HeatmapShades(:final glyphs) => glyphs.length,
    HeatmapColors() => HeatmapShades.defaultGlyphs.length,
  };

  int get _legendWidth {
    final (less, more) = _legendLabels;
    final seg = _segmenter;
    return seg.width(less) + 1 + _legendSteps + 1 + seg.width(more);
  }

  int get _naturalWidth {
    var cells = _left + _cellsWidth;
    if (_columnLabels case final labels?) {
      // the last label, which runs on past the cells where it is longer
      for (var c = labels.length - 1; c >= 0; c--) {
        if (labels[c].isNotEmpty) {
          final end = _left + c * _cellWidth + _segmenter.width(labels[c]);
          if (end > cells) {
            cells = end;
          }
          break;
        }
      }
    }
    if (!_showLegend) {
      return cells;
    }
    final legend = _legendWidth;
    return legend > cells ? legend : cells;
  }

  int get _naturalHeight => _top + _rows + (_showLegend ? 1 : 0);

  @override
  int computeMinIntrinsicWidth(int height) => _naturalWidth;

  @override
  int computeMaxIntrinsicWidth(int height) => _naturalWidth;

  @override
  int computeMinIntrinsicHeight(int width) => _naturalHeight;

  @override
  int computeMaxIntrinsicHeight(int width) => _naturalHeight;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_naturalWidth);
    height = c.constrainH(_naturalHeight);
  }

  /// The row and the column of the cell at ([x], [y]), on any of its
  /// columns; null where there is none.
  (int, int)? cellAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return null;
    }
    final col = x - _left;
    final row = y - _top;
    if (col < 0 || row < 0 || row >= _rows || col >= _columns * _cellWidth) {
      return null;
    }
    return (row, col ~/ _cellWidth);
  }

  // the values of the last paint, NaN for none
  var _values = Float64List(0);

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final seg = canvas.segmenter;
    final base = opaque(_style);
    final basePen = base.penIn(styles);
    canvas.fill(0, 0, width, height, basePen);
    final left = _left;
    final top = _top;
    final labelPen = base.merge(_labelStyle).penIn(styles);

    if (_rowLabels case final labels?) {
      for (var r = 0; r < _rows; r++) {
        _clipped(canvas, 0, top + r, left, labels[r], labelPen);
      }
    }
    if (_columnLabels case final labels?) {
      for (var c = 0; c < _columns; c++) {
        if (labels[c].isEmpty) {
          continue;
        }
        var next = c + 1;
        while (next < _columns && labels[next].isEmpty) {
          next++;
        }
        final x = left + c * _cellWidth;
        final room = next < _columns ? (next - c) * _cellWidth - 1 : width - x;
        _clipped(canvas, x, 0, room, labels[c], labelPen);
      }
    }

    // the values, and the range they are shown over
    final n = _rows * _columns;
    if (_values.length != n) {
      _values = Float64List(n);
    }
    final values = _values;
    var lo = _min;
    var hi = _max;
    double? least;
    double? most;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _columns; c++) {
        final v = _value(r, c);
        if (v == null || !v.isFinite) {
          values[r * _columns + c] = double.nan;
          continue;
        }
        values[r * _columns + c] = v;
        if (least == null || v < least) {
          least = v;
        }
        if (most == null || v > most) {
          most = v;
        }
      }
    }
    lo ??= least ?? 0;
    hi ??= most ?? 0;

    final look = _Look.of(_scale, styles.colorMode, seg, _cellWidth);
    final cursor = _cursor;
    // the hidden cursor on the marked cell
    if (cursor case (final r, final c)) {
      restCursor(ctx, this, left + c * _cellWidth, top + r);
    } else {
      clearRestCursor(ctx, this);
    }
    for (var r = 0; r < _rows; r++) {
      final y = top + r;
      for (var c = 0; c < _columns; c++) {
        final x = left + c * _cellWidth;
        final v = values[r * _columns + c];
        final marked = cursor != null && cursor.$1 == r && cursor.$2 == c;
        final cell = marked ? base.merge(_cursorStyle) : base;
        if (marked) {
          canvas.fill(x, y, _cellWidth, 1, cell.penIn(styles));
        }
        if (v.isNaN) {
          continue;
        }
        look.paint(canvas, x, y, _fraction(v, lo, hi), cell);
      }
    }

    if (_showLegend) {
      final (less, more) = _legendLabels;
      final y = top + _rows;
      var x = width - _legendWidth;
      if (x < 0) {
        x = 0;
      }
      canvas.text(x, y, less, labelPen);
      x += seg.width(less) + 1;
      final steps = _legendSteps;
      for (var i = 0; i < steps; i++) {
        look.paintOne(canvas, x + i, y, steps == 1 ? 1 : i / (steps - 1), base);
      }
      x += steps + 1;
      canvas.text(x, y, more, labelPen);
    }
  }

  /// Where [v] is from [lo] (0) to [hi] (1): at or below [lo] 0, at or
  /// above [hi] 1.
  static double _fraction(double v, double lo, double hi) {
    if (v <= lo) {
      return 0;
    }
    if (v >= hi) {
      return 1;
    }
    return (v - lo) / (hi - lo);
  }

  /// [text] at ([x], [y]), cut off at [room] columns.
  static void _clipped(
    Canvas canvas,
    int x,
    int y,
    int room,
    String text,
    int pen,
  ) {
    if (room <= 0 || text.isEmpty) {
      return;
    }
    canvas
      ..save()
      ..clipRect(x, y, room, 1)
      ..text(x, y, text, pen)
      ..restore();
  }
}

/// How the cells of a paint look: the glyphs of a scale as they fit in a
/// cell, and its colors where the terminal shows them.
final class _Look {
  _Look._(this.glyphs, this.widths, this.cellWidth, this.gradient, this.fill);

  /// The look of [scale] on a terminal of [mode], measured by [segmenter],
  /// in cells [cellWidth] columns wide.
  factory _Look.of(
    HeatmapScale scale,
    ColorMode mode,
    TextSegmenter segmenter,
    int cellWidth,
  ) {
    final (glyphs, gradient) = switch (scale) {
      HeatmapColors(:final gradient, :final glyph)
          when mode == ColorMode.trueColor =>
        ([glyph], gradient),
      HeatmapColors() => (HeatmapShades.defaultGlyphs, null),
      HeatmapShades(:final glyphs) => (glyphs, null),
    };
    final shown = <String>[];
    final widths = <int>[];
    var fill = false;
    for (var i = 0; i < glyphs.length; i++) {
      var g = glyphs[i];
      var w = segmenter.width(g);
      if (w < 1 || w > cellWidth) {
        if (gradient != null) {
          // a colored blank in place of a glyph that does not fit
          fill = true;
          g = ' ';
        } else {
          g =
              _ascii[glyphs.length == 1
                  ? _ascii.length - 1
                  : (i * (_ascii.length - 1) / (glyphs.length - 1)).round()];
        }
        w = 1;
      }
      shown.add(g);
      widths.add(w);
    }
    return _Look._(shown, widths, cellWidth, gradient, fill);
  }

  static const _ascii = [' ', '.', ':', '+', '#'];

  final List<String> glyphs;
  final List<int> widths;
  final int cellWidth;

  /// The colors; null for shades.
  final Gradient? gradient;

  /// Whether a cell is a blank on its color, rather than its glyph in it.
  final bool fill;

  int _index(double f) {
    final last = glyphs.length - 1;
    if (last <= 0) {
      return 0;
    }
    // the first glyph at 0 alone
    final i = (f * last).ceil();
    return i > last ? last : (i < 0 ? 0 : i);
  }

  Style _colored(Style style, double f) {
    final g = gradient;
    if (g == null) {
      return style;
    }
    final c = _colorAt(g, f);
    return fill ? style.merge(Style(bg: c)) : style.merge(Style(fg: c));
  }

  /// The cell at ([x], [y]), [f] of the way along the scale, over [style].
  void paint(Canvas canvas, int x, int y, double f, Style style) {
    final i = gradient == null ? _index(f) : 0;
    final glyph = glyphs[i];
    final w = widths[i];
    final pen = _colored(style, f).penIn(canvas.styles);
    final span = cellWidth > 1 ? cellWidth - 1 : 1;
    if (fill) {
      canvas.fill(x, y, span, 1, pen);
      return;
    }
    if (w <= span) {
      for (var at = 0; at + w <= span; at += w) {
        canvas.text(x + at, y, glyph, pen);
      }
    } else {
      canvas.text(x, y, glyph, pen);
    }
  }

  /// One column of the legend at ([x], [y]), [f] of the way along: the
  /// glyph of a cell, or where it is wider than a column, a blank on its
  /// color or its shade in `.:+#`.
  void paintOne(Canvas canvas, int x, int y, double f, Style style) {
    final i = gradient == null ? _index(f) : 0;
    if (gradient case final g? when fill || widths[i] > 1) {
      canvas.fill(
        x,
        y,
        1,
        1,
        style.merge(Style(bg: _colorAt(g, f))).penIn(canvas.styles),
      );
      return;
    }
    final pen = _colored(style, f).penIn(canvas.styles);
    canvas.text(
      x,
      y,
      widths[i] > 1 ? _ascii[(f * (_ascii.length - 1)).round()] : glyphs[i],
      pen,
    );
  }
}

/// The color of [gradient] [f] of the way from its first color (0) to its
/// last (1), between the two stops around it as `Color.lerp` mixes them.
Color _colorAt(Gradient gradient, double f) {
  final colors = gradient.colors;
  final last = colors.length - 1;
  if (last <= 0) {
    return colors[0];
  }
  final stops = gradient.stops;
  double stop(int k) => stops?[k] ?? k / last;
  if (f <= stop(0)) {
    return colors[0];
  }
  for (var k = 0; k < last; k++) {
    final a = stop(k);
    final b = stop(k + 1);
    if (f <= b) {
      return b <= a
          ? colors[k + 1]
          : Color.lerp(colors[k], colors[k + 1], (f - a) / (b - a));
    }
  }
  return colors[last];
}

/// Counts by day as a [Heatmap], a column a week from [firstWeekday] and a
/// row a weekday, the last column the week of [end]: [weeks] weeks, the
/// oldest at the left. A day without a count is at 0, the lowest shade
/// (`·` by default, [defaultScale]); the days after [end] are blank. The
/// largest count is the last shade.
///
/// Every other weekday is labelled from the first (`Mon`, `Wed`, `Fri`,
/// `Sun`, [weekdayNames]), and the month of a week that has its first day
/// over that week (`Oct`, [monthNames]); over the first week too where its
/// name fits before the next.
///
/// The arrows, Enter, Space, the mouse and the tooltips are a [Heatmap]'s:
/// [tooltip] says what a day says, by default `3 on 2026-10-21`;
/// [onSelected] is called with the day selected, local at midnight, the
/// days after [end] not.
///
/// The commits of the last half year, a day opened when it is chosen:
///
/// ```dart
/// ActivityHeatmap(counts: commits, showLegend: true, onSelected: open)
/// ```
final class ActivityHeatmap extends StatelessWidget {
  /// Shows [counts] over the [weeks] weeks up to [end]; asserts that
  /// [firstWeekday] is a weekday, that [weeks] is at least one, and that
  /// there are 7 [weekdayNames] and 12 [monthNames].
  const ActivityHeatmap({
    required this.counts,
    super.key,
    this.end,
    this.weeks = 26,
    this.firstWeekday = DateTime.monday,
    this.tooltip,
    this.scale = defaultScale,
    this.onSelected,
    this.showLegend = false,
    this.legendLabels = ('less', 'more'),
    this.cellWidth = 2,
    this.weekdayNames = englishWeekdayNames,
    this.monthNames = englishMonthNames,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.labelStyle,
    this.cursorStyle,
  }) : assert(
         firstWeekday >= DateTime.monday && firstWeekday <= DateTime.sunday,
         'firstWeekday from DateTime.monday to DateTime.sunday',
       ),
       assert(weeks >= 1, 'a week at least'),
       assert(weekdayNames.length == 7, 'a name for each weekday'),
       assert(monthNames.length == 12, 'a name for each month');

  /// `·░▒▓█`: a dot for no count, so that the weeks show.
  static const defaultScale = HeatmapScale.shades(['·', '░', '▒', '▓', '█']);

  /// Monday to Sunday, three letters each.
  static const englishWeekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// January to December, three letters each.
  static const englishMonthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// The count of each day: of a key it reads the year, the month and the
  /// day, whatever its time and zone; the counts of keys of the same day
  /// are added up.
  final Map<DateTime, num> counts;

  /// The last day shown; null for the day of the build.
  final DateTime? end;

  /// How many weeks, a column each.
  final int weeks;

  /// The weekday of the first row, [DateTime.monday] to
  /// [DateTime.sunday].
  final int firstWeekday;

  /// What a day says on the mouse or marked; null for `3 on 2026-10-21`.
  final String Function(DateTime day, num count)? tooltip;

  /// The shades or the colors; [defaultScale] by default.
  final HeatmapScale scale;

  /// Called with the day Enter, Space or a click selected.
  final void Function(DateTime day)? onSelected;

  /// See [Heatmap.showLegend].
  final bool showLegend;

  /// See [Heatmap.legendLabels].
  final (String, String) legendLabels;

  /// See [Heatmap.cellWidth].
  final int cellWidth;

  /// The weekdays' names, Monday first.
  final List<String> weekdayNames;

  /// The months' names, January first.
  final List<String> monthNames;

  /// See [Heatmap.focusNode].
  final FocusNode? focusNode;

  /// See [Heatmap.autofocus].
  final bool autofocus;

  /// See [Heatmap.style].
  final Style? style;

  /// See [Heatmap.labelStyle].
  final Style? labelStyle;

  /// See [Heatmap.cursorStyle].
  final Style? cursorStyle;

  /// [count] on [day], as `3 on 2026-10-21`.
  static String defaultTooltip(DateTime day, num count) =>
      '${formatValue(count.toDouble())} on ${_iso(day)}';

  @override
  Widget build(BuildContext context) {
    final last = dayOf(end ?? DateTime.now());
    final lastWeek = last - (weekdayOfDay(last) - firstWeekday) % 7;
    final first = lastWeek - (weeks - 1) * 7;
    final byDay = <int, num>{};
    for (final MapEntry(:key, :value) in counts.entries) {
      final day = dayOf(key);
      byDay[day] = (byDay[day] ?? 0) + value;
    }
    int dayAt(int row, int column) => first + column * 7 + row;

    final months = List.filled(weeks, '');
    var firstLabelled = weeks;
    for (var c = 0; c < weeks; c++) {
      final start = first + c * 7;
      for (var d = 0; d < 7; d++) {
        final date = utcOfDay(start + d);
        if (date.day == 1) {
          months[c] = monthNames[date.month - 1];
          if (firstLabelled == weeks) {
            firstLabelled = c;
          }
          break;
        }
      }
    }
    if (months[0].isEmpty) {
      final name = monthNames[utcOfDay(first).month - 1];
      if (firstLabelled * cellWidth > segmenterOf(context).width(name)) {
        months[0] = name;
      }
    }

    final say = tooltip ?? defaultTooltip;
    final select = onSelected;
    return Heatmap(
      rows: 7,
      columns: weeks,
      value: (row, column) {
        final day = dayAt(row, column);
        return day > last ? null : (byDay[day] ?? 0).toDouble();
      },
      min: 0,
      scale: scale,
      rowLabels: [
        for (var r = 0; r < 7; r++)
          if (r.isEven) weekdayNames[(firstWeekday - 1 + r) % 7] else '',
      ],
      columnLabels: months,
      cellWidth: cellWidth,
      showLegend: showLegend,
      legendLabels: legendLabels,
      tooltip: (row, column) {
        final day = dayAt(row, column);
        return day > last ? '' : say(dateOfDay(day), byDay[day] ?? 0);
      },
      onSelected: select == null
          ? null
          : (cell) {
              final day = dayAt(cell.$1, cell.$2);
              if (day <= last) {
                select(dateOfDay(day));
              }
            },
      focusNode: focusNode,
      autofocus: autofocus,
      style: style,
      labelStyle: labelStyle,
      cursorStyle: cursorStyle,
    );
  }
}

/// [date] as `2026-10-21`.
String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
