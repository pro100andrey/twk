/// Text that links to a URL: [Link].
library;

import 'package:twk_core/twk_core.dart' show Attr;

import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../semantics/semantics.dart';
import '../style/color_mix.dart';
import '../style/style.dart';
import '../text/widgets.dart';

/// Text linked to [url] as a hyperlink (OSC 8), which a terminal that
/// knows them opens when it is clicked.
///
/// It shows [text], the [url] itself when null. Most terminals open the
/// URL with Ctrl or Shift held while the app reads the mouse; others show
/// the text alone. Drawn in [style], or the theme's
/// [ThemeData.primary] underlined; [hoverStyle] over it while the mouse is
/// over it, by default its color 0.35 of the way to the theme's text, in
/// bold. Wrapped as [Text] wraps. A screen reader reads it as a
/// [SemanticsRole.link] of its text.
///
/// The hover has the app read the motion of the mouse while the link is
/// shown. `hoverStyle: const Style()` leaves the link without a hover and
/// the mouse unread: a click opens the URL with no key held.
///
/// ```dart
/// const Row(
///   children: [
///     Text('Docs: '),
///     Link('https://dart.dev', text: 'dart.dev'),
///   ],
/// )
/// ```
final class Link extends StatefulWidget {
  /// A link to [url] that shows [text], or the URL.
  const Link(this.url, {super.key, this.text, this.style, this.hoverStyle});

  /// What the link opens: `https://…`, `file:///…`.
  final String url;

  /// What the link shows; null for the [url].
  final String? text;

  /// The text; [ThemeData.primary] underlined when null.
  final Style? style;

  /// Over [style] while the mouse is over it; when null, the color of
  /// [style] 0.35 of the way to the theme's [ThemeData.text] where both
  /// are RGB, in bold. An empty style for no hover.
  final Style? hoverStyle;

  @override
  State<Link> createState() => _LinkState();
}

final class _LinkState extends State<Link> {
  var _hovered = false;

  void _hover(bool hovered) {
    if (hovered != _hovered) {
      setState(() => _hovered = hovered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        widget.style ?? theme.primary.merge(const Style(attrs: Attr.underline));
    final hover =
        widget.hoverStyle ??
        Style(fg: mixRgb(style.fg, theme.text.fg, 0.35), attrs: Attr.bold);
    final hovers = hover != const Style();
    Widget link = Text(
      widget.text ?? widget.url,
      style: (hovers && _hovered ? style.merge(hover) : style).merge(
        Style(link: widget.url),
      ),
    );
    if (hovers) {
      link = MouseRegion(
        onEnter: (_) => _hover(true),
        onExit: (_) => _hover(false),
        child: link,
      );
    }
    return Semantics(role: SemanticsRole.link, child: link);
  }
}
