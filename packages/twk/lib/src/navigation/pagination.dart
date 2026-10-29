/// The pages of a long list on one row, to go from one to another:
/// [Pagination].
library;

import 'package:twk_core/twk_core.dart' show Attr, TextSegmenter;

import '../controls/pressable.dart';
import '../focus/focus.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/hit_row.dart';

/// The [pageCount] pages of a list loaded a page at a time, from an API
/// or a database, on one row, the [page] shown among them:
/// `« First ‹ Prev 1 [2] 3 4 5 … 42 Next › Last »  (21–40 of 840)`.
///
/// The first and the last page are always there, the current one
/// between brackets with [siblings] pages on either side of it, and `…`
/// for the pages between them and the ends; a gap of one page shows that
/// page instead, so the row keeps as many pages wherever the current one
/// is. With [showFirstLast] and [showPrevNext], `« First` and `Last »`,
/// `‹ Prev` and `Next ›` go to the first, the last, the page before and
/// the page after; they are muted, and do nothing, where there is none
/// to go to. With both [itemCount] and [pageSize] given, the items of the
/// page shown follow, `(21–40 of 840)`.
///
/// Fits the width it gets: where the row does not fit, the words of the
/// arrows go first, `« ‹ 1 [2] 3 4 5 … 42 › »`, then the siblings one by
/// one, then the range of items; past that it is cut off at the right.
/// Never wrapped.
///
/// Changing the page calls [onChanged] with the new one, from 0; the app
/// loads it and builds the row with it. Disabled when [onChanged] is
/// null, all of it muted: then it takes neither the focus, which Tab
/// passes by, nor the mouse.
///
/// One stop of Tab. While it has the focus: Left and Right go to the
/// page before and after, PageUp and PageDown ten pages back and on,
/// Home and End to the first and the last; digits typed show after the
/// row, `→ 12`, and Enter goes to that page (the last where there are
/// fewer), Backspace takes the last digit back and Escape, or any other
/// key, drops them. A click on a page or an arrow goes there; the mouse
/// over one underlines it. Left, Right, the digits and, while some are
/// typed, Enter are hinted.
///
/// The styles, each merged over the theme's text: [style] for the row;
/// [currentStyle] for the current page, [ThemeData.primary] in bold when
/// null; [ThemeData.selection] over it while the row has the focus;
/// [ThemeData.muted] for what cannot be pressed, the `…` and the range.
///
/// A screen reader reads it as a [SemanticsRole.list] of
/// [SemanticsRole.button]s: the arrows, `First page`, `Previous page`,
/// `Next page`, `Last page`, `disabled` where they go nowhere, and the
/// pages shown, `Page 2`, the current one `selected` and, while the row
/// has the focus, the focused node; then the range.
///
/// The pages of a table of 840 rows, 20 a page:
///
/// ```dart
/// final page = ValueNotifier(1);
/// final view = ValueListenableBuilder(
///   valueListenable: page,
///   builder: (context, value, _) => Pagination(
///     page: value,
///     pageCount: 42,
///     itemCount: 840,
///     pageSize: 20,
///     onChanged: (value) => page.value = value,
///   ),
/// );
/// ```
///
/// See also:
///
///  * `Breadcrumbs`, the path to where a screen is.
///  * `ListView`, which scrolls a list that is loaded whole.
final class Pagination extends StatefulWidget {
  /// The [pageCount] pages, [page] the one shown; disabled when
  /// [onChanged] is null.
  const Pagination({
    required this.page,
    required this.pageCount,
    required this.onChanged,
    super.key,
    this.itemCount,
    this.pageSize,
    this.siblings = 1,
    this.showFirstLast = true,
    this.showPrevNext = true,
    this.focusNode,
    this.style,
    this.currentStyle,
  });

  /// The page shown, from 0.
  final int page;

  /// How many pages there are.
  final int pageCount;

  /// Called with the page to go to, from 0; null for a disabled row.
  final void Function(int page)? onChanged;

  /// How many items there are in all; with [pageSize], the range of the
  /// page's items is shown.
  final int? itemCount;

  /// How many items a page has; with [itemCount], the range of the page's
  /// items is shown.
  final int? pageSize;

  /// How many pages are shown on either side of the current one, where
  /// they fit.
  final int siblings;

  /// Whether `« First` and `Last »` are shown.
  final bool showFirstLast;

  /// Whether `‹ Prev` and `Next ›` are shown.
  final bool showPrevNext;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// The row, the theme's text under it.
  final Style? style;

  /// The current page; [ThemeData.primary] in bold when null.
  final Style? currentStyle;

  @override
  State<Pagination> createState() => _PaginationState();
}

