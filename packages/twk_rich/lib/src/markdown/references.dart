/// Reference links made links or text by the link reference definitions of
/// their document: [resolveReferences], [resolveInlines].
library;

import 'inlines.dart';
import 'nodes.dart';

/// [blocks] with each [MdReference] in them resolved by [definitions], the
/// definitions of their document by the [normalizeLabel] of their label.
///
/// A reference whose label a definition matches is a link or image to its
/// destination; one that no definition matches, and a link reference within
/// a link, is its literal text, such as `[text][label]`. A block with no
/// reference in it is itself.
List<MdBlock> resolveReferences(
  List<MdBlock> blocks,
  Map<String, MdDefinition> definitions,
) => _Resolver(definitions).blocks(blocks);

/// [inlines] with each [MdReference] in them resolved by [definitions], as
/// [resolveReferences] resolves those of blocks.
List<MdInline> resolveInlines(
  List<MdInline> inlines,
  Map<String, MdDefinition> definitions,
) => _Resolver(definitions).inlines(inlines, inLink: false);

final class _Resolver {
  _Resolver(this.definitions);

  final Map<String, MdDefinition> definitions;

  List<MdBlock> blocks(List<MdBlock> blocks) =>
      _same(blocks, [for (final block in blocks) this.block(block)]);

  MdBlock block(MdBlock block) {
    switch (block) {
      case MdParagraph(:final children):
        final resolved = inlines(children, inLink: false);
        return identical(resolved, children) ? block : MdParagraph(resolved);
      case MdHeading(:final level, :final children):
        final resolved = inlines(children, inLink: false);
        return identical(resolved, children)
            ? block
            : MdHeading(level, resolved);
      case MdBlockQuote(:final children):
        final resolved = blocks(children);
        return identical(resolved, children) ? block : MdBlockQuote(resolved);
      case MdList(:final items):
        final resolved = _same(items, [
          for (final item in items) this.item(item),
        ]);
        return identical(resolved, items)
            ? block
            : MdList(
                resolved,
                start: block.start,
                marker: block.marker,
                tight: block.tight,
              );
      case MdTable(:final align, :final header, :final rows):
        final resolvedHeader = cells(header);
        final resolvedRows = _same(rows, [for (final row in rows) cells(row)]);
        return identical(resolvedHeader, header) &&
                identical(resolvedRows, rows)
            ? block
            : MdTable(align, resolvedHeader, resolvedRows);
      case MdCodeBlock() || MdThematicBreak():
        return block;
    }
  }

  MdListItem item(MdListItem item) {
    final children = blocks(item.children);
    return identical(children, item.children)
        ? item
        : MdListItem(children, checked: item.checked);
  }

  List<List<MdInline>> cells(List<List<MdInline>> cells) =>
      _same(cells, [for (final cell in cells) inlines(cell, inLink: false)]);

  /// [inlines] resolved, within a link where [inLink]; their text with links
  /// of the email addresses in it where [emails], as text parsed within a
  /// reference that turns out not to be a link has none.
  List<MdInline> inlines(
    List<MdInline> inlines, {
    required bool inLink,
    bool emails = false,
  }) {
    final out = <MdInline>[];
    void add(MdInline inline) {
      if (inline case MdText(:final text)
          when out.isNotEmpty && out.last is MdText) {
        out.last = MdText((out.last as MdText).text + text);
      } else {
        out.add(inline);
      }
    }

    for (final inline in inlines) {
      switch (inline) {
        case MdReference():
          reference(inline, add, inLink: inLink);
        case MdText(:final text) when emails:
          linkEmails(text).forEach(add);
        case MdEmphasis(:final children):
          final resolved = this.inlines(
            children,
            inLink: inLink,
            emails: emails,
          );
          add(identical(resolved, children) ? inline : MdEmphasis(resolved));
        case MdStrong(:final children):
          final resolved = this.inlines(
            children,
            inLink: inLink,
            emails: emails,
          );
          add(identical(resolved, children) ? inline : MdStrong(resolved));
        case MdStrikethrough(:final children):
          final resolved = this.inlines(
            children,
            inLink: inLink,
            emails: emails,
          );
          add(
            identical(resolved, children) ? inline : MdStrikethrough(resolved),
          );
        case MdLink(:final destination, :final children, :final title):
          final resolved = this.inlines(children, inLink: true);
          add(
            identical(resolved, children)
                ? inline
                : MdLink(destination, resolved, title: title),
          );
        case MdImage(:final source, :final children, :final title):
          final resolved = this.inlines(children, inLink: inLink);
          add(
            identical(resolved, children)
                ? inline
                : MdImage(source, resolved, title: title),
          );
        case MdText() || MdCode() || MdSoftBreak() || MdHardBreak():
          add(inline);
      }
    }
    return _same(inlines, out);
  }

  /// Adds [reference] resolved, within a link where [inLink], by [add].
  void reference(
    MdReference reference,
    void Function(MdInline) add, {
    required bool inLink,
  }) {
    final definition = reference.image || !inLink
        ? definitions[normalizeLabel(reference.label)]
        : null;
    final MdReference(:children, :image, :label, :kind) = reference;
    if (definition != null) {
      final MdDefinition(:destination, :title) = definition;
      add(
        image
            ? MdImage(
                destination,
                inlines(children, inLink: inLink),
                title: title,
              )
            : MdLink(
                destination,
                inlines(children, inLink: true),
                title: title,
              ),
      );
      return;
    }
    add(MdText(image ? '![' : '['));
    inlines(children, inLink: inLink, emails: !inLink).forEach(add);
    switch (kind) {
      case MdReferenceKind.full:
        add(const MdText(']['));
        inlines(parseInlines(label), inLink: inLink).forEach(add);
        add(const MdText(']'));
      case MdReferenceKind.collapsed:
        add(const MdText('][]'));
      case MdReferenceKind.shortcut:
        add(const MdText(']'));
    }
  }
}

/// [old] where [fresh] holds the very elements it does, [fresh] otherwise.
List<T> _same<T>(List<T> old, List<T> fresh) {
  if (old.length != fresh.length) {
    return fresh;
  }
  for (var k = 0; k < old.length; k++) {
    if (!identical(old[k], fresh[k])) {
      return fresh;
    }
  }
  return old;
}
