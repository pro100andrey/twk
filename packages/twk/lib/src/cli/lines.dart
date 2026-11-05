/// What a [Cli] writes, as lines: a message made lines of spans
/// ([messageLines]), lines of spans written as text with or without
/// escapes ([encodeLine]), and a widget laid out and painted once, its rows
/// written so ([widgetLines]).
///
/// @docImport 'cli.dart';
library;

import 'package:twk_core/twk_core.dart'
    show LineEncoder, PaintContext, PipelineOwner, RenderList, Screen, StyleId;

import '../../twk.dart';

/// The lines of [message], each a list of spans, every span's style merged
/// onto [style].
///
/// A [String] is read as a terminal would show it ([parseAnsi]): its SGR
/// sequences and OSC 8 links become the styles of its spans, every other
/// sequence is dropped, so a string styled elsewhere follows `--no-color`
/// too. A [Span] is itself; an [Iterable] is its elements one after
/// another, each a string or a span; null is an empty line; anything else
/// its `toString`. There is always at least one line.
List<List<Span>> messageLines(Object? message, Style style) {
  final lines = <List<Span>>[[]];
  void add(Object? part) {
    switch (part) {
      case null:
        return;
      case Span():
        lines.last.add(part);
      case String():
        final parsed = parseAnsi(part);
        for (var i = 0; i < parsed.length; i++) {
          if (i > 0) {
            lines.add([]);
          }
          lines.last.addAll(parsed[i]);
        }
        if (part.endsWith('\n')) {
          lines.add([]);
        }
      case Iterable<Object?>():
        part.forEach(add);
      default:
        add('$part');
    }
  }

  add(message);
  if (lines.length > 1 && lines.last.isEmpty) {
    // a message that ends with a line break is the lines before it
    lines.removeLast();
  }
  return [
    for (final line in lines)
      [
        for (final span in line)
          if (span.text.isNotEmpty) _onto(span, style),
      ],
  ];
}

Span _onto(Span span, Style style) => span.gradient == null
    ? Span(span.text, style.merge(span.style))
    : Span.gradient(span.text, span.gradient!, style.merge(span.style));

/// [line] as text ([LineEncoder]): with [ansi] each span's style as the
/// SGR sequences that write it in [colorMode], a styled underline as a
/// plain one without [styledUnderlines], its link as OSC 8 with
/// [hyperlinks], and the style reset at its end; without, the text alone.
/// The controls in a span's text, but a tab, are left out, as a `Text`
/// leaves them out: nothing written can act on the terminal.
String encodeLine(
  List<Span> line, {
  required bool ansi,
  bool hyperlinks = false,
  ColorMode colorMode = ColorMode.trueColor,
  bool styledUnderlines = true,
}) {
  if (!ansi) {
    return line.map((s) => _printable(s.text)).join();
  }
  final key = (colorMode, hyperlinks, styledUnderlines);
  final out = _encoders[key] ??= LineEncoder(
    StyleTable(colorMode: colorMode, styledUnderlines: styledUnderlines),
    hyperlinks: hyperlinks,
  );
  final styles = out.styles;
  for (final span in line) {
    out.text(
      styles.compose(StyleId.base, styles.pen(span.style.pen)),
      _printable(span.text),
    );
  }
  out.end();
  final text = out.take();
  if (styles.length > _maxStyles) {
    // a table that grew past what a console's lines use starts again
    _encoders.remove(key);
  }
  return text;
}

/// C0 and C1 controls and DEL, a tab apart.
final _controls = RegExp('[\x00-\x08\x0A-\x1F\x7F-\x9F]');

/// [text] without its controls ([_controls]).
String _printable(String text) =>
    _controls.hasMatch(text) ? text.replaceAll(_controls, '') : text;

/// The encoders of [encodeLine], by colour mode, whether links are
/// written and whether underline styles are: its styles' SGR sequences and
/// link targets are encoded once.
final _encoders = <(ColorMode, bool, bool), LineEncoder>{};

/// The styles an encoder of [encodeLine] keeps before it is dropped.
const _maxStyles = 1024;

