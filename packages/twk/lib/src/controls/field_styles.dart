/// What the controls that build a `TextField` without a box around it
/// (NumberInput, DatePicker, TextFormField, FilePicker) show it in: sunk
/// in the well at rest, on the selection colour while it has the focus,
/// its own selection a step towards the primary colour. Hidden from the
/// library's exports.
library;

import 'package:twk_core/twk_core.dart' show Attr;

import '../style/color_mix.dart';
import '../style/style.dart';

/// A field without a box at rest: [ThemeData.well], and where that is the
/// background itself (the terminal's own colors) underlined in
/// [ThemeData.border]'s color, so that the field has an edge.
Style fieldRest(ThemeData theme) => theme.well.bg == theme.background.bg
    ? theme.well.merge(
        Style(attrs: Attr.underline, underlineColor: theme.border.fg),
      )
    : theme.well;

/// A field without a box while it has the focus: [ThemeData.selection].
Style fieldFocused(ThemeData theme) => theme.selection;

/// The text selected in a field on [fieldFocused]: [ThemeData.selection]
/// 0.4 of the way to [ThemeData.primary]; where either is not RGB, the
/// primary color filled ([ThemeData.fill]), not the selection the field
/// is on.
Style fieldSelection(ThemeData theme) {
  final to = mixRgb(theme.selection.bg, theme.primary.fg, 0.4);
  return to == null ? theme.fill(theme.primary.fg) : Style(bg: to);
}
