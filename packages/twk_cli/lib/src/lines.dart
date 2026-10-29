/// What a [Cli] writes, as lines: a message made lines of spans
/// ([messageLines]), lines of spans written as text with or without
/// escapes ([encodeLine]), and a widget laid out and painted once, its rows
/// written so ([widgetLines]).
///
/// @docImport 'cli.dart';
library;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show LineEncoder, PaintContext, PipelineOwner, Screen;

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
String encodeLine(
  List<Span> line, {
  required bool ansi,
  bool hyperlinks = false,
  ColorMode colorMode = ColorMode.trueColor,
  bool styledUnderlines = true,
}) {
  if (!ansi) {
    return line.map((s) => s.text).join();
  }
  final key = (colorMode, hyperlinks, styledUnderlines);
  final out = _encoders[key] ??= LineEncoder(
    StyleTable(colorMode: colorMode, styledUnderlines: styledUnderlines),
    hyperlinks: hyperlinks,
  );
  final styles = out.styles;
  for (final span in line) {
    out.text(styles.compose(0, styles.pen(span.style.pen)), span.text);
  }
  out.end();
  final text = out.take();
  if (styles.length > _maxStyles) {
    // a table that grew past what a console's lines use starts again
    _encoders.remove(key);
  }
  return text;
}

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
/// The widget is built outside an app: what needs one (focus, a frame
/// callback, an animation) shows its first frame. What the render tree
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
    child: theme == null ? widget : Theme(data: theme, child: widget),
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
      return const [];
    }
    screen.resize(width, height);
    pipeline
      ..markAllDirty()
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
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
