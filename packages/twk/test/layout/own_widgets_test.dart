// An app's own layout widgets, written with twk.dart alone: one over a
// render object with a child returns a OneChildElement, which takes a
// child, another in its place and none; one over a render object with a
// list of children returns a ChildListElement, which keeps them in order
// as they are added, moved and taken away.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [child] a column in.
final class _Indent extends SingleChildRenderObjectWidget {
  const _Indent({super.child});

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderIndent createRenderObject(BuildContext context) => _RenderIndent();
}

final class _RenderIndent extends RenderObject with RenderObjectWithChildMixin {
  @override
  void performLayout(BoxConstraints c) {
    var h = 0;
    if (child case final child?) {
      child
        ..layout(BoxConstraints(0, c.maxW - 1, 0, c.maxH), parentUsesSize: true)
        ..parentData.dx = 1;
      h = child.height;
    }
    width = c.maxW;
    height = c.constrainH(h);
  }

  @override
  void paint(PaintContext ctx) {
    if (child case final child?) {
      paintChild(ctx, child);
    }
  }
}

final class _LineData extends ParentData with ContainerParentDataMixin {}

/// Its [children] a row each, top to bottom.
final class _Lines extends MultiChildRenderObjectWidget {
  const _Lines({super.children});

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderLines createRenderObject(BuildContext context) => _RenderLines();
}

final class _RenderLines extends RenderObject
    with ContainerRenderObjectMixin<_LineData> {
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _LineData) {
      child.parentData = _LineData();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    var y = 0;
    for (var o = firstChild; o != null; o = childAfter(o)) {
      o
        ..layout(BoxConstraints(0, c.maxW, 0, 1))
        ..parentData.dy = y;
      y += 1;
    }
    width = c.maxW;
    height = c.constrainH(y);
  }

  @override
  void paint(PaintContext ctx) => visitChildren((o) => paintChild(ctx, o));
}

void main() {
  testTwk("an app's own widget with a child returns a OneChildElement: it "
      'shows the child, another in its place, and none', (t) async {
    await t.pumpWidget(const _Indent(child: Text('one')), size: (6, 2));
    expect(t, matchesScreen(' one'));
    await t.pumpWidget(const _Indent(child: Text('two')));
    expect(t, matchesScreen(' two'));
    await t.pumpWidget(const _Indent(child: Center(child: Text('x'))));
    expect(t, hasTextAt(3, 0, 'x'));
    await t.pumpWidget(const _Indent());
    expect(t, matchesScreen(''));
    await t.pumpWidget(const _Indent(child: Text('back')));
    expect(t, matchesScreen(' back'));
  });

  testTwk("an app's own widget with children returns a ChildListElement: "
      'it keeps them in order as they are added, moved and taken away', (
    t,
  ) async {
    Widget lines(List<String> texts) => _Lines(
      children: [for (final s in texts) Text(s, key: ValueKey(s))],
    );
    await t.pumpWidget(lines(['a', 'b']), size: (4, 4));
    expect(t, matchesScreen('a\nb'));
    await t.pumpWidget(lines(['a', 'c', 'b']));
    expect(t, matchesScreen('a\nc\nb'));
    await t.pumpWidget(lines(['b', 'a', 'c']));
    expect(t, matchesScreen('b\na\nc'));
    await t.pumpWidget(lines(['c']));
    expect(t, matchesScreen('c'));
    await t.pumpWidget(lines([]));
    expect(t, matchesScreen(''));
  });
}
