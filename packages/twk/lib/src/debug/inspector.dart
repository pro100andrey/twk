/// What the binding's `ext.twk.*` service extensions see of an app
/// (`AppBinding.callServiceExtension`): ids for its elements and render
/// objects, their descriptions as JSON, the node at a cell, and the
/// outline over a node (`DebugAids.highlight`).
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        Color,
        DiagnosticsNode,
        HitTestResult,
        PaintContext,
        Pen,
        RenderObject,
        StyleTable,
        kCont,
        kWide;

import '../framework/framework.dart';

/// Gives the elements and the render objects of an app ids, and describes
/// them as JSON ([Element.describe], [RenderObject.describe]).
///
/// An id is a positive int, one sequence for elements and render objects,
/// given to a node the first time an answer names it, and kept by it for
/// as long as the inspector lives: an element keeps its id through its
/// rebuilds. An id is never given twice, and one whose node has left the
/// tree names none ([nodeOf]).
final class Inspector {
  /// An inspector of the trees under [root], the app's element [app], and
  /// the render objects [hitTest] finds at a cell.
  Inspector({required this.root, required this.app, required this.hitTest});

  /// The version of the JSON the answers have: an answer a client that
  /// reads this one would misread comes with another.
  static const version = 1;

  /// The root of the element tree; null before the first frame mounts it.
  final Element? Function() root;

  /// The element of the app's widget, below those of the binding.
  final Element? Function() app;

  /// Adds the render objects at a cell of the screen to a result, the
  /// deepest first (`PipelineOwner.hitTest`).
  final void Function(HitTestResult result, int x, int y) hitTest;

  final _ids = Expando<int>('inspector id');
  var _lastId = 0;

  /// The id of [node], an element or a render object.
  int idOf(Object node) => _ids[node] ??= ++_lastId;

  /// The element or render object of the trees [id] names, found by a walk
  /// of the trees; null for none.
  Object? nodeOf(int id) {
    Object? found;
    void element(Element e) {
      if (found != null) {
        return;
      }
      if (_ids[e] == id) {
        found = e;
        return;
      }
      e.visitChildren(element);
    }

    void render(RenderObject o) {
      if (found != null) {
        return;
      }
      if (_ids[o] == id) {
        found = o;
        return;
      }
      o.visitChildren(render);
    }

    final top = root();
    if (top != null) {
      element(top);
      final o = _topOf(top.renderObject);
      if (found == null && o != null) {
        render(o);
      }
    }
    return found;
  }

  /// The render object of [node]: an element's own, or that of the nearest
  /// element below it with one; a render object itself.
  RenderObject? renderObjectOf(Object node) => switch (node) {
    final Element e => e.renderObject,
    final RenderObject o => o,
    _ => null,
  };

  /// The element tree from its root, or with [render] the render tree:
  /// `tree` (`element` or `render`), `app` (the id of the app's element,
  /// in the element tree once mounted) and `root` (the root's node with
  /// those below it, null before the first frame).
  Map<String, Object?> tree({bool render = false}) {
    final top = root();
    if (render) {
      final o = _topOf(top?.renderObject);
      return {
        'tree': 'render',
        'root': o == null ? null : _renderNode(o, o.describe(), _owners()),
      };
    }
    final app = this.app();
    return {
      'tree': 'element',
      'app': app == null ? null : idOf(app),
      'root': top == null ? null : _elementNode(top, top.describe()),
    };
  }

  /// [node] as [tree] has it, without `children`.
  Map<String, Object?> properties(Object node) => switch (node) {
    final Element e => _fields(e, e.describe())..addAll(_links(e)),
    final RenderObject o => _fields(o, o.describe())..addAll(_link(o)),
    _ => throw ArgumentError.value(node, 'node', 'not a node'),
  };

  /// The layout of [node]'s render object ([renderObjectOf]): its id
  /// (`render`) and type (`name`); once laid out, its `constraints`
  /// (`minWidth`, `maxWidth`, `minHeight`, `maxHeight`, null for no limit)
  /// and `size` (`width`, `height`); its `offset` (`x`, `y`) in its parent
  /// and `global`, on the screen (of the region in the inline mode). Only
  /// `id` for a node without one.
  Map<String, Object?> layout(Object node) {
    final o = renderObjectOf(node);
    if (o == null) {
      return {'id': idOf(node)};
    }
    final c = o.constraints;
    final at = o.parentData;
    final (gx, gy) = o.globalOffset;
    return {
      'id': idOf(node),
      'render': idOf(o),
      'name': '${o.runtimeType}',
      if (c != null)
        'constraints': {
          'minWidth': _limit(c.minW),
          'maxWidth': _limit(c.maxW),
          'minHeight': _limit(c.minH),
          'maxHeight': _limit(c.maxH),
        },
      if (c != null) 'size': {'width': o.width, 'height': o.height},
      'offset': {'x': at.dx, 'y': at.dy},
      'global': {'x': gx, 'y': gy},
    };
  }

