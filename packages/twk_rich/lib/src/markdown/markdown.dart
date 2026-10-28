/// Markdown shown as widgets, also while it streams in: blocks that are
/// finished are not rebuilt when more text arrives.
///
/// [parseMarkdown] and [MarkdownStream] parse it into a tree of plain
/// values, [MdBlock]s holding [MdInline] content, and collect its link
/// reference definitions, by which [resolveReferences] makes the
/// [MdReference]s of the tree links or text. [MarkdownView] shows a
/// document, or blocks parsed already, in the styles of a [MarkdownTheme];
/// an app in the inline mode puts the blocks of an answer in the
/// terminal's history as they settle while the rest streams in
/// ([MarkdownStream.takeSettled]).
library;

import 'markdown_theme.dart';
import 'markdown_view.dart';
import 'nodes.dart';
import 'references.dart';
import 'stream.dart';

export 'markdown_theme.dart';
export 'markdown_view.dart';
export 'nodes.dart';
export 'references.dart';
export 'stream.dart';
