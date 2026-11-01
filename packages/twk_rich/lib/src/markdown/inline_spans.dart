/// What [MarkdownView] and [renderMarkdown] both make of a block: its
/// inlines as styled spans, and the markers of its lists.
///
/// @docImport 'markdown_lines.dart';
/// @docImport 'markdown_view.dart';
library;

import 'package:twk/twk.dart';

import 'markdown_theme.dart';
import 'nodes.dart';
import 'references.dart';

/// A link or an image of a paragraph, a heading or a table cell: the text
/// it covers, from `start` to `end` of the paragraph's, where it leads and
/// its title.
typedef InlineLink = ({int start, int end, String destination, String? title});

/// [inlines], their references resolved by [definitions], as spans in the
/// styles of [theme]: adjacent runs of one style are one span, a link and
/// an image a hyperlink to their destination where its scheme is one of
/// [schemes] and [hyperlinks] is true. Adds the links and images to
/// [links], the innermost first, with the text they cover. Returns the
/// spans and whether there is a link or an image among them.
({List<Span> spans, bool linked}) inlineSpans(
  List<MdInline> inlines,
  Map<String, MdDefinition> definitions,
  MarkdownTheme theme, {
  required bool hyperlinks,
  required Set<String> schemes,
  List<InlineLink>? links,
}) {
  bool hyperlinked(String destination) {
    if (!hyperlinks) {
      return false;
    }
    final scheme = Uri.tryParse(destination)?.scheme ?? '';
    return scheme.isNotEmpty && schemes.contains(scheme.toLowerCase());
  }

  final out = <Span>[];
  var length = 0;
  var linked = false;
  void put(String text, Style style) {
    length += text.length;
    if (out.isNotEmpty && out.last.style == style) {
      out.last = Span(out.last.text + text, style);
    } else {
      out.add(Span(text, style));
    }
  }

  void add(List<MdInline> inlines, Style style) {
    for (final inline in inlines) {
      switch (inline) {
        case MdText(:final text):
          put(text, style);
        case MdCode(:final code):
          put(code, style.merge(theme.code));
        case MdEmphasis(:final children):
          add(children, style.merge(theme.emphasis));
        case MdStrong(:final children):
          add(children, style.merge(theme.strong));
        case MdStrikethrough(:final children):
          add(children, style.merge(theme.strikethrough));
        case MdLink(:final destination, :final title, :final children):
          linked = true;
          final start = length;
          final shown = style.merge(theme.link);
          add(
            children,
            hyperlinked(destination)
                ? shown.merge(Style(link: destination))
                : shown,
          );
          links?.add((
            start: start,
            end: length,
            destination: destination,
            title: title,
          ));
        case MdImage(:final source, :final title, :final alt):
          linked = true;
          final start = length;
          final shown = style.merge(theme.image);
          put(
            alt.isEmpty ? source : alt,
            hyperlinked(source) ? shown.merge(Style(link: source)) : shown,
          );
          links?.add((
            start: start,
            end: length,
            destination: source,
            title: title,
          ));
        case MdReference(:final children):
          // none is left once resolved
          add(children, style);
        case MdSoftBreak():
          put(' ', style);
        case MdHardBreak():
          put('\n', style);
      }
    }
  }

  add(resolveInlines(inlines, definitions), const Style());
  return (spans: out, linked: linked);
}

/// The marker of each item of [list], a list [depth] lists deep, and the
/// markers its column is as wide as the widest of: all the different
/// bullets, the widest number. The bullets are [glyphs]' [Glyphs.bullet]
/// and [Glyphs.taskPending] in turn, a task's box its checkbox marks.
({List<String> markers, List<String> column}) listMarkers(
  MdList list,
  int depth, [
  Glyphs glyphs = Glyphs.unicode,
]) {
  final bullets = [glyphs.bullet, glyphs.taskPending, glyphs.bullet];
  final (open, close) = glyphs.checkboxBrackets;
  final items = list.items;
  final start = list.start;
  String box(bool checked) =>
      '$open${checked ? glyphs.checkboxOn : glyphs.checkboxOff}$close';
  final markers = [
    for (var k = 0; k < items.length; k++)
      switch ((start, items[k].checked)) {
        (null, null) => bullets[depth % bullets.length],
        (null, final checked?) => box(checked),
        (final start?, null) => '${start + k}${list.marker}',
        (final start?, final checked?) =>
          '${start + k}${list.marker} ${box(checked)}',
      },
  ];
  final column = start == null
      ? markers.toSet().toList()
      : [markers.reduce((a, b) => b.length > a.length ? b : a)];
  return (markers: markers, column: column);
}
