// PipelineOwner.debugCheckIntrinsics: the intrinsic sizes of an object that
// is laid out are not negative and a minimum is not above its maximum.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// Answers [minW], [maxW], [minH] and [maxH] whatever it is asked.
final class Answers extends RenderObject {
  Answers({this.minW = 0, this.maxW = 0, this.minH = 0, this.maxH = 0});

  final int minW;
  final int maxW;
  final int minH;
  final int maxH;

  @override
  int computeMinIntrinsicWidth(int height) => minW;

  @override
  int computeMaxIntrinsicWidth(int height) => maxW;

  @override
  int computeMinIntrinsicHeight(int width) => minH;

  @override
  int computeMaxIntrinsicHeight(int width) => maxH;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainWidth(1);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) {}
}

/// Lays [object] out under an owner that checks (or not).
void lay(RenderObject object, {bool check = true}) {
  PipelineOwner(() {})
    ..debugCheckIntrinsics = check
    ..root = object
    ..flushLayout(10, 4);
}

Matcher failsWith(String text) => throwsA(
  isA<AssertionError>().having(
    (e) => '${e.message}',
    'message',
    contains(text),
  ),
);

void main() {
  test('an object that answers within the contract passes', () {
    lay(Answers(minW: 1, maxW: 5, maxH: 2));
  });

  test('a negative answer asserts, naming the query', () {
    expect(
      () => lay(Answers(minH: -1)),
      failsWith('computeMinHeightIntrinsic(1073741824) is negative: -1'),
    );
    expect(() => lay(Answers(maxW: -2)), failsWith('computeMaxWidthIntrinsic'));
  });

  test('a minimum above its maximum asserts', () {
    expect(
      () => lay(Answers(minW: 4, maxW: 3)),
      failsWith('computeMinWidthIntrinsic(1073741824) = 4 is above '),
    );
    expect(() => lay(Answers(minH: 2)), failsWith('computeMinHeightIntrinsic'));
  });

  test('a child that breaks it is named, not the parent that asks it', () {
    expect(
      () =>
          lay(RenderPadding(padding: EdgeInsets.zero, child: Answers(minW: 2))),
      failsWith("Instance of 'Answers'"),
    );
  });

  test('off by default: nothing is asked, nothing asserts', () {
    lay(Answers(minW: 4, maxW: 3), check: false);
  });
}
