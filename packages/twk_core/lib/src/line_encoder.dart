/// [LineEncoder], lines of text written from runs of styled text or from
/// the rows of a [Surface], with the SGR sequences and OSC 8 hyperlinks of
/// their styles where the output takes them.
///
/// @docImport 'headless.dart';
/// @docImport 'presenter.dart';
library;

import 'dart:convert';
import 'dart:typed_data';

import 'byte_sink.dart';
import 'style.dart';
import 'surface.dart';

/// Writes lines of text, each from runs of text in a style ([text]) or from
/// a row of a [Surface] ([row]), into [out]: with [ansi], each style as
/// the shortest SGR sequence from the one before in the [styles]' colour
/// mode, and where [hyperlinks] are taken too, each link as OSC 8, its
/// target percent-encoded as the [Presenter] writes it ([linkTarget]);
/// without [ansi], the text alone.
///
/// A line ends with [end], which closes its link and resets its style, so
/// the next line starts from the terminal's defaults; [take] hands over
/// what was written as a string. Line breaks are the caller's to write.
///
/// Two lines in a style of a link, written as text with escapes:
///
/// ```dart
/// final styles = StyleTable();
/// final bold = styles.style(attrs: Attr.bold, link: 'https://dart.dev');
/// final lines = LineEncoder(styles, hyperlinks: true)
///   ..text(bold, 'Dart')
///   ..text(0, ' is here')
///   ..end();
/// print(lines.take()); // Dart, bold and a link, then " is here"
/// ```
///
/// See also:
///
///  * [Presenter], which writes a whole screen as the fewest bytes that
///    change what the terminal shows, cursor moves among them.
///  * [renderToString], a render tree painted once, as text.
final class LineEncoder {
  /// An encoder of lines in the styles of [styles] into [out], a sink of
  /// its own when left out.
  ///
  /// [ansi], true by default, writes the styles' SGR sequences; false,
  /// the text alone. [hyperlinks], false by default, writes their links
  /// as OSC 8 too, where [ansi] is true.
  LineEncoder(
    this.styles, {
    this.ansi = true,
    this.hyperlinks = false,
    ByteSink? out,
  }) : out = out ?? ByteSink(256);

  /// The table the style ids written are in; its colour mode is the one
  /// the SGR sequences are written in.
  final StyleTable styles;

  /// Whether the styles are written as SGR sequences.
  final bool ansi;

  /// Whether links are written as OSC 8, where [ansi] is true.
  final bool hyperlinks;

  /// The bytes written: UTF-8 text with the sequences between.
  final ByteSink out;

  /// The style the terminal is in after what was written.
  var _style = 0;

  /// The link id open after what was written; 0 for none.
  var _link = 0;

  final _targets = <int, Uint8List>{};

  /// Writes [text] in style [style] of [styles]; a lone surrogate in it
  /// as U+FFFD, as UTF-8 has none.
  void text(int style, String text) {
    _to(style);
    for (final c in text.runes) {
      out.codePoint(c >= 0xD800 && c <= 0xDFFF ? 0xFFFD : c);
    }
  }

  /// Writes row [y] of [surface], its glyphs in [glyphs], as a line, and
  /// ends it ([end]): a wide glyph once for its two cells, without the
  /// blanks that end the row and look as the terminal's default does (all
  /// of them without [ansi]).
  void row(Surface surface, GlyphTable glyphs, int y) {
    final width = surface.width;
    final at = y * width;
    final cells = surface.cells;
    final cellStyles = surface.styles;
    var last = at + width;
    while (last > at && _trailingBlank(cells[last - 1], cellStyles[last - 1])) {
      last--;
    }
    for (var i = at; i < last; i++) {
      final cell = cells[i];
      if (cell & kCont != 0) {
        continue;
      }
      _to(cellStyles[i]);
      final glyph = cell & kGlyphMask;
      if (glyph < kFirstInterned) {
        out.codePoint(glyph);
      } else {
        out.bytes(glyphs.bytesOf(glyph));
      }
    }
    end();
  }

  /// Ends the line: closes its link and resets its style, where they were
  /// written.
  void end() {
    if (_link != 0) {
      _osc8(0);
    }
    if (styles.transition(_style, 0).isNotEmpty) {
      out.ascii('\x1B[0m');
    }
    _style = 0;
  }

  /// What was written since the last take, as a string; [out] is emptied.
  String take() {
    final s = utf8.decode(out.view);
    out.reset();
    return s;
  }

  /// Whether a cell of [cell] in [style] at the end of a row is left out:
  /// a blank, and without [ansi] any blank, with it one that looks as the
  /// terminal's default does and has no link to write.
  bool _trailingBlank(int cell, int style) =>
      cell == kBlank &&
      (!ansi ||
          (styles.transition(0, styles.blankStyleOf(style)).isEmpty &&
              (!hyperlinks || styles.linkIdOf(style) == 0)));

  void _to(int style) {
    if (!ansi) {
      return;
    }
    if (style != _style) {
      out.bytes(styles.transition(_style, style));
      _style = style;
    }
    if (hyperlinks) {
      final link = styles.linkIdOf(style);
      if (link != _link) {
        _osc8(link);
      }
    }
  }

  /// OSC 8 to link [link] of [styles]; 0 closes the one open.
  void _osc8(int link) {
    out.ascii('\x1B]8;;');
    if (link != 0) {
      out.bytes(_targets[link] ??= linkTarget(styles.linkUri(link)));
    }
    out.ascii('\x1B\\');
    _link = link;
  }

  /// [uri] as the target of an OSC 8 hyperlink: printable ASCII, the other
  /// bytes of its UTF-8 form (non-ASCII text, spaces, controls)
  /// percent-encoded, which keeps the target and cannot end the sequence
  /// early.
  ///
  /// ```dart
  /// final target = LineEncoder.linkTarget('https://x.dev/é');
  /// print(String.fromCharCodes(target)); // https://x.dev/%C3%A9
  /// ```
  static Uint8List linkTarget(String uri) {
    const hex = '0123456789ABCDEF';
    final b = BytesBuilder(copy: false);
    for (final c in utf8.encode(uri)) {
      if (c > 0x20 && c < 0x7F) {
        b.addByte(c);
      } else {
        b
          ..addByte(0x25) // %
          ..addByte(hex.codeUnitAt(c >> 4))
          ..addByte(hex.codeUnitAt(c & 0xF));
      }
    }
    return b.takeBytes();
  }
}
