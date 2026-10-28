// The stage: a page's widget alone on a quiet field of dots, its corners
// marked and its size under it.
import 'package:twk/twk.dart';

import '../page.dart';
import '../paint.dart';
import 'tokens.dart';

/// Shows [child] on the stage: centred in the room the stage has, less
/// three columns each side and a row above and below for its marks, on
/// dots every fourth column of every second row from [pad] on, the dots
/// cleared around it, its corners marked (`┌ ┐ └ ┘`, brighter while
/// [focused]) and its size under the right corner (`48 × 4`). With
/// [fill] the child gets the whole room, else as much as it takes of it.
/// [onRoom] hears the room at each layout, for the page's Code.
final class Stage extends SingleChildRenderObjectWidget {
  const Stage({
    required this.tokens,
    required this.pad,
    required this.focused,
    super.key,
    this.fill = false,
    this.onRoom,
    super.child,
  });

  final Tokens tokens;
  final int pad;
  final bool focused;
  final bool fill;
  final void Function(StageRoom room)? onRoom;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderStage createRenderObject(BuildContext context) =>
      RenderStage(tokens, pad, focused: focused, fill: fill)..onRoom = onRoom;

  @override
  void updateRenderObject(BuildContext context, RenderStage renderObject) {
    renderObject
      ..tokens = tokens
      ..pad = pad
      ..focused = focused
      ..fill = fill
      ..onRoom = onRoom;
  }
}

/// What a [Stage] lays out and paints.
final class RenderStage extends RenderObject with RenderObjectWithChildMixin {
  RenderStage(
    this._tokens,
    this._pad, {
    required this._focused,
    required this._fill,
  });

  Tokens _tokens;
  Tokens get tokens => _tokens;
  set tokens(Tokens t) {
    _tokens = t;
    markNeedsPaint();
  }

  int _pad;
  int get pad => _pad;
  set pad(int p) {
    if (p != _pad) {
      _pad = p;
      markNeedsPaint();
    }
  }

  bool _focused;
  bool get focused => _focused;
  set focused(bool f) {
    if (f != _focused) {
      _focused = f;
      markNeedsPaint();
    }
  }

  bool _fill;
  bool get fill => _fill;
  set fill(bool f) {
    if (f != _fill) {
      _fill = f;
      markNeedsLayout();
    }
  }

  /// Hears the room the child is given at each layout.
  void Function(StageRoom room)? onRoom;

  @override
  bool get sizedByParent => true;

  @override
  int computeMaxIntrinsicHeight(int width) {
    final child = this.child;
    if (child == null || _fill) {
      return 4;
    }
    return child.getMaxIntrinsicHeight(width - 6 < 0 ? 0 : width - 6) + 2;
  }

  @override
  int computeMinIntrinsicHeight(int width) => computeMaxIntrinsicHeight(width);

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
    final rw = width - 6 < 0 ? 0 : width - 6;
    final rh = height - 2 < 0 ? 0 : height - 2;
    onRoom?.call(StageRoom(rw, rh));
    final child = this.child;
    if (child == null) {
      return;
    }
    child.layout(
      _fill ? BoxConstraints.tight(rw, rh) : BoxConstraints(0, rw, 0, rh),
      parentUsesSize: true,
    );
    final w = child.width;
    final h = child.height;
    final x = (width - w) >> 1 < 3 ? 3 : (width - w) >> 1;
    final y = ((height - h) / 2.2).floor() < 1
        ? 1
        : ((height - h) / 2.2).floor();
    child.parentData
      ..dx = x
      ..dy = y;
  }

  @override
  void paint(PaintContext ctx) {
    final t = _tokens;
    final canvas = ctx.canvas
      ..save()
      ..clipRect(0, 0, width, height);
    final p = Painter(canvas, width, height)
      ..fill(0, 0, width, height, Style(bg: t.background, fg: t.text));
    final dot = Style(fg: t.faint);
    for (var y = 1; y < height - 1; y += 2) {
      for (var x = _pad + 1; x < width - 2; x += 4) {
        p.text(x, y, '·', dot);
      }
    }
    final child = this.child;
    if (child != null) {
      final w = child.width;
      final h = child.height;
      final x = child.parentData.dx;
      final y = child.parentData.dy;
      p.fill(x - 3, y - 1, w + 6, h + 2, Style(bg: t.background, fg: t.text));
      final mark = Style(fg: _focused ? t.muted : t.faint);
      p
        ..text(x - 2, y - 1, '┌', mark)
        ..text(x + w + 1, y - 1, '┐', mark)
        ..text(x - 2, y + h, '└', mark)
        ..text(x + w + 1, y + h, '┘', mark);
      final label = '$w × $h';
      if (w >= widthOf(label) + 2 && y + h + 1 < height) {
        p.text(x + w + 1 - widthOf(label), y + h + 1, label, Style(fg: t.dim));
      }
      canvas.restore();
      paintChild(ctx, child);
      return;
    }
    // a page of the catalog that no GalleryPage draws yet
    const msg = [
      'No widget is on this page yet.',
      'Its title and what it is about come from the catalog.',
    ];
    final w = widthOf(msg[1]) + 4;
    final x = (width - w) >> 1 < _pad ? _pad : (width - w) >> 1;
    final y = (height - 4) >> 1 < 1 ? 1 : (height - 4) >> 1;
    p
      ..fill(x - 2, y - 1, w + 4, 4, Style(bg: t.background))
      ..text(x, y, '◇  ${msg[0]}', Style(fg: t.muted))
      ..text(x + 3, y + 1, msg[1], Style(fg: t.dim));
    canvas.restore();
  }
}
