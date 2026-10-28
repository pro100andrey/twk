/// A Markdown document as widgets: [MarkdownView].
library;

import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderParagraph;

import '../highlight/highlight.dart';
import 'appended.dart';
import 'markdown_theme.dart';
import 'nodes.dart';
import 'references.dart';
import 'stream.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late String readme, help, answer, lastPiece;
// void setState(void Function() fn) {}
// bool open(String destination) => true;

/// The Markdown document [data] as widgets, its blocks one under another
/// with a blank row between them, in the styles of [theme], by default
/// [MarkdownTheme.from] the [Theme].
///
/// A paragraph or a heading is a [Text.rich] that wraps by words: CJK
/// text between its characters, wide characters as wide as the terminal
/// draws them. Emphasis, strong and struck text, code spans, links and
/// images take their styles over the text's; a link, and an image, which
/// shows its description (its source when it has none), is a hyperlink
/// (OSC 8) to its destination. A reference is a link once a definition of
/// its label has arrived, before it or after, and its text, such as
/// `[label]`, until then. A line ending within a paragraph is a space.
/// While the mouse is over a link or an image, in a paragraph, a heading
/// or a table, the pointer has the shape of a hand
/// ([PointerShape.pointer]), where the terminal shows the pointer's shape
/// (see [MouseRegion.cursor]); then, and only while the view has a link,
/// the terminal reports the mouse's motion.
///
/// A list item has its marker before its blocks, which wrap under their
/// own first column: a bullet by the depth of the list, `•`, `◦`, `▪` and
/// round again; a number and its delimiter, aligned at their right; a box,
/// `☐` or `☑`, in place of a bullet or after a number for a task item. A
/// loose list has a blank row between its items and their blocks, a tight
/// one none. A block quote has a bar down its left side, its blocks in the
/// quote style. A block of code is a [CodeView] in the language the first
/// word of its info string names ([languageNamed]: plain text where none
/// does), on the code block fill, a cell in from either side, its lines
/// broken as [codeWrap] says, a tab moving to the next multiple of
/// [tabWidth] columns. A table is a [Table] that shows all its rows, its
/// columns as wide as their text within the width and aligned as the
/// delimiter row says, with lines between them and under the header; the
/// mouse goes through it, so that the wheel over it scrolls what is
/// around the view. A thematic break is a line across.
///
/// The bullets, numbers, boxes and bars are not text: below a
/// [SelectionArea], which the app puts around the view (around many, to
/// select across them), only the text of the blocks is selected and
/// copied.
///
/// When [data] is the [data] before with text added at its end, as when
/// an answer streams in, only what that text may change is parsed again
/// ([MarkdownStream.add]). To see that it is, the view compares the [data]
/// before with the start of the new, the whole of it, unless [appended]
/// says what was added: then only that. The widgets of a block are made
/// once: a block the text leaves as it was, the very same block, keeps its
/// widgets, and they are not built again, unless a definition one of its
/// references uses changed; so does an item a growing list keeps. Other
/// new [data] is parsed whole. [MarkdownView.blocks] shows blocks parsed
/// already. The view takes the width it is given, which must be bounded,
/// and is as tall as its blocks: in a [SingleChildScrollView] to scroll.
///
/// The links can be the app's own, as a chat's or a help viewer's are: with
/// an [onLinkTap], a click on a link or an image (the left button pressed
/// and released on the same cell of it) tells it the destination and the
/// title, where the terminal would otherwise be left to open the
/// hyperlink; the innermost, of an image in a link. The hyperlink is still
/// written, unless [hyperlinks] is false; a link in a table is clicked
/// only while it is. Links take no focus, nor keys: they are runs of text
/// that wraps, many to a document and many documents to a chat, which Tab
/// would otherwise have to cross one by one; an app that wants them from
/// the keyboard lists them itself. The headings, with the slugs GitHub
/// gives them ([markdownHeadings]), are those of its [controller], which
/// scrolls to one ([MarkdownController.scrollToHeading]): a link to
/// `#slug` the app follows so.
///
/// A README that scrolls, its text selected and copied with the mouse:
///
/// ```dart
/// SelectionArea(
///   child: SingleChildScrollView(child: MarkdownView(readme)),
/// )
/// ```
///
/// An answer streamed in, each piece given as [appended], so that a piece
/// costs its own length and the blocks it leaves as they were keep their
/// widgets:
///
/// ```dart
/// // in the State of the chat, on each piece of the answer
/// void onPiece(String piece) => setState(() {
///   answer += piece;
///   lastPiece = piece;
/// });
///
/// // in its build
/// Widget build(BuildContext context) =>
///     MarkdownView(answer, appended: lastPiece);
/// ```
///
/// See also:
///
///  * [MarkdownStream], to put the blocks of an answer in the terminal's
///    history as they settle, with [MarkdownView.blocks].
///  * [MarkdownController], the headings of the view and scrolling to one.
///  * [MarkdownTheme], the styles of its parts.
final class MarkdownView extends StatefulWidget {
  /// Shows the document [data], parsing it again only where text was
  /// added at its end, [appended] if the caller says what; code blocks
  /// broken between graphemes with tabs 4 columns apart, links hyperlinks
  /// the terminal opens unless [onLinkTap] takes their clicks.
  const MarkdownView(
    String this.data, {
    super.key,
    this.appended,
    this.theme,
    this.codeWrap = TextWrap.grapheme,
    this.tabWidth = 4,
    this.onLinkTap,
    this.hyperlinks = true,
    this.controller,
  }) : blocks = null,
       definitions = const {},
       assert(tabWidth > 0, 'tabWidth < 1');

