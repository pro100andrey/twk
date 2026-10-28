// Stacks of widgets: the render objects of the children go into the stack
// in order, painted one over another, and positioned children keep their
// edges and sizes whatever is rebuilt below them.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderStack, StackParentData;

import 'view.dart';

/// The edges and sizes on [o]: left, top, right, bottom, width, height.
List<int?> pinsOf(RenderObject o) {
  final at = o.parentData as StackParentData;
  return [at.left, at.top, at.right, at.bottom, at.width, at.height];
}

void main() {
  test('a Stack paints its children one over another, in order', () {
    final v = View(6, 2)
      ..pump(
        const Stack(
          children: [
            Fill('.'),
            Positioned(left: 1, top: 1, child: Label('abc')),
            Positioned(left: 2, top: 1, child: Label('d')),
          ],
        ),
      );
    expect(v.rows(), ['......', '.adc..']);
  });

  test('a Stack gives its settings to its render object', () {
    final v = View(6, 2)
      ..pump(
        const Stack(
          alignment: Alignment.bottomRight,
          fit: StackFit.expand,
          children: [Label('ab')],
        ),
      );
    final stack = v.top as RenderStack;
    expect(
      [stack.alignment, stack.fit],
      [
        Alignment.bottomRight,
        StackFit.expand,
      ],
    );
    expect(v.rows(), ['ab', '']);
    v.pump(
      const Stack(
        alignment: Alignment.bottomRight,
        children: [Label('ab')],
      ),
    );
    expect(v.top, same(stack));
    expect(stack.fit, StackFit.loose);
    expect(v.rows(), ['', '    ab']);
  });

  test('a Positioned puts its edges and size on its child', () {
    final v = View(10, 3)
      ..pump(
        const Stack(
          children: [
            Positioned(left: 1, top: 2, width: 3, child: Fill('x')),
            Positioned(right: 1, bottom: 0, height: 1, child: Label('ab')),
          ],
        ),
      );
    final [a, b] = childrenOf(v.top);
    expect(pinsOf(a), [1, 2, null, null, 3, null]);
    expect(pinsOf(b), [null, null, 1, 0, null, 1]);
    expect(v.rows(), ['', '', ' xxx   ab']);
  });

  test('Positioned.fill pins its child to every edge', () {
    final v = View(6, 3)
      ..pump(
        const Stack(
          children: [
            Positioned.fill(child: Fill('.')),
            Positioned.fill(left: 1, top: 1, right: 2, child: Fill('x')),
          ],
        ),
      );
    final [a, b] = childrenOf(v.top);
    expect(pinsOf(a), [0, 0, 0, 0, null, null]);
    expect(pinsOf(b), [1, 1, 2, 0, null, null]);
    expect(v.rows(), ['......', '.xxx..', '.xxx..']);
  });

  test('a Positioned with all three along an axis is an error', () {
    expect(
      () => Positioned(left: 0, right: 0, width: 1, child: const Label('a')),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => Positioned(top: 0, bottom: 0, height: 1, child: const Label('a')),
      throwsA(isA<AssertionError>()),
    );
  });

  test('new edges lay the stack out again; the same ask for nothing', () {
    Widget at(int left) => Stack(
      children: [
        Positioned(left: left, child: const Label('ab')),
      ],
    );
    final v = View(6, 1)..pump(at(1));
    expect(v.rows(), [' ab']);
    v.pump(at(3));
    expect(v.rows(), ['   ab']);
    final state = (v..pump(Toggle(() => at(3), () => at(3)))).root;
    toggleIn(state).toggle();
    v.owner.buildScope();
    expect(v.pipeline.hasWork, isFalse);
  });

  test('a Positioned keeps its edges when what is below it is rebuilt '
      'into another render object', () {
    final v = View(6, 1)
      ..pump(
        Stack(
          children: [
            Positioned(
              left: 2,
              child: Toggle(() => const Label('ab'), () => const Fill('x')),
            ),
          ],
        ),
      );
    expect(v.rows(), ['  ab']);
    toggleIn(v.root).toggle();
    v.frame();
    expect(v.rows(), ['  xxxx']);
  });

  test('a child that is no longer Positioned goes where the alignment puts '
      'it', () {
    final v = View(6, 1)
      ..pump(
        Stack(
          alignment: Alignment.centerRight,
          children: [
            Toggle(
              () => const Positioned(left: 0, child: Label('ab')),
              () => const Label('ab'),
            ),
          ],
        ),
      );
    expect(v.rows(), ['ab']);
    toggleIn(v.root).toggle();
    v.frame();
    expect(v.rows(), ['    ab']);
    expect(pinsOf(childrenOf(v.top).single), List.filled(6, null));
  });

  test('keyed children moved to the front are painted over the others', () {
    final v = View(4, 1)
      ..pump(
        const Stack(
          children: [
            Label('abcd', key: Key('a')),
            Label('ef', key: Key('b')),
          ],
        ),
      );
    final [a, b] = childrenOf(v.top);
    expect(v.rows(), ['efcd']);
    v.pump(
      const Stack(
        children: [
          Label('ef', key: Key('b')),
          Label('abcd', key: Key('a')),
        ],
      ),
    );
    expect(childrenOf(v.top), [same(b), same(a)]);
    expect(v.rows(), ['abcd']);
  });

  test('a Positioned outside a Stack is an error', () {
    final v = View(10, 1);
    expect(
      () => v.pump(const Row(children: [Positioned(child: Label('a'))])),
      throwsA(isA<AssertionError>()),
    );
  });
}
