/// The styles a [DiffView] draws in: [DiffTheme].
library;

import 'package:twk/twk.dart';

import 'diff_view.dart';

/// The styles of the parts of a [DiffView]. A style left unset is the
/// empty style: the part is drawn in the style of what is under it.
final class DiffTheme {
  /// The styles of the parts, each the empty style unless given.
  const DiffTheme({
    this.added = const Style(),
    this.removed = const Style(),
    this.addedWords = const Style(),
    this.removedWords = const Style(),
    this.addedSign = const Style(),
    this.removedSign = const Style(),
    this.lineNumbers = const Style(),
    this.collapsed = const Style(),
    this.file = const Style(),
    this.divider = const Style(),
  });

  /// The styles in the colors of [theme], so that a diff follows the app's
  /// theme and the terminal's brightness with it: added lines on a tint of
  /// its success color and removed ones on a tint of its error color, the
  /// words changed in them on a stronger one and their signs in those
  /// colors; line numbers muted, collapsed lines muted on its surface,
  /// files bold in its info color on its surface, and the divider of the
  /// sides in its border color.
  DiffTheme.from(ThemeData theme)
    : this(
        added: _tint(theme.success, 0x30),
        removed: _tint(theme.error, 0x30),
        addedWords: _tint(theme.success, 0x70),
        removedWords: _tint(theme.error, 0x70),
        addedSign: theme.success,
        removedSign: theme.error,
        lineNumbers: theme.muted,
        collapsed: theme.surface.merge(theme.muted),
        file: theme.surface
            .merge(theme.info)
            .merge(const Style(attrs: Attr.bold)),
        divider: theme.border,
      );

  /// The rows of added lines, their line numbers and sign included.
  final Style added;

  /// The rows of removed lines.
  final Style removed;

  /// The words an added line changed, over [added] and the syntax colors.
  final Style addedWords;

  /// The words a removed line changed, over [removed] and the syntax
  /// colors.
  final Style removedWords;

  /// The `+` of an added line.
  final Style addedSign;

  /// The `-` of a removed line.
  final Style removedSign;

  /// The numbers of the lines, and their blanks.
  final Style lineNumbers;

  /// The rows that stand for unchanged lines left out.
  final Style collapsed;

  /// The rows that name a file.
  final Style file;

  /// The line between the old side and the new.
  final Style divider;
}

/// A background of the text color of [style] at [alpha]; none when it
/// sets no text color.
Style _tint(Style style, int alpha) => switch (style.fg) {
  final color? => Style(bg: color, bgAlpha: alpha),
  null => const Style(),
};