  /// [blocks] parsed already, shown as those of a document are, their
  /// references resolved by [definitions]: such as the blocks of an answer
  /// still live, and each block of it gone to the terminal's history (see
  /// [MarkdownStream]). A block given again, the very same block, keeps its
  /// widgets, as one of [data] does.
  const MarkdownView.blocks(
    List<MdBlock> this.blocks, {
    super.key,
    this.definitions = const {},
    this.theme,
    this.codeWrap = TextWrap.grapheme,
    this.tabWidth = 4,
    this.onLinkTap,
    this.hyperlinks = true,
    this.controller,
  }) : data = null,
       appended = null,
       assert(tabWidth > 0, 'tabWidth < 1');

  /// The document; null where [blocks] are given.
  final String? data;

  /// The blocks given in place of a document; null where [data] is.
  final List<MdBlock>? blocks;

  /// The text added at the end of the [data] of the view before to make
  /// this [data], where the caller knows it, as a chat does the piece of an
  /// answer that just arrived: the view then compares only that much of
  /// [data], as long as [data] is as long as the [data] before and this
  /// together, and the piece of a long answer costs its own length rather
  /// than the answer's. Null, or not of that length, and the whole of the
  /// [data] before is compared with the start of [data].
  ///
  /// It must be all [data] has after the [data] before, where the length
  /// says it is: the view does not read the rest again, and an assert
  /// checks it. Given again with [data] as it was, it is not added again.
  final String? appended;

  /// The link reference definitions the references of [blocks] resolve by,
  /// by the [normalizeLabel] of their label. A document's are its own.
  final Map<String, MdDefinition> definitions;

  /// The styles; null for [MarkdownTheme.from] the [Theme].
  final MarkdownTheme? theme;

  /// How the lines of a block of code break: between any two graphemes by
  /// default, so that none is cut off.
  final TextWrap codeWrap;

  /// Columns between tab stops in blocks of code.
  final int tabWidth;

  /// Told of a click on a link or an image, with its destination (an
  /// image's source) and its title; null leaves the click to the terminal.
  final MarkdownLinkCallback? onLinkTap;

  /// Whether a link and an image are hyperlinks (OSC 8) to their
  /// destination, which the terminal opens; false leaves them to
  /// [onLinkTap].
  final bool hyperlinks;

  /// What has the view's headings and scrolls to one; one view at a time
  /// has it.
  final MarkdownController? controller;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

/// What a [MarkdownView] tells a click on a link with: its [destination]
/// and its [title], null where it has none.
typedef MarkdownLinkCallback = void Function(String destination, String? title);

/// A heading of a document: its [text], its [level], from 1 to 6, and its
/// [slug], the anchor of a link to it (`#slug`).
final class MarkdownHeading {
  /// A heading showing [text], of [level], whose anchor is [slug].
  const MarkdownHeading(this.text, this.level, this.slug);

  /// The text shown, without its styles, line breaks as spaces.
  final String text;

  /// 1 for the topmost heading, `#`, to 6, `######`.
  final int level;

  /// The [text] as GitHub makes it an anchor: lowercase, of letters,
  /// digits, `_`, `-` and spaces made `-`, with `-1`, `-2` and on after it
  /// for each heading before it that had it.
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is MarkdownHeading &&
      other.text == text &&
      other.level == level &&
      other.slug == slug;