  /// What is at [x], [y] of the screen (of the region in the inline
  /// mode), by a hit test of the last layout: `id`, the deepest element
  /// whose render object is hit there, null for none; `path`, the ids of
  /// the elements from the root down to it; `render`, the ids of the
  /// render objects hit, the deepest first.
  Map<String, Object?> select(int x, int y) {
    final (hit, result) = _hit(x, y);
    final path = <int>[];
    if (hit != null) {
      path.add(idOf(hit));
      hit.visitAncestorElements((e) {
        path.add(idOf(e));
        return true;
      });
    }
    return {
      'id': hit == null ? null : idOf(hit),
      'path': path.reversed.toList(),
      'render': [for (var i = 0; i < result.length; i++) idOf(result[i])],
    };
  }

  /// The deepest element whose render object is hit at [x], [y], as
  /// [select] finds it; null for none.
  Element? elementAt(int x, int y) => _hit(x, y).$1;

  (Element?, HitTestResult) _hit(int x, int y) {
    final result = HitTestResult();
    hitTest(result, x, y);
    final owners = _owners();
    Element? hit;
    for (var i = 0; i < result.length && hit == null; i++) {
      hit = owners[result[i]];
    }
    return (hit, result);
  }

  /// [e] and the elements below it, [node] its description.
  Map<String, Object?> _elementNode(Element e, DiagnosticsNode node) {
    final children = <Element>[];
    e.visitChildren(children.add);
    assert(node.children.length == children.length, 'a node for each child');
    return _fields(e, node)
      ..addAll(_links(e))
      ..['children'] = [
        for (var i = 0; i < children.length; i++)
          _elementNode(children[i], node.children[i]),
      ];
  }

  /// [o] and the render objects below it, [node] its description, each
  /// with the id of its element in [owners].
  Map<String, Object?> _renderNode(
    RenderObject o,
    DiagnosticsNode node,
    Map<RenderObject, Element> owners,
  ) {
    final children = <RenderObject>[];
    o.visitChildren(children.add);
    assert(node.children.length == children.length, 'a node for each child');
    final owner = owners[o];
    return _fields(o, node)
      ..addAll({if (owner != null) 'element': idOf(owner)})
      ..['children'] = [
        for (var i = 0; i < children.length; i++)
          _renderNode(children[i], node.children[i], owners),
      ];
  }

  /// The fields of [node], the description of [object], but its children.
  Map<String, Object?> _fields(Object object, DiagnosticsNode node) => {
    'id': idOf(object),
    'name': node.name,
    if (node.key != null) 'key': node.key,
    'properties': [for (final p in node.properties) p.toJson()],
    if (node.size case (final w, final h)) 'size': {'width': w, 'height': h},
    'flags': [for (final f in node.flags) f.name],
  };

  /// The id of [e]'s render object, if it has one ([renderObjectOf]), and
  /// the type whose `build` makes its child, for the element of a
  /// stateless or stateful widget ([buildTypeOf]).
  Map<String, Object?> _links(Element e) => {
    if (e.renderObject case final o?) 'render': idOf(o),
    'build': ?buildTypeOf(e),
  };

  /// The name of the type whose `build` method makes [e]'s child: the
  /// widget's for a [StatelessElement], the state's for a
  /// [StatefulElement]; null for any other element, whose child comes
  /// from its widget (a proxy) or which has render objects for children.
  static String? buildTypeOf(Element e) => switch (e) {
    final StatefulElement e => '${e.state.runtimeType}',
    StatelessElement(:final widget) => '${widget.runtimeType}',
    _ => null,
  };

  /// The id of the element whose render object [o] is, if any.
  Map<String, Object?> _link(RenderObject o) => {
    if (_owners()[o] case final e?) 'element': idOf(e),
  };

  /// The elements of the tree that have render objects of their own, by
  /// those.
  Map<RenderObject, Element> _owners() {
    final owners = Map<RenderObject, Element>.identity();
    void visit(Element e) {
      if (e is RenderObjectElement) {
        owners[e.renderObject] = e;
      }
      e.visitChildren(visit);
    }

    final top = root();
    if (top != null) {
      visit(top);
    }
    return owners;
  }

  static RenderObject? _topOf(RenderObject? object) {
    var o = object;
    while (o?.parent != null) {
      o = o!.parent;
    }
    return o;
  }