/// What a part of the row is.
enum _Kind { first, prev, page, gap, next, last, range, typed }

/// A part of the row: what it is, its text, and the page it goes to (-1
/// for none).
typedef _Part = ({_Kind kind, String text, int to});

final class _PaginationState extends State<Pagination> {
  /// The digits typed, of a page to go to.
  var _typed = '';

  /// The parts of the row as last laid out.
  var _parts = const <_Part>[];

  /// Where each part of [_parts] is along the row, and the one the mouse
  /// is over.
  final _hits = HitRow();

  FocusNode? _own;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(Pagination oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.focusNode, oldWidget.focusNode)) {
      (oldWidget.focusNode ?? _own)?.removeListener(_focusChanged);
      _node.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_focusChanged);
    _own?.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_node.hasFocus && _typed.isNotEmpty) {
      setState(() => _typed = '');
    }
  }

  int get _count => widget.pageCount < 0 ? 0 : widget.pageCount;

  int get _page => widget.page.clamp(0, _count > 0 ? _count - 1 : 0);

  bool get _enabled => widget.onChanged != null && _count > 0;

  /// Goes to [page], within the pages, where that is another one; the
  /// digits typed dropped.
  void _go(int page) {
    final onChanged = widget.onChanged;
    if (_typed.isNotEmpty) {
      setState(() => _typed = '');
    }
    if (onChanged == null || _count == 0) {
      return;
    }
    final to = page.clamp(0, _count - 1);
    if (to != _page) {
      onChanged(to);
    }
  }

  void _digit(int digit) {
    final typed = _typed == '0' ? '$digit' : '$_typed$digit';
    // no more digits than the last page has
    if (typed.length <= '$_count'.length) {
      setState(() => _typed = typed);
    }
  }

  void _enter() {
    final n = int.tryParse(_typed);
    if (n != null) {
      _go((n < 1 ? 1 : n) - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final page = _page;
    final count = _count;
    final typing = _typed.isNotEmpty;
    final pressable = Pressable(
      enabled: enabled,
      focusNode: _node,
      bindings: {
        'left': () => _go(page - 1),
        'right': () => _go(page + 1),
        'pageup': () => _go(page - 10),
        'pagedown': () => _go(page + 10),
        'home': () => _go(0),
        'end': () => _go(count - 1),
        for (var d = 0; d <= 9; d++) '$d': () => _digit(d),
        if (typing) ...{
          'enter': _enter,
          'backspace': () =>
              setState(() => _typed = _typed.substring(0, _typed.length - 1)),
          'escape': () => setState(() => _typed = ''),
        },
      },
      hints: {
        'left': 'previous',
        'right': 'next',
        '0': '…9 page',
        if (typing) 'enter': 'go',
      },
      onTap: enabled
          ? (event) {
              final i = _hits.at(event.x);
              if (i >= 0 && _parts[i].to >= 0) {
                _go(_parts[i].to);
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
    final range = _range();
    return Semantics(
      role: SemanticsRole.list,
      nodes: [
        if (widget.showFirstLast) _button('First page', enabled && page > 0),
        if (widget.showPrevNext) _button('Previous page', enabled && page > 0),
        for (final p in _pages(page, count, widget.siblings))
          if (p >= 0)
            SemanticsNode(
              role: SemanticsRole.button,
              label: 'Page ${p + 1}',
              state: SemanticsState(selected: p == page, disabled: !enabled),
              focused: p == page,
            ),
        if (widget.showPrevNext)
          _button('Next page', enabled && page < count - 1),
        if (widget.showFirstLast)
          _button('Last page', enabled && page < count - 1),
        if (range != null) SemanticsNode(label: range),
      ],
      child: pressable,
    );
  }

  static SemanticsNode _button(String label, bool enabled) => SemanticsNode(
    role: SemanticsRole.button,
    label: label,
    state: SemanticsState(disabled: !enabled),
  );

  /// The range of the page's items, `21–40 of 840`, where there is one.
  String? _range() {
    final items = widget.itemCount;
    final size = widget.pageSize;
    if (items == null || size == null) {
      return null;
    }
    final first = _page * size + 1;
    final last = (_page + 1) * size;
    if (items <= 0 || size <= 0 || first > items) {
      return '0 of ${items < 0 ? 0 : items}';
    }
    return '$first–${last < items ? last : items} of $items';
  }

  /// The parts of the row with the words of the arrows or not, [siblings]
  /// pages either side of the current one, and the range or not.
  List<_Part> _layout({
    required bool words,
    required int siblings,
    required bool range,
  }) {
    final page = _page;
    final count = _count;
    final atStart = page <= 0;
    final atEnd = page >= count - 1;
    final parts = <_Part>[];
    void add(_Kind kind, String text, int to) =>
        parts.add((kind: kind, text: text, to: to));
    if (widget.showFirstLast) {
      add(_Kind.first, words ? '« First' : '«', atStart ? -1 : 0);
    }
    if (widget.showPrevNext) {
      add(_Kind.prev, words ? '‹ Prev' : '‹', atStart ? -1 : page - 1);
    }
    for (final p in _pages(page, count, siblings)) {
      if (p < 0) {
        add(_Kind.gap, '…', -1);
      } else if (p == page) {
        add(_Kind.page, '[${p + 1}]', -1);
      } else {
        add(_Kind.page, '${p + 1}', p);
      }
    }
    if (widget.showPrevNext) {
      add(_Kind.next, words ? 'Next ›' : '›', atEnd ? -1 : page + 1);
    }
    if (widget.showFirstLast) {
      add(_Kind.last, words ? 'Last »' : '»', atEnd ? -1 : count - 1);
    }
    final items = range ? _range() : null;
    if (items != null) {
      add(_Kind.range, ' ($items)', -1);
    }
    if (_typed.isNotEmpty) {
      add(_Kind.typed, ' → $_typed', -1);
    }
    return parts;
  }

  /// The parts that fit in [width] columns as [segmenter] measures them, a
  /// blank between two: the words of the arrows dropped first, then the
  /// siblings one by one, then the range.
  List<_Part> _fit(TextSegmenter segmenter, int width) {
    bool fits(List<_Part> parts) {
      var w = parts.length - 1;
      for (final part in parts) {
        w += segmenter.width(part.text);
      }
      return w <= width;
    }

    var parts = _layout(words: true, siblings: widget.siblings, range: true);
    if (fits(parts)) {
      return parts;
    }
    for (var s = widget.siblings < 0 ? 0 : widget.siblings; s >= 0; s--) {
      parts = _layout(words: false, siblings: s, range: true);
      if (fits(parts)) {
        return parts;
      }
    }
    return _layout(words: false, siblings: 0, range: false);
  }

  /// The row in [theme], [width] columns at most as [segmenter] measures
  /// them, each part a target of [_hits].
  Widget _row(
    ThemeData theme,
    TextSegmenter segmenter,
    int width, {
    required bool enabled,
    required bool focused,
  }) {
    final row = theme.text.merge(widget.style ?? const Style());
    final muted = row.merge(theme.muted);
    final current = row.merge(widget.currentStyle ?? markStyle(theme));
    final parts = _fit(segmenter, width);
    _parts = parts;
    final spans = <HitSpan>[];
    var lit = -1;
    for (final (i, part) in parts.indexed) {
      if (i > 0) {
        spans.add((span: Span(' ', row), target: -1));
      }
      final live = enabled && part.to >= 0;
      var style = switch (part.kind) {
        _Kind.page when part.to < 0 => enabled ? current : muted,
        _Kind.typed => row.merge(theme.selection),
        _ => live ? row : muted,
      };
      if (part.kind == _Kind.page && part.to < 0 && enabled && focused) {
        style = style.merge(focusedRow(theme));
        lit = i;
      } else if (live && i == _hits.hovered) {
        style = style.merge(const Style(attrs: Attr.underline));
      }
      spans.add((span: Span(part.text, style), target: i));
    }
    return _hits.row(
      spans,
      segmenter,
      style: row,
      onHover: enabled ? (_) => setState(() {}) : null,
      // the hidden cursor on the current page
      active: lit,
    );
  }
}

/// The pages shown of [count], [page] the current one, from 0, with
/// [siblings] either side of it: the first and the last always, -1 for a
/// gap between them and the siblings, the page itself where the gap would
/// be one page; as many in all wherever [page] is, where there are as
/// many pages.
List<int> _pages(int page, int count, int siblings) {
  if (count <= 0) {
    return const [];
  }
  final s = siblings < 0 ? 0 : siblings;
  // from 1, the first and the last a boundary each
  final current = page + 1;
  var start = current - s;
  if (start > count - 2 * s - 2) {
    start = count - 2 * s - 2;
  }
  if (start < 3) {
    start = 3;
  }
  var end = current + s;
  if (end < 2 * s + 3) {
    end = 2 * s + 3;
  }
  if (end > count - 2) {
    end = count - 2;
  }
  return [
    0,
    if (start > 3) -1 else if (count > 3) 1,
    for (var p = start; p <= end; p++) p - 1,
    if (end < count - 2) -1 else if (count - 1 > 1) count - 2,
    if (count > 1) count - 1,
  ];
}