  @override
  int get hashCode => Object.hash(text, level, slug);

  @override
  String toString() => 'MarkdownHeading($text, $level, #$slug)';
}

/// The headings of [blocks] in the order of the document, also those in
/// block quotes and list items, their references resolved by
/// [definitions]; as a [MarkdownView] of them shows them.
List<MarkdownHeading> markdownHeadings(
  List<MdBlock> blocks, [
  Map<String, MdDefinition> definitions = const {},
]) => _headingsOf(blocks, definitions).$1;

/// The headings of [blocks] and the nodes they are of.
(List<MarkdownHeading>, List<MdHeading>) _headingsOf(
  List<MdBlock> blocks,
  Map<String, MdDefinition> definitions,
) {
  final nodes = <MdHeading>[];
  void collect(List<MdBlock> blocks) {
    for (final block in blocks) {
      switch (block) {
        case final MdHeading heading:
          nodes.add(heading);
        case MdBlockQuote(:final children):
          collect(children);
        case MdList(:final items):
          for (final item in items) {
            collect(item.children);
          }
        case MdParagraph() || MdCodeBlock() || MdThematicBreak() || MdTable():
          break;
      }
    }
  }

  collect(blocks);
  final seen = <String, int>{};
  final headings = [
    for (final node in nodes)
      () {
        final text = _plain(resolveInlines(node.children, definitions));
        final base = text
            .toLowerCase()
            .replaceAll(_notInSlug, '')
            .replaceAll(
              ' ',
              '-',
            );
        var slug = base;
        while (seen.containsKey(slug)) {
          final n = seen[base]! + 1;
          seen[base] = n;
          slug = '$base-$n';
        }
        seen[slug] = 0;
        return MarkdownHeading(text, node.level, slug);
      }(),
  ];
  return (headings, nodes);
}

/// What a slug leaves out of the text: all but letters, marks, digits,
/// connectors such as `_`, spaces and `-`.
final _notInSlug = RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc} -]', unicode: true);

/// The text [inlines] show, resolved already, line breaks as spaces.
String _plain(List<MdInline> inlines) {
  final out = StringBuffer();
  void add(List<MdInline> inlines) {
    for (final inline in inlines) {
      switch (inline) {
        case MdText(:final text):
          out.write(text);
        case MdCode(:final code):
          out.write(code);
        case MdImage(:final source, :final alt):
          out.write(alt.isEmpty ? source : alt);
        case MdEmphasis(:final children) ||
            MdStrong(:final children) ||
            MdStrikethrough(:final children) ||
            MdLink(:final children) ||
            MdReference(:final children):
          add(children);
        case MdSoftBreak() || MdHardBreak():
          out.write(' ');
      }
    }
  }

  add(inlines);
  return out.toString();
}

/// The headings of a [MarkdownView], given to it as its `controller`, and
/// a way to scroll to one: [headings], whose listeners are told as they
/// change, after the frame that changed them, also while a document
/// streams in; [scrollToHeading]. One view at a time has it: given to
/// one built in place of its view, it goes over to that one.
///
/// A help page whose `#install` links scroll to their heading, the other
/// links left to the app:
///
/// ```dart
/// final controller = MarkdownController();
/// SingleChildScrollView(
///   child: MarkdownView(
///     help,
///     controller: controller,
///     onLinkTap: (destination, _) => destination.startsWith('#')
///         ? controller.scrollToHeading(destination)
///         : open(destination),
///   ),
/// );
/// ```
final class MarkdownController extends ChangeNotifier {
  /// A controller with no headings until a [MarkdownView] has it.
  MarkdownController();

  final _hosts = ControllerHost<_MarkdownViewState>();

  _MarkdownViewState? get _state => _hosts.host;

  /// The headings of the view's document ([markdownHeadings]); none while
  /// no view has the controller.
  List<MarkdownHeading> get headings => _state?._headings ?? const [];

  /// Scrolls each scrollable around the view, the nearest first, the least
  /// that shows the heading whose [MarkdownHeading.slug] is [slug], with or
  /// without a `#` before it ([Scrollable.ensureVisible]); whether the view
  /// shows such a heading, laid out already.
  bool scrollToHeading(String slug) =>
      _state?._scrollTo(slug.startsWith('#') ? slug.substring(1) : slug) ??
      false;

