/// Markdown parsed into blocks, whole or as it streams in: [parseMarkdown],
/// [MarkdownStream].
library;

import 'dart:collection' show ListBase;

import 'blocks.dart';
import 'nodes.dart';
import 'references.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late MarkdownStream answer;
// late List<MdBlock> history;
// late Widget prompt;
// void setState(void Function() fn) {}

/// The blocks of the Markdown document [text].
///
/// ```dart
/// parseMarkdown('# Title\n\nSome *text*.');
/// // [MdHeading(1, [MdText('Title')]),
/// //  MdParagraph([MdText('Some '), MdEmphasis([MdText('text')]), MdText('.')])]
/// ```
///
/// CommonMark without HTML, which is text, and with GFM's tables, task list
/// items, strikethrough and links of URLs and addresses in the text. Block
/// quotes and list items nest at most 32 deep: a `>` or list marker that
/// would go deeper is text, so that no text nests past what the stack
/// holds.
///
/// Link reference definitions are left out of the blocks, and the reference
/// links and images that may use them are [MdReference]s: the
/// [MarkdownStream.definitions] of [text] has the definitions, which
/// [resolveReferences] makes them links or text by.
List<MdBlock> parseMarkdown(String text) => MarkdownStream(text).blocks;

/// A Markdown document that arrives in pieces, such as the answer of an
/// agent.
///
/// A block is [settled] once a complete line closes it: no text added later
/// changes it, and [blocks] keeps holding it as the very object it held.
/// [add] takes its own complete lines into the parser where it left off;
/// the blocks not settled are made again when they are next read, from
/// those lines and the line after them that more text may continue, so
/// that pieces added between two reads, as an answer streams in between
/// two frames, cost one making. Of the blocks not settled, any part equal
/// to what it was is kept, such as the finished items of a list that is
/// still growing, and a table parses only the rows added since; the text
/// of an open paragraph is parsed whole at each making.
///
/// Text added in any pieces parses as it would whole, by [parseMarkdown];
/// [close] says that no more comes, which settles the last block.
///
/// A link reference definition may come after the references that use it,
/// so it changes [definitions] and not the blocks: a view resolves the
/// references of a block by [resolveReferences] when it shows the block.
///
/// An app in the inline mode puts each block of an answer in the
/// terminal's history as it settles, by a `Static` of the blocks
/// [takeSettled] gives, and shows the rest, [live], in its region below
/// them; so an answer taller than the terminal is all there, scrolled by
/// the terminal, and the region holds only what still changes, the rows
/// a block took in it given back as it goes (see `Static`):
///
/// ```dart
/// // in the State that shows the answer, which has
/// // final answer = MarkdownStream(), history = <MdBlock>[];
/// void onPiece(String piece) => setState(() {
///   answer.add(piece); // answer.close() once the answer ends
///   history.addAll(answer.takeSettled());
/// });
///
/// Widget build(BuildContext context) => Column(
///   crossAxisAlignment: CrossAxisAlignment.stretch,
///   children: [
///     Static(
///       items: history,
///       builder: (_, block) => spaced(MarkdownView.blocks([block])),
///     ),
///     spaced(
///       MarkdownView.blocks(answer.live, definitions: answer.definitions),
///     ),
///     prompt,
///   ],
/// );
///
/// // child with a blank row above, as the blocks of a view are apart
/// Widget spaced(Widget child) =>
///     Padding(padding: const EdgeInsets.only(top: 1), child: child);
/// ```
///
/// The history takes whole blocks: a list or a block of code is live until
/// it ends, the region showing as much of it as fits. A block in the
/// history no longer changes, so [takeSettled] resolves its references by
/// the definitions settled by then; one defined later is its text there.
/// Holding a block back until its references are defined would hold back
/// every block after it too, and text in brackets that no definition ever
/// names, as most of it in an answer is, would hold the rest of the answer
/// in the region until it ends.
final class MarkdownStream {
  /// A stream that starts with [text].
  MarkdownStream([String text = '']) {
    add(text);
  }

  final _settled = <MdBlock>[];

  /// The definitions of the blocks settled, by [normalizeLabel].
  final _settledDefinitions = <String, MdDefinition>{};

  /// [_settledDefinitions], unmodifiable, made again when they change.
  Map<String, MdDefinition> _settledView = const {};

  /// The complete lines from the start of the first block not settled, as
  /// one parser sees them: those of the blocks settled are forgotten.
  var _parser = BlockParser();

