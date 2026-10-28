/// The line the binding shows over the bottom row of an app while the
/// prefix of the debug keys, Ctrl+G, waits for its command
/// (`DebugAids.keys`): which key does what.
library;

import 'package:twk_core/twk_core.dart'
    show Attr, BoxConstraints, PaintContext, RenderObject;

import '../data/chart_glyphs.dart' show opaque;
import '../style/style.dart';

/// A row as wide as it is laid out that names the prefix, ` ctrl+g `, then
/// lists the commands of the debug keys, each key and what it does
/// ([commands]), in [theme]'s colors: the prefix in reverse video, it and
/// the keys bold in its primary color, what they do in its muted one, on
/// its surface. The commands that do not fit are left out, from the last.
/// A repaint boundary.
final class RenderKeyHint extends RenderObject {
  /// The line of the debug keys, in [theme].
  RenderKeyHint(this.theme);

  /// What it starts with, the prefix; ASCII, a cell a character.
  static const prefix = ' ctrl+g ';

  /// The keys after Ctrl+G and what each does, in the order shown; all of
  /// them ASCII, a cell a character.
  static const commands = [
    ('o', 'overlay'),
    ('r', 'rainbow'),
    ('c', 'console'),
    ('l', 'relayout'),
    ('f', 'level'),
    ('y', 'copy'),
    ('s', 'save'),
    ('x', 'clear'),
    ('h', 'reload'),
    ('H', 'restart'),
    ('ctrl+g', 'to the app'),
  ];

  /// What it is painted in: its surface, text, primary and muted colors.
  final ThemeData theme;

  /// Whether it has been painted: until then the cells it is over hold
  /// what the app painted.
  bool get painted => _painted;
  var _painted = false;

  @override
  bool get isRepaintBoundary => true;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    _painted = true;
    if (width == 0 || height == 0) {
      return;
    }
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final base = opaque(theme.surface.merge(theme.text));
    canvas.fill(0, 0, width, height, base.penIn(styles));
    final key = base.merge(theme.primary).merge(const Style(attrs: Attr.bold));
    final does = base.merge(theme.muted).penIn(styles);
    canvas.text(
      0,
      0,
      prefix,
      key.merge(theme.fill(theme.primary.fg)).penIn(styles),
    );
    final keyPen = key.penIn(styles);
    var x = prefix.length + 1;
    for (final (k, d) in commands) {
      final end = x + k.length + 1 + d.length;
      if (end > width) {
        break;
      }
      canvas
        ..text(x, 0, k, keyPen)
        ..text(x + k.length + 1, 0, d, does);
      x = end + 2;
    }
  }
}