  /// [state] serves the controller, in place of the view that did.
  void _attach(_MarkdownViewState state) => _hosts.attach(state);

  /// [state] lets go of the controller: where no view takes it over and it
  /// had headings, the listeners are told after the build.
  void _detach(_MarkdownViewState state) => _hosts.detach(
    state,
    state._headings.isNotEmpty ? notifyListeners : null,
  );

  /// Tells the listeners after the build, unless the controller is
  /// disposed by then.
  void _tell() => _hosts.afterBuild(notifyListeners);

  @override
  void dispose() {
    _hosts.dispose();
    super.dispose();
  }
}

/// The labels of references a widget was made with, by [normalizeLabel],
/// and the definition each had then: null for none.
typedef _Uses = Map<String, MdDefinition?>;

/// The widget made for a block or a list item, what else it was made by,
/// and the definitions its references had.
final class _Made {
  _Made(this.widget, this.by, this.uses, {required this.linked});

  final Widget widget;
  final Object by;
  final _Uses uses;

  /// Whether the widget shows a link or an image.
  final bool linked;
}

/// A link or an image of a paragraph, a heading or a table cell: the text
/// it covers, from `start` to `end` of the paragraph's, where it leads and
/// its title.
typedef _Link = ({int start, int end, String destination, String? title});

final class _MarkdownViewState extends State<MarkdownView> {
  /// What [MarkdownView.data] is parsed by; null where blocks are given.
  MarkdownStream? _stream;

  /// The text [_stream] holds.
  var _parsed = '';

  /// The widget made for each block and item, by the very object.
  var _made = Expando<_Made>();

  /// What every widget in [_made] was made with; a change drops them.
  Object? _madeWith;

  late MarkdownTheme _theme;

  /// The theme made from [_madeFrom] ([MarkdownTheme.from]), kept while the
  /// app's theme is the same object, so that a build makes none.
  late MarkdownTheme _fromTheme;
  ThemeData? _madeFrom;
  var _definitions = const <String, MdDefinition>{};

  /// Whether a widget made or kept since this was last cleared shows a
  /// link or an image.
  var _linked = false;

