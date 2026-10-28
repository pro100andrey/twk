// Rows and columns of widgets: the render objects of the children go into
// the flex's in order, and flexible children keep their flex factor and
// fit whatever is rebuilt below them.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderConstrainedBox, RenderFlex;

import 'view.dart';

void main() {
  test('a Row lays its children out side by side, gap cells apart', () {
    final v = View(12, 1)
      ..pump(const Row(gap: 1, children: [Label('ab'), Label('cd')]));
    expect(v.rows(), ['ab cd']);
  });

  test('a Column lays them out one below another', () {
    final v = View(4, 3)
      ..pump(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Label('ab'), Label('c')],
        ),
      );
    expect(v.rows(), ['ab', 'c', '']);
  });

  test('a Flex gives its settings to its render object', () {
    final v = View(6, 4)
      ..pump(
        const Flex(
          direction: Axis.vertical,
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          gap: 1,
          children: [Label('a'), Label('b')],
        ),
      );
    final flex = v.top as RenderFlex;
    expect(
      [
        flex.direction,
        flex.mainAxisAlignment,
        flex.mainAxisSize,
        flex.crossAxisAlignment,
        flex.gap,
      ],
      [
        Axis.vertical,
        MainAxisAlignment.end,
        MainAxisSize.min,
        CrossAxisAlignment.end,
        1,
      ],
    );
    expect(v.rows(), ['', '     a', '', '     b']);
  });

  test('a new widget changes the settings of the same render object', () {
    final v = View(6, 1)..pump(const Row(children: [Label('a'), Label('b')]));
    final flex = v.top;
    expect(v.rows(), ['ab']);
    v.pump(
      const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        gap: 2,
        children: [Label('a'), Label('b')],
      ),
    );
    expect(v.top, same(flex));
    expect(v.rows(), ['  a  b']);
    expect(
      [
        (flex as RenderFlex).mainAxisAlignment,
        flex.mainAxisSize,
        flex.crossAxisAlignment,
        flex.gap,
      ],
      [
        MainAxisAlignment.end,
        MainAxisSize.min,
        CrossAxisAlignment.stretch,
        2,
      ],
    );
  });

  test('an Expanded child fills the cells the others leave', () {
    final v = View(10, 1)
      ..pump(
        const Row(
          children: [
            Label('ab'),
            Expanded(child: Fill('x')),
          ],
        ),
      );
    expect(v.rows(), ['abxxxxxxxx']);
  });

  test('a Flexible child takes what it wants of its share', () {
    final v = View(10, 1)
      ..pump(
        const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(child: Label('ab')),
            Expanded(child: Fill('x')),
          ],
        ),
      );
    expect(v.rows(), ['   abxxxxx']);
  });

  test('flexible children share by their flex factors', () {
    final v = View(10, 1)
      ..pump(
        const Row(
          children: [
            Expanded(child: Fill('x')),
            Expanded(flex: 2, child: Fill('y')),
          ],
        ),
      );
    // 3.3 and 6.7 cells, the leftover one to the first
    expect(v.rows(), ['xxxxyyyyyy']);
  });

  test('a new flex factor or fit lays the flex out again', () {
    final v = View(10, 1)
      ..pump(
        const Row(
          children: [
            Expanded(child: Fill('x')),
            Expanded(child: Fill('y')),
          ],
        ),
      );
    expect(v.rows(), ['xxxxxyyyyy']);
    v.pump(
      const Row(
        children: [
          Expanded(flex: 3, child: Fill('x')),
          Expanded(child: Fill('y')),
        ],
      ),
    );
    expect(v.rows(), ['xxxxxxxxyy']);
    v.pump(
      const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(flex: 3, child: Label('ab')),
          Expanded(child: Fill('y')),
        ],
      ),
    );
    expect(v.rows(), ['ab      yy']);
    v.pump(
      const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(flex: 3, child: Label('ab')),
          Expanded(child: Fill('y')),
        ],
      ),
    );
    expect(v.rows(), ['      abyy']);
  });

  test('Spacers push their siblings apart by their flex factors', () {
    final v = View(12, 1)
      ..pump(
        const Row(
          children: [
            Label('a'),
            Spacer(),
            Label('b'),
            Spacer(flex: 2),
            Label('c'),
          ],
        ),
      );
    expect(v.rows(), ['a   b      c']);
    // each an empty box
    final spacer = childrenOf(v.top)[1];
    expect(
      (spacer as RenderConstrainedBox).additionalConstraints,
      const BoxConstraints.tight(0, 0),
    );
    expect(childrenOf(spacer), isEmpty);
  });

  test('the render objects of children inserted, moved and removed keep '
      'their order', () {
    final v = View(10, 1)..pump(const Row(children: [Label('a'), Label('c')]));
    final [a, c] = childrenOf(v.top);
    v.pump(
      const Row(
        children: [
          Label('a'),
          Expanded(child: Fill('b')),
          Label('c'),
        ],
      ),
    );
    expect(v.rows(), ['abbbbbbbbc']);
    final children = childrenOf(v.top);
    expect([children.first, children.last], [same(a), same(c)]);
    v.pump(const Row(children: [Label('a'), Label('c')]));
    expect(v.rows(), ['ac']);
    expect(childrenOf(v.top), [same(a), same(c)]);
  });

  test('the render objects of keyed children move with them', () {
    final v = View(10, 1)
      ..pump(
        const Row(
          children: [
            Label('a', key: Key('a')),
            Label('b', key: Key('b')),
            Label('c', key: Key('c')),
          ],
        ),
      );
    final [a, b, c] = childrenOf(v.top);
    v.pump(
      const Row(
        children: [
          Label('a', key: Key('a')),
          Label('c', key: Key('c')),
          Label('b', key: Key('b')),
        ],
      ),
    );
    expect(v.rows(), ['acb']);
    expect(childrenOf(v.top), [same(a), same(c), same(b)]);
  });

  group('a Flexible keeps its flex factor and fit when what is below it '
      'is rebuilt into another render object', () {
    Widget x() => const Fill('x');
    Widget y() => const Label('yyyyyyy');
    Widget z() => const Label('zzzzzzzzzzzz');

    test('directly in the Flex', () {
      final v = View(10, 1)
        ..pump(
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(child: Toggle(x, y)),
              const Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['xxxxxxxxx|']);
      toggleIn(v.root).toggle();
      v.frame();
      // tight: the label is stretched over its share
      expect(v.rows(), ['yyyyyyy  |']);
    });

    test('through a widget in between', () {
      final v = View(10, 1)
        ..pump(
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Wrapper(Flexible(child: Toggle(x, z))),
              const Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['xxxxxxxxx|']);
      toggleIn(v.root).toggle();
      v.frame();
      // loose: the label is as wide as it wants, up to its share
      expect(v.rows(), ['zzzzzzzzz|']);
    });
  });

  test('a child that is no longer Flexible is laid out as inflexible', () {
    final v = View(10, 1)
      ..pump(
        Row(
          children: [
            Toggle(
              () => const Expanded(child: Fill('x')),
              () => const Label('ab'),
            ),
            const Label('|'),
          ],
        ),
      );
    expect(v.rows(), ['xxxxxxxxx|']);
    toggleIn(v.root).toggle();
    v.frame();
    expect(v.rows(), ['ab|']);
  });

  test('a Flexible outside a Flex is an error', () {
    final v = View(10, 1);
    expect(
      () => v.pump(const Flexible(child: Label('a'))),
      throwsA(isA<AssertionError>()),
    );
  });
}
