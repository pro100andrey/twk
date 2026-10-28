// Blocks written as the HTML the reference implementations write, to check
// them against the examples of the CommonMark and GFM specs.
import 'dart:convert';

import 'package:twk_rich/twk_rich.dart';

/// [blocks] as commonmark.js writes them, tables and task list items as
/// cmark-gfm does.
String html(List<MdBlock> blocks) => (_Html()..blocks(blocks)).out.toString();

final class _Html {
  final out = StringBuffer();
  var _last = '\n';

  void write(String text) {
    if (text.isNotEmpty) {
      out.write(text);
      _last = text[text.length - 1];
    }
  }

  /// Starts a line unless one has just started.
  void cr() {
    if (_last != '\n') {
      write('\n');
    }
  }

  void blocks(List<MdBlock> blocks, {bool tight = false}) {
    for (final block in blocks) {
      this.block(block, tight: tight);
    }
  }

  void block(MdBlock block, {required bool tight}) {
    switch (block) {
      case MdParagraph(:final children):
        if (tight) {
          inlines(children);
        } else {
          cr();
          write('<p>');
          inlines(children);
          write('</p>');
          cr();
        }
      case MdHeading(:final level, :final children):
        cr();
        write('<h$level>');
        inlines(children);
        write('</h$level>');
        cr();
      case MdThematicBreak():
        cr();
        write('<hr />');
        cr();
      case MdCodeBlock(:final code, :final language):
        cr();
        write('<pre><code');
        if (language.isNotEmpty) {
          write(' class="language-${escape(language)}"');
        }
        write('>${escape(code)}</code></pre>');
        cr();
      case MdBlockQuote(:final children):
        cr();
        write('<blockquote>');
        cr();
        blocks(children);
        cr();
        write('</blockquote>');
        cr();
      case MdList(:final items, :final start, tight: final listTight):
        final tag = start == null ? 'ul' : 'ol';
        cr();
        write(start == null || start == 1 ? '<$tag>' : '<$tag start="$start">');
        cr();
        for (final item in items) {
          write('<li>');
          if (item.checked != null) {
            write(
              item.checked!
                  ? '<input checked="" disabled="" type="checkbox"> '
                  : '<input disabled="" type="checkbox"> ',
            );
          }
          blocks(item.children, tight: listTight);
          write('</li>');
          cr();
        }
        cr();
        write('</$tag>');
        cr();
      case MdTable(:final align, :final header, :final rows):
        cr();
        write('<table>\n<thead>\n');
        row('th', align, header);
        write('</thead>\n');
        if (rows.isNotEmpty) {
          write('<tbody>\n');
          for (final cells in rows) {
            row('td', align, cells);
          }
          write('</tbody>\n');
        }
        write('</table>');
        cr();
    }
  }

  void row(String tag, List<MdAlign> align, List<List<MdInline>> cells) {
    write('<tr>\n');
    for (var k = 0; k < cells.length; k++) {
      write(
        align[k] == MdAlign.none ? '<$tag>' : '<$tag align="${align[k].name}">',
      );
      inlines(cells[k]);
      write('</$tag>\n');
    }
    write('</tr>\n');
  }

  void inlines(List<MdInline> inlines) {
    for (final inline in inlines) {
      switch (inline) {
        case MdText(:final text):
          write(escape(text));
        case MdSoftBreak():
          write('\n');
        case MdHardBreak():
          write('<br />\n');
        case MdCode(:final code):
          write('<code>${escape(code)}</code>');
        case MdEmphasis(:final children):
          write('<em>');
          this.inlines(children);
          write('</em>');
        case MdStrong(:final children):
          write('<strong>');
          this.inlines(children);
          write('</strong>');
        case MdStrikethrough(:final children):
          write('<del>');
          this.inlines(children);
          write('</del>');
        case MdLink(:final destination, :final title, :final children):
          write('<a href="${escape(normalizeUri(destination))}"');
          if (title != null && title.isNotEmpty) {
            write(' title="${escape(title)}"');
          }
          write('>');
          this.inlines(children);
          write('</a>');
        case MdReference():
          throw ArgumentError.value(inline, 'inline', 'is not resolved');
        case MdImage(:final source, :final title, :final alt):
          write('<img src="${escape(normalizeUri(source))}"');
          write(' alt="${escape(alt)}"');
          if (title != null && title.isNotEmpty) {
            write(' title="${escape(title)}"');
          }
          write(' />');
      }
    }
  }
}

String escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// [uri] percent-encoded as mdurl's `encode` does for commonmark.js: what
/// is neither alphanumeric, one of `;/?:@&=+$,-_.!~*'()#` nor a `%` before
/// two hex digits is encoded as UTF-8.
String normalizeUri(String uri) {
  const kept = r";/?:@&=+$,-_.!~*'()#";
  final hex = RegExp('[0-9a-fA-F]{2}');
  final out = StringBuffer();
  final runes = uri.runes.toList();
  for (var k = 0; k < runes.length; k++) {
    final c = runes[k];
    final char = String.fromCharCode(c);
    if (c == 0x25 &&
        k + 2 < runes.length &&
        hex.hasMatch(String.fromCharCodes(runes.sublist(k + 1, k + 3)))) {
      out.write(char);
    } else if ((c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        kept.contains(char)) {
      out.write(char);
    } else {
      for (final byte in utf8.encode(char)) {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
  }
  return out.toString();
}