  /// The headings of the blocks shown, while there is a controller, and
  /// the nodes they are of.
  var _headings = const <MarkdownHeading>[];
  var _headingNodes = const <MdHeading>[];

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _parse();
  }

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
      // told to the new one's listeners as found
      _headings = const [];
    }
    _parse();
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  /// Makes [_stream] hold [MarkdownView.data]: adds what it has at its end
  /// to the text held, parses other text whole.
  void _parse() {
    final data = widget.data;
    final stream = _stream;
    if (data == null) {
      _stream = null;
    } else if (stream == null || !identical(data, _parsed)) {
      final added = stream == null
          ? null
          : appendedTo(_parsed, data, widget.appended);
      if (stream == null || added == null) {
        _stream = MarkdownStream(data);
      } else {
        stream.add(added);
      }
      _parsed = data;
    }
  }

  MarkdownTheme _themeFrom(ThemeData data) {
    if (!identical(data, _madeFrom)) {
      _madeFrom = data;
      _fromTheme = MarkdownTheme.from(data);
    }
    return _fromTheme;
  }

  @override
  Widget build(BuildContext context) {
    _theme = widget.theme ?? _themeFrom(Theme.of(context));
    final madeWith = (
      _theme,
      widget.codeWrap,
      widget.tabWidth,
      widget.hyperlinks,
    );
    if (madeWith != _madeWith) {
      _madeWith = madeWith;
      _made = Expando();
    }
    final stream = _stream;
    _definitions = stream?.definitions ?? widget.definitions;
    _linked = false;
    final blocks = stream?.blocks ?? widget.blocks!;
    final column = _column(blocks, 0, 1, {});
    if (widget.controller case final controller?) {
      _findHeadings(blocks, controller);
    }
    return _LinkPointer(
      linked: _linked,
      shaped: widget.hyperlinks || widget.onLinkTap != null,
      onLinkTap: widget.onLinkTap,
      child: column,
    );
  }

  /// Keeps the headings of [blocks]; tells [controller]'s listeners, after
  /// this frame, where they changed.
  void _findHeadings(List<MdBlock> blocks, MarkdownController controller) {
    final (headings, nodes) = _headingsOf(blocks, _definitions);
    _headingNodes = nodes;
    if (!_sameHeadings(headings, _headings)) {
      _headings = headings;
      controller._tell();
    }
  }

  static bool _sameHeadings(List<MarkdownHeading> a, List<MarkdownHeading> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var k = 0; k < a.length; k++) {
      if (a[k] != b[k]) {
        return false;
      }
    }
    return true;
  }

  /// See [MarkdownController.scrollToHeading].
  bool _scrollTo(String slug) {
    final k = _headings.indexWhere((heading) => heading.slug == slug);
    if (k < 0 || !mounted) {
      return false;
    }
    final node = _headingNodes[k];
    Element? found;
    void visit(Element element) {
      if (found != null) {
        return;
      }
      if (element.widget case _HeadingMark(:final heading)
          when identical(heading, node)) {
        found = element;
      } else {
        element.visitChildren(visit);
      }
    }

    (context as Element).visitChildren(visit);
    final element = found;
    if (element == null || element.findRenderObject() == null) {
      return false;
    }
    Scrollable.ensureVisible(element);
    return true;
  }

  /// [blocks] one under another, [gap] rows apart, lists in them [depth]
  /// lists deep; adds the definitions their references use to [uses].
  Widget _column(List<MdBlock> blocks, int depth, int gap, _Uses uses) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        gap: gap,
        children: [for (final block in blocks) _block(block, depth, uses)],
      );

  /// The widget made for [node], a block or a list item, where that was
  /// made [by] the same and its references have the definitions they had;
  /// adds the definitions its references use to [uses]. Null where it is
  /// to be made again, by [_made].
  Widget? _kept(Object node, Object by, _Uses uses) {
    final made = _made[node];
    if (made == null || made.by != by || !_stillDefined(made.uses)) {
      return null;
    }
    if (made.uses.isNotEmpty) {
      uses.addAll(made.uses);
    }
    _linked = _linked || made.linked;
    return made.widget;
  }

  /// The widget [make] makes for [node], remembered as made [by] what it
  /// was; adds the definitions its references use to [uses].
  Widget _make(
    Object node,
    Object by,
    _Uses uses,
    Widget Function(_Uses uses) make,
  ) {
    final own = <String, MdDefinition?>{};
    final outer = _linked;
    _linked = false;
    final widget = make(own);
    _made[node] = _Made(widget, by, own, linked: _linked);
    uses.addAll(own);
    _linked = outer || _linked;
    return widget;
  }

  bool _stillDefined(_Uses uses) {
    if (uses.isEmpty) {
      return true;
    }
    for (final MapEntry(:key, :value) in uses.entries) {
      if (_definitions[key] != value) {
        return false;
      }
    }
    return true;
  }

  Widget _block(MdBlock block, int depth, _Uses uses) =>
      _kept(block, depth, uses) ?? _newBlock(block, depth, uses);

  /// Apart from [_block], whose context the closure would otherwise cost
  /// for every block kept.
  Widget _newBlock(MdBlock block, int depth, _Uses uses) =>
      _make(block, depth, uses, (uses) => _makeBlock(block, depth, uses));

  Widget _makeBlock(MdBlock block, int depth, _Uses uses) => switch (block) {
    MdParagraph(:final children) => _text(children, uses),
    final MdHeading heading => _HeadingMark(
      heading,
      child: _text(
        heading.children,
        uses,
        style: _theme.heading(heading.level),
      ),
    ),
    MdCodeBlock(:final code, :final language) => Box(
      style: _theme.codeBlock,
      padding: const EdgeInsets.x(1),
      child: CodeView(
        code,
        language: languageNamed(language),
        tabWidth: widget.tabWidth,
        wrap: widget.codeWrap,
      ),
    ),
    MdThematicBreak() => Divider(style: _theme.rule),
    MdBlockQuote(:final children) => Box(
      border: Border(left: _theme.quoteBar),
      padding: const EdgeInsets.only(left: 1),
      child: DefaultTextStyle(
        style: _theme.quote,
        child: _column(children, depth, 1, uses),
      ),
    ),
    final MdList list => _list(list, depth, uses),
    final MdTable table => _table(table, uses),
  };

  /// [inlines] as a [Text.rich] in [style], which knows its links.
  Widget _text(
    List<MdInline> inlines,
    _Uses uses, {
    Style style = const Style(),
  }) {
    final links = <_Link>[];
    final text = Text.rich(_spans(inlines, uses, links), style: style);
    return links.isEmpty ? text : _Links(links, child: text);
  }

  static const _bullets = ['•', '◦', '▪'];

  Widget _list(MdList list, int depth, _Uses uses) {
    final items = list.items;
    final start = list.start;
    final markers = [
      for (var k = 0; k < items.length; k++)
        switch ((start, items[k].checked)) {
          (null, null) => _bullets[depth % _bullets.length],
          (null, final checked?) => _box(checked),
          (final start?, null) => '${start + k}${list.marker}',
          (final start?, final checked?) =>
            '${start + k}${list.marker} ${_box(checked)}',
        },
    ];
    // the markers the column is as wide as the widest of
    final column = start == null
        ? markers.toSet().toList()
        : [markers.reduce((a, b) => b.length > a.length ? b : a)];
    final gap = list.tight ? 0 : 1;
    final columnKey = column.join('\n');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      gap: gap,
      children: [
        for (var k = 0; k < items.length; k++)
          _item(
            items[k],
            (depth, gap, markers[k], columnKey),
            markers[k],
            column,
            depth,
            uses,
            end: start != null,
          ),
      ],
    );
  }

  /// The widget of [item], marked by [marker] in a column of [column]'s
  /// width, made [by] these.
  Widget _item(
    MdListItem item,
    (int, int, String, String) by,
    String marker,
    List<String> column,
    int depth,
    _Uses uses, {
    required bool end,
  }) =>
      _kept(item, by, uses) ??
      _newItem(item, by, marker, column, depth, uses, end: end);

  /// Apart from [_item], whose context the closure would otherwise cost
  /// for every item kept.
  Widget _newItem(
    MdListItem item,
    (int, int, String, String) by,
    String marker,
    List<String> column,
    int depth,
    _Uses uses, {
    required bool end,
  }) => _make(
    item,
    by,
    uses,
    (uses) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        _Marker(marker, column: column, end: end, style: _theme.marker),
        Expanded(child: _column(item.children, depth + 1, by.$2, uses)),
      ],
    ),
  );

  static String _box(bool checked) => checked ? '☑' : '☐';

  Widget _table(MdTable table, _Uses uses) {
    final header = [
      for (final cell in table.header)
        _spans(cell, uses).map((span) => span.text).join(),
    ];
    final links = <_Link>[];
    final rows = [
      for (final row in table.rows)
        [for (final cell in row) _spans(cell, uses, links)],
    ];
    final inert = _Inert(
      child: SizedBox(
        height: rows.length + 2,
        child: Table<List<List<Span>>>(
          rows: rows,
          columns: [
            for (var j = 0; j < table.align.length; j++)
              TableColumn(
                title: header[j],
                cell: (row) => TableCell.rich(row[j]),
                align: switch (table.align[j]) {
                  MdAlign.none || MdAlign.left => TextAlign.left,
                  MdAlign.center => TextAlign.center,
                  MdAlign.right => TextAlign.right,
                },
              ),
          ],
          selection: TableSelection.none,
          canRequestFocus: false,
          columnGap: 3,
          border: BorderType.single,
          headerStyle: _theme.tableHeader,
          borderStyle: _theme.tableBorder,
        ),
      ),
    );
    return links.isEmpty ? inert : _Links(links, cells: true, child: inert);
  }

  /// [inlines], their references resolved, as spans in their styles;
  /// adds the definitions the references use to [uses], and the links and
  /// images to [links], the innermost first.
  List<Span> _spans(
    List<MdInline> inlines,
    _Uses uses, [
    List<_Link>? links,
  ]) {
    _refer(inlines, uses);
    final theme = _theme;
    final hyperlinks = widget.hyperlinks;
    final out = <Span>[];
    var length = 0;
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
            _linked = true;
            final start = length;
            final linked = style.merge(theme.link);
            add(
              children,
              hyperlinks ? linked.merge(Style(link: destination)) : linked,
            );
            links?.add((
              start: start,
              end: length,
              destination: destination,
              title: title,
            ));
          case MdImage(:final source, :final title, :final alt):
            _linked = true;
            final start = length;
            final shown = style.merge(theme.image);
            put(
              alt.isEmpty ? source : alt,
              hyperlinks ? shown.merge(Style(link: source)) : shown,
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

    add(resolveInlines(inlines, _definitions), const Style());
    return out;
  }

  /// Adds the labels of the references in [inlines] to [uses], each with
  /// its definition now.
  void _refer(List<MdInline> inlines, _Uses uses) {
    for (final inline in inlines) {
      switch (inline) {
        case MdReference(:final label, :final children):
          final key = normalizeLabel(label);
          uses[key] = _definitions[key];
          _refer(children, uses);
        case MdEmphasis(:final children) ||
            MdStrong(:final children) ||
            MdStrikethrough(:final children) ||
            MdLink(:final children) ||
            MdImage(:final children):
          _refer(children, uses);
        case MdText() || MdCode() || MdSoftBreak() || MdHardBreak():
          break;
      }
    }
  }
}

