/// The block structure of Markdown, line by line: [BlockParser].
library;

import 'inlines.dart';
import 'nodes.dart';

/// A top-level block of a document converted: the block, null for a
/// paragraph of link reference definitions alone, and the definitions in
/// it, in order.
typedef Converted = ({MdBlock? block, List<MdDefinition> definitions});

/// How many block quotes and list items a block can be in, itself counted:
/// a `>` or list marker that would start one deeper is text.
const maxNesting = 32;

/// Parses Markdown into blocks one line at a time, after CommonMark's
/// algorithm, with GFM's tables and task list items. HTML blocks are
/// paragraphs; the link reference definitions a paragraph starts with are
/// taken out of it.
///
/// A block quote or list item starts only within fewer than [maxNesting]
/// of them; deeper, its marker is text. A document of nothing but `>`
/// would otherwise nest as deep as it is long, past what the stack holds
/// for the passes that walk the blocks.
///
/// A closed block stays as it is whatever lines are added later.
final class BlockParser {
  final _document = _Block(_Kind.document, 0, null);
  late _Block _tip = _document;
  late _Block _oldTip = _document;
  late _Block _lastMatched = _document;
  var _allClosed = true;

  var _line = '';
  var _lineNumber = -1;
  var _offset = 0;
  var _column = 0;
  var _nextNonspace = 0;
  var _nextNonspaceColumn = 0;
  var _indent = 0;
  var _indented = false;
  var _blank = false;
  var _partiallyConsumedTab = false;

  /// The line each top-level block starts on, counting from 0.
  List<int> get starts => [for (final block in _document.children) block.start];

  /// How many of the top-level blocks, from the first, are closed: all but
  /// the last, and the last too when no line can continue it.
  int get closed {
    final blocks = _document.children;
    return blocks.isNotEmpty && blocks.last.open
        ? blocks.length - 1
        : blocks.length;
  }

  /// Parses [line], which has no line ending.
  void add(String line) {
    _lineNumber++;
    _line = line;
    _offset = 0;
    _column = 0;
    _blank = false;
    _partiallyConsumedTab = false;
    _oldTip = _tip;

    var container = _document;
    matching:
    while (true) {
      final last = container.lastChild;
      if (last == null || !last.open) {
        break;
      }
      container = last;
      _findNextNonspace();
      switch (_continue(container)) {
        case _Match.yes:
          continue;
        case _Match.no:
          container = container.parent!;
          break matching;
        case _Match.done:
          return;
      }
    }

    _allClosed = identical(container, _oldTip);
    _lastMatched = container;
    var matchedLeaf = container.kind == _Kind.code;
    while (!matchedLeaf) {
      _findNextNonspace();
      if (!_indented && !_maybeSpecial()) {
        _advanceNextNonspace();
        break;
      }
      final started = _start(container);
      if (started == _Match.no) {
        _advanceNextNonspace();
        break;
      }
      container = _tip;
      matchedLeaf = started == _Match.done;
    }

    if (!_allClosed && !_blank && _tip.kind == _Kind.paragraph) {
      _addLine();
    } else {
      _closeUnmatched();
      switch (container.kind) {
        case _Kind.code || _Kind.paragraph:
          _addLine();
        case _Kind.table:
          if (_offset < _line.length && !_blank) {
            container.cells.add(
              _cells(_line.substring(_offset), container.columns),
            );
          }
        case _Kind.document ||
            _Kind.blockQuote ||
            _Kind.list ||
            _Kind.item ||
            _Kind.heading ||
            _Kind.thematicBreak:
          if (_offset < _line.length && !_blank) {
            _addChild(_Kind.paragraph);
            _advanceNextNonspace();
            _addLine();
          }
      }
    }
    if (_line.codeUnits.any((c) => !_isSpaceOrTab(c)) ||
        (_tip.kind == _Kind.code && _tip.fenced)) {
      _tip.touch(_lineNumber);
    }
  }

  /// The blocks of the lines added, one for each of [starts].
  ///
  /// A closed block is converted once: asked again, it is the very block it
  /// was.
  List<Converted> finish() => [
    for (final block in _document.children) _convertTop(block),
  ];

