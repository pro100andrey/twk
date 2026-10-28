/// What a render object of an app's own does to be selected in a
/// `SelectionArea` with the `Text`s: [Selectable].
library;

import 'package:twk_core/twk_core.dart' show RenderObject;

import '../style/style.dart';

/// A render object of an app's own that a `SelectionArea` above it selects
/// in, across with the `Text`s in the order of the tree, as it selects in
/// a Text: a painted view (a log, a code view, a chart's labels).
///
/// It holds [selectableText], one string for all its rows, a line break
/// between two rows that are lines of their own (not one line wrapped);
/// the area selects ranges of it, offsets in UTF-16 code units, and
/// copies what they hold. [selectableRangeAt] says which range each of its
/// cells is. What is painted but is not text (line numbers, a gutter, a
/// border) is left out of [selectableText]: a cell of it is the empty
/// range where its row starts, or where the next one does, and it is
/// neither selected nor copied.
///
/// The area tells it what is selected ([selection], in the area's
/// [selectionStyle]) and marks it for paint when that changes; its paint
/// draws what is selected in the style [selectionStyleAt] gives. Its
/// children, if it has any, are selected in after it.
///
/// A view that scrolls its rows itself scrolls by [scrollSelectionBy]
/// while a drag that selects in it is past its top or bottom, and one that
/// scrolls its columns by [scrollSelectionAcross] while it is past its
/// left or right edge.
mixin Selectable on RenderObject {
  /// Its text, as the area selects in it and copies it: its rows in
  /// order, each line ended by a line break. Asked whenever the area
  /// looks for what is under the mouse: kept, not built anew each time.
  /// Empty, it takes no part (a view with nothing to select now).
  String get selectableText;

  /// The range of [selectableText] the cell [x], [y] (in its own
  /// coordinates, possibly outside it) stands for, as
  /// `RenderParagraph.textRangeAt` gives it for a Text: the cluster drawn
  /// there, at either cell of a wide one; left of a row's text the empty
  /// range where the row starts, right of it the one where the next row
  /// starts (after its line break); above the first row (0, 0), below the
  /// last the end of the text.
  (int, int) selectableRangeAt(int x, int y);

  /// Scrolls its rows by [rows] (down for more than 0), for a drag past
  /// its top or bottom that selects in it; whether they moved. False by
  /// default: it does not scroll itself.
  bool scrollSelectionBy(int rows) => false;

  /// Scrolls its columns by [columns] (right for more than 0), for a drag
  /// past its left or right edge that selects in it; whether they moved.
  /// False by default: it does not scroll itself sideways.
  bool scrollSelectionAcross(int columns) => false;

  (int, int)? _selection;
  var _selectionStyle = const Style();

  /// The range of [selectableText] selected, start before end; null when
  /// none of it is.
  (int, int)? get selection => _selection;

  /// What the area merges onto the style of the text it selects.
  Style get selectionStyle => _selectionStyle;

  /// [style], merged with [selectionStyle] when the text at [offset] of
  /// [selectableText] is selected.
  Style selectionStyleAt(int offset, Style style) {
    final s = _selection;
    return s != null && offset >= s.$1 && offset < s.$2
        ? style.merge(_selectionStyle)
        : style;
  }
}

/// Tells [selectable] what is selected of it, [selection] in [style],
/// marking it for paint when that changed; what a `SelectionArea` calls.
/// Hidden from the library's exports.
void selectInSelectable(
  Selectable selectable,
  (int, int)? selection,
  Style style,
) {
  if (selection == selectable._selection &&
      style == selectable._selectionStyle) {
    return;
  }
  selectable
    .._selection = selection
    .._selectionStyle = style
    ..markNeedsPaint();
}
