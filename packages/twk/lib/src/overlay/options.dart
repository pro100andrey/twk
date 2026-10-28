/// Options to choose from, one highlighted, as an autocomplete and a
/// command palette list them: [OptionList].
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        Canvas,
        ClusterScan,
        HitTestBehavior,
        PaintContext,
        RenderObject,
        StyleTable,
        TextSegmenter;

import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../style/style.dart';

// Examples can assume:
// var typed = '';
// void run(int index) {}

/// A row of an [OptionList]: [label], the characters of it at [marks]
/// standing out, and [detail] after it.
///
/// Two equal options are the same row: a list given options equal to
/// those it has is not laid out again.
///
/// ```dart
/// const Option('Open file', marks: [0, 5], detail: 'ctrl+o')
/// ```
@immutable
final class Option {
  /// A row of [label], the characters at [marks] standing out, and
  /// [detail] after it.
  const Option(this.label, {this.marks = const [], this.detail});

  /// What the row says.
  final String label;

  /// Where in [label] the characters that stand out start, in order, as a
  /// `FuzzyMatch` gives them.
  final List<int> marks;

  /// What is said after the label, at the right edge; null for nothing.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is Option &&
      other.label == label &&
      other.detail == detail &&
      sameList(other.marks, marks);

  @override
  int get hashCode => Object.hash(label, detail, Object.hashAll(marks));
}

/// [options] in rows, each its label after a blank, the characters marked
/// in it in the theme's primary color in bold, and its detail in the
/// theme's muted text before a blank at the right edge; [highlighted] in
/// the theme's selection, with [bar] a primary `▎` in its first column, the
/// rest in its surface and text. At most [rows] rows show: from the first,
/// moved on as far as keeps the highlighted one among them; with [thumb],
/// while not all show, a `▐` in the theme's border color down the last
/// column says where those shown are. As wide as the widest row asks for,
/// within its constraints; a label that does not fit is cut off before the
/// detail.
///
/// The mouse: moved onto a row, it calls [onHighlight] with its index (the
/// app highlights it); a button pressed and released on a row calls
/// [onSelected] with it; the wheel calls [onHighlight] with the option
/// after or before the highlighted one. Without them the list takes no
/// mouse.
///
/// The commands that match what is typed, the first highlighted, the
/// characters that match in each marked:
///
/// ```dart
/// OptionList(
///   options: [
///     for (final c in ['Open file', 'Profile'])
///       if (fuzzyMatch(typed, c) case final m?) Option(c, marks: m.positions),
///   ],
///   highlighted: 0,
///   onSelected: run,
/// )
/// ```
final class OptionList extends StatefulWidget {
  /// Lists [options], [highlighted] among them, in [rows] rows at most.
  const OptionList({
    required this.options,
    super.key,
    this.highlighted = -1,
    this.rows = 8,
    this.bar = true,
    this.thumb = true,
    this.onHighlight,
    this.onSelected,
  }) : assert(rows > 0, 'rows below 1');

  /// The rows, in order.
  final List<Option> options;

  /// The option highlighted; -1 for none.
  final int highlighted;

  /// The most rows shown: 8 by default; asserted to be 1 or more.
  final int rows;

  /// Whether the highlighted row has a primary `▎` in its first column.
  final bool bar;

  /// Whether a `▐` down the last column shows where the rows shown are
  /// while not all show.
  final bool thumb;

  /// Called with the option the mouse moved onto, or the wheel moved the
  /// highlight to; null for none.
  final void Function(int index)? onHighlight;

  /// Called with the option clicked; null for none.
  final void Function(int index)? onSelected;

  @override
  State<OptionList> createState() => _OptionListState();
}

final class _OptionListState extends State<OptionList> {
  final GlobalKey _box = GlobalKey();

  // the option a button was pressed on
  int? _pressed;

  _RenderOptionList? get _render =>
      _box.currentContext?.findRenderObject() as _RenderOptionList?;

  int? _at(PointerEvent event) => _render?.optionAt(event.x, event.y);