/// [child], a heading of the view: what
/// [MarkdownController.scrollToHeading] finds [heading] by.
final class _HeadingMark extends StatelessWidget {
  const _HeadingMark(this.heading, {required this.child});

  final MdHeading heading;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// [child] in a [MouseRegion] whose pointer has the shape of a hand while
/// the mouse is over a link: a run of a paragraph that a [_Links] around it
/// covers, or a cell whose style links it (OSC 8). Only where the view has
/// a link ([linked]), a link does something ([shaped]) and the terminal
/// shows the pointer's shape does it follow the mouse. A click on a link,
/// pressed and released on the same cell, it tells [onLinkTap].
final class _LinkPointer extends StatefulWidget {
  const _LinkPointer({
    required this.linked,
    required this.shaped,
    required this.onLinkTap,
    required this.child,
  });

  final bool linked;
  final bool shaped;
  final MarkdownLinkCallback? onLinkTap;
  final Widget child;

  @override
  State<_LinkPointer> createState() => _LinkPointerState();
}

final class _LinkPointerState extends State<_LinkPointer> {
  /// Whether the mouse is over a link.
  var _over = false;

  /// The cell the left button was pressed on, while it is held.
  (int, int)? _pressed;

  @override
  void didUpdateWidget(_LinkPointer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.linked) {
      _over = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final follows =
        widget.linked &&
        widget.shaped &&
        (TerminalStatus.of(context)?.showsPointerShape ?? false);
    final taps = widget.linked && widget.onLinkTap != null;
    return MouseRegion(
      onHover: follows ? _hover : null,
      onExit: follows ? _exit : null,
      cursor: follows && _over ? PointerShape.pointer : null,
      behavior: HitTestBehavior.translucent,
      child: Listener(
        onDown: taps ? _down : null,
        onUp: taps ? _up : null,
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      ),
    );
  }

