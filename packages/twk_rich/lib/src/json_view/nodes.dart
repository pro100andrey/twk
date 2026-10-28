part of 'view.dart';

/// The path of a value in a JSON document: [root], then each of
/// [segments] after it, an [int] as an index (`[0]`) and anything else as
/// a key, named as `toString` gives it: `.name` where it is an identifier
/// (a letter, `_` or `$`, then letters, digits, `_` and `$`), else
/// `["a key"]`, in quotes and escaped as a JSON string is.
///
/// Two lists of segments never give the same path: `[0]` is an index and
/// `["0"]` a key.
///
/// ```dart
/// jsonPath(['scripts', 0]); // $.scripts[0]
/// jsonPath(['a key'], root: 'data'); // data["a key"]
/// ```
String jsonPath(List<Object> segments, {String root = r'$'}) {
  final out = StringBuffer(root);
  for (final segment in segments) {
    _writeSegment(out, segment);
  }
  return out.toString();
}

void _writeSegment(StringBuffer out, Object segment) {
  if (segment is int) {
    out
      ..write('[')
      ..write(segment)
      ..write(']');
    return;
  }
  final name = '$segment';
  if (_identifier.hasMatch(name)) {
    out
      ..write('.')
      ..write(name);
  } else {
    out
      ..write('[')
      ..write(jsonEncode(name))
      ..write(']');
  }
}

final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

/// The paths of the values above the one at [path], which starts with
/// [root]: [root] first, then one segment longer each; empty when [path]
/// does not start with [root] or is not one [jsonPath] writes.
List<String> _ancestorsOf(String path, String root) {
  if (!path.startsWith(root)) {
    return const [];
  }
  final ancestors = <String>[];
  var i = root.length;
  while (i < path.length) {
    ancestors.add(path.substring(0, i));
    final c = path.codeUnitAt(i);
    if (c == 0x2E) {
      // .name: to the next segment
      i++;
      while (i < path.length &&
          path.codeUnitAt(i) != 0x2E &&
          path.codeUnitAt(i) != 0x5B) {
        i++;
      }
    } else if (c == 0x5B) {
      // [0] or ["key"]
      i++;
      if (i < path.length && path.codeUnitAt(i) == 0x22) {
        i++;
        while (i < path.length && path.codeUnitAt(i) != 0x22) {
          i += path.codeUnitAt(i) == 0x5C ? 2 : 1;
        }
        i++;
      }
      while (i < path.length && path.codeUnitAt(i) != 0x5D) {
        i++;
      }
      if (i >= path.length) {
        return const [];
      }
      i++;
    } else {
      return const [];
    }
  }
  return ancestors;
}

/// What stands in for a value that cannot be shown as one: `<cycle>`, or
/// the error a `toJson` threw.
final class _Marker {
  const _Marker(this.text);

  final String text;

  @override
  String toString() => text;
}

const _cycle = _Marker('<cycle>');

/// The key of the row that closes the object or array at [path].
final class _Close {
  const _Close(this.path);

  final String path;

  @override
  bool operator ==(Object other) => other is _Close && other.path == path;

  @override
  int get hashCode => Object.hash(_Close, path);
}

/// A value of the tree as given ([raw]) and as JSON ([value]), where it is
/// ([path], [segment]), and its entries ([children]), made as they are
/// first asked for; or, with [closes], the row that closes an object or
/// array.
final class _Node {
  _Node(
    this.parent,
    this.segment,
    this.raw,
    this.path, {
    required this.last,
    required this.sortKeys,
  }) : depth = parent == null ? 0 : parent.depth + 1,
       closes = null,
       value = _jsonOf(raw, parent);

  _Node._close(_Node container)
    : parent = container,
      segment = null,
      raw = null,
      path = container.path,
      last = true,
      sortKeys = false,
      depth = container.depth + 1,
      closes = container,
      value = null;

  final _Node? parent;

  /// Its key in its parent: a [String] or an [int] of a map, the [int]
  /// index of a list; null for the root.
  final Object? segment;

  /// The value as it was given.
  final Object? raw;

  /// [raw] as JSON: a [Map], a [List], a [String], a [num], a [bool],
  /// null, or a [_Marker].
  final Object? value;

  final String path;

  /// Whether it is the last entry of its parent.
  final bool last;

  final bool sortKeys;

  /// How far below the root it is.
  final int depth;

  /// The object or array this row closes; null for a value's row.
  final _Node? closes;

  /// What the view expands and selects it by.
  Object get key => closes == null ? path : _Close(path);

  /// Whether it is an object or array with entries.
  bool get hasEntries => switch (value) {
    final Map<Object?, Object?> map => map.isNotEmpty,
    final List<Object?> list => list.isNotEmpty,
    _ => false,
  };

  /// Whether its parent is an object: it shows its key.
  bool get keyed => parent?.value is Map;

  /// Its key as it shows: the map key as text; null in a list.
  String? get keyText => keyed ? '${_mapKey ?? segment}' : null;

  // the key of the map, where the segment is not it
  Object? _mapKey;

  List<_Node>? _children;

