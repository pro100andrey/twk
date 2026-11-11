// A flexible child in an unbounded main axis is laid out by its content;
// in debug the flex says so, once.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

import 'flex_test.dart' show Label, flexible, printed;

void main() {
  var asserts = false;
  assert(asserts = true, 'debug only');

  List<String> layout(RenderFlex row, int maxWidth) => printed(
    () => row.layout(
      BoxConstraints(maxWidth: maxWidth, maxHeight: 1),
      parentUsesSize: true,
    ),
  );

  test('a flexible child of an unbounded axis is hinted once per flex', () {
    final label = Label('ab');
    final row = RenderFlex(children: [label]);
    flexible(label, 1);
    final first = layout(row, BoxConstraints.unbounded);
    label.text = 'abc';
    final second = layout(row, BoxConstraints.unbounded);
    expect(row.width, 3, reason: 'laid out by its content');
    expect(second, isEmpty);
    expect(first.length, asserts ? 1 : 0);
    if (asserts) {
      expect(first.single, contains('warning'));
      expect(first.single, contains('Expanded'));
      expect(first.single, contains('width'));
    }
  });

  test('a bounded axis, or no flex factor, says nothing', () {
    final a = Label('ab');
    final bounded = RenderFlex(children: [a]);
    flexible(a, 1);
    expect(layout(bounded, 10), isEmpty);
    final plain = RenderFlex(children: [Label('x')]);
    expect(layout(plain, BoxConstraints.unbounded), isEmpty);
  });
}