/// [widget] laid out [width] columns wide, as tall as its max intrinsic
/// height there, under [theme] where there is one, painted once, and its
/// rows as lines: without the blanks that end them, and, with [ansi], in
/// the SGR sequences of the cells' styles, a styled underline a plain one
/// without [styledUnderlines], and with OSC 8 links where [hyperlinks] are
/// taken.
///
/// The widget is built outside an app, under an [Overlay] of its own (as
/// [App] places one), so that a `Tooltip`, a `Popover` or a menu shows the
/// child it is anchored to; what needs a running app (focus, a frame
/// callback, an animation, a tooltip's hover) shows its first frame, and
/// an entry nothing inserts is not drawn. What the render tree
/// warns of (a flex its children overflow, in debug) goes to [onLog],
/// and to `log` without one ([PipelineOwner.onLog]).
List<String> widgetLines(
  Widget widget,
  int width, {
  ThemeData? theme,
  void Function(LogRecord record)? onLog,
  bool ansi = false,
  bool hyperlinks = false,
  ColorMode colorMode = ColorMode.trueColor,
  bool styledUnderlines = true,
}) {
  if (width < 1) {
    return const [];
  }
  final owner = BuildOwner();
  final root = RootWidget(
    child: theme == null
        ? Overlay(child: widget)
        : Theme(
            data: theme,
            child: Overlay(child: widget),
          ),
  ).attach(owner);
  try {
    owner.buildScope();
    final top = root.renderObject;
    if (top == null) {
      return const [];
    }
    // the screen is resized to the height once the width is known
    final screen = Screen(
      width,
      1,
      caps: TerminalCaps(styledUnderlines: styledUnderlines),
      colorMode: colorMode,
    );
    final pipeline = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
      ..onLog = onLog
      ..root = top;
    final height = top.getMaxIntrinsicHeight(width);
    if (height < 1) {
      // nothing is drawn, but a list that measured no rows is told of
      pipeline
        ..markAllDirty()
        ..flushLayout(width, 0);
      _warnOfListsWithoutRows(top, onLog);
      top.detach();
      return const [];
    }
    screen.resize(width, height);
    pipeline
      ..markAllDirty()
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    _warnOfListsWithoutRows(top, onLog);
    top.detach();
    return _rows(screen, ansi: ansi, hyperlinks: hyperlinks);
  } finally {
    // unmounts the tree: the states of its widgets are disposed
    const RootWidget(child: SizedBox()).attach(owner, root);
    owner
      ..buildScope()
      ..finalizeTree();
  }
}

/// What a list that has items and was given no rows is told of: a list
/// asks for no height of its own (it is virtual, and what it holds may be
/// any number of rows), so a [Table], a [TreeTable] or a [ListView] shown
/// without a bounded height has none to show.
const noRowsWarning =
    'A list of items was given no rows and shows none of them: inline a list '
    'asks for no height of its own (give it one with a SizedBox).';

/// Whether [root] holds a list of items that was laid out with no rows,
/// which [noRowsWarning] tells of. Read from the render tree, so a build
/// without asserts finds it too.
bool hasListWithoutRows(RenderObject root) {
  var found = false;
  void visit(RenderObject object) {
    if (found) {
      return;
    }
    if (object is RenderList &&
        object.itemCount > 0 &&
        object.width > 0 &&
        object.height == 0) {
      found = true;
      return;
    }
    object.visitChildren(visit);
  }

  visit(root);
  return found;
}

void _warnOfListsWithoutRows(
  RenderObject root,
  void Function(LogRecord record)? onLog,
) {
  if (!hasListWithoutRows(root)) {
    return;
  }
  if (onLog == null) {
    log(noRowsWarning, level: LogLevel.warning);
  } else {
    onLog(LogRecord(DateTime.now(), LogLevel.warning, noRowsWarning));
  }
}

List<String> _rows(
  Screen screen, {
  required bool ansi,
  required bool hyperlinks,
}) {
  final out = LineEncoder(screen.styles, ansi: ansi, hyperlinks: hyperlinks);
  return [
    for (var y = 0; y < screen.height; y++)
      (out..row(screen.surface, screen.glyphs, y)).take(),
  ];
}
