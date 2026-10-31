/// Matchers of the screen a [TwkTester] reads back, and of the style of a
/// cell ([VtCell]). One of the screen that fails shows the screen, the
/// style of each run of cells marked as [matchesScreen] marks it, the
/// app's widget tree and the render tree.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart' show Attr, ClusterScan, Color;

import '../vt.dart';
import 'finders.dart';
import 'screen_file.dart';
import 'screen_text.dart';
import 'tester.dart';

/// A rectangle of the screen, as [FinderTester.rect] gives one.
typedef _Rect = ({int x, int y, int width, int height});

// Examples can assume:
// import 'package:test/test.dart';
// import 'package:twk/twk.dart';
// late TwkTester t;

/// Matches a [TwkTester] whose screen has a row that is [line], the blanks
/// that end either aside, or one [line] matches when it is a [Matcher]
/// (`startsWith('sent:')`); a row is text as [TwkTester.lines] gives it.
///
/// With [within], a [Finder] or a rectangle `(x:, y:, width:, height:)`
/// as [FinderTester.rect] gives it, the rows are those of its cells alone
/// ([TwkTester.linesIn]), from its first column. One that fails for a
/// [line] that is a string says where the screen shows it, outside
/// [within], if it does; a [Finder] that does not find one widget fails
/// with what [FinderTester.element] says.
///
/// ```dart
/// expect(t, containsLine('Saved'));
/// expect(t, containsLine(startsWith('sent:')));
/// expect(t, containsLine('> one', within: find.byType(ListView)));
/// ```
Matcher containsLine(Object? line, {Object? within}) => _ContainsLine(
  line is String ? equals(line.trimRight()) : wrapMatcher(line),
  line is String ? line.trim() : null,
  _checkedRegion(within),
);

/// Matches a [TwkTester] whose screen shows [text] from column [x] of row
/// [y] on: the cells [text] is as wide as show it, a wide glyph once.
///
/// With [within], a [Finder] or a rectangle as [containsLine] takes it,
/// [x] and [y] are from the first cell of the region, and the cells read
/// stop at its edge. One that fails says where the screen shows [text]
/// outside [within], if it does.
///
/// ```dart
/// expect(t, hasTextAt(2, 0, 'Title'));
/// expect(t, hasTextAt(0, 1, '> one', within: find.byType(ListView)));
/// ```
Matcher hasTextAt(int x, int y, String text, {Object? within}) =>
    _HasTextAt(x, y, text, _checkedRegion(within));

/// [within] as the matchers keep it: null, a [Finder] or a rectangle; an
/// [ArgumentError] for anything else.
Object? _checkedRegion(Object? within) => switch (within) {
  null || Finder() => within,
  _Rect() => within,
  _ => throw ArgumentError.value(
    within,
    'within',
    'is not a Finder or a rectangle (x:, y:, width:, height:)',
  ),
};

_Rect _asRect(Object region) => region as _Rect;

/// The region [within] is on [t]'s screen; a [StateError] when a finder
/// does not find one widget. Null for none.
_Rect? _regionOn(
  TwkTester t,
  Object? within,
) => switch (within) {
  null => null,
  final Finder finder => t.rect(finder),
  _ => _asRect(within),
};

/// The region as a mismatch names it: `the cells (2, 3), 6×1`.
String _regionName(_Rect r) =>
    'the cells (${r.x}, ${r.y}), ${r.width}×${r.height}';

/// The column and row of the first place [vt]'s screen shows [text] on one
/// row; null if it shows it nowhere.
(int, int)? _locate(Vt vt, String text) {
  if (text.isEmpty) {
    return null;
  }
  for (var y = 0; y < vt.height; y++) {
    final at = rowText(vt, y).indexOf(text);
    if (at != -1) {
      return (_columnOf(vt, y, at), y);
    }
  }
  return null;
}

/// Adds where [vt]'s screen shows [text], if it does.
void _addElsewhere(Description d, Vt vt, String text) {
  final at = _locate(vt, text);
  if (at != null) {
    d
        .add(', but the screen shows ')
        .addDescriptionOf(text)
        .add(' at column ${at.$1}, row ${at.$2}');
  }
}