  /// A parser in the state of this one: lines added to either leave the
  /// other as it is. The two share the closed blocks, which no line
  /// changes, so this costs the open ones.
  BlockParser copy() {
    final copy = BlockParser()
      .._lineNumber = _lineNumber
      .._allClosed = true;
    var from = _document;
    var to = copy._document;
    while (true) {
      to.children.addAll(from.children);
      final last = from.lastChild;
      if (last == null || !last.open) {
        break;
      }
      final open = last._copy(to);
      to.children.last = open;
      from = last;
      to = open;
    }
    assert(identical(from, _tip), 'the tip is not the deepest open block');
    return copy
      .._tip = to
      .._oldTip = to
      .._lastMatched = to;
  }

  /// Drops the first [count] top-level blocks, which are [closed]: what
  /// [starts] and [finish] give begins after them.
  void forget(int count) {
    assert(count <= closed, 'an open block forgotten');
    _document.children.removeRange(0, count);
  }

  int _peek(int at) => at < _line.length ? _line.codeUnitAt(at) : -1;

  bool _isSpaceOrTab(int c) => c == _space || c == _tab;

  void _findNextNonspace() {
    var k = _offset;
    var columns = _column;
    var c = _peek(k);
    while (_isSpaceOrTab(c)) {
      columns += c == _space ? 1 : 4 - columns % 4;
      c = _peek(++k);
    }
    _blank = c < 0;
    _nextNonspace = k;
    _nextNonspaceColumn = columns;
    _indent = columns - _column;
    _indented = _indent >= 4;
  }

  void _advanceNextNonspace() {
    _offset = _nextNonspace;
    _column = _nextNonspaceColumn;
    _partiallyConsumedTab = false;
  }

  /// Moves past [count] characters or, when [columns], [count] columns, of
  /// which a tab may cover several.
  void _advanceOffset(int count, {bool columns = false}) {
    var left = count;
    while (left > 0 && _offset < _line.length) {
      if (_line.codeUnitAt(_offset) == _tab) {
        final toTab = 4 - _column % 4;
        if (columns) {
          _partiallyConsumedTab = toTab > left;
          final advance = toTab > left ? left : toTab;
          _column += advance;
          _offset += _partiallyConsumedTab ? 0 : 1;
          left -= advance;
        } else {
          _partiallyConsumedTab = false;
          _column += toTab;
          _offset++;
          left--;
        }
      } else {
        _partiallyConsumedTab = false;
        _offset++;
        _column++;
        left--;
      }
    }
  }

  void _addLine() {
    if (_partiallyConsumedTab) {
      _offset++;
      final toTab = 4 - _column % 4;
      _tip.lines.add(' ' * toTab + _line.substring(_offset));
    } else {
      _tip.lines.add(_line.substring(_offset));
    }
  }

  _Block _addChild(_Kind kind, {int? start}) {
    while (!_tip.canContain(kind)) {
      _close(_tip);
    }
    final block = _Block(kind, start ?? _lineNumber, _tip);
    _tip.children.add(block);
    return _tip = block;
  }

  void _close(_Block block) {
    block.open = false;
    _tip = block.parent!;
  }

  void _closeUnmatched() {
    if (!_allClosed) {
      while (!identical(_oldTip, _lastMatched)) {
        final parent = _oldTip.parent!;
        _close(_oldTip);
        _oldTip = parent;
      }
      _allClosed = true;
    }
  }

  /// Replaces [old] with [block] among the children of its parent.
  void _replace(_Block old, _Block block) {
    final siblings = old.parent!.children;
    siblings[siblings.indexOf(old)] = block;
    old.open = false;
    _tip = block;
  }

  bool _maybeSpecial() => switch (_peek(_nextNonspace)) {
    0x23 || 0x60 || 0x7E || 0x2A || 0x2B || 0x5F || 0x3D || 0x3E => true,
    0x2D || 0x7C || 0x3A => true,
    final c => c >= 0x30 && c <= 0x39,
  };