  void _move(PointerEvent event) {
    final i = _at(event);
    if (i != null && i != widget.highlighted) {
      widget.onHighlight?.call(i);
    }
  }

  void _scroll(PointerEvent event) {
    final n = widget.options.length;
    final step = event.scrollY;
    if (n == 0 || step == 0) {
      return;
    }
    final h = widget.highlighted;
    final to = h < 0 ? (step > 0 ? 0 : n - 1) : (h + step).clamp(0, n - 1);
    if (to != h) {
      widget.onHighlight?.call(to);
    }
  }

  void _up(PointerEvent event) {
    final i = _at(event);
    final pressed = _pressed;
    _pressed = null;
    if (i != null && i == pressed) {
      widget.onSelected?.call(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _OptionListBox(
      key: _box,
      options: widget.options,
      highlighted: widget.highlighted,
      rows: widget.rows,
      bar: widget.bar,
      thumb: widget.thumb,
    );
    if (widget.onHighlight == null && widget.onSelected == null) {
      return list;
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onMove: widget.onHighlight == null ? null : _move,
      onScroll: widget.onHighlight == null ? null : _scroll,
      onDown: widget.onSelected == null
          ? null
          : (event) => _pressed = _at(event),
      onUp: widget.onSelected == null ? null : _up,
      child: list,
    );
  }
}

/// What an [OptionList] draws.
final class _OptionListBox extends LeafRenderObjectWidget {
  const _OptionListBox({
    required this.options,
    required this.highlighted,
    required this.rows,
    required this.bar,
    required this.thumb,
    super.key,
  });

  final List<Option> options;
  final int highlighted;
  final int rows;
  final bool bar;
  final bool thumb;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOptionList(
    options,
    highlighted,
    rows,
    _styles(context),
    bar: bar,
    thumb: thumb,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderOptionList)
        ..options = options
        ..highlighted = highlighted
        ..rows = rows
        ..styles = _styles(context)
        ..bar = bar
        ..thumb = thumb;

  static _Styles _styles(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.surface.merge(theme.text);
    return _Styles(
      base: base,
      highlight: base.merge(theme.selection),
      mark: theme.primary.merge(const Style(attrs: Attr.bold)),
      muted: theme.muted,
      bar: theme.primary,
      thumb: theme.border,
    );
  }
}

/// The styles of an [OptionList]: a row's, the highlighted row's, and
/// what the marks and the details merge over them.
@immutable
final class _Styles {
  const _Styles({
    required this.base,
    required this.highlight,
    required this.mark,
    required this.muted,
    required this.bar,
    required this.thumb,
  });

  final Style base;
  final Style highlight;
  final Style mark;
  final Style muted;
  final Style bar;
  final Style thumb;

  @override
  bool operator ==(Object other) =>
      other is _Styles &&
      other.base == base &&
      other.highlight == highlight &&
      other.mark == mark &&
      other.muted == muted &&
      other.bar == bar &&
      other.thumb == thumb;

  @override
  int get hashCode => Object.hash(base, highlight, mark, muted, bar, thumb);
}

/// What an [OptionList] lays out and paints.
final class _RenderOptionList extends RenderObject {
  _RenderOptionList(
    this._options,
    this._highlighted,
    this._rows,
    this._styles, {
    required this._bar,
    required this._thumb,
  });

  List<Option> _options;
  List<Option> get options => _options;
  set options(List<Option> o) {
    if (!sameList(o, _options)) {
      _options = o;
      markNeedsLayout();
    }
  }

  int _highlighted;
  int get highlighted => _highlighted;
  set highlighted(int h) {
    if (h != _highlighted) {
      _highlighted = h;
      markNeedsPaint();
    }
  }

  int _rows;
  int get rows => _rows;
  set rows(int r) {
    if (r != _rows) {
      _rows = r;
      markNeedsLayout();
    }
  }

  _Styles _styles;
  _Styles get styles => _styles;
  set styles(_Styles s) {
    if (s != _styles) {
      _styles = s;
      markNeedsPaint();
    }
  }

  bool _bar;
  bool get bar => _bar;
  set bar(bool b) {
    if (b != _bar) {
      _bar = b;
      markNeedsPaint();
    }
  }

  bool _thumb;
  bool get thumb => _thumb;
  set thumb(bool t) {
    if (t != _thumb) {
      _thumb = t;
      markNeedsPaint();
    }
  }

  // the first option shown
  var _top = 0;

  /// The option shown at the cell [x], [y] of the list, as it last
  /// painted; null where there is none.
  int? optionAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return null;
    }
    final i = _top + y;
    return i < _options.length ? i : null;
  }