/// The column of row [y] whose cell holds the character at [offset] of the
/// row's text.
int _columnOf(Vt vt, int y, int offset) {
  var length = 0;
  for (var x = 0; x < vt.width; x++) {
    final cell = vt.cell(x, y);
    if (cell.role == -1) {
      continue;
    }
    if (offset < length + cell.text.length) {
      return x;
    }
    length += cell.text.length;
  }
  return vt.width;
}

/// Matches a [TwkTester] whose cell at column [x] of row [y] [style]
/// matches: [hasAttr], [hasFg], [hasBg], or any matcher of a [VtCell].
///
/// ```dart
/// expect(t, styleAt(0, 0, hasFg(Color.red)));
/// expect(t, styleAt(0, 0, allOf(hasAttr(Attr.bold), hasBg(Color.blue))));
/// ```
Matcher styleAt(int x, int y, Matcher style) => _StyleAt(x, y, style);

/// Matches a [VtCell] with every attribute of [attrs], [Attr]'s bits; an
/// underline in [attrs] is that kind of underline and no other; an
/// [ArgumentError] for none.
Matcher hasAttr(int attrs) {
  if (attrs == 0) {
    throw ArgumentError.value(attrs, 'attrs', 'has no attribute');
  }
  return _HasAttr(attrs);
}

/// Matches a [VtCell] whose text is in [color].
Matcher hasFg(Color color) => _HasColor('fg', color.value, (c) => c.fg);

/// Matches a [VtCell] on the background [color].
Matcher hasBg(Color color) => _HasColor('bg', color.value, (c) => c.bg);

/// Matches a [TwkTester] whose screen shows the cursor at column [x] of
/// row [y]: hidden, it matches nowhere.
///
/// ```dart
/// expect(t, cursorAt(5, 0));
/// ```
Matcher cursorAt(int x, int y) => _CursorAt(x, y);

/// Matches a [TwkTester] whose screen is [snapshot]: its lines are the
/// rows of the screen from the top, as text ([TwkTester.lines]), the
/// blanks that end a line and the empty lines that end the screen left
/// out of both. One that fails shows the rows that differ.
///
/// With [styles] each run of cells of one style is marked:
/// `[bold]sent:[/] [red on #102030]ok[/]`. A style is the cells'
/// attributes, named as [Attr] names them (`bold`, `curlyUnderline`), their
/// color, `on` and their background, and `ul=` and the color of their
/// underline, in that order, each left out when it is the default. A color
/// is named as [Color] names it (`red`, `brightBlack`), `indexed(n)` for
/// the rest of the palette and `#rrggbb` for one of 24 bits. A `[` of the
/// text is doubled; the cells that end a row are left out while they show
/// nothing: spaces without a background and without an attribute that
/// shows on a blank ([Attr.visibleOnBlank]).
///
/// ```dart
/// expect(t, matchesScreen('''
/// Name: Ada
/// [ Save ]
/// '''));
/// expect(t, matchesScreen('[bold red]Error[/]', styles: true));
/// ```
Matcher matchesScreen(String snapshot, {bool styles = false}) =>
    _MatchesScreen(snapshot, styles);

/// Matches a [TwkTester] whose screen is the one the file at [path] holds:
/// its size, where its cursor is, the text of each row and the style of
/// each cell. A relative [path] is from the directory the test runs in,
/// the package's.
///
/// With the environment variable `TWK_UPDATE_GOLDENS` set (to anything
/// but `0`), it writes the screen to the file instead, making its
/// directories, and matches. The styles keep the characters the file gave
/// them, so a file written again changes where the screen did.
///
/// The file is text: a line `screen 40×10, cursor at 5,2` (or `cursor
/// hidden`); `text` and a row a line, the text of its cells between `│`,
/// a wide glyph once; `styles` and a row a line, a character a cell, a
/// space for a cell without a style; `legend` and a line for each
/// character, the character, a space and its style. A style is named as
/// [matchesScreen] names one (`bold #e6e8eb on #1c1f25`), with `link=` and
/// the target of a hyperlink. Images are not in it.
///
/// ```
/// screen 12×2, cursor hidden
/// text
/// │sent: привет│
/// │[ Save ]    │
/// styles
/// │aaaaa       │
/// │bbbbbbbb    │
/// legend
/// a bold
/// b reverse
/// ```
///
/// One that fails names the rows that differ in each layer, and the first
/// cells whose style differs with both styles.
///
/// ```dart
/// expect(t, matchesScreenFile('test/goldens/form.txt'));
/// ```
Matcher matchesScreenFile(String path) => _MatchesScreenFile(path);

