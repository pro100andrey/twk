/// The tree a Markdown document parses into: [MdBlock]s holding [MdInline]
/// content, all of them plain values.
library;

/// A block of a Markdown document: [MdParagraph], [MdHeading],
/// [MdCodeBlock], [MdThematicBreak], [MdBlockQuote], [MdList] or [MdTable].
///
/// Blocks are values: two are equal when they are of one kind and hold equal
/// content.
sealed class MdBlock {
  const MdBlock();
}

/// A paragraph.
final class MdParagraph extends MdBlock {
  /// A paragraph of [children].
  const MdParagraph(this.children);

  /// The inline content.
  final List<MdInline> children;

  @override
  bool operator ==(Object other) =>
      other is MdParagraph && _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdParagraph, _hash(children));

  @override
  String toString() => 'MdParagraph($children)';
}

/// A heading, of [level] 1 to 6.
final class MdHeading extends MdBlock {
  /// A heading of [level] showing [children].
  const MdHeading(this.level, this.children);

  /// 1 for the topmost heading to 6.
  final int level;

  /// The inline content.
  final List<MdInline> children;

  @override
  bool operator ==(Object other) =>
      other is MdHeading &&
      other.level == level &&
      _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdHeading, level, _hash(children));

  @override
  String toString() => 'MdHeading($level, $children)';
}

/// A block of code: fenced, with an info string, or indented.
final class MdCodeBlock extends MdBlock {
  /// A block of [code], indented unless [fenced], with [info] after its
  /// opening fence, none by default.
  const MdCodeBlock(this.code, {this.info = '', this.fenced = false});

  /// The lines of code, each ending in a line feed.
  final String code;

  /// The text after the opening fence; empty for indented code.
  final String info;

  /// Whether the code is fenced rather than indented.
  final bool fenced;

  /// The first word of [info]: the language of the code, by convention.
  String get language {
    final end = info.indexOf(RegExp('[ \t]'));
    return end < 0 ? info : info.substring(0, end);
  }

  @override
  bool operator ==(Object other) =>
      other is MdCodeBlock &&
      other.code == code &&
      other.info == info &&
      other.fenced == fenced;

  @override
  int get hashCode => Object.hash(MdCodeBlock, code, info, fenced);

  @override
  String toString() =>
      'MdCodeBlock(${_quote(code)}, info: ${_quote(info)}, fenced: $fenced)';
}

/// A thematic break: a line across.
final class MdThematicBreak extends MdBlock {
  /// A thematic break.
  const MdThematicBreak();

  @override
  bool operator ==(Object other) => other is MdThematicBreak;

  @override
  int get hashCode => (MdThematicBreak).hashCode;

  @override
  String toString() => 'MdThematicBreak()';
}

/// A block quote.
final class MdBlockQuote extends MdBlock {
  /// A block quote of [children].
  const MdBlockQuote(this.children);

  /// The blocks quoted.
  final List<MdBlock> children;

  @override
  bool operator ==(Object other) =>
      other is MdBlockQuote && _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdBlockQuote, _hash(children));

  @override
  String toString() => 'MdBlockQuote($children)';
}

/// A list: a bullet list, or an ordered one when [start] is not null.
final class MdList extends MdBlock {
  /// A list of [items], bullet unless [start] is given, marked by
  /// [marker], `-` by default, and tight unless [tight] is false.
  const MdList(this.items, {this.start, this.marker = '-', this.tight = true});

  /// The items.
  final List<MdListItem> items;

  /// The number of the first item of an ordered list; null for a bullet
  /// list.
  final int? start;

  /// The bullet, `-`, `+` or `*`; for an ordered list the delimiter after
  /// each number, `.` or `)`.
  final String marker;

  /// Whether no blank line separates the items or the blocks within one: the
  /// paragraphs of a tight list are shown without space between them.
  final bool tight;

  /// Whether the items are numbered.
  bool get ordered => start != null;

  @override
  bool operator ==(Object other) =>
      other is MdList &&
      other.start == start &&
      other.marker == marker &&
      other.tight == tight &&
      _equal(other.items, items);

  @override
  int get hashCode => Object.hash(MdList, start, marker, tight, _hash(items));

  @override
  String toString() =>
      'MdList($items, start: $start, marker: $marker, tight: $tight)';
}

/// An item of an [MdList].
final class MdListItem {
  /// An item of [children], a task whose box is [checked] or not where
  /// that is given.
  const MdListItem(this.children, {this.checked});

  /// The blocks of the item.
  final List<MdBlock> children;

  /// Whether the box of a task list item is checked; null for an item that
  /// is not a task.
  final bool? checked;

  @override
  bool operator ==(Object other) =>
      other is MdListItem &&
      other.checked == checked &&
      _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdListItem, checked, _hash(children));

  @override
  String toString() =>
      'MdListItem($children${checked == null ? '' : ', checked: $checked'})';
}