  void _hover(PointerEvent event) => _show(_linkUnder(event) != null);

  void _exit(PointerEvent event) => _show(false);

  void _show(bool over) {
    if (over != _over) {
      setState(() => _over = over);
    }
  }

  void _down(PointerEvent event) =>
      _pressed = event.button == 0 ? (event.x, event.y) : null;

  void _up(PointerEvent event) {
    final pressed = _pressed;
    _pressed = null;
    if (event.button != 0 || pressed != (event.x, event.y)) {
      return;
    }
    if (_linkUnder(event) case final link?) {
      widget.onLinkTap?.call(link.destination, link.title);
    }
  }

  /// The link under the mouse, if there is one.
  _Link? _linkUnder(PointerEvent event) {
    final region = context.findRenderObject();
    return region == null ? null : _linkAt(region, event.x, event.y, null);
  }

  /// The link at the cell [x], [y] of [object], in its coordinates: of the
  /// cluster there of the deepest paragraph, by the [_RenderLinks]
  /// [around] it; a cell whose style links it, in a table or outside one,
  /// for a link without a title, or with that of the first of the table's
  /// to the same destination.
  static _Link? _linkAt(
    RenderObject object,
    int x,
    int y,
    _RenderLinks? around,
  ) {
    if (x < 0 || y < 0 || x >= object.width || y >= object.height) {
      return null;
    }
    if (object is RenderParagraph) {
      final (start, end) = object.textRangeAt(x, y);
      if (end == start) {
        return null;
      }
      if (around != null && !around.cells) {
        for (final link in around.links) {
          if (link.start <= start && start < link.end) {
            return link;
          }
        }
        return null;
      }
      var at = 0;
      for (final (text, pen) in object.spans) {
        at += text.length;
        if (start < at) {
          final destination = pen.link;
          if (destination == null) {
            return null;
          }
          String? title;
          for (final link in around?.links ?? const <_Link>[]) {
            if (link.destination == destination) {
              title = link.title;
              break;
            }
          }
          return (start: 0, end: 0, destination: destination, title: title);
        }
      }
      return null;
    }
    final inner = object is _RenderLinks ? object : around;
    _Link? found;
    object.visitChildren((child) {
      found ??= _linkAt(
        child,
        x - child.parentData.dx,
        y - child.parentData.dy,
        inner,
      );
    });
    return found;
  }
}

/// [child], a paragraph, a heading or (where [cells]) a table, whose
/// [links] its render object keeps for the pointer of the view.
final class _Links extends SingleChildRenderObjectWidget {
  const _Links(this.links, {required Widget super.child, this.cells = false});