  _Match _continue(_Block block) {
    switch (block.kind) {
      case _Kind.document || _Kind.list:
        return _Match.yes;
      case _Kind.blockQuote:
        if (_indented || _peek(_nextNonspace) != 0x3E) {
          return _Match.no;
        }
        _advanceNextNonspace();
        _advanceOffset(1);
        if (_isSpaceOrTab(_peek(_offset))) {
          _advanceOffset(1, columns: true);
        }
        return _Match.yes;
      case _Kind.item:
        final width = block.list!.markerOffset + block.list!.padding;
        if (_blank) {
          if (block.children.isEmpty) {
            return _Match.no;
          }
          _advanceNextNonspace();
        } else if (_indent >= width) {
          _advanceOffset(width, columns: true);
        } else {
          return _Match.no;
        }
        return _Match.yes;
      case _Kind.heading || _Kind.thematicBreak:
        return _Match.no;
      case _Kind.code:
        if (block.fenced) {
          if (_indent <= 3 && _closingFence(block)) {
            block.touch(_lineNumber);
            _close(block);
            return _Match.done;
          }
          for (var k = block.fenceOffset; k > 0; k--) {
            if (!_isSpaceOrTab(_peek(_offset))) {
              break;
            }
            _advanceOffset(1, columns: true);
          }
        } else if (_indent >= 4) {
          _advanceOffset(4, columns: true);
        } else if (_blank) {
          _advanceNextNonspace();
        } else {
          return _Match.no;
        }
        return _Match.yes;
      case _Kind.paragraph || _Kind.table:
        return _blank ? _Match.no : _Match.yes;
    }
  }

  bool _closingFence(_Block code) {
    var k = _nextNonspace;
    while (_peek(k) == code.fenceChar) {
      k++;
    }
    if (k - _nextNonspace < code.fenceLength) {
      return false;
    }
    while (_isSpaceOrTab(_peek(k))) {
      k++;
    }
    return k == _line.length;
  }

  /// Starts the block the line opens with, if any: [_Match.yes] for a
  /// container that more blocks may start in, [_Match.done] for a leaf.
  _Match _start(_Block container) {
    final c = _peek(_nextNonspace);
    final nests = container.nesting < maxNesting;
    if (!_indented) {
      if (c == 0x3E && nests) {
        _advanceNextNonspace();
        _advanceOffset(1);
        if (_isSpaceOrTab(_peek(_offset))) {
          _advanceOffset(1, columns: true);
        }
        _closeUnmatched();
        _addChild(_Kind.blockQuote);
        return _Match.yes;
      }
      if (c == 0x23 && _atxHeading()) {
        return _Match.done;
      }
      if ((c == 0x60 || c == 0x7E) && _fence(c)) {
        return _Match.done;
      }
      if (container.kind == _Kind.paragraph &&
          (c == 0x3D || c == 0x2D) &&
          _setextHeading(container)) {
        return _Match.done;
      }
      if ((c == 0x2A || c == 0x5F || c == 0x2D) && _thematicBreak(c)) {
        _closeUnmatched();
        _addChild(_Kind.thematicBreak);
        _advanceOffset(_line.length - _offset);
        return _Match.done;
      }
    }
    if (nests && (!_indented || container.kind == _Kind.list)) {
      final list = _listMarker(container);
      if (list != null) {
        _closeUnmatched();
        if (_tip.kind != _Kind.list || !_tip.list!.matches(list)) {
          _addChild(_Kind.list).list = list;
        }
        _addChild(_Kind.item).list = list;
        return _Match.yes;
      }
    }
    if (_indented && _tip.kind != _Kind.paragraph && !_blank) {
      _advanceOffset(4, columns: true);
      _closeUnmatched();
      _addChild(_Kind.code);
      return _Match.done;
    }
    if (!_indented && container.kind == _Kind.paragraph && _table(container)) {
      return _Match.done;
    }
    return _Match.no;
  }

  bool _atxHeading() {
    var k = _nextNonspace;
    while (_peek(k) == 0x23) {
      k++;
    }
    final level = k - _nextNonspace;
    if (level > 6 || (k < _line.length && !_isSpaceOrTab(_peek(k)))) {
      return false;
    }
    while (_isSpaceOrTab(_peek(k))) {
      k++;
    }
    _advanceNextNonspace();
    _advanceOffset(k - _offset);
    _closeUnmatched();
    _addChild(_Kind.heading)
      ..level = level
      ..lines.add(
        _line
            .substring(_offset)
            .replaceFirst(_emptyClosingSequence, '')
            .replaceFirst(_closingSequence, ''),
      );
    _advanceOffset(_line.length - _offset);
    return true;
  }