  /// The text after the last line ending.
  final _tail = StringBuffer();

  /// Whether [_tail] ends with a carriage return, which a line feed may
  /// follow.
  var _tailReturn = false;

  /// Whether text was added since the blocks were made.
  var _added = false;

  List<MdBlock> _open = const [];
  List<MdBlock> _blocks = const [];
  Map<String, MdDefinition> _definitions = const {};

  /// How many of [blocks] [takeSettled] took.
  var _taken = 0;

  var _closed = false;

  /// The blocks so far.
  List<MdBlock> get blocks {
    _make();
    return _blocks;
  }

  /// The link reference definitions so far, the first of each label, by
  /// the [normalizeLabel] of their label: what the [MdReference]s of
  /// [blocks] resolve by. One in a block not settled may still change.
  Map<String, MdDefinition> get definitions {
    _make();
    return _definitions;
  }

  /// How many of [blocks], from the first, no text added later changes.
  int get settled {
    _make();
    return _settled.length;
  }

  /// The blocks [takeSettled] has not taken, after those it has: what an
  /// app shows live while the ones before are in its history.
  List<MdBlock> get live {
    _make();
    return _taken == 0
        ? _blocks
        : _Blocks(_settled, _taken, _settled.length, _open);
  }

  /// The blocks settled since the last call, in order, each with its
  /// references resolved ([resolveReferences]) by the definitions of the
  /// blocks settled by now: a reference whose definition is still to come,
  /// or in a block not settled, is its text. Each is the settled block
  /// itself where it has no reference. What an app in the inline mode
  /// puts in the terminal's history as the rest streams in (see
  /// [MarkdownStream]).
  List<MdBlock> takeSettled() {
    _make();
    final taken = _settled.sublist(_taken);
    _taken = _settled.length;
    return resolveReferences(taken, _settledDefinitions);
  }

  /// Ends the document: no text comes after, the last line is complete
  /// without its line ending, and every block is settled. [add] is then an
  /// error, [close] nothing.
  void close() {
    if (_closed) {
      return;
    }
    _make();
    _closed = true;
    _settled.addAll(_open);
    _open = const [];
    _settledDefinitions.addAll(_definitions);
    _settledView = _definitions;
    _parser = BlockParser();
    _tail.clear();
    _tailReturn = false;
  }

  /// Appends [text]; a [StateError] once [close]d.
  ///
  /// The complete lines of [text] go on in the parser where the last ones
  /// left it, and the blocks they may change are made again when next
  /// read.
  void add(String text) {
    if (_closed) {
      throw StateError('text added to a closed MarkdownStream');
    }
    if (text.isEmpty) {
      return;
    }
    _split(text);
    _added = true;
  }

  /// Makes the blocks again where text was added since they were made: the
  /// line after the last line ending, which more text may continue, is
  /// parsed by a copy of the parser. So the making costs the lines added
  /// and the blocks still open, of which a closed list item or block in a
  /// quote is the very block it was.
  void _make() {
    if (!_added) {
      return;
    }
    _added = false;
    final done = _parser.closed;
    // a carriage return at the end ends the line before it, a line feed
    // may still follow
    final tail = _tail.toString();
    final parser = tail.isEmpty
        ? _parser
        : (_parser.copy()
            ..add(_tailReturn ? tail.substring(0, tail.length - 1) : tail));
    final converted = parser.finish();
    final fresh = [for (final top in converted) ?top.block];
    final kept = [
      for (var k = 0; k < fresh.length; k++)
        if (k < _open.length) _keep(_open[k], fresh[k]) else fresh[k],
    ];
    var doneBlocks = 0;
    if (done > 0) {
      final count = _settledDefinitions.length;
      for (final top in converted.take(done)) {
        if (top.block != null) {
          doneBlocks++;
        }
        _define(_settledDefinitions, top.definitions);
      }
      if (_settledDefinitions.length != count) {
        _settledView = Map.unmodifiable(_settledDefinitions);
      }
      _settled.addAll(kept.take(doneBlocks));
      _parser.forget(done);
    }
    _open = kept.sublist(doneBlocks);
    _blocks = _Blocks(_settled, 0, _settled.length, _open);
    if (converted.skip(done).every((top) => top.definitions.isEmpty)) {
      _definitions = _settledView;
    } else {
      final definitions = {..._settledDefinitions};
      for (final top in converted.skip(done)) {
        _define(definitions, top.definitions);
      }
      _definitions = Map.unmodifiable(definitions);
    }
  }

