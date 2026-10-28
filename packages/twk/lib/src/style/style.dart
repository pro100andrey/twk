/// Style values as widgets use them: colors, attributes and text styles,
/// the themes made of them ([Theme]), and gradients ([Gradient]).
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show Attr, Color, Pen, StyleTable;

import '../text/widgets.dart' show DefaultTextStyle, Text;
import 'gradient.dart';
import 'theme.dart';

export 'animated_theme.dart';
export 'gradient.dart' hide textColorsAlong;
export 'theme.dart';

/// How text looks: colors, attributes and a hyperlink. A field left unset
/// (null, or an attribute in neither [attrs] nor [attrsOff]) takes its value
/// from the style this one is merged onto ([merge]); when the text is
/// painted, an unset color is that of the cell painted over and an unset
/// attribute is off ([pen]).
///
/// Bold text in yellow, and a style that turns bold off whatever it is
/// merged onto:
///
/// ```dart
/// const warning = Style(fg: Color.yellow, attrs: Attr.bold);
/// const plain = Style(attrsOff: Attr.bold);
/// assert(warning.merge(plain).attrs == 0);
/// ```
///
/// See also:
///
///  * [Span] and [StringStyles], for text in a style: `'x'.bold`.
///  * [Theme], the styles of an app by what they are for.
@immutable
final class Style {
  /// A style of the fields given, every other one unset.
  ///
  /// An attribute in both [attrs] and [attrsOff] is an error; any underline
  /// bit in [attrsOff] turns off every kind of underline. [fgAlpha] and
  /// [bgAlpha] go from 0 to 255 (an assert), and need a color.
  const Style({
    this.fg,
    this.bg,
    this.fgAlpha = 255,
    this.bgAlpha = 255,
    this.underlineColor,
    this.attrs = 0,
    int attrsOff = 0,
    this.link,
  }) : attrsOff = (attrsOff & Attr.underlineMask) == 0
           ? attrsOff
           : attrsOff | Attr.underlineMask,
       assert(fg != null || fgAlpha == 255, 'fgAlpha without an fg'),
       assert(bg != null || bgAlpha == 255, 'bgAlpha without a bg'),
       assert(fgAlpha >= 0 && fgAlpha <= 255, 'fgAlpha out of 0..255'),
       assert(bgAlpha >= 0 && bgAlpha <= 255, 'bgAlpha out of 0..255'),
       assert(
         (attrs & attrsOff) == 0 &&
             ((attrs & Attr.underlineMask) == 0 ||
                 (attrsOff & Attr.underlineMask) == 0),
         'an attribute both on and off',
       );

  /// Text color; null shows the text color of the cell painted over.
  final Color? fg;

  /// Background color; null keeps the background of the cell painted over.
  final Color? bg;

  /// Opacity of [fg] (255 opaque): the text blends over the background it
  /// ends up on.
  final int fgAlpha;

  /// Opacity of [bg] (255 opaque, 0 invisible): it blends over the
  /// background of the cell painted over.
  final int bgAlpha;

  /// Color of the underline; [Color.defaultColor] draws it in the text
  /// color.
  final Color? underlineColor;

  /// [Attr] bits turned on; the underline bits hold a kind of underline.
  final int attrs;

  /// [Attr] bits turned off.
  final int attrsOff;

  /// Hyperlink target (OSC 8); empty for none.
  final String? link;

  /// This style with the fields [other] sets taken from [other]: a color
  /// together with its alpha, an underline as a whole. This style itself
  /// where [other] sets nothing, and [other] itself where this one sets
  /// nothing: a merge allocates only a style that differs from both.
  Style merge(Style other) {
    if (other._setsNothing) {
      return this;
    }
    if (_setsNothing) {
      return other;
    }
    var set = other.attrs | other.attrsOff;
    if ((other.attrs & Attr.underlineMask) != 0) {
      set |= Attr.underlineMask;
    }
    final takeFg = other.fg != null;
    final takeBg = other.bg != null;
    return Style(
      fg: takeFg ? other.fg : fg,
      bg: takeBg ? other.bg : bg,
      fgAlpha: takeFg ? other.fgAlpha : fgAlpha,
      bgAlpha: takeBg ? other.bgAlpha : bgAlpha,
      underlineColor: other.underlineColor ?? underlineColor,
      attrs: (attrs & ~set) | other.attrs,
      attrsOff: (attrsOff & ~set) | other.attrsOff,
      link: other.link ?? link,
    );
  }

  /// Whether this style sets no field: what `const Style()` is.
  bool get _setsNothing =>
      fg == null &&
      bg == null &&
      underlineColor == null &&
      attrs == 0 &&
      attrsOff == 0 &&
      link == null;

  /// The core's pen for this style. Unset colors stay null, so they are
  /// those of the cell painted over; the attributes, underline color and
  /// link replace those of the cell, so unset ones are off.
  Pen get pen => Pen(
    fg: fg,
    bg: bg,
    fgAlpha: fgAlpha,
    bgAlpha: bgAlpha,
    attrs: attrs,
    underlineColor: underlineColor ?? Color.defaultColor,
    link: link == null || link!.isEmpty ? null : link,
  );

  /// The id of [pen] in [table]: registered on first use, the same id for
  /// every equal style after that. A style looked up before in [table],
  /// or one equal to it, costs no [Pen]: the ids are kept by style for
  /// each table (a table never forgets a pen).
  int penIn(StyleTable table) {
    final ids = _penIds[table] ??= <Style, int>{};
    return ids[this] ??= table.pen(pen);
  }

  /// The ids [penIn] found, by table and style.
  static final _penIds = Expando<Map<Style, int>>('Style.penIn');