/// A matcher of a [TwkTester]'s screen; its mismatch ends with the screen,
/// the widget tree from the widget [TwkTester.pumpWidget] showed down, as
/// [Finder]s see it, and the render tree.
abstract base class _ScreenMatcher extends Matcher {
  const _ScreenMatcher();

  /// Whether [t]'s screen matches; what [_which] needs goes in
  /// [matchState].
  bool _matches(TwkTester t, Map<dynamic, dynamic> matchState);

  /// Adds what [t]'s screen has in place of what is expected.
  void _which(TwkTester t, Description d, Map<dynamic, dynamic> matchState);

  /// Whether the mismatch shows the screen after [_which], which shows it
  /// itself otherwise.
  bool get _showsScreen => true;

  /// Whether the screen it shows has its styles marked: for a matcher of a
  /// style; a matcher of text shows the text alone.
  bool get _marksStyles => false;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is TwkTester && _matches(item, matchState);

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (item is! TwkTester) {
      return mismatchDescription.add('is not a TwkTester');
    }
    _which(item, mismatchDescription, matchState);
    final vt = item.vt;
    return mismatchDescription
        .add('\n\n')
        .add(
          [
            if (_showsScreen) ...[
              'screen ${vt.width}×${vt.height}:',
              describeScreen(vt, styles: _marksStyles),
              '',
            ],
            'widget tree:',
            appRoot(item)?.describe().toStringDeep() ?? 'none',
            '',
            describeApp(vt, item.binding.twkApp.owner.root, screen: false),
          ].join('\n'),
        );
  }
}

/// What [vt] has no cell at ([x], [y]) for; null when it has one.
String? _offScreen(Vt vt, int x, int y) {
  if (y < 0 || y >= vt.height) {
    return 'has no row $y: the screen has ${vt.height} rows';
  }
  if (x < 0 || x >= vt.width) {
    return 'has no column $x: the screen has ${vt.width} columns';
  }
  return null;
}

/// How [cell] is styled, for a mismatch: `is bold red`, `is unstyled`.
String _isStyled(VtCell cell) {
  final style = styleOf(cell);
  return style.isEmpty ? 'is unstyled' : 'is $style';
}

final class _ContainsLine extends _ScreenMatcher {
  const _ContainsLine(this._line, this._text, this._within);

  final Matcher _line;

  /// The text of a line given as a string, to look for outside [_within].
  final String? _text;

  final Object? _within;

  @override
  bool _matches(TwkTester t, Map<dynamic, dynamic> matchState) {
    final List<String> lines;
    try {
      final region = _regionOn(t, _within);
      lines = region == null ? t.lines : t.linesIn(region);
      // ignore: avoid_catching_errors, a finder that finds no one widget fails the match with its message
    } on StateError catch (e) {
      matchState['error'] = e.message;
      return false;
    }
    return lines.any((line) => _line.matches(line, <dynamic, dynamic>{}));
  }

  @override
  Description describe(Description description) {
    description.add('a line of the screen');
    if (_within case final Finder finder) {
      description.add(' in ').add(finder.description);
    } else if (_within case final Object region) {
      description.add(' in ${_regionName(_asRect(region))}');
    }
    return description.add(': ').addDescriptionOf(_line);
  }

  @override
  void _which(TwkTester t, Description d, Map<dynamic, dynamic> matchState) {
    if (matchState['error'] case final String error) {
      d.add(error);
      return;
    }
    d.add('has none');
    final region = _regionOn(t, _within);
    if (region == null) {
      return;
    }
    d.add(' in ${_regionName(region)}');
    final text = _text;
    if (text != null) {
      _addElsewhere(d, t.vt, text);
    }
  }
}

final class _HasTextAt extends _ScreenMatcher {
  const _HasTextAt(this._x, this._y, this._text, this._within);

  final int _x;
  final int _y;
  final String _text;
  final Object? _within;

