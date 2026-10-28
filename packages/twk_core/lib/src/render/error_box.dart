part of 'render.dart';

// ---------------------------------------------------------------- errors --

/// What an error's message is shown in.
const _errorPen = Pen(fg: Color.brightWhite, bg: Color.red);

/// The columns of the widest line of [message] unbroken, as the canvas of
/// [o]'s owner draws it.
int _messageWidth(RenderObject o, String message) {
  final seg = o.owner?.segmenter ?? _detachedSegmenter;
  final scan = _widthScan;
  var widest = 0;
  for (final line in message.split('\n')) {
    var w = 0;
    for (var i = 0; i < line.length; i = scan.end) {
      seg.scan(line, i, scan);
      w += _clusterWidth(scan);
    }
    if (w > widest) {
      widest = w;
    }
  }
  return widest;
}

/// [message] in lines of at most [width] columns: a line break in it ends
/// a line, and a line too long breaks after its last space that fits, or
/// within the word that does not.
List<String> _messageLines(RenderObject o, String message, int width) {
  final lines = <String>[];
  if (width <= 0) {
    return lines;
  }
  final seg = o.owner?.segmenter ?? _detachedSegmenter;
  final scan = _widthScan;
  for (final text in message.split('\n')) {
    var start = 0;
    do {
      var cols = 0;
      var space = -1;
      var i = start;
      while (i < text.length) {
        seg.scan(text, i, scan);
        final w = _clusterWidth(scan);
        if (cols + w > width && i > start) {
          break;
        }
        if (scan.first == 0x20) {
          space = i;
        }
        cols += w;
        i = scan.end;
      }
      if (i == text.length) {
        lines.add(text.substring(start));
        break;
      }
      final cut = text.codeUnitAt(i) != 0x20 && space > start ? space : i;
      lines.add(text.substring(start, cut).trimRight());
      start = cut;
      while (start < text.length && text.codeUnitAt(start) == 0x20) {
        start++;
      }
    } while (start < text.length);
  }
  return lines;
}

/// The columns of the cluster in [scan] as the canvas draws it: a tab is
/// one blank.
int _clusterWidth(ClusterScan scan) => scan.first == 0x09 ? 1 : scan.width;

/// Fills [width] × [height] with [errorPen], the error pen by default, and
/// writes [lines] on it.
void _paintMessage(
  PaintContext ctx,
  List<String> lines,
  int width,
  int height, [
  Pen errorPen = _errorPen,
]) {
  final canvas = ctx.canvas;
  final pen = canvas.styles.pen(errorPen);
  canvas.fill(0, 0, width, height, pen);
  for (var y = 0; y < lines.length && y < height; y++) {
    canvas.text(0, y, lines[y], pen);
  }
}

/// [message] in [color] (bright white by default) on red, broken into
/// lines between words where it can and within a word where it must; as
/// wide as its longest line and as tall as its lines, within the
/// constraints: the block a render object whose layout or paint threw
/// shows in its place, and what the widget layer shows for a widget whose
/// build threw.
final class RenderErrorBox extends RenderObject {
  /// Shows [message] in [color], bright white unless given, on red.
  RenderErrorBox(this._message, {this._color = Color.brightWhite});

  String _message;

  /// The text shown, typically an error's `toString()`; a new one lays the
  /// box out again.
  String get message => _message;
  set message(String m) {
    if (m != _message) {
      _message = m;
      markNeedsLayout();
    }
  }

  Color _color;

  /// The color of its text, bright white by default.
  Color get color => _color;
  set color(Color c) {
    if (c != _color) {
      _color = c;
      markNeedsPaint();
    }
  }

  // the lines laid out
  var _lines = const <String>[];

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addValue(_message);
  }

  @override
  int computeMinIntrinsicWidth(int height) => _message.isEmpty ? 0 : 1;

  @override
  int computeMaxIntrinsicWidth(int height) => _messageWidth(this, _message);

  @override
  int computeMinIntrinsicHeight(int width) =>
      _messageLines(this, _message, width).length;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _messageLines(this, _message, width).length;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_messageWidth(this, _message));
    _lines = _messageLines(this, _message, width);
    height = c.constrainH(_lines.length);
  }

  @override
  void paint(PaintContext ctx) => _paintMessage(
    ctx,
    _lines,
    width,
    height,
    _color == Color.brightWhite ? _errorPen : Pen(fg: _color, bg: Color.red),
  );
}