  bool _fence(int c) {
    var k = _nextNonspace;
    while (_peek(k) == c) {
      k++;
    }
    final length = k - _nextNonspace;
    if (length < 3 || (c == 0x60 && _line.indexOf('`', k) >= 0)) {
      return false;
    }
    _closeUnmatched();
    _addChild(_Kind.code)
      ..fenced = true
      ..fenceChar = c
      ..fenceLength = length
      ..fenceOffset = _indent;
    _advanceNextNonspace();
    _advanceOffset(length);
    return true;
  }

  bool _setextHeading(_Block paragraph) {
    final c = _peek(_nextNonspace);
    var k = _nextNonspace;
    while (_peek(k) == c) {
      k++;
    }
    while (_isSpaceOrTab(_peek(k))) {
      k++;
    }
    if (k < _line.length) {
      return false;
    }
    final definitions = <MdDefinition>[];
    final text = _takeDefinitions(_trim(paragraph.lines), definitions);
    if (text.isEmpty) {
      return false;
    }
    _closeUnmatched();
    _replace(
      paragraph,
      _Block(_Kind.heading, paragraph.start, paragraph.parent)
        ..level = c == 0x3D ? 1 : 2
        ..lines.add(text)
        ..definitions.addAll(definitions),
    );
    _advanceOffset(_line.length - _offset);
    return true;
  }

  /// Turns the last line of [paragraph] into the header of a table when
  /// this line is a delimiter row with as many cells.
  bool _table(_Block paragraph) {
    final row = _line.substring(_nextNonspace).trim();
    if (!row.contains('|')) {
      return false;
    }
    final align = <MdAlign>[];
    for (final cell in _split(row)) {
      final match = _delimiterCell.matchAsPrefix(cell.trim());
      if (match == null) {
        return false;
      }
      final left = match[1]!.isNotEmpty;
      final right = match[2]!.isNotEmpty;
      align.add(
        left && right
            ? MdAlign.center
            : left
            ? MdAlign.left
            : right
            ? MdAlign.right
            : MdAlign.none,
      );
    }
    final header = _split(paragraph.lines.last);
    if (header.length != align.length) {
      return false;
    }
    _closeUnmatched();
    final table = _Block(_Kind.table, _lineNumber - 1, paragraph.parent)
      ..align = align
      ..cells.add([for (final cell in header) _cell(cell)]);
    if (paragraph.lines.length == 1) {
      _replace(paragraph, table);
    } else {
      paragraph
        ..lines.removeLast()
        ..end = _lineNumber - 2;
      _close(paragraph);
      paragraph.parent!.children.add(table);
      _tip = table;
    }
    _advanceOffset(_line.length - _offset);
    return true;
  }

  bool _thematicBreak(int c) {
    var count = 0;
    for (var k = _nextNonspace; k < _line.length; k++) {
      final d = _line.codeUnitAt(k);
      if (d == c) {
        count++;
      } else if (!_isSpaceOrTab(d)) {
        return false;
      }
    }
    return count >= 3;
  }