  /// Adds the complete lines of [_tail] and [text] to [_parser]; a
  /// carriage return at the end stays in [_tail] for the line feed that
  /// may follow. A piece of no line ending after a tail of none is only
  /// written to the tail, so that a long line in many pieces is not copied
  /// for each.
  void _split(String text) {
    final clean = text.contains('\u0000')
        ? text.replaceAll('\u0000', '�')
        : text;
    if (!_tailReturn && !clean.contains('\n') && !clean.contains('\r')) {
      _tail.write(clean);
      return;
    }
    final told = _tail.length;
    final s = '$_tail$clean';
    _tail.clear();
    var start = 0;
    // the tail has no line ending but a carriage return at its end
    for (var k = told == 0 ? 0 : told - 1; k < s.length; k++) {
      final c = s.codeUnitAt(k);
      if (c == 0x0A) {
        _parser.add(s.substring(start, k));
        start = k + 1;
      } else if (c == 0x0D && k + 1 < s.length) {
        _parser.add(s.substring(start, k));
        if (s.codeUnitAt(k + 1) == 0x0A) {
          k++;
        }
        start = k + 1;
      }
    }
    _tail.write(s.substring(start));
    _tailReturn = s.endsWith('\r') && start < s.length;
  }
}

/// The blocks settled from [_from] to [_to], then the open ones: a list
/// that stays as it is, as [MarkdownStream._settled] only grows, made
/// without copying either.
final class _Blocks extends ListBase<MdBlock> {
  _Blocks(this._settled, this._from, this._to, this._open);

  final List<MdBlock> _settled;
  final int _from;
  final int _to;
  final List<MdBlock> _open;

  @override
  int get length => _to - _from + _open.length;

  @override
  MdBlock operator [](int index) {
    RangeError.checkValidIndex(index, this);
    final k = _from + index;
    return k < _to ? _settled[k] : _open[k - _to];
  }

  @override
  void operator []=(int index, MdBlock value) =>
      throw UnsupportedError('the blocks of a MarkdownStream are unmodifiable');

  @override
  set length(int length) =>
      throw UnsupportedError('the blocks of a MarkdownStream are unmodifiable');
}

/// Adds to [definitions] each of [found] whose label it has none for.
void _define(Map<String, MdDefinition> definitions, List<MdDefinition> found) {
  for (final definition in found) {
    definitions.putIfAbsent(normalizeLabel(definition.label), () => definition);
  }
}

/// [fresh], with each part of it that equals the matching part of [old]
/// replaced by that part of [old]: [old] itself where all of it is equal.
///
/// A part the parser gave again, a closed item or block, is the very part,
/// so only the rest is compared.
MdBlock _keep(MdBlock old, MdBlock fresh) {
  if (identical(old, fresh)) {
    return old;
  }
  switch ((old, fresh)) {
    case (MdBlockQuote(children: final was), MdBlockQuote(children: final now)):
      final children = _keepAll(was, now);
      return identical(children, was) ? old : MdBlockQuote(children);
    case (final MdList was, final MdList now):
      final items = _keepEach(was.items, now.items, _keepItem);
      return identical(items, was.items) &&
              was.start == now.start &&
              was.marker == now.marker &&
              was.tight == now.tight
          ? old
          : MdList(
              items,
              start: now.start,
              marker: now.marker,
              tight: now.tight,
            );
    case _:
      return old == fresh ? old : fresh;
  }
}

MdListItem _keepItem(MdListItem old, MdListItem fresh) {
  if (identical(old, fresh)) {
    return old;
  }
  final children = _keepAll(old.children, fresh.children);
  return identical(children, old.children) && old.checked == fresh.checked
      ? old
      : MdListItem(children, checked: fresh.checked);
}

List<MdBlock> _keepAll(List<MdBlock> old, List<MdBlock> fresh) =>
    _keepEach(old, fresh, _keep);

/// [fresh], each of it kept of the one of [old] at its index by [keep]:
/// [old] itself where every one is kept and there are as many.
List<T> _keepEach<T>(List<T> old, List<T> fresh, T Function(T, T) keep) {
  var same = old.length == fresh.length;
  final kept = [
    for (var k = 0; k < fresh.length; k++)
      if (k < old.length) keep(old[k], fresh[k]) else fresh[k],
  ];
  for (var k = 0; same && k < kept.length; k++) {
    same = identical(kept[k], old[k]);
  }
  return same ? old : kept;
}