  /// The cells the matcher reads: the screen's, or the region's cut by it.
  _Rect _area(TwkTester t) {
    final vt = t.vt;
    final r = _regionOn(t, _within);
    if (r == null) {
      return (x: 0, y: 0, width: vt.width, height: vt.height);
    }
    final left = r.x < 0 ? 0 : r.x;
    final top = r.y < 0 ? 0 : r.y;
    final right = r.x + r.width < vt.width ? r.x + r.width : vt.width;
    final bottom = r.y + r.height < vt.height ? r.y + r.height : vt.height;
    return (x: left, y: top, width: right - left, height: bottom - top);
  }

  /// What [area] has no cell at ([_x], [_y]) of for; null when it has one.
  String? _off(_Rect area) {
    final where = _within == null ? 'the screen' : 'the region';
    if (_y < 0 || _y >= area.height) {
      return 'has no row $_y: $where has ${area.height} rows';
    }
    if (_x < 0 || _x >= area.width) {
      return 'has no column $_x: $where has ${area.width} columns';
    }
    return null;
  }

  /// What the cells [_text] would take show, and whether the row ends
  /// before they do.
  (String, bool) _shown(Vt vt, _Rect area) {
    final scan = ClusterScan();
    final x0 = area.x + _x;
    final y0 = area.y + _y;
    final limit = area.x + area.width;
    var end = x0;
    for (var i = 0; i < _text.length; i = scan.end) {
      vt.segmenter.scan(_text, i, scan);
      end += scan.width;
    }
    final shown = [
      for (var x = x0; x < end && x < limit; x++)
        if (vt.cell(x, y0) case VtCell(role: != -1, :final text)) text,
    ].join();
    return (shown, end > limit);
  }

  @override
  bool _matches(TwkTester t, Map<dynamic, dynamic> matchState) {
    final _Rect area;
    try {
      area = _area(t);
      // ignore: avoid_catching_errors, a finder that finds no one widget fails the match with its message
    } on StateError catch (e) {
      matchState['error'] = e.message;
      return false;
    }
    return _off(area) == null && _shown(t.vt, area).$1 == _text;
  }

  @override
  Description describe(Description description) {
    description.addDescriptionOf(_text).add(' at column $_x, row $_y');
    return switch (_within) {
      null => description,
      final Finder finder => description.add(' in ${finder.description}'),
      final Object r => description.add(' in ${_regionName(_asRect(r))}'),
    };
  }

  @override
  void _which(TwkTester t, Description d, Map<dynamic, dynamic> matchState) {
    if (matchState['error'] case final String error) {
      d.add(error);
      return;
    }
    final area = _area(t);
    final off = _off(area);
    if (off != null) {
      d.add(off);
    } else {
      final (shown, cut) = _shown(t.vt, area);
      d.add('has ').addDescriptionOf(shown).add(' there');
      if (cut) {
        d.add(', at the end of the ${_within == null ? 'row' : 'region'}');
      }
    }
    if (_within != null) {
      _addElsewhere(d, t.vt, _text);
    }
  }
}

final class _StyleAt extends _ScreenMatcher {
  const _StyleAt(this._x, this._y, this._style);

  final int _x;
  final int _y;
  final Matcher _style;

  @override
  bool get _marksStyles => true;

  @override
  bool _matches(TwkTester t, Map<dynamic, dynamic> matchState) {
    final vt = t.vt;
    if (_offScreen(vt, _x, _y) != null) {
      return false;
    }
    final state = <dynamic, dynamic>{};
    matchState['state'] = state;
    return _style.matches(vt.cell(_x, _y), state);
  }

  @override
  Description describe(Description description) => description
      .add('the cell at column $_x, row $_y: ')
      .addDescriptionOf(_style);

  @override
  void _which(TwkTester t, Description d, Map<dynamic, dynamic> matchState) {
    final vt = t.vt;
    final off = _offScreen(vt, _x, _y);
    if (off != null) {
      d.add(off);
      return;
    }
    final cell = vt.cell(_x, _y);
    final inner = StringDescription();
    _style.describeMismatch(
      cell,
      inner,
      matchState['state'] as Map<dynamic, dynamic>,
      false,
    );
    d
        .add('has ')
        .addDescriptionOf(cell.role == -1 ? '' : cell.text)
        .add(' there, which ')
        .add(inner.length == 0 ? _isStyled(cell) : '$inner');
  }
}