  /// Whether [other] is a style of equal fields.
  @override
  bool operator ==(Object other) =>
      other is Style &&
      other.fg == fg &&
      other.bg == bg &&
      other.fgAlpha == fgAlpha &&
      other.bgAlpha == bgAlpha &&
      other.underlineColor == underlineColor &&
      other.attrs == attrs &&
      other.attrsOff == attrsOff &&
      other.link == link;

  @override
  int get hashCode => Object.hash(
    fg,
    bg,
    fgAlpha,
    bgAlpha,
    underlineColor,
    attrs,
    attrsOff,
    link,
  );
}

/// Text in one [Style], what styled text is made of, its text colors
/// along a [Gradient] when it has one ([Span.gradient]). Made from a string
/// by [StringStyles]; each of its members returns the span with its style
/// merged with one more field, a kind of underline replacing the one there
/// was, its gradient kept.
///
/// A line of styled text for [Text.rich]:
///
/// ```dart
/// Text.rich([
///   'Error: '.bold.fg(Color.red),
///   const Span('file not found'),
/// ])
/// ```
@immutable
final class Span {
  /// [text] in [style], unset by default.
  const Span(this.text, [this.style = const Style()]) : gradient = null;

  /// [text] in [style], its text colors along [gradient].
  const Span.gradient(
    this.text,
    Gradient this.gradient, [
    this.style = const Style(),
  ]);

  const Span._(this.text, this.style, this.gradient);

  /// What is shown.
  final String text;

  /// How [text] looks; merged, where it is shown, onto the style there
  /// ([DefaultTextStyle]).
  final Style style;

  /// The text colors along the graphemes of [text], in place of the text
  /// color of [style] and its opacity: the first grapheme in the color at
  /// 0, the last in that at 1, whatever lines they are on; a control that
  /// takes no cell, such as a line break, is not one. The gradient's
  /// direction does not matter. Null for the text color of [style].
  final Gradient? gradient;

  /// This span in bold.
  Span get bold => _with(const Style(attrs: Attr.bold));

  /// This span dimmed.
  Span get dim => _with(const Style(attrs: Attr.dim));

  /// This span in italics.
  Span get italic => _with(const Style(attrs: Attr.italic));

  /// This span underlined with a single line.
  Span get underline => _with(const Style(attrs: Attr.underline));

  /// This span underlined with a double line.
  Span get doubleUnderline => _with(const Style(attrs: Attr.doubleUnderline));

  /// This span underlined with a curly line.
  Span get curlyUnderline => _with(const Style(attrs: Attr.curlyUnderline));

  /// This span underlined with a dotted line.
  Span get dottedUnderline => _with(const Style(attrs: Attr.dottedUnderline));

  /// This span underlined with a dashed line.
  Span get dashedUnderline => _with(const Style(attrs: Attr.dashedUnderline));

  /// This span in reverse video: its text color and background swapped.
  Span get reverse => _with(const Style(attrs: Attr.reverse));

  /// This span struck through.
  Span get strike => _with(const Style(attrs: Attr.strike));

  /// This span with a line over it.
  Span get overline => _with(const Style(attrs: Attr.overline));

  /// This span in the text color [color], opaque.
  Span fg(Color color) => _with(Style(fg: color));

  /// This span on the background [color], opaque.
  Span bg(Color color) => _with(Style(bg: color));

  /// This span as a hyperlink to [url] (OSC 8).
  Span link(String url) => _with(Style(link: url));

  Span _with(Style other) => Span._(text, style.merge(other), gradient);

  /// Whether [other] is a span of an equal text, style and gradient.
  @override
  bool operator ==(Object other) =>
      other is Span &&
      other.text == text &&
      other.style == style &&
      other.gradient == gradient;

  @override
  int get hashCode => Object.hash(text, style, gradient);
}

/// A string as a [Span] of one style: `'x'.bold.fg(.green)`.
///
/// ```dart
/// Text.rich(['Saved'.bold.fg(Color.green), ' to disk'.dim])
/// ```
extension StringStyles on String {
  /// This string in bold ([Span.bold]).
  Span get bold => Span(this).bold;

  /// This string dimmed ([Span.dim]).
  Span get dim => Span(this).dim;

  /// This string in italics ([Span.italic]).
  Span get italic => Span(this).italic;

  /// This string underlined with a single line ([Span.underline]).
  Span get underline => Span(this).underline;

  /// This string underlined with a double line ([Span.doubleUnderline]).
  Span get doubleUnderline => Span(this).doubleUnderline;

  /// This string underlined with a curly line ([Span.curlyUnderline]).
  Span get curlyUnderline => Span(this).curlyUnderline;

  /// This string underlined with a dotted line ([Span.dottedUnderline]).
  Span get dottedUnderline => Span(this).dottedUnderline;

  /// This string underlined with a dashed line ([Span.dashedUnderline]).
  Span get dashedUnderline => Span(this).dashedUnderline;

  /// This string in reverse video ([Span.reverse]).
  Span get reverse => Span(this).reverse;

  /// This string struck through ([Span.strike]).
  Span get strike => Span(this).strike;

  /// This string with a line over it ([Span.overline]).
  Span get overline => Span(this).overline;

  /// This string in the text color [color] ([Span.fg]).
  Span fg(Color color) => Span(this).fg(color);

  /// This string on the background [color] ([Span.bg]).
  Span bg(Color color) => Span(this).bg(color);

  /// This string as a hyperlink to [url] ([Span.link]).
  Span link(String url) => Span(this).link(url);

  /// This string, its text colors along [gradient] ([Span.gradient]).
  Span gradient(Gradient gradient) => Span.gradient(this, gradient);
}
