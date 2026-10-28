/// Where a screen is in a hierarchy, on one row, each level a link up:
/// [Breadcrumbs].
library;

import 'package:twk_core/twk_core.dart' show Attr, TextSegmenter, fitText;

import '../controls/pressable.dart';
import '../focus/focus.dart';
import '../framework/framework.dart';
import '../overlay/menu.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/hit_row.dart';

/// The path of [items] to where a screen is, root first, on one row:
/// `Root › Projects › my_app › lib › src › widgets`, each but the
/// [current] one a link that calls [onSelected] with its index.
///
/// Where the row does not fit, the items in the middle are collapsed into
/// one `…`: the first [keepLeading] are kept, then `…`, then as many of
/// the last as fit, `Root › … › src › widgets`; the items are hidden from
/// the inside out, those after the leading ones first. Where even the
/// last one does not fit after them, the leading ones go too,
/// `… › widgets`, and then the last is cut off with `…`. Never wrapped.
///
/// The [current] item, the last when null, is where the screen is: shown
/// in [currentStyle], the theme's text in bold when null, and no link.
/// With [onSelected] null the crumbs are shown only: in the theme's text,
/// taking neither the focus nor the mouse.
///
/// One stop of Tab. While it has the focus one crumb is highlighted, at
/// first the one before the current, the way up: Left and Right move the
/// highlight to the link before and after it, Home and End to the first
/// and the last; Enter selects the highlighted one. The `…` is a stop of
/// its own: Enter on it, or a click, opens a [Menu] of the items it hides
/// ([showContextMenu]), under the row, or under the `…` when clicked,
/// whose items select them. A click on a link selects it; the mouse over
/// a link underlines it. Left, Right and Enter are hinted.
///
/// The styles, each merged over the theme's text: [style] for the links
/// and the `…`, [ThemeData.primary] when null; [currentStyle] for the
/// current one; [ThemeData.muted] for the [separator]s;
/// [ThemeData.selection] for the highlighted crumb while it has the focus.
///
/// A screen reader reads it as a [SemanticsRole.list] of every item, the
/// hidden ones too: each a [SemanticsRole.link] of its label, the current
/// one a [SemanticsRole.listItem], `selected`; while it has the focus, the
/// highlighted one is the focused node.
///
/// The folders above a file, each opening its own listing:
///
/// ```dart
/// final path = ValueNotifier(['Root', 'Projects', 'my_app', 'lib', 'src']);
/// final view = ValueListenableBuilder(
///   valueListenable: path,
///   builder: (context, items, _) => Breadcrumbs(
///     items: items,
///     onSelected: (i) => path.value = items.sublist(0, i + 1),
///   ),
/// );
/// ```
///
/// See also:
///
///  * `Pagination`, the pages of a long list on one row.
///  * `TabBar`, the views of a screen side by side.
final class Breadcrumbs extends StatefulWidget {
  /// The path of [items], root first; shown only when [onSelected] is
  /// null.
  const Breadcrumbs({
    required this.items,
    super.key,
    this.onSelected,
    this.current,
    this.separator = ' › ',
    this.keepLeading = 1,
    this.focusNode,
    this.style,
    this.currentStyle,
  });

  /// The levels of the path, the root first.
  final List<String> items;

  /// Called with the index of the item selected; null for crumbs shown
  /// only.
  final void Function(int index)? onSelected;

  /// The index of the item where the screen is, which is no link; the
  /// last when null.
  final int? current;

  /// What is between two crumbs.
  final String separator;

  /// How many of the first items are kept before the `…` where the row
  /// does not fit.
  final int keepLeading;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// The links and the `…`; [ThemeData.primary] when null.
  final Style? style;

  /// The current item; the theme's text in bold when null.
  final Style? currentStyle;

  @override
  State<Breadcrumbs> createState() => _BreadcrumbsState();
}

/// A crumb as laid out: the item `index` it shows, or with `hidden` not
/// empty the `…` of those items.
typedef _Stop = ({int index, List<int> hidden});

final class _BreadcrumbsState extends State<Breadcrumbs> {
  /// The item highlighted, the last a `…` hides standing for it; -1
  /// before one is.
  var _highlight = -1;