  _ListData? _listMarker(_Block container) {
    if (_indent >= 4) {
      return null;
    }
    final c = _peek(_nextNonspace);
    final interrupts = container.kind == _Kind.paragraph;
    final _ListData list;
    var length = 1;
    if (c == 0x2A || c == 0x2B || c == 0x2D) {
      list = _ListData(c, null, _indent);
    } else {
      while (length <= 9 && _isDigit(_peek(_nextNonspace + length - 1))) {
        length++;
      }
      final d = _peek(_nextNonspace + length - 1);
      if (length == 1 || length > 10 || (d != 0x2E && d != 0x29)) {
        return null;
      }
      final start = int.parse(
        _line.substring(_nextNonspace, _nextNonspace + length - 1),
      );
      if (interrupts && start != 1) {
        return null;
      }
      list = _ListData(d, start, _indent);
    }
    final after = _peek(_nextNonspace + length);
    if (after >= 0 && !_isSpaceOrTab(after)) {
      return null;
    }
    if (interrupts && _line.substring(_nextNonspace + length).trim().isEmpty) {
      return null;
    }
    _advanceNextNonspace();
    _advanceOffset(length, columns: true);
    final startColumn = _column;
    final startOffset = _offset;
    do {
      _advanceOffset(1, columns: true);
    } while (_column - startColumn < 5 && _isSpaceOrTab(_peek(_offset)));
    final spaces = _column - startColumn;
    if (spaces >= 5 || spaces < 1 || _offset >= _line.length) {
      list.padding = length + 1;
      _column = startColumn;
      _offset = startOffset;
      if (_isSpaceOrTab(_peek(_offset))) {
        _advanceOffset(1, columns: true);
      }
    } else {
      list.padding = length + spaces;
    }
    return list;
  }

  Converted _convertTop(_Block block) {
    final definitions = <MdDefinition>[];
    return (block: _convert(block, definitions), definitions: definitions);
  }

  /// [block] as an [MdBlock], null for a paragraph of link reference
  /// definitions alone; the definitions in it are added to [definitions].
  MdBlock? _convert(_Block block, List<MdDefinition> definitions) {
    if (block.converted case final converted?) {
      definitions.addAll(converted.definitions);
      return converted.block;
    }
    if (block.open) {
      return _make(block, definitions);
    }
    final own = <MdDefinition>[];
    final made = _make(block, own);
    block.converted = (block: made, definitions: own);
    definitions.addAll(own);
    return made;
  }

  /// The code of the fenced block [block], its lines after the info
  /// string: what of it the block it was copied from has too is joined
  /// once, kept on that block, and only the lines added since joined
  /// again, as a long block streams in a line at a time.
  static String _fencedCode(_Block block) {
    final memo = block.origin ?? block;
    final lines = block.lines;
    final known = memo.lines.length;
    if (memo.codeLines < known - 1) {
      memo.code += [
        for (var i = 1 + memo.codeLines; i < known; i++) '${lines[i]}\n',
      ].join();
      memo.codeLines = known - 1;
    }
    return lines.length == known
        ? memo.code
        : memo.code +
              [for (var i = known; i < lines.length; i++) '${lines[i]}\n']
                  .join();
  }

  /// The table [block]: the rows of it that the block it was copied from
  /// has too are parsed once, kept on that block, and only the rows added
  /// since parsed again, as a long table streams in a row at a time.
  static MdTable _tableOf(_Block block) {
    final memo = block.origin ?? block;
    final known = memo.cells.length;
    final parsed = memo.parsedCells;
    while (parsed.length < known) {
      parsed.add([
        for (final cell in memo.cells[parsed.length]) parseInlines(cell),
      ]);
    }
    List<List<MdInline>> row(int k) => k < known
        ? parsed[k]
        : [for (final cell in block.cells[k]) parseInlines(cell)];
    return MdTable(block.align, row(0), [
      for (var k = 1; k < block.cells.length; k++) row(k),
    ]);
  }

  MdBlock? _make(_Block block, List<MdDefinition> definitions) {
    definitions.addAll(block.definitions);
    return switch (block.kind) {
      _Kind.paragraph => _paragraph(block.lines, definitions),
      _Kind.heading => MdHeading(block.level, parseInlines(_trim(block.lines))),
      _Kind.thematicBreak => const MdThematicBreak(),
      _Kind.code when block.fenced => MdCodeBlock(
        _fencedCode(block),
        info: unescape(block.lines.first.trim()),
        fenced: true,
      ),
      _Kind.code => MdCodeBlock(
        [
          for (final line in block.lines) '$line\n',
        ].join().replaceFirst(_trailingBlankLines, '\n'),
      ),
      _Kind.blockQuote => MdBlockQuote(
        _convertAll(block.children, definitions),
      ),
      _Kind.list => _convertList(block, definitions),
      _Kind.table => _tableOf(block),
      _Kind.document || _Kind.item => throw StateError('$block is converted'),
    };
  }