/// How the cells of a column of an [MdTable] are aligned.
enum MdAlign {
  /// As the reader sees fit: no colon in the delimiter row.
  none,

  /// To the left: `:--`.
  left,

  /// Centered: `:-:`.
  center,

  /// To the right: `--:`.
  right,
}

/// A table: a header row, the alignment of each column and rows of cells.
final class MdTable extends MdBlock {
  /// A table of [header] and [rows], its columns aligned as [align] says:
  /// the header and each row with a cell per entry of [align].
  const MdTable(this.align, this.header, this.rows);

  /// The alignment of each column; one per column.
  final List<MdAlign> align;

  /// The inline content of each cell of the header row; one per column.
  final List<List<MdInline>> header;

  /// The rows below the header, each with the inline content of one cell per
  /// column.
  final List<List<List<MdInline>>> rows;

  @override
  bool operator ==(Object other) =>
      other is MdTable &&
      _equal(other.align, align) &&
      _equal(other.header, header) &&
      _equal(other.rows, rows);

  @override
  int get hashCode =>
      Object.hash(MdTable, _hash(align), _hash(header), _hash(rows));

  @override
  String toString() => 'MdTable($align, $header, $rows)';
}

/// Inline content: [MdText], [MdCode], [MdEmphasis], [MdStrong],
/// [MdStrikethrough], [MdLink], [MdImage], [MdReference], [MdSoftBreak] or
/// [MdHardBreak].
///
/// Inline nodes are values, as blocks are.
sealed class MdInline {
  const MdInline();
}

/// Text, with backslash escapes and character references resolved.
final class MdText extends MdInline {
  /// [text] as it is shown.
  const MdText(this.text);

  /// The text.
  final String text;

  @override
  bool operator ==(Object other) => other is MdText && other.text == text;

  @override
  int get hashCode => Object.hash(MdText, text);

  @override
  String toString() => 'MdText(${_quote(text)})';
}

/// A code span.
final class MdCode extends MdInline {
  /// A code span of [code].
  const MdCode(this.code);

  /// The code, line endings turned to spaces.
  final String code;

  @override
  bool operator ==(Object other) => other is MdCode && other.code == code;

  @override
  int get hashCode => Object.hash(MdCode, code);

  @override
  String toString() => 'MdCode(${_quote(code)})';
}

/// Emphasis: `*this*` or `_this_`.
final class MdEmphasis extends MdInline {
  /// [children] emphasized.
  const MdEmphasis(this.children);

  /// The content emphasized.
  final List<MdInline> children;

  @override
  bool operator ==(Object other) =>
      other is MdEmphasis && _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdEmphasis, _hash(children));

  @override
  String toString() => 'MdEmphasis($children)';
}

/// Strong emphasis: `**this**` or `__this__`.
final class MdStrong extends MdInline {
  /// [children] strongly emphasized.
  const MdStrong(this.children);

  /// The content emphasized.
  final List<MdInline> children;

  @override
  bool operator ==(Object other) =>
      other is MdStrong && _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdStrong, _hash(children));

  @override
  String toString() => 'MdStrong($children)';
}

/// Struck through text: `~~this~~` or `~this~`.
final class MdStrikethrough extends MdInline {
  /// [children] struck through.
  const MdStrikethrough(this.children);

  /// The content struck through.
  final List<MdInline> children;

  @override
  bool operator ==(Object other) =>
      other is MdStrikethrough && _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdStrikethrough, _hash(children));

  @override
  String toString() => 'MdStrikethrough($children)';
}

/// A link: `[text](destination "title")`, an autolink `<destination>` or a
/// URL or email address in the text.
final class MdLink extends MdInline {
  /// A link to [destination] showing [children], with [title] or none.
  const MdLink(this.destination, this.children, {this.title});

  /// Where the link leads, with escapes and references resolved; `mailto:`
  /// before an email address and `http://` before a `www.` address.
  final String destination;

  /// The link text.
  final List<MdInline> children;

  /// The title; null when the link has none.
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is MdLink &&
      other.destination == destination &&
      other.title == title &&
      _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdLink, destination, title, _hash(children));

  @override
  String toString() =>
      'MdLink(${_quote(destination)}, $children'
      '${title == null ? '' : ', title: ${_quote(title!)}'})';
}

/// An image, `![description](source "title")`, which a terminal shows as
/// its [alt] text.
final class MdImage extends MdInline {
  /// An image at [source] described by [children], with [title] or none.
  const MdImage(this.source, this.children, {this.title});

  /// The location of the image.
  final String source;

  /// The description.
  final List<MdInline> children;

  /// The title; null when the image has none.
  final String? title;

  /// The description as plain text, line breaks as line feeds.
  String get alt => _plain(children);

  @override
  bool operator ==(Object other) =>
      other is MdImage &&
      other.source == source &&
      other.title == title &&
      _equal(other.children, children);

  @override
  int get hashCode => Object.hash(MdImage, source, title, _hash(children));

