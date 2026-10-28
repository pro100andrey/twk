// Boxes with a border, titles and padding, and dividers: their styles
// turned into the pens of the core's render objects, which they set up and
// change, and the child put into the box, swapped and taken out.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show BoxBorder, BoxTitle, RenderDecoratedBox, RenderDivider;

import 'view.dart';

const red = Color.rgb(200, 0, 0);
const blue = Color.rgb(0, 0, 200);

void main() {
  group('Box', () {
    test('draws a border with titles and padding around its child', () {
      final v = View(10, 5)
        ..pump(
          const Box(
            border: Border.all(type: BorderType.rounded),
            titles: [
              BorderTitle(' Log '),
              BorderTitle('2', alignment: Alignment.bottomRight),
            ],
            padding: EdgeInsets.x(1),
            child: Fill('x'),
          ),
        );
      expect(v.rows(), [
        '╭ Log ───╮',
        '│ xxxxxx │',
        '│ xxxxxx │',
        '│ xxxxxx │',
        '╰───────2╯',
      ]);
    });

    test('is as big as its child and border, and as wide as its titles', () {
      final v = View(9, 4)
        ..pump(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Box(border: Border.all(), child: Label('ab')),
              Box(
                border: Border(top: Style()),
                titles: [BorderTitle('title')],
                child: Label('a'),
              ),
            ],
          ),
        );
      expect(v.rows(), ['┌──┐', '│ab│', '└──┘', 'title']);
    });

    test('gives its render object the pens of its styles', () {
      final v = View(6, 3)
        ..pump(
          const Box(
            style: Style(bg: blue),
            border: Border(
              type: BorderType.heavy,
              top: Style(fg: red),
              left: Style(),
            ),
            titles: [
              BorderTitle(
                'a',
                style: Style(fg: blue),
                alignment: Alignment.topCenter,
              ),
            ],
          ),
        );
      final box = v.top as RenderDecoratedBox;
      expect(box.background, const Pen(bg: blue));
      expect(
        box.border,
        const BoxBorder(
          type: BorderType.heavy,
          top: Pen(fg: red),
          left: Pen(),
        ),
      );
      expect(box.titles, const [
        BoxTitle(
          'a',
          pen: Pen(fg: blue),
          alignment: Alignment.topCenter,
        ),
      ]);
      expect(v.rows(), ['┏━━a━━', '┃', '┃']);
    });

    test('new settings change the same render object', () {
      final v = View(6, 3)
        ..pump(const Box(border: Border.all(), child: Fill('x')));
      final box = v.top;
      v.pump(
        const Box(
          style: Style(fg: red),
          border: Border(bottom: Style()),
          titles: [BorderTitle('t')],
          padding: EdgeInsets.only(left: 1),
          child: Fill('x'),
        ),
      );
      expect(v.top, same(box));
      expect(
        [
          (box as RenderDecoratedBox).background,
          box.border,
          box.titles,
          box.padding,
        ],
        [
          const Pen(fg: red),
          const BoxBorder(bottom: Pen()),
          const [BoxTitle('t')],
          const EdgeInsets.only(left: 1),
        ],
      );
      expect(v.rows(), ['t', ' xxxxx', '──────']);
      v.pump(const Box(child: Fill('x')));
      expect(
        [box.background, box.border, box.titles, box.padding],
        [null, null, isEmpty, EdgeInsets.zero],
      );
      expect(v.rows(), ['xxxxxx', 'xxxxxx', 'xxxxxx']);
    });

    test('rebuilt the same asks for neither a layout nor a paint', () {
      // new instances on each build
      Style red(int r) => Style(fg: Color.rgb(r, 0, 0));
      Box box() => Box(
        style: red(200),
        border: Border.all(style: red(200)),
        titles: [BorderTitle('t', style: red(200))],
        child: const Fill('x'),
      );
      final v = View(4, 3)..pump(Toggle(box, box));
      toggleIn(v.root).toggle();
      v.owner.buildScope();
      expect(v.pipeline.hasWork, isFalse);
    });

    test('swaps its child for the render object of a new one', () {
      final v = View(4, 3)
        ..pump(
          Toggle(
            () => const Box(border: Border.all(), child: Label('a')),
            () => const Box(border: Border.all(), child: Fill('x')),
          ),
        );
      final box = v.top as RenderObjectWithChildMixin;
      final first = box.child;
      expect(v.rows(), ['┌──┐', '│a │', '└──┘']);
      toggleIn(v.root).toggle();
      v.frame();
      expect(box.child, isNot(same(first)));
      expect(first!.parent, isNull);
      expect(v.rows(), ['┌──┐', '│xx│', '└──┘']);
    });

    test('with a border that merges joins the lines under it', () {
      final v = View(9, 3)
        ..pump(
          const Stack(
            children: [
              Positioned(
                left: 0,
                width: 5,
                top: 0,
                bottom: 0,
                child: Box(border: Border.all(type: BorderType.heavy)),
              ),
              Positioned(
                left: 4,
                width: 5,
                top: 0,
                bottom: 0,
                child: Box(
                  border: Border.all(type: BorderType.heavy, merge: true),
                ),
              ),
            ],
          ),
        );
      expect(v.rows(), ['┏━━━┳━━━┓', '┃   ┃   ┃', '┗━━━┻━━━┛']);
      final stack = v.top as ContainerRenderObjectMixin;
      expect(
        [
          for (final b in [stack.firstChild, stack.lastChild])
            (b! as RenderDecoratedBox).border!.merge,
        ],
        [false, true],
      );
    });

    test('takes its child out when it has none, and puts it back', () {
      final v = View(4, 3)
        ..pump(
          Toggle(
            () => const Box(border: Border.all(), child: Fill('x')),
            () => const Box(border: Border.all()),
          ),
        );
      final box = v.top as RenderObjectWithChildMixin;
      final child = box.child;
      toggleIn(v.root).toggle();
      v.frame();
      expect([box.child, child!.parent], [null, null]);
      expect(v.rows(), ['┌──┐', '│  │', '└──┘']);
      toggleIn(v.root).toggle();
      v.frame();
      expect(box.child, isNotNull);
      expect(v.rows(), ['┌──┐', '│xx│', '└──┘']);
    });
  });

  group('Border and BorderTitle', () {
    test('are equal when what they hold is', () {
      // new instances on each call
      Style red(int r) => Style(fg: Color.rgb(r, 0, 0));
      Border all(int r) => Border.all(style: red(r));
      BorderTitle title(int r) => BorderTitle('a', style: red(r));
      expect(all(200), all(200));
      expect(all(200).hashCode, all(200).hashCode);
      expect(
        all(200),
        Border(
          top: red(200),
          right: red(200),
          bottom: red(200),
          left: red(200),
        ),
      );
      expect(all(200), isNot(all(100)));
      expect(const Border(top: Style()), isNot(const Border(bottom: Style())));
      expect(
        const Border.all(),
        isNot(const Border.all(type: BorderType.double)),
      );
      expect(const Border.all(), isNot(const Border.all(merge: true)));
      expect(
        const Border.all(merge: true).hashCode,
        const Border.all(merge: true).hashCode,
      );
      expect(title(200), title(200));
      expect(title(200).hashCode, title(200).hashCode);
      expect(title(200), isNot(title(100)));
      expect(
        const BorderTitle('a'),
        isNot(const BorderTitle('a', alignment: Alignment.bottomLeft)),
      );
      expect(const BorderTitle('a'), isNot(const BorderTitle('b')));
    });
  });

  group('Divider', () {
    test('draws a line across a column, a vertical one down a row', () {
      final v = View(5, 3)
        ..pump(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Label('ab'),
              Divider(type: BorderType.double),
              SizedBox(
                height: 1,
                child: Row(
                  children: [Label('a'), VerticalDivider(), Label('b')],
                ),
              ),
            ],
          ),
        );
      expect(v.rows(), ['ab', '═════', 'a│b']);
    });

    test('that merge join the lines of a box they are stacked on', () {
      final v = View(7, 5)
        ..pump(
          const Stack(
            children: [
              Box(border: Border.all(type: BorderType.double)),
              Positioned(
                left: 0,
                right: 0,
                top: 2,
                child: Divider(merge: true),
              ),
              Positioned(
                left: 3,
                top: 0,
                bottom: 0,
                child: VerticalDivider(type: BorderType.double, merge: true),
              ),
            ],
          ),
        );
      expect(v.rows(), [
        '╔══╦══╗',
        '║  ║  ║',
        '╟──╫──╢',
        '║  ║  ║',
        '╚══╩══╝',
      ]);
    });

    test('new settings change the same render object', () {
      final v = View(3, 1)..pump(const Divider());
      final line = v.top;
      v.pump(
        const Divider(
          type: BorderType.heavy,
          style: Style(fg: red),
          merge: true,
        ),
      );
      expect(v.top, same(line));
      expect(
        [(line as RenderDivider).type, line.pen, line.direction, line.merge],
        [BorderType.heavy, const Pen(fg: red), Axis.horizontal, true],
      );
      expect(v.rows(), ['━━━']);
      v.pump(const VerticalDivider(type: BorderType.ascii));
      expect(v.top, isNot(same(line)));
      expect((v.top as RenderDivider).direction, Axis.vertical);
      // in the middle of the room it gets
      expect(v.rows(), [' |']);
    });
  });
}