  /// The blocks of [blocks], paragraphs of link reference definitions alone
  /// left out.
  List<MdBlock> _convertAll(
    Iterable<_Block> blocks,
    List<MdDefinition> definitions,
  ) => [for (final block in blocks) ?_convert(block, definitions)];

  MdList _convertList(_Block list, List<MdDefinition> definitions) {
    final items = list.children;
    var tight = true;
    for (var k = 0; k < items.length && tight; k++) {
      if (k + 1 < items.length && items[k + 1].start > items[k].end + 1) {
        tight = false;
      }
      final children = items[k].children;
      for (var j = 0; j + 1 < children.length; j++) {
        if (children[j + 1].start > children[j].end + 1) {
          tight = false;
        }
      }
    }
    final data = list.list!;
    return MdList(
      [for (final item in items) _convertItem(item, definitions)],
      start: data.start,
      marker: String.fromCharCode(data.marker),
      tight: tight,
    );
  }

  MdListItem _convertItem(_Block item, List<MdDefinition> definitions) {
    if (item.convertedItem case (final made, final own)) {
      definitions.addAll(own);
      return made;
    }
    if (item.open) {
      return _makeItem(item, definitions);
    }
    final own = <MdDefinition>[];
    final made = _makeItem(item, own);
    item.convertedItem = (made, own);
    definitions.addAll(own);
    return made;
  }

  MdListItem _makeItem(_Block item, List<MdDefinition> definitions) {
    final children = item.children;
    if (children.isNotEmpty && children.first.kind == _Kind.paragraph) {
      final text = _trim(children.first.lines);
      final match = _taskMarker.matchAsPrefix(text);
      if (match != null) {
        final rest = text.substring(match.end).trimLeft();
        return MdListItem([
          if (rest.isNotEmpty) MdParagraph(parseInlines(rest)),
          ..._convertAll(children.skip(1), definitions),
        ], checked: match[1] != ' ' && match[1] != '\t');
      }
    }
    return MdListItem(_convertAll(children, definitions));
  }
}

const _tab = 0x09;
const _space = 0x20;

final _emptyClosingSequence = RegExp(r'^[ \t]*#+[ \t]*$');
final _closingSequence = RegExp(r'[ \t]+#+[ \t]*$');
final _trailingBlankLines = RegExp(r'(\n *)+$');
final _delimiterCell = RegExp(r'^(:?)-+(:?)$');
final _taskMarker = RegExp(r'\[([ \txX])\](?=[ \t\n]|$)');

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// The paragraph of [lines] after the link reference definitions it starts
/// with, which are added to [definitions]; null when nothing follows them.
MdParagraph? _paragraph(List<String> lines, List<MdDefinition> definitions) {
  final text = _takeDefinitions(_trim(lines), definitions);
  return text.isEmpty ? null : MdParagraph(parseInlines(text));
}

/// [text], the content of a paragraph, after the link reference
/// definitions it starts with, which are added to [definitions].
String _takeDefinitions(String text, List<MdDefinition> definitions) {
  var start = 0;
  while (start < text.length && text.codeUnitAt(start) == 0x5B) {
    final found = parseDefinition(text, start);
    if (found == null) {
      break;
    }
    definitions.add(found.definition);
    start = found.end;
  }
  return start == 0 ? text : _trimText(text.substring(start));
}

/// The lines joined, without spaces, tabs or line endings at either end.
String _trim(List<String> lines) => _trimText(lines.join('\n'));

