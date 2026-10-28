/// Descriptions of trees for debugging: a [DiagnosticsNode] for each render
/// object or element, with its name, properties, size, flags and children,
/// built only when asked for and rendered as text
/// ([DiagnosticsNode.toStringDeep]) or as JSON ([DiagnosticsNode.toJson]).
library;

import '../style.dart';
import '../unicode/unicode.dart';

/// A state of a node worth seeing at a glance: its [symbol] follows the
/// node's size in a dump, which explains the symbols it shows in a legend.
enum DiagnosticsFlag {
  /// Repaints on its own, over its own previous output.
  repaintBoundary('◆', 'repaint boundary'),

  /// Its size can't change its parent's layout: a layout mark stops here.
  relayoutBoundary('◇', 'relayout boundary'),

  /// An element to be rebuilt in the next build scope.
  needsBuild('✱', 'needs build'),

  /// To be laid out on the next frame.
  needsLayout('⟳', 'needs layout'),

  /// To be repainted on the next frame.
  needsPaint('✎', 'needs paint'),

  /// Its children don't fit in it: they are cut off at its bounds.
  overflow('⇥', 'overflow'),

  /// Shows an error in place of what it would show: its build, layout or
  /// paint threw.
  error('✗', 'error');

  const DiagnosticsFlag(this.symbol, this.meaning);

  /// One column wide.
  final String symbol;

  /// What the legend says it is.
  final String meaning;
}

/// A property of a [DiagnosticsNode]: `name: value`, or a [value] alone (a
/// word such as `sticky`, an excerpt of text).
final class DiagnosticsProperty {
  /// A property named [name], or with a null name a [value] alone.
  const DiagnosticsProperty(this.name, this.value);

  /// What the property is, such as `padding`; null for a value alone.
  final String? name;

  /// The value as text ([describeValue]).
  final String value;

  /// The property as JSON: `{"name": …, "value": …}`, without the name
  /// where it has none.
  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    'value': value,
  };

  @override
  String toString() => name == null ? value : '$name: $value';
}

// what DiagnosticPropertiesBuilder.add shows whatever the value
const _always = Object();

/// What a `debugFillProperties` method adds the properties and flags of a
/// node to.
final class DiagnosticPropertiesBuilder {
  /// A builder with no properties or flags yet.
  DiagnosticPropertiesBuilder();

  /// The properties added, in order.
  final properties = <DiagnosticsProperty>[];

  /// The flags raised.
  final flags = <DiagnosticsFlag>{};

  /// Adds [name]: [value], formatted by [describeValue], unless [value] is
  /// [defaultValue] (where one is given), which is not worth showing.
  void add(String name, Object? value, {Object? defaultValue = _always}) {
    if (value != defaultValue) {
      properties.add(DiagnosticsProperty(name, describeValue(value)));
    }
  }

  /// Adds [value] without a name, formatted by [describeValue]: a string
  /// as a quoted excerpt.
  void addValue(Object? value) =>
      properties.add(DiagnosticsProperty(null, describeValue(value)));

  /// Adds [name]: [message], as it is.
  void addMessage(String name, String message) =>
      properties.add(DiagnosticsProperty(name, message));

  /// Adds [tag], a word such as `sticky` or `focused`, as it is.
  void addTag(String tag) => properties.add(DiagnosticsProperty(null, tag));

  /// Raises [flag].
  void flag(DiagnosticsFlag flag) => flags.add(flag);

  /// The node named [name] with the properties and flags added so far.
  DiagnosticsNode toNode(
    String name, {
    String? key,
    (int, int)? size,
    List<DiagnosticsNode> children = const [],
  }) => DiagnosticsNode(
    name,
    key: key,
    properties: properties,
    size: size,
    flags: [
      for (final f in DiagnosticsFlag.values)
        if (flags.contains(f)) f,
    ],
    children: children,
  );
}

/// A render object or an element as a debugging aid shows it: its [name]
/// (the type), [key], [properties], [size] once laid out, [flags] and
/// [children]. The same node feeds a dump ([toStringDeep]), an inspector
/// ([toJson]) and messages ([toString]).
///
/// A render object makes its own (`RenderObject.describe`):
///
/// ```dart
/// final box = RenderPadding(padding: const EdgeInsets.all(1));
/// final dump = box.describe().toStringDeep(); // RenderPadding ‹padding: 1›
/// ```
final class DiagnosticsNode {
  /// A node named [name] with what it shows; without the rest, a name
  /// alone.
  const DiagnosticsNode(
    this.name, {
    this.key,
    this.properties = const [],
    this.size,
    this.flags = const [],
    this.children = const [],
  });

  /// What the node is: the type of the render object or the widget.
  final String name;

  /// The widget's key, as a string; null for none.
  final String? key;

