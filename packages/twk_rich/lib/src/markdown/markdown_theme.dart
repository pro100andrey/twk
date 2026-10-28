/// The styles a [MarkdownView] shows a document in: [MarkdownTheme].
library;

import 'package:twk/twk.dart';

import '../highlight/highlight.dart';
import 'markdown_view.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late BuildContext context;
// late String readme;

/// The style of each part of a Markdown document, merged onto the style of
/// the text around it. A style left unset is the empty style: the part
/// looks as the text around it does.
///
/// A view whose headings and links are those of the theme, and whose code
/// spans are bold instead:
///
/// ```dart
/// MarkdownView(
///   readme,
///   theme: MarkdownTheme.from(Theme.of(context)).copyWith(
///     code: const Style(attrs: Attr.bold),
///   ),
/// )
/// ```
final class MarkdownTheme {
  /// The style of each part, the empty style unless given.
  const MarkdownTheme({
    this.heading1 = const Style(),
    this.heading2 = const Style(),
    this.heading3 = const Style(),
    this.heading4 = const Style(),
    this.heading5 = const Style(),
    this.heading6 = const Style(),
    this.emphasis = const Style(),
    this.strong = const Style(),
    this.strikethrough = const Style(),
    this.code = const Style(),
    this.link = const Style(),
    this.image = const Style(),
    this.codeBlock = const Style(),
    this.quote = const Style(),
    this.quoteBar = const Style(),
    this.marker = const Style(),
    this.rule = const Style(),
    this.tableHeader = const Style(),
    this.tableBorder = const Style(),
  });

  /// The styles in the colors of [theme], so that a document follows the
  /// app's theme and the terminal's brightness with it: headings bold, the
  /// first two in its primary color, the first underlined, the third in
  /// its accent and the last muted; emphasis italic, strong text bold,
  /// struck text struck through; code in its accent on its surface, code
  /// blocks on its surface; links in its primary color underlined, images
  /// in its info color italic; quotes muted with a bar in its border
  /// style, as are rules and the lines of tables; bullets and numbers
  /// muted; table headers bold.
  MarkdownTheme.from(ThemeData theme)
    : this(
        heading1: theme.primary.merge(_boldUnderline),
        heading2: theme.primary.merge(_bold),
        heading3: theme.accent.merge(_bold),
        heading4: _bold,
        heading5: _bold,
        heading6: theme.muted.merge(_bold),
        emphasis: const Style(attrs: Attr.italic),
        strong: _bold,
        strikethrough: const Style(attrs: Attr.strike),
        code: theme.accent.merge(theme.surface),
        link: theme.primary.merge(const Style(attrs: Attr.underline)),
        image: theme.info.merge(const Style(attrs: Attr.italic)),
        codeBlock: theme.surface,
        quote: theme.muted,
        quoteBar: theme.border,
        marker: theme.muted,
        rule: theme.border,
        tableHeader: _bold,
        tableBorder: theme.border,
      );

  static const _bold = Style(attrs: Attr.bold);
  static const _boldUnderline = Style(attrs: Attr.bold | Attr.underline);

  /// A heading of level 1, the topmost.
  final Style heading1;

  /// A heading of level 2.
  final Style heading2;

  /// A heading of level 3.
  final Style heading3;

  /// A heading of level 4.
  final Style heading4;

  /// A heading of level 5.
  final Style heading5;

  /// A heading of level 6, the lowest.
  final Style heading6;

  /// `*text*`.
  final Style emphasis;

  /// `**text**`.
  final Style strong;

  /// `~~text~~`.
  final Style strikethrough;

  /// A code span, `` `code` ``.
  final Style code;

  /// The text of a link, over the link itself.
  final Style link;

  /// What shows of an image: its description.
  final Style image;

  /// What a block of code is filled with, under the [SyntaxTheme]'s
  /// styles of its tokens.
  final Style codeBlock;

  /// The text of a block quote.
  final Style quote;

  /// The bar down the left of a block quote.
  final Style quoteBar;

  /// The bullets, numbers and boxes of list items.
  final Style marker;

  /// A thematic break, a line across.
  final Style rule;

  /// The header row of a table.
  final Style tableHeader;

  /// The lines between the columns of a table and under its header.
  final Style tableBorder;

  /// The style of a heading of [level], 1 to 6.
  Style heading(int level) => switch (level) {
    1 => heading1,
    2 => heading2,
    3 => heading3,
    4 => heading4,
    5 => heading5,
    _ => heading6,
  };

  /// This theme with the styles given replaced.
  MarkdownTheme copyWith({
    Style? heading1,
    Style? heading2,
    Style? heading3,
    Style? heading4,
    Style? heading5,
    Style? heading6,
    Style? emphasis,
    Style? strong,
    Style? strikethrough,
    Style? code,
    Style? link,
    Style? image,
    Style? codeBlock,
    Style? quote,
    Style? quoteBar,
    Style? marker,
    Style? rule,
    Style? tableHeader,
    Style? tableBorder,
  }) => MarkdownTheme(
    heading1: heading1 ?? this.heading1,
    heading2: heading2 ?? this.heading2,
    heading3: heading3 ?? this.heading3,
    heading4: heading4 ?? this.heading4,
    heading5: heading5 ?? this.heading5,
    heading6: heading6 ?? this.heading6,
    emphasis: emphasis ?? this.emphasis,
    strong: strong ?? this.strong,
    strikethrough: strikethrough ?? this.strikethrough,
    code: code ?? this.code,
    link: link ?? this.link,
    image: image ?? this.image,
    codeBlock: codeBlock ?? this.codeBlock,
    quote: quote ?? this.quote,
    quoteBar: quoteBar ?? this.quoteBar,
    marker: marker ?? this.marker,
    rule: rule ?? this.rule,
    tableHeader: tableHeader ?? this.tableHeader,
    tableBorder: tableBorder ?? this.tableBorder,
  );

  // Compared and hashed field by field: a list of the styles would be
  // made for each comparison, and MarkdownView compares its theme at each
  // build.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownTheme &&
          other.heading1 == heading1 &&
          other.heading2 == heading2 &&
          other.heading3 == heading3 &&
          other.heading4 == heading4 &&
          other.heading5 == heading5 &&
          other.heading6 == heading6 &&
          other.emphasis == emphasis &&
          other.strong == strong &&
          other.strikethrough == strikethrough &&
          other.code == code &&
          other.link == link &&
          other.image == image &&
          other.codeBlock == codeBlock &&
          other.quote == quote &&
          other.quoteBar == quoteBar &&
          other.marker == marker &&
          other.rule == rule &&
          other.tableHeader == tableHeader &&
          other.tableBorder == tableBorder;

  @override
  int get hashCode => Object.hash(
    heading1,
    heading2,
    heading3,
    heading4,
    heading5,
    heading6,
    emphasis,
    strong,
    strikethrough,
    code,
    link,
    image,
    codeBlock,
    quote,
    quoteBar,
    marker,
    rule,
    tableHeader,
    tableBorder,
  );
}