/// [text] without spaces, tabs or line endings at either end.
String _trimText(String text) {
  var start = 0;
  var end = text.length;
  bool space(int c) => c == _space || c == _tab || c == 0x0A;
  while (start < end && space(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && space(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(start, end);
}

/// The cells of the table row [row], split at pipes a backslash does not
/// escape; a pipe at either end is left out.
List<String> _split(String row) {
  var text = row.trim();
  if (text.startsWith('|')) {
    text = text.substring(1);
  }
  if (text.endsWith('|') && !text.endsWith(r'\|')) {
    text = text.substring(0, text.length - 1);
  }
  final cells = <String>[];
  var start = 0;
  for (var k = 0; k < text.length; k++) {
    final c = text.codeUnitAt(k);
    if (c == 0x5C) {
      k++;
    } else if (c == 0x7C) {
      cells.add(text.substring(start, k));
      start = k + 1;
    }
  }
  cells.add(text.substring(start));
  return cells;
}

/// The content of a cell: trimmed, its escaped pipes unescaped.
String _cell(String cell) => cell.trim().replaceAll(r'\|', '|');

/// The cells of the table row [row], as many as [columns].
List<String> _cells(String row, int columns) {
  final cells = _split(row);
  return [
    for (var k = 0; k < columns; k++)
      if (k < cells.length) _cell(cells[k]) else '',
  ];
}

enum _Match { no, yes, done }

enum _Kind {
  document,
  blockQuote,
  list,
  item,
  paragraph,
  heading,
  code,
  thematicBreak,
  table,
}

/// A block while the parser builds it.
final class _Block {
  _Block(this.kind, this.start, this.parent)
    : end = start,
      nesting =
          (parent?.nesting ?? 0) +
          (kind == _Kind.blockQuote || kind == _Kind.item ? 1 : 0);

  final _Kind kind;

  /// How many block quotes and list items the block is in, itself counted.
  final int nesting;

  /// The line the block starts on.
  final int start;

  /// The last line that has content of the block: blank lines count only
  /// within fenced code.
  int end;

  final _Block? parent;
  final children = <_Block>[];
  var open = true;

  /// The lines of a paragraph, heading or code block; of fenced code, the
  /// info string first.
  final lines = <String>[];

  var level = 0;

  var fenced = false;
  var fenceChar = 0;
  var fenceLength = 0;
  var fenceOffset = 0;

  /// How a list or item is marked.
  _ListData? list;

  List<MdAlign> align = const [];

  /// The header row of a table, then its rows.
  final cells = <List<String>>[];

  /// The link reference definitions taken out of a paragraph that turned
  /// into this heading.
  final definitions = <MdDefinition>[];

  /// What the block converted to once closed, with the definitions in it.
  Converted? converted;

  /// The block of the parser this one's was copied from; null for one of
  /// that parser's own.
  _Block? origin;

  /// Of fenced code, its first [codeLines] lines after the info string,
  /// joined, each with its line feed ([BlockParser._fencedCode]).
  var code = '';
  var codeLines = 0;

  /// Of a table, the inlines of the cells of its first rows, the header
  /// first ([BlockParser._tableOf]).
  final parsedCells = <List<List<MdInline>>>[];

  /// What the item converted to once closed, with the definitions in it.
  (MdListItem, List<MdDefinition>)? convertedItem;

  int get columns => align.length;

  /// This open block, under [parent]: its own lists copied, the closed
  /// blocks in them shared.
  _Block _copy(_Block parent) {
    final copy = _Block(kind, start, parent)
      ..origin = origin ?? this
      ..end = end
      ..level = level
      ..fenced = fenced
      ..fenceChar = fenceChar
      ..fenceLength = fenceLength
      ..fenceOffset = fenceOffset
      ..list = list
      ..align = align;
    copy.lines.addAll(lines);
    copy.cells.addAll(cells);
    copy.definitions.addAll(definitions);
    return copy;
  }

  _Block? get lastChild => children.isEmpty ? null : children.last;

  bool canContain(_Kind child) => switch (kind) {
    _Kind.document || _Kind.blockQuote || _Kind.item => child != _Kind.item,
    _Kind.list => child == _Kind.item,
    _ => false,
  };

  /// Marks [line] as one with content of this block and those around it.
  void touch(int line) {
    for (_Block? block = this; block != null; block = block.parent) {
      block.end = line;
    }
  }

  @override
  String toString() => '_Block($kind, $start..$end)';
}

/// How a list item is marked.
final class _ListData {
  _ListData(this.marker, this.start, this.markerOffset);

  /// The bullet, or the delimiter after the number.
  final int marker;

  /// The number of an ordered item; null for a bullet.
  final int? start;

  /// The columns before the marker.
  final int markerOffset;

  /// The columns from the marker to the content.
  var padding = 0;

  /// Whether an item marked by [other] continues a list marked by this.
  bool matches(_ListData other) =>
      (start == null) == (other.start == null) && marker == other.marker;
}