  /// The crumbs as last laid out.
  var _stops = const <_Stop>[];

  /// Where each crumb of [_stops] is along the row, and the one the mouse
  /// is over.
  final _hits = HitRow();

  List<String> get _items => widget.items;

  int get _current {
    final n = _items.length;
    final current = widget.current ?? n - 1;
    return current < 0 || current >= n ? n - 1 : current;
  }

  /// Whether there is a link: an item other than the current one.
  bool get _enabled => widget.onSelected != null && _items.length > 1;

  /// Whether the crumb [stop] can be selected, or opened.
  bool _link(_Stop stop) => stop.hidden.isNotEmpty || stop.index != _current;

  @override
  void didUpdateWidget(Breadcrumbs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.items;
    final b = widget.items;
    var same = a.length == b.length;
    for (var i = 0; same && i < a.length; i++) {
      same = a[i] == b[i];
    }
    if (!same) {
      _highlight = -1;
      _hits.hovered = -1;
    }
  }

  /// The crumb of [stops] that stands for [index], the `…` for one it
  /// hides; -1 for none.
  static int _stopOf(List<_Stop> stops, int index) {
    for (var s = 0; s < stops.length; s++) {
      final stop = stops[s];
      if (stop.hidden.isEmpty
          ? stop.index == index
          : stop.hidden.contains(index)) {
        return s;
      }
    }
    return -1;
  }

  /// The item highlighted: [_highlight] while it is a link, else the one
  /// before the current one, the way up, else the first link; -1 for none.
  int get _item {
    final n = _items.length;
    final current = _current;
    final h = _highlight;
    if (h >= 0 && h < n && h != current) {
      return h;
    }
    if (current > 0) {
      return current - 1;
    }
    return n > 1 ? 1 : -1;
  }

  /// The link [step] crumbs of [_stops] on from [from], not round; -1 for
  /// none.
  int _next(int from, int step) {
    for (var s = from + step; s >= 0 && s < _stops.length; s += step) {
      if (_link(_stops[s])) {
        return s;
      }
    }
    return -1;
  }

  /// Highlights the crumb [s] of [_stops]: its item, or the last a `…`
  /// hides.
  void _moveTo(int s) {
    if (s < 0) {
      return;
    }
    final stop = _stops[s];
    final item = stop.hidden.isEmpty ? stop.index : stop.hidden.last;
    if (item != _highlight) {
      setState(() => _highlight = item);
    }
  }

  void _move(int step) {
    final from = _stopOf(_stops, _item);
    if (from >= 0) {
      _moveTo(_next(from, step));
    }
  }

  /// Selects the crumb [s] of [_stops], or opens the menu of those its
  /// `…` hides, at the cell [at] of the row or with it null under the row.
  void _select(int s, {(int, int)? at}) {
    final onSelected = widget.onSelected;
    if (onSelected == null || s < 0 || s >= _stops.length) {
      return;
    }
    final stop = _stops[s];
    if (!_link(stop)) {
      return;
    }
    _moveTo(s);
    if (stop.hidden.isEmpty) {
      onSelected(stop.index);
      return;
    }
    showContextMenu(context, [
      for (final i in stop.hidden)
        MenuItem(
          _items[i].replaceAll('&', '&&'),
          onSelected: () => onSelected(i),
        ),
    ], at: at);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final current = _current;
    final pressable = Pressable(
      enabled: enabled,
      focusNode: widget.focusNode,
      bindings: {
        'left': () => _move(-1),
        'right': () => _move(1),
        'home': () => _moveTo(_next(-1, 1)),
        'end': () => _moveTo(_next(_stops.length, -1)),
        'enter': () => _select(_stopOf(_stops, _item)),
      },
      hints: const {'left': 'previous', 'right': 'next', 'enter': 'open'},
      onTap: enabled
          ? (event) {
              final s = _hits.at(event.x);
              if (s >= 0) {
                _select(s, at: (_hits.startOf(s), 1));
              }
            }
          : null,
      builder: (context, focused) => LayoutBuilder(
        builder: (context, constraints) => _row(
          Theme.of(context),
          segmenterOf(context),
          constraints.maxW,
          enabled: enabled,
          focused: focused,
        ),
      ),
    );
    final highlighted = enabled ? _item : -1;
    return Semantics(
      role: SemanticsRole.list,
      nodes: [
        for (var i = 0; i < _items.length; i++)
          SemanticsNode(
            role: enabled && i != current
                ? SemanticsRole.link
                : SemanticsRole.listItem,
            label: _items[i],
            state: SemanticsState(selected: i == current),
            focused: i == highlighted,
          ),
      ],
      child: pressable,
    );
  }