/// A matcher of a [VtCell]'s style; its mismatch is how the cell is
/// styled.
abstract base class _CellMatcher extends Matcher {
  const _CellMatcher();

  bool _matches(VtCell cell);

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is VtCell && _matches(item);

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) => mismatchDescription.add(
    item is VtCell ? _isStyled(item) : 'is not a VtCell',
  );
}

final class _HasAttr extends _CellMatcher {
  const _HasAttr(this._attrs);

  final int _attrs;

  @override
  bool _matches(VtCell cell) {
    const others = ~Attr.underlineMask;
    final underline = _attrs & Attr.underlineMask;
    return cell.attrs & _attrs & others == _attrs & others &&
        (underline == 0 || cell.attrs & Attr.underlineMask == underline);
  }

  @override
  Description describe(Description description) =>
      description.add(attrNames(_attrs).join(' and '));
}

final class _HasColor extends _CellMatcher {
  const _HasColor(this._name, this._color, this._of);

  final String _name;
  final int _color;
  final int Function(VtCell cell) _of;

  @override
  bool _matches(VtCell cell) => _of(cell) == _color;

  @override
  Description describe(Description description) =>
      description.add('$_name ${colorName(_color)}');
}

final class _CursorAt extends _ScreenMatcher {
  const _CursorAt(this._x, this._y);

  final int _x;
  final int _y;

  @override
  bool _matches(TwkTester t, Map<dynamic, dynamic> matchState) =>
      t.cursorVisible && t.cursor == (_x, _y);

  @override
  Description describe(Description description) =>
      description.add('the cursor at column $_x, row $_y');

  @override
  void _which(TwkTester t, Description d, Map<dynamic, dynamic> matchState) {
    final (x, y) = t.cursor;
    d.add(
      t.cursorVisible
          ? 'has it at column $x, row $y'
          : 'has it hidden, at column $x, row $y',
    );
  }
}

final class _MatchesScreen extends _ScreenMatcher {
  _MatchesScreen(String snapshot, this._styles)
    : _rows = [for (final line in snapshot.split('\n')) line.trimRight()] {
    while (_rows.isNotEmpty && _rows.last.isEmpty) {
      _rows.removeLast();
    }
  }

  final bool _styles;
  final List<String> _rows;

  @override
  bool get _showsScreen => !_styles;

  @override
  bool _matches(TwkTester t, Map<dynamic, dynamic> matchState) {
    final rows = screenRows(t.vt, styles: _styles);
    return rows.length == _rows.length &&
        Iterable<int>.generate(rows.length).every((y) => rows[y] == _rows[y]);
  }

  @override
  Description describe(Description description) => description.add(
    _styles
        ? 'the screen of the snapshot, styles marked'
        : 'the screen of the snapshot',
  );

  @override
  void _which(TwkTester t, Description d, Map<dynamic, dynamic> matchState) {
    final rows = screenRows(t.vt, styles: _styles);
    final count = rows.length > _rows.length ? rows.length : _rows.length;
    String rowOf(List<String> rows, int y) => y < rows.length ? rows[y] : '';
    final differ = [
      for (var y = 0; y < count; y++)
        if (rowOf(rows, y) != rowOf(_rows, y)) y,
    ];
    final digits = '${count - 1}'.length;
    final lines = [
      for (var y = 0; y < count; y++)
        if (differ.contains(y)) ...[
          '- ${'$y'.padLeft(digits)}│${rowOf(_rows, y)}',
          '+ ${'$y'.padLeft(digits)}│${rowOf(rows, y)}',
        ] else
          '  ${'$y'.padLeft(digits)}│${rowOf(rows, y)}',
    ];
    final which = differ.length == 1
        ? 'row ${differ.single}'
        : 'rows ${differ.take(differ.length - 1).join(', ')} '
              'and ${differ.last}';
    d.add(
      'differs in $which (- the snapshot, + the screen):\n'
      '${lines.join('\n')}',
    );
  }
}

final class _MatchesScreenFile extends _ScreenMatcher {
  const _MatchesScreenFile(this._path);