  /// Its entries, then the row that closes it; none for a value that is
  /// not an object or array with entries.
  List<_Node> get children => _children ??= _makeChildren();

  /// Its entries, without the row that closes it.
  Iterable<_Node> get entries => children.where((c) => c.closes == null);

  List<_Node> _makeChildren() {
    final value = this.value;
    final children = <_Node>[];
    if (value is Map<Object?, Object?> && value.isNotEmpty) {
      final keys = value.keys.toList();
      if (sortKeys) {
        keys.sort((a, b) => '$a'.compareTo('$b'));
      }
      // a key that is neither a string nor an int is its text, told apart
      // from the other keys by a number where they are alike
      final used = {
        for (final key in keys)
          if (key is String) key,
      };
      for (var i = 0; i < keys.length; i++) {
        final key = keys[i];
        final Object segment;
        if (key is String || key is int) {
          segment = key!;
        } else {
          var text = '$key';
          for (var n = 2; used.contains(text); n++) {
            text = '$key ($n)';
          }
          used.add(text);
          segment = text;
        }
        final out = StringBuffer(path);
        _writeSegment(out, segment);
        children.add(
          _Node(
            this,
            segment,
            value[key],
            out.toString(),
            last: i == keys.length - 1,
            sortKeys: sortKeys,
          ).._mapKey = key,
        );
      }
    } else if (value is List<Object?> && value.isNotEmpty) {
      for (var i = 0; i < value.length; i++) {
        children.add(
          _Node(
            this,
            i,
            value[i],
            '$path[$i]',
            last: i == value.length - 1,
            sortKeys: sortKeys,
          ),
        );
      }
    }
    if (children.isNotEmpty) {
      children.add(_Node._close(this));
    }
    return children;
  }

  /// [raw] as JSON below [parent]: a JSON value as it is (a [Set] as a
  /// list), [_cycle] for one of the values above it, else what its
  /// `toJson()` gives, or its `toString()` where it has none.
  static Object? _jsonOf(Object? raw, _Node? parent) {
    if (raw == null || raw is String || raw is num || raw is bool) {
      return raw;
    }
    if (_isAbove(raw, parent)) {
      return _cycle;
    }
    if (raw is Map || raw is List) {
      return raw;
    }
    if (raw is Set) {
      return raw.toList(growable: false);
    }
    Object? json;
    try {
      // whatever it is, it may have one
      json = (raw as dynamic).toJson();
      // a method it does not have
      // ignore: avoid_catching_errors
    } on NoSuchMethodError {
      return '$raw';
      // what a toJson throws shows in its place, whatever it is
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      return _Marker('<toJson() threw $error>');
    }
    if (json == null || json is String || json is num || json is bool) {
      return json;
    }
    if (_isAbove(json, parent)) {
      return _cycle;
    }
    if (json is Map || json is List) {
      return json;
    }
    if (json is Set) {
      return json.toList(growable: false);
    }
    return '$json';
  }

  /// Whether [value] is the value of [node] or of one above it.
  static bool _isAbove(Object value, _Node? node) {
    for (var n = node; n != null; n = n.parent) {
      if (identical(n.raw, value) || identical(n.value, value)) {
        return true;
      }
    }
    return false;
  }

  /// The value as JSON a [jsonEncode] takes: markers as their text,
  /// numbers that are not finite as text.
  Object? get encodable {
    final value = this.value;
    return switch (value) {
      final Map<Object?, Object?> _ => {
        for (final c in entries) '${c.keyText}': c.encodable,
      },
      final List<Object?> _ => [for (final c in entries) c.encodable],
      final double d when !d.isFinite => '$d',
      _Marker() => '$value',
      _ => value,
    };
  }

  /// The value as JSON text, indented two blanks a level.
  String get encoded => const JsonEncoder.withIndent('  ').convert(encodable);

  /// Whether it is a string longer than [max] characters.
  bool cut(int? max) {
    final value = this.value;
    return max != null && value is String && value.runes.length > max;
  }
}