  @override
  String toString() =>
      'MdImage(${_quote(source)}, $children'
      '${title == null ? '' : ', title: ${_quote(title!)}'})';
}

/// How an [MdReference] is written.
enum MdReferenceKind {
  /// `[text][label]`.
  full,

  /// `[label][]`: the label is the text.
  collapsed,

  /// `[label]`: the label is the text.
  shortcut,
}

/// A reference link, `[text][label]`, `[label][]` or `[label]`, or, with a
/// `!` before it, a reference image.
///
/// Which it is depends on the link reference definitions of the whole
/// document, which may come after it: where one defines a label that
/// matches [label] (by [normalizeLabel]) the reference is a link or image to
/// its destination, and where none does it is its literal text, such as
/// `[label]`. A link reference within a link is its literal text, as links
/// do not nest.
final class MdReference extends MdInline {
  /// A reference to [label] showing [children], written as [kind] says,
  /// a full reference by default, an image where [image].
  const MdReference(
    this.label,
    this.children, {
    this.kind = MdReferenceKind.full,
    this.image = false,
  });

  /// The label as written between its brackets.
  final String label;

  /// The link text, or the description of an image.
  final List<MdInline> children;

  /// How the reference is written.
  final MdReferenceKind kind;

  /// Whether a `!` makes it an image.
  final bool image;

  @override
  bool operator ==(Object other) =>
      other is MdReference &&
      other.label == label &&
      other.kind == kind &&
      other.image == image &&
      _equal(other.children, children);

  @override
  int get hashCode =>
      Object.hash(MdReference, label, kind, image, _hash(children));

  @override
  String toString() =>
      'MdReference(${_quote(label)}, $children, kind: ${kind.name}, '
      'image: $image)';
}

/// A link reference definition, `[label]: destination "title"`: where the
/// [MdReference]s whose label matches [label] lead.
final class MdDefinition {
  /// A definition of [label] leading to [destination], with [title] or
  /// none.
  const MdDefinition(this.label, this.destination, {this.title});

  /// The label as written between its brackets.
  final String label;

  /// Where the references lead, with escapes and character references
  /// resolved.
  final String destination;

  /// The title; null when the definition has none.
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is MdDefinition &&
      other.label == label &&
      other.destination == destination &&
      other.title == title;

  @override
  int get hashCode => Object.hash(MdDefinition, label, destination, title);

  @override
  String toString() =>
      'MdDefinition(${_quote(label)}, ${_quote(destination)}'
      '${title == null ? '' : ', title: ${_quote(title!)}'})';
}

/// The key of the link label [label] among link reference definitions:
/// case-folded, without whitespace at either end and with each run of
/// spaces, tabs and line endings within it one space. Two labels match
/// when their keys are equal.
String normalizeLabel(String label) => label
    .trim()
    .replaceAll(_labelSpace, ' ')
    .toLowerCase()
    .replaceAll('ß', 'ss')
    .toUpperCase();

final _labelSpace = RegExp('[ \t\r\n]+');

/// A line ending within a paragraph, shown as a space or a line ending.
final class MdSoftBreak extends MdInline {
  /// A line ending within a paragraph.
  const MdSoftBreak();

  @override
  bool operator ==(Object other) => other is MdSoftBreak;

  @override
  int get hashCode => (MdSoftBreak).hashCode;

  @override
  String toString() => 'MdSoftBreak()';
}

/// A hard line break: two spaces or a backslash before a line ending.
final class MdHardBreak extends MdInline {
  /// A hard line break.
  const MdHardBreak();

  @override
  bool operator ==(Object other) => other is MdHardBreak;

  @override
  int get hashCode => (MdHardBreak).hashCode;

  @override
  String toString() => 'MdHardBreak()';
}

String _plain(List<MdInline> inlines) {
  final out = StringBuffer();
  void add(List<MdInline> inlines) {
    for (final inline in inlines) {
      switch (inline) {
        case MdText(:final text):
          out.write(text);
        case MdCode(:final code):
          out.write(code);
        case MdSoftBreak() || MdHardBreak():
          out.write('\n');
        case MdEmphasis(:final children) ||
            MdStrong(:final children) ||
            MdStrikethrough(:final children) ||
            MdLink(:final children) ||
            MdImage(:final children) ||
            MdReference(:final children):
          add(children);
      }
    }
  }

  add(inlines);
  return out.toString();
}

/// Whether [a] and [b] hold equal elements, lists compared element by
/// element.
bool _equal(List<Object?> a, List<Object?> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var k = 0; k < a.length; k++) {
    final x = a[k];
    final y = b[k];
    if (x is List<Object?> && y is List<Object?>) {
      if (!_equal(x, y)) {
        return false;
      }
    } else if (x != y) {
      return false;
    }
  }
  return true;
}

int _hash(List<Object?> list) => Object.hashAll([
  for (final x in list)
    if (x is List<Object?>) _hash(x) else x,
]);

String _quote(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll("'", r"\'");
  return "'$escaped'";
}