  final List<_Link> links;
  final bool cells;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderLinks createRenderObject(BuildContext context) =>
      _RenderLinks(links, cells: cells);

  @override
  void updateRenderObject(BuildContext context, _RenderLinks renderObject) =>
      renderObject
        ..links = links
        ..cells = cells;
}

/// What a [_Links] lays out and paints: its child as its own, hit as it is.
/// Its [links] cover the text of the paragraph it is around, unless
/// [cells]: then they are those of a table's cells, in no paragraph's
/// text.
final class _RenderLinks extends _RenderProxy {
  _RenderLinks(this.links, {required this.cells});

  List<_Link> links;
  bool cells;
}

/// [text] on the first row, in [style] merged onto the [DefaultTextStyle],
/// at the end of a column as wide as the widest of [column] where [end],
/// at its start otherwise. Not a [Text]: a [SelectionArea] leaves it out.
final class _Marker extends LeafRenderObjectWidget {
  const _Marker(
    this.text, {
    required this.column,
    required this.end,
    required this.style,
  });

  final String text;
  final List<String> column;
  final bool end;
  final Style style;

  @override
  _RenderMarker createRenderObject(BuildContext context) => _RenderMarker(
    text,
    column,
    end,
    DefaultTextStyle.of(context).merge(style),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderMarker renderObject) {
    renderObject
      ..text = text
      ..column = column
      ..end = end
      ..style = DefaultTextStyle.of(context).merge(style);
  }
}

/// What a [_Marker] lays out and paints: a row as tall, its text measured
/// as the canvas draws it.
final class _RenderMarker extends RenderObject {
  _RenderMarker(this._text, this._column, this._end, this._style);

  String _text;
  String get text => _text;
  set text(String t) {
    if (t != _text) {
      _text = t;
      markNeedsPaint();
    }
  }

  List<String> _column;
  List<String> get column => _column;
  set column(List<String> c) {
    if (c.length == _column.length) {
      var k = 0;
      while (k < c.length && c[k] == _column[k]) {
        k++;
      }
      if (k == c.length) {
        return;
      }
    }
    _column = c;
    markNeedsLayout();
  }

  bool _end;
  bool get end => _end;
  set end(bool e) {
    if (e != _end) {
      _end = e;
      markNeedsPaint();
    }
  }

  Style _style;
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  /// The columns [text] takes as the owner's segmenter measures it.
  int _widthOf(String text) {
    final segmenter = owner?.segmenter;
    return segmenter == null
        ? stringWidth(text)
        : stringWidth(
            text,
            mode: segmenter.mode,
            ambiguousWidth: segmenter.ambiguousWidth,
          );
  }

  int get _columnWidth =>
      _column.fold(0, (widest, text) => math.max(widest, _widthOf(text)));

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_columnWidth);
    height = c.constrainH(1);
  }

  @override
  int computeMinIntrinsicWidth(int height) => _columnWidth;

  @override
  int computeMaxIntrinsicWidth(int height) => _columnWidth;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    canvas.text(
      _end ? width - _widthOf(_text) : 0,
      0,
      _text,
      _style.penIn(canvas.styles),
    );
  }
}

/// [child] laid out and painted as its own, but not hit by the mouse: the
/// wheel over it goes to a scrollable around it, a press to a
/// [SelectionArea] around it.
final class _Inert extends SingleChildRenderObjectWidget {
  const _Inert({required Widget super.child});

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderInert createRenderObject(BuildContext context) => _RenderInert();
}

/// What an [_Inert] lays out and paints: as big as its child, never hit.
final class _RenderInert extends _RenderProxy {
  @override
  bool hitTestChildren(HitTestResult result, int x, int y) => false;
}

/// A render object as big as its child, which it lays out and paints as
/// its own.
abstract class _RenderProxy extends RenderObject
    with RenderObjectWithChildMixin {
  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}