  /// What describes the node, in the order it was added
  /// ([DiagnosticPropertiesBuilder]).
  final List<DiagnosticsProperty> properties;

  /// Width and height, in cells; null before the first layout.
  final (int, int)? size;

  /// In the order of [DiagnosticsFlag.values].
  final List<DiagnosticsFlag> flags;

  /// The nodes of the objects below this one, in order.
  final List<DiagnosticsNode> children;

  /// The name, the key after a dash, and the properties:
  /// `Box-[<'a'>] ‹border: rounded, padding: 0 1›`.
  @override
  String toString() {
    final head = key == null ? name : '$name-$key';
    return properties.isEmpty ? head : '$head ‹${properties.join(', ')}›';
  }

  /// This node and those below it, one per line under box drawing guides,
  /// with the sizes in a column after the widest line (aligned on the ×)
  /// and the flags' symbols after them; a legend of the symbols shown
  /// follows a blank line. A run of [fold] or more siblings of the same
  /// name is one line, `… 19 MessageView`; a [fold] of 0 folds none.
  ///
  /// ```text
  /// Column                       80×24
  /// ├─ Header ‹title: "agent"›   80×1
  /// ├─ ListView ‹items: 214›     80×19 ◆
  /// │  └─ … 19 MessageView
  /// └─ KeyHints ‹2 bindings›     80×1
  ///
  /// ◆ repaint boundary
  /// ```
  String toStringDeep({int fold = 5}) {
    final rows = <_Row>[];
    _addRows(this, '', '', rows, fold);
    var labels = 0;
    var widths = 0;
    var heights = 0;
    final shown = <DiagnosticsFlag>{};
    for (final row in rows) {
      final node = row.node;
      if (node == null || (node.size == null && node.flags.isEmpty)) {
        continue;
      }
      labels = row.width > labels ? row.width : labels;
      if (node.size case (final w, final h)) {
        widths = '$w'.length > widths ? '$w'.length : widths;
        heights = '$h'.length > heights ? '$h'.length : heights;
      }
      shown.addAll(node.flags);
    }
    final lines = <String>[];
    for (final row in rows) {
      final node = row.node;
      if (node == null || (node.size == null && node.flags.isEmpty)) {
        lines.add(row.text);
        continue;
      }
      final columns = [
        if (node.size case (final w, final h))
          '${'$w'.padLeft(widths)}×${'$h'.padRight(heights)}'
        else if (widths > 0)
          ' ' * (widths + 1 + heights),
        if (node.flags.isNotEmpty) node.flags.map((f) => f.symbol).join(' '),
      ];
      lines.add(
        '${row.text}${' ' * (labels - row.width + 1)}${columns.join(' ')}'
            .trimRight(),
      );
    }
    if (shown.isNotEmpty) {
      lines
        ..add('')
        ..add(
          [
            for (final f in DiagnosticsFlag.values)
              if (shown.contains(f)) '${f.symbol} ${f.meaning}',
          ].join(', '),
        );
    }
    return lines.join('\n');
  }

  /// Adds the rows of [node], after [lead], and of the nodes below it,
  /// after [rest] and their own guides.
  static void _addRows(
    DiagnosticsNode node,
    String lead,
    String rest,
    List<_Row> rows,
    int fold,
  ) {
    rows.add(_Row('$lead$node', node));
    final children = node.children;
    for (var i = 0; i < children.length;) {
      final name = children[i].name;
      var end = i + 1;
      while (end < children.length && children[end].name == name) {
        end++;
      }
      if (fold > 0 && end - i >= fold) {
        final guide = end == children.length ? '└─ ' : '├─ ';
        rows.add(_Row('$rest$guide… ${end - i} $name', null));
      } else {
        for (var k = i; k < end; k++) {
          final last = k == children.length - 1;
          _addRows(
            children[k],
            '$rest${last ? '└─ ' : '├─ '}',
            '$rest${last ? '   ' : '│  '}',
            rows,
            fold,
          );
        }
      }
      i = end;
    }
  }

  /// This node and those below it as JSON: `name`, `key` (if any),
  /// `properties` (each with its `name`, if any, and `value`), `size` (if
  /// laid out: `width`, `height`), `flags` (by name) and `children`.
  Map<String, Object?> toJson() => {
    'name': name,
    if (key != null) 'key': key,
    'properties': [for (final p in properties) p.toJson()],
    if (size case (final w, final h)) 'size': {'width': w, 'height': h},
    'flags': [for (final f in flags) f.name],
    'children': [for (final c in children) c.toJson()],
  };
}

/// A line of a dump: its text, guides included, as wide as [width]
/// columns; the node it shows, or null for a folded run.
final class _Row {
  _Row(this.text, this.node) : width = stringWidth(text);

