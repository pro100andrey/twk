// What the pages of the group share.
part of 'app.dart';

/// The stage of a page that draws a terminal around its app: [under], the
/// terminal [width] × [height]; the app at [at] (x, y, w, h), when it
/// shows; [over], what is drawn over them, such as a background lit
/// under the app's text.
Widget _terminal({
  required int width,
  required int height,
  required void Function(Painter p) under,
  Widget? app,
  (int, int, int, int)? at,
  void Function(Painter p)? over,
}) => SizedBox(
  width: width,
  height: height,
  child: Stack(
    children: [
      CellPaint(under, width: width, height: height),
      if (app != null && at != null)
        Positioned(
          left: at.$1,
          top: at.$2,
          width: at.$3,
          height: at.$4,
          child: CodeApp(child: app),
        ),
      if (over != null)
        CellPaint(over, width: width, height: height, hit: false),
    ],
  ),
);

/// A rounded box's border at [x], [y], [w] × [h] in [fg], with [title]
/// on its top edge after the corner in [titleFg] (the border's where
/// null), as twk's Box draws a BorderTitle.
void _box(
  Painter p,
  int x,
  int y,
  int w,
  int h,
  Color fg, {
  String? title,
  Color? titleFg,
}) {
  if (w < 2 || h < 2) {
    return;
  }
  final s = Style(fg: fg);
  p
    ..text(x, y, '╭', s)
    ..text(x + w - 1, y, '╮', s)
    ..text(x, y + h - 1, '╰', s)
    ..text(x + w - 1, y + h - 1, '╯', s)
    ..hline(x + 1, y, w - 2, fg, '─')
    ..hline(x + 1, y + h - 1, w - 2, fg, '─')
    ..vline(x, y + 1, h - 2, fg, '│')
    ..vline(x + w - 1, y + 1, h - 2, fg, '│');
  if (title != null) {
    p.text(x + 1, y, ' $title ', Style(fg: titleFg ?? fg), max: w - 2);
  }
}

/// Spans of text and their style, drawn one after another from [x], at
/// most [max] columns; returns the columns they take.
int _spans(Painter p, int x, int y, List<(String, Style)> spans, int max) {
  var cx = x;
  for (final (text, style) in spans) {
    final left = x + max - cx;
    if (left <= 0) {
      break;
    }
    cx += p.text(cx, y, text, style, max: left);
  }
  return cx - x;
}

/// The shell's prompt, then [cmd].
List<(String, Style)> _prompt(Tokens t, String cmd) => [
  (r'$ ', Style(fg: t.success)),
  (cmd, Style(fg: t.text)),
];

/// The terminal's cursor's blink.
const _blink = 530;

/// The terminal's cursor, a blinking block, at [x], [y], at [now] ms;
/// asks for a build when it blinks.
void _blinking(
  Painter p,
  Tokens t,
  int x,
  int y,
  int now,
  void Function(int) wake,
) {
  final k = now ~/ _blink;
  wake((k + 1) * _blink);
  if (k.isEven) {
    p.fill(x, y, 1, 1, Style(bg: t.text));
  }
}

/// The background of a strip of the terminal's window: the surface, a
/// shade nearer the background on a dark theme.
Color _strip(Tokens t) =>
    t.dark ? mix(t.background, t.surface, 0.9) : t.surface;

/// A step of the build; the pause after it ends, before it runs again.
const _stepMs = 800;

const _pause = 2000;

const _cmd = 'dart run tool/build.dart';

/// The terminal.
const _tw = 44;

const _th = 10;