  /// The row in [theme], [width] columns at most as [segmenter] measures
  /// them, each crumb a target of [_hits].
  Widget _row(
    ThemeData theme,
    TextSegmenter segmenter,
    int width, {
    required bool enabled,
    required bool focused,
  }) {
    final row = theme.text;
    final link = enabled
        ? row.merge(widget.style ?? theme.primary)
        : row.merge(widget.style ?? const Style());
    final here = row.merge(
      widget.currentStyle ?? const Style(attrs: Attr.bold),
    );
    final between = row.merge(theme.muted);
    final crumbs = _fit(
      segmenter,
      _items,
      widget.separator,
      widget.keepLeading,
      width,
    );
    final current = _current;
    final stops = [
      for (final (index, hidden, _) in crumbs) (index: index, hidden: hidden),
    ];
    _stops = stops;
    final highlight = enabled && focused ? _stopOf(stops, _item) : -1;
    final spans = <HitSpan>[];
    for (final (s, stop) in stops.indexed) {
      if (s > 0) {
        spans.add((span: Span(widget.separator, between), target: -1));
      }
      final isLink = enabled && _link(stop);
      var style = isLink
          ? link
          : stop.hidden.isNotEmpty
          ? between
          : stop.index == current
          ? here
          : link;
      if (s == highlight) {
        style = style.merge(focusedRow(theme));
      } else if (isLink && s == _hits.hovered) {
        style = style.merge(const Style(attrs: Attr.underline));
      }
      spans.add((span: Span(crumbs[s].$3, style), target: s));
    }
    return _hits.row(
      spans,
      segmenter,
      style: row,
      onHover: enabled ? (_) => setState(() {}) : null,
    );
  }
}

/// The crumbs of [items] that fit in [width] columns with [separator]
/// between them, as [segmenter] measures them: each the index of its
/// item, the indices a `…` hides (none for an item), and its text.
List<(int, List<int>, String)> _fit(
  TextSegmenter segmenter,
  List<String> items,
  String separator,
  int keepLeading,
  int width,
) {
  final n = items.length;
  if (n == 0) {
    return const [];
  }
  final widths = [for (final item in items) segmenter.width(item)];
  final sep = segmenter.width(separator);
  final gap = segmenter.width('…');
  int span(int from, int to) {
    var w = 0;
    for (var i = from; i < to; i++) {
      w += widths[i];
    }
    return w;
  }

  List<(int, List<int>, String)> crumbs(int lead, int tail) => [
    for (var i = 0; i < lead; i++) (i, const <int>[], items[i]),
    if (tail > lead) (lead, [for (var i = lead; i < tail; i++) i], '…'),
    for (var i = tail; i < n; i++) (i, const <int>[], items[i]),
  ];

  if (span(0, n) + sep * (n - 1) <= width) {
    return crumbs(0, 0);
  }
  final keep = keepLeading.clamp(0, n - 1);
  for (var lead = keep; lead >= 0; lead--) {
    // the leading ones, the … and the last ones from [tail]
    for (var tail = lead + 1; tail < n; tail++) {
      final count = lead + 1 + n - tail;
      final w = span(0, lead) + gap + span(tail, n) + sep * (count - 1);
      if (w <= width) {
        return crumbs(lead, tail);
      }
    }
  }
  // the last one alone after a …, cut off
  final last = items[n - 1];
  final room = n > 1 ? width - gap - sep : width;
  return [
    if (n > 1) (0, [for (var i = 0; i < n - 1; i++) i], '…'),
    (n - 1, const <int>[], fitText(segmenter, last, room)),
  ];
}