  final String _path;

  @override
  bool get _showsScreen => false;

  @override
  bool _matches(TwkTester t, Map<dynamic, dynamic> matchState) {
    final file = File(_path);
    ScreenFile? held;
    if (file.existsSync()) {
      try {
        held = ScreenFile.parse(file.readAsStringSync());
      } on FormatException catch (e) {
        if (!updatingScreenFiles) {
          matchState[#error] = 'is not a screen file: ${e.message}';
          return false;
        }
      }
    }
    final cursor = t.cursorVisible ? t.cursor : null;
    final ScreenFile shown;
    try {
      shown = ScreenFile.of(t.vt, cursor, previous: held);
    } on ScreenFileException catch (e) {
      matchState[#error] = 'cannot hold the screen: ${e.message}';
      return false;
    }
    if (updatingScreenFiles) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(shown.write());
      return true;
    }
    if (held == null) {
      matchState[#error] =
          'does not exist; $updateScreenFilesVariable=1 writes the screen '
          'to it';
      return false;
    }
    matchState[#held] = held;
    matchState[#shown] = shown;
    return _differences(held, shown).isEmpty;
  }

  @override
  Description describe(Description description) =>
      description.add('the screen of $_path');

  @override
  void _which(TwkTester t, Description d, Map<dynamic, dynamic> matchState) {
    if (matchState[#error] case final String error) {
      d.add('$_path $error');
      return;
    }
    final held = matchState[#held] as ScreenFile;
    final shown = matchState[#shown] as ScreenFile;
    d.add(
      'differs from $_path (- the file, + the screen; '
      '$updateScreenFilesVariable=1 writes the screen to it):\n'
      '${_differences(held, shown).join('\n')}',
    );
  }

  /// What differs between [held] and [shown], as lines of the failure
  /// message; none when they are the same screen.
  static List<String> _differences(ScreenFile held, ScreenFile shown) {
    if (held.width != shown.width || held.height != shown.height) {
      final from = '${held.width}×${held.height}';
      return ['the size: - $from, + ${shown.width}×${shown.height}'];
    }
    final out = <String>[];
    if (held.cursor != shown.cursor) {
      String where((int, int)? c) =>
          c == null ? 'hidden' : 'at ${c.$1},${c.$2}';
      out.add('the cursor: - ${where(held.cursor)}, + ${where(shown.cursor)}');
    }
    final digits = '${held.height - 1}'.length;
    String row(String sign, int y, String text) =>
        '$sign ${'$y'.padLeft(digits)}│$text│';
    final text = [
      for (var y = 0; y < held.height; y++)
        if (held.text[y] != shown.text[y]) ...[
          row('-', y, held.text[y]),
          row('+', y, shown.text[y]),
        ],
    ];
    if (text.isNotEmpty) {
      out
        ..add('text:')
        ..addAll(text);
    }
    final styles = <String>[];
    final cells = <String>[];
    for (var y = 0; y < held.height; y++) {
      final differ = [
        for (var x = 0; x < held.width; x++)
          if (held.styleAt(x, y) != shown.styleAt(x, y)) x,
      ];
      if (differ.isEmpty) {
        continue;
      }
      // the screen's row in the file's characters, `?` for a style the
      // file has no character for
      final chars = {
        for (final MapEntry(key: char, value: style) in held.legend.entries)
          style: char,
      };
      final mapped = [
        for (var x = 0; x < held.width; x++)
          switch (shown.styleAt(x, y)) {
            '' => ' ',
            final style => chars[style] ?? '?',
          },
      ].join();
      styles
        ..add(row('-', y, held.styles[y]))
        ..add(row('+', y, mapped));
      for (final x in differ) {
        if (cells.length == 8) {
          break;
        }
        String name(String? style) => switch (style) {
          null => 'a character the legend lacks',
          '' => 'none',
          final s => s,
        };
        cells.add(
          '  ($x, $y): - ${name(held.styleAt(x, y))}, '
          '+ ${name(shown.styleAt(x, y))}',
        );
      }
    }
    if (styles.isNotEmpty) {
      out
        ..add('styles:')
        ..addAll(styles)
        ..add('the first cells whose style differs:')
        ..addAll(cells);
    }
    return out;
  }
}