  static int? _limit(int v) => v >= BoxConstraints.unbounded ? null : v;
}

// ------------------------------------------------------------ highlight --

/// What a highlight tints its node with: its edges, and the cells inside
/// them.
const _highlightColor = Color.rgb(0, 128, 255);
const _edgeAlpha = 0xC0;
const _insideAlpha = 0x40;

/// The cells of [target] the screen shows, from (x0, y0) to (x1, y1)
/// exclusive, in the coordinates of the root: its bounds cut off where an
/// ancestor cuts it off, as paint cuts it; null for none, or while it is
/// detached.
(int, int, int, int)? _shownOf(RenderObject target) {
  if (target.owner == null) {
    return null;
  }
  final (gx, gy) = target.globalOffset;
  var x0 = gx;
  var y0 = gy;
  var x1 = gx + target.width;
  var y1 = gy + target.height;
  var ax = gx;
  var ay = gy;
  for (var o = target; o.parent != null; o = o.parent!) {
    ax -= o.parentData.dx;
    ay -= o.parentData.dy;
    final p = o.parent!;
    x0 = x0 > ax ? x0 : ax;
    y0 = y0 > ay ? y0 : ay;
    x1 = x1 < ax + p.width ? x1 : ax + p.width;
    y1 = y1 < ay + p.height ? y1 : ay + p.height;
  }
  return x0 < x1 && y0 < y1 ? (x0, y0, x1, y1) : null;
}

/// Whether the outline over [target] ([paintHighlight]) reaches the cells
/// [x], [y], [w] × [h] of the root.
bool highlightReaches(RenderObject target, int x, int y, int w, int h) {
  final shown = _shownOf(target);
  if (shown == null) {
    return false;
  }
  final (x0, y0, x1, y1) = shown;
  return x0 < x + w && x < x1 && y0 < y + h && y < y1;
}

/// Paints an outline over the cells of [target] the screen shows, within
/// the clip of [ctx]'s canvas, whose origin is at the root: the background
/// of each cell blended with blue, its glyph, text color and attributes
/// kept, its edges more than the cells inside them, a two-column glyph
/// cut by the outline tinted whole; nothing while it is detached.
void paintHighlight(PaintContext ctx, RenderObject target) {
  final shown = _shownOf(target);
  if (shown == null) {
    return;
  }
  final canvas = ctx.canvas;
  final (cx0, cy0, cx1, cy1) = canvas.clipBounds;
  final (sx0, sy0, sx1, sy1) = shown;
  final x0 = sx0 > cx0 ? sx0 : cx0;
  final y0 = sy0 > cy0 ? sy0 : cy0;
  final x1 = sx1 < cx1 ? sx1 : cx1;
  final y1 = sy1 < cy1 ? sy1 : cy1;
  if (x0 >= x1 || y0 >= y1) {
    return;
  }
  final styles = canvas.styles;
  final edge = styles.pen(
    const Pen(bg: _highlightColor, bgAlpha: _edgeAlpha),
  );
  final inside = styles.pen(
    const Pen(bg: _highlightColor, bgAlpha: _insideAlpha),
  );
  final (gx, gy) = target.globalOffset;
  final right = gx + target.width - 1;
  final bottom = gy + target.height - 1;
  final thin = target.width <= 2;
  final surface = canvas.surface;
  final cells = surface.cells;
  final sty = surface.styles;
  final width = surface.width;
  for (var y = y0; y < y1; y++) {
    final row = y * width;
    final edgeRow = thin || y == gy || y == bottom;
    var a = x0;
    var b = x1;
    if (a > 0 && (cells[row + a] & kCont) != 0) {
      a--;
    }
    if (b < width && (cells[row + b - 1] & kWide) != 0) {
      b++;
    }
    for (var x = a; x < b;) {
      // both halves of a two-column glyph keep one style
      final n = (cells[row + x] & kWide) != 0 && x + 1 < b ? 2 : 1;
      final last = x + n - 1;
      final onEdge =
          edgeRow || (x <= gx && gx <= last) || (x <= right && right <= last);
      final tinted = _tinted(styles, sty[row + x], onEdge ? edge : inside);
      for (var k = 0; k < n; k++) {
        sty[row + x + k] = tinted;
      }
      x += n;
    }
    surface.markDirty(y, a, b);
  }
}

/// [style] with its background blended with that of [tint], a pen with a
/// translucent background alone, all else kept.
int _tinted(StyleTable styles, int style, int tint) => styles.style(
  fg: styles.fgOf(style),
  bg: styles.bgOf(styles.compose(style, tint)),
  attrs: styles.attrsOf(style),
  underlineColor: styles.underlineColorOf(style),
  link: styles.linkOf(style),
);