  // the columns of the widest label and the widest detail
  var _labels = 0;
  var _details = 0;

  int _measure() {
    final segmenter = owner?.segmenter ?? TextSegmenter();
    _labels = 0;
    _details = 0;
    for (final option in _options) {
      final l = segmenter.width(option.label);
      if (l > _labels) {
        _labels = l;
      }
      final d = segmenter.width(option.detail ?? '');
      if (d > _details) {
        _details = d;
      }
    }
    return 1 + _labels + (_details > 0 ? 2 + _details : 0) + 1;
  }

  int get _shown => _options.length < _rows ? _options.length : _rows;

  @override
  int computeMinIntrinsicWidth(int height) => _measure();

  @override
  int computeMaxIntrinsicWidth(int height) => _measure();

  @override
  int computeMinIntrinsicHeight(int width) => _shown;

  @override
  int computeMaxIntrinsicHeight(int width) => _shown;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_measure());
    height = c.constrainH(_shown);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final n = _options.length;
    final h = height;
    final w = width;
    final h0 = _highlighted;
    if (h0 >= 0 && h0 < _top) {
      _top = h0;
    } else if (h0 >= _top + h) {
      _top = h0 - h + 1;
    }
    if (_top > n - h) {
      _top = n - h < 0 ? 0 : n - h;
    }
    final s = _styles;
    for (var row = 0; row < h; row++) {
      final i = _top + row;
      final style = i == h0 ? s.highlight : s.base;
      final pen = style.penIn(styles);
      canvas.fill(0, row, w, 1, pen);
      if (i >= n) {
        continue;
      }
      final option = _options[i];
      var labelEnd = w - 1;
      final detail = option.detail;
      if (detail != null && detail.isNotEmpty) {
        final dw = canvas.segmenter.width(detail);
        labelEnd = w - 3 - dw;
        canvas
          ..save()
          ..clipRect(1, row, w - 2, 1)
          ..text(w - 1 - dw, row, detail, style.merge(s.muted).penIn(styles))
          ..restore();
      }
      canvas
        ..save()
        ..clipRect(1, row, labelEnd - 1, 1);
      _paintLabel(canvas, styles, row, option, style);
      canvas.restore();
      if (i == h0 && _bar && w > 0) {
        canvas.text(0, row, '▎', style.merge(s.bar).penIn(styles));
      }
    }
    if (_thumb && n > h && h > 0 && w > 0) {
      // as long as the share of the rows shown, where they are
      final th = (h * h / n).round().clamp(1, h);
      final ty = (_top / (n - h) * (h - th)).round();
      for (var row = ty; row < ty + th; row++) {
        final i = _top + row;
        final under = i == h0 ? s.highlight : s.base;
        canvas.text(w - 1, row, '▐', under.merge(s.thumb).penIn(styles));
      }
    }
  }

  /// Paints the label of [option] on [row] in [style], its marks in the
  /// mark style merged over it.
  void _paintLabel(
    Canvas canvas,
    StyleTable styles,
    int row,
    Option option,
    Style style,
  ) {
    final label = option.label;
    final pen = style.penIn(styles);
    final marked = style.merge(_styles.mark).penIn(styles);
    final scan = ClusterScan();
    var x = 1;
    var from = 0;
    for (final at in option.marks) {
      if (at < from || at >= label.length) {
        continue;
      }
      canvas.segmenter.scan(label, at, scan);
      x += canvas.text(x, row, label.substring(from, at), pen);
      x += canvas.text(x, row, label.substring(at, scan.end), marked);
      from = scan.end;
    }
    canvas.text(x, row, label.substring(from), pen);
  }
}