/// What a row of a value shows, in [theme]'s styles: its key (in an
/// object), its value, and a comma where an entry follows it.
///
/// An object or array [expanded] shows its opening bracket; collapsed,
/// both brackets around how many entries it has (`{ 4 keys }`). A string
/// longer than [maxStringLength] characters is cut there with `…`, unless
/// [whole]. The characters of its key at [marks] (offsets into
/// [_Node.keyText]) are in [markStyle] over the key's style.
List<Span> _rowSpans(
  _Node node,
  SyntaxTheme theme, {
  required bool expanded,
  bool whole = false,
  int? maxStringLength,
  List<int> marks = const [],
  Style markStyle = const Style(attrs: Attr.bold | Attr.underline),
}) {
  final punctuation = theme.punctuation;
  final spans = <Span>[];
  final container = node.closes;
  if (container != null) {
    spans.add(Span(container.value is Map ? '}' : ']', punctuation));
    if (!container.last) {
      spans.add(Span(',', punctuation));
    }
    return spans;
  }
  if (node.keyText case final key?) {
    final quoted = jsonEncode(key);
    if (marks.isEmpty || quoted.length != key.length + 2) {
      spans.add(Span(quoted, theme.key));
    } else {
      final marked = theme.key.merge(markStyle);
      final at = marks.toSet();
      spans.add(Span('"', theme.key));
      var from = 0;
      for (var i = 0; i <= key.length; i++) {
        final isMark = i < key.length && at.contains(i);
        final wasMark = from < key.length && at.contains(from);
        if (i == key.length || isMark != wasMark) {
          if (i > from) {
            spans.add(
              Span(key.substring(from, i), wasMark ? marked : theme.key),
            );
          }
          from = i;
        }
      }
      spans.add(Span('"', theme.key));
    }
    spans.add(Span(': ', punctuation));
  }
  final value = node.value;
  switch (value) {
    case final Map<Object?, Object?> map:
      _bracketed(spans, theme, '{', '}', map.length, 'key', expanded);
    case final List<Object?> list:
      _bracketed(spans, theme, '[', ']', list.length, 'item', expanded);
    case final String text:
      final cut = !whole && node.cut(maxStringLength);
      final shown = cut
          ? String.fromCharCodes(text.runes.take(maxStringLength!))
          : text;
      final quoted = jsonEncode(shown);
      if (cut) {
        _string(spans, theme, quoted.substring(0, quoted.length - 1));
        spans
          ..add(Span('…', theme.comment))
          ..add(Span('"', theme.string));
      } else {
        _string(spans, theme, quoted);
      }
    case final num n:
      spans.add(Span('$n', theme.number));
    case final bool b:
      spans.add(Span('$b', theme.constant));
    case null:
      spans.add(Span('null', theme.constant));
    case _:
      spans.add(Span('$value', theme.comment));
  }
  // an object or array expanded has its comma after its closing bracket
  if (!node.last && !(expanded && node.hasEntries)) {
    spans.add(Span(',', punctuation));
  }
  return spans;
}

/// Adds an object's or array's brackets to [spans]: [open] alone when
/// [expanded], `[open][close]` when it has no entries, else both around
/// the count of its entries, [count] [noun]s.
void _bracketed(
  List<Span> spans,
  SyntaxTheme theme,
  String open,
  String close,
  int count,
  String noun,
  bool expanded,
) {
  final punctuation = theme.punctuation;
  if (count == 0) {
    spans.add(Span('$open$close', punctuation));
  } else if (expanded) {
    spans.add(Span(open, punctuation));
  } else {
    spans
      ..add(Span('$open ', punctuation))
      ..add(Span('$count $noun${count == 1 ? '' : 's'}', theme.comment))
      ..add(Span(' $close', punctuation));
  }
}

/// Adds the JSON string [quoted] to [spans], its escapes in their style.
void _string(List<Span> spans, SyntaxTheme theme, String quoted) {
  var from = 0;
  while (from < quoted.length) {
    final escape = quoted.indexOf(r'\', from);
    if (escape < 0) {
      spans.add(Span(quoted.substring(from), theme.string));
      break;
    }
    if (escape > from) {
      spans.add(Span(quoted.substring(from, escape), theme.string));
    }
    final end = quoted.codeUnitAt(escape + 1) == 0x75 ? escape + 6 : escape + 2;
    spans.add(Span(quoted.substring(escape, end), theme.escape));
    from = end;
  }
}

/// The lines [value] shows in as a [JsonView] shows it, every object and
/// array expanded, or those less than [expandedDepth] levels below the
/// top: indented two blanks a level, with their closing brackets, each
/// line a list of spans in [theme]'s styles. For a program's output, such
/// as a console's: as text, its spans one after another.
///
/// [value] is taken as [JsonView.value] is: other objects through their
/// `toJson()`, cycles as `<cycle>`. [theme] is null for one
/// [SyntaxTheme.from] the terminal's own colors ([ThemeData.terminal]);
/// [sortKeys] orders the keys of objects; strings longer than
/// [maxStringLength] characters are cut with `…`, none when it is null.
///
/// ```dart
/// final lines = jsonLines({'name': 'twk', 'tags': ['tui']});
/// for (final line in lines) {
///   print(line.map((span) => span.text).join());
/// }
/// // {
/// //   "name": "twk",
/// //   "tags": [
/// //     "tui"
/// //   ]
/// // }
/// ```
List<List<Span>> jsonLines(
  Object? value, {
  SyntaxTheme? theme,
  int? expandedDepth,
  bool sortKeys = false,
  int? maxStringLength,
}) {
  final syntax =
      theme ?? SyntaxTheme.from(const ThemeData.terminal(Brightness.dark));
  final lines = <List<Span>>[];
  final root = _Node(null, null, value, r'$', last: true, sortKeys: sortKeys);
  final stack = [root];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    final depth = node.closes?.depth ?? node.depth;
    final expanded =
        node.hasEntries && (expandedDepth == null || depth < expandedDepth);
    lines.add([
      if (depth > 0) Span('  ' * depth),
      ..._rowSpans(
        node,
        syntax,
        expanded: expanded,
        maxStringLength: maxStringLength,
      ),
    ]);
    if (expanded) {
      stack.addAll(node.children.reversed);
    }
  }
  return lines;
}