  final String text;
  final DiagnosticsNode? node;
  final int width;
}

/// [value] as a property shows it: a string as a quoted excerpt
/// ([describeText]), a [Pen] as [describePen] says, an enum value by its
/// name, anything else as its `toString` (a [Color] is an int there: see
/// [describeColor]).
String describeValue(Object? value) => switch (value) {
  final String s => describeText(s),
  final Pen p => describePen(p),
  final Enum e => e.name,
  _ => '$value',
};

final _excerptSegmenter = TextSegmenter();
final _excerptScan = ClusterScan();

/// [text] in double quotes, cut off with "…" after [max] columns; a line
/// break, a tab, a quote, a backslash and other controls are escaped (`\n`,
/// `\t`, `\"`, `\\`, `\u{1b}`).
String describeText(String text, {int max = 24}) {
  // each piece as shown, and the columns it takes
  final pieces = <String>[];
  final widths = <int>[];
  var total = 0;
  for (var i = 0; i < text.length;) {
    final start = i;
    _excerptSegmenter.scan(text, i, _excerptScan);
    i = _excerptScan.end;
    final first = _excerptScan.first;
    if (_excerptScan.width == 0 && first < 0xA0) {
      // a control, CR LF included: each code unit escaped
      for (var k = start; k < i; k++) {
        pieces.add(_escape(text.codeUnitAt(k)));
        widths.add(pieces.last.length);
        total += pieces.last.length;
      }
    } else if (first == 0x22 || first == 0x5C) {
      pieces.add(first == 0x22 ? r'\"' : r'\\');
      widths.add(2);
      total += 2;
    } else {
      pieces.add(text.substring(start, i));
      widths.add(_excerptScan.width);
      total += _excerptScan.width;
    }
  }
  final sb = StringBuffer('"');
  if (total <= max) {
    pieces.forEach(sb.write);
  } else {
    var used = 0;
    for (var k = 0; k < pieces.length && used + widths[k] < max; k++) {
      sb.write(pieces[k]);
      used += widths[k];
    }
    sb.write('…');
  }
  sb.write('"');
  return sb.toString();
}

String _escape(int unit) => switch (unit) {
  0x0A => r'\n',
  0x0D => r'\r',
  0x09 => r'\t',
  _ => '\\u{${unit.toRadixString(16)}}',
};

const _colorNames = [
  'black',
  'red',
  'green',
  'yellow',
  'blue',
  'magenta',
  'cyan',
  'white',
  'brightBlack',
  'brightRed',
  'brightGreen',
  'brightYellow',
  'brightBlue',
  'brightMagenta',
  'brightCyan',
  'brightWhite',
];

/// [color] by name: `default`, the 16 basic colors by their names (`red`,
/// `brightBlack`), the rest of the palette as `color123`, 24-bit colors
/// as `#1e90ff`.
String describeColor(Color color) {
  if (color.isRgb) {
    return '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
  if (color.isIndexed) {
    return color.index < 16 ? _colorNames[color.index] : 'color${color.index}';
  }
  return 'default';
}

// by the underline bits of the attributes
const _underlines = [
  '',
  'underline',
  'double-underline',
  'curly-underline',
  'dotted-underline',
  'dashed-underline',
  'underline',
  'underline',
];

/// [pen] in a few words: its attributes, its text color, `on` its
/// background, a translucent color's alpha as a percentage after it
/// (`black/50%`), `ul:` the underline color and `link` for a hyperlink;
/// `plain` for none of them. Colors left to the cells underneath are left
/// out: `bold red on blue`, `dim`, `default on default`.
String describePen(Pen pen) {
  final attrs = pen.attrs;
  final underline = (attrs & Attr.underlineMask) >> 3;
  final words = [
    if (attrs & Attr.bold != 0) 'bold',
    if (attrs & Attr.dim != 0) 'dim',
    if (attrs & Attr.italic != 0) 'italic',
    if (underline > 0) _underlines[underline],
    if (attrs & Attr.blink != 0) 'blink',
    if (attrs & Attr.reverse != 0) 'reverse',
    if (attrs & Attr.hidden != 0) 'hidden',
    if (attrs & Attr.strike != 0) 'strike',
    if (attrs & Attr.overline != 0) 'overline',
    if (pen.fg case final fg?) _translucent(fg, pen.fgAlpha),
    if (pen.bg case final bg?) 'on ${_translucent(bg, pen.bgAlpha)}',
    if (!pen.underlineColor.isDefault)
      'ul:${describeColor(pen.underlineColor)}',
    if (pen.link != null) 'link',
  ];
  return words.isEmpty ? 'plain' : words.join(' ');
}

String _translucent(Color color, int alpha) => alpha == 255
    ? describeColor(color)
    : '${describeColor(color)}/${(alpha * 100 / 255).round()}%';
