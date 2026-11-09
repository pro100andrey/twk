// The layout contract on the relayout path: a layout bug found after
// performLayout shows as the error box of the object that has it, also when
// the object is laid out by the owner alone; a list moving its own items
// while its parent asks it for intrinsic sizes in the parent's layout is
// valid code and marks nothing wrongly.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// Takes a size outside its constraints once [bad] is set.
final class Faulty extends RenderObject {
  var bad = false;

  @override
  void performLayout(BoxConstraints c) {
    width = bad ? c.maxWidth + 5 : c.constrainWidth(3);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) {}
}

final class Data extends ParentData with ContainerParentDataMixin {}

/// Children in a row; moves the first one to the end in its layout when
/// [shuffle] is set, as a list sorting its items does.
final class Shuffler extends RenderObject
    with ContainerRenderObjectMixin<Data> {
  var shuffle = false;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! Data) {
      child.parentData = Data();
    }
  }

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    if (shuffle) {
      shuffle = false;
      move(firstChild!, after: lastChild);
    }
    for (
      var k = firstChild;
      k != null;
      k = (k.parentData as Data).nextSibling
    ) {
      k.layout(c.loosen());
    }
    width = c.constrainWidth(2);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) {}
}

/// Asks its child's intrinsic height, then lays it out, as IntrinsicHeight.
final class Asker extends RenderObject with RenderObjectWithChildMixin {
  @override
  void performLayout(BoxConstraints c) {
    final k = child!;
    final h = c.constrainHeight(k.getMaxIntrinsicHeight(c.maxWidth));
    k.layout(BoxConstraints.tight(c.maxWidth, h), parentUsesSize: true);
    width = c.constrainWidth(c.maxWidth);
    height = h;
  }

  @override
  void paint(PaintContext ctx) {}
}

void main() {
  test('a size outside the constraints on the relayout path is the '
      "object's error box, not an exception out of flushLayout", () {
    final reports = <String>[];
    final f = Faulty();
    final owner = PipelineOwner(() {})
      ..onError = (o, phase, error, stack) {
        reports.add('$o: $error');
      }
      ..root = f
      ..flushLayout(20, 5);
    expect(reports, isEmpty);
    f
      ..bad = true
      ..markNeedsLayout();
    owner.flushLayout(20, 5);
    expect(reports.join(), contains('outside its constraints'));
    expect(reports.single, startsWith("Instance of 'Faulty'"));
  });

  test('an object moving its own children in a layout a parent asked '
      'intrinsics of marks no one wrongly', () {
    final reports = <String>[];
    final s = Shuffler()..addAll([Faulty(), Faulty()]);
    final root = Asker()..child = s;
    final owner = PipelineOwner(() {})
      ..onError = (o, phase, error, stack) {
        reports.add('$o: $error');
      }
      ..root = root
      ..flushLayout(20, 5);
    expect(reports, isEmpty);
    s
      ..shuffle = true
      ..markNeedsLayout();
    owner.flushLayout(20, 5);
    expect(reports, isEmpty);
  });
}
