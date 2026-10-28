import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderBox;

import '../layout/view.dart';

void main() {
  late View view;
  late int pen;

  setUp(() {
    view = View(30, 12);
    pen = view.screen.styles.pen(const Pen(bg: Color.blue));
    view.pump(
      Column(
        children: [
          const _Header('agent'),
          Expanded(
            child: Box(
              border: const Border.all(type: BorderType.rounded),
              padding: const EdgeInsets.x(1),
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++)
                    Text('message $i', key: ValueKey(i)),
                ],
              ),
            ),
          ),
          const _Counter(key: Key('counter')),
          SizedBox(height: 1, child: _Panel(pen)),
        ],
      ),
    );
  });

  test('debugDumpTree prints the element tree from its root', () {
    final context = _find<_Counter>(view.root);
    expect(_printed(() => debugDumpTree(context)), [
      '''
RootWidget                                            30×12
└─ Column ‹vertical›                                  30×12
   ├─ _Header ‹title: "agent"›                         5×1
   │  └─ Text ‹"agent"›                                5×1
   ├─ Expanded                                        13×9
   │  └─ Box ‹border: rounded, padding: 0 1, flex: 1› 13×9
   │     └─ Column ‹vertical›                          9×7
   │        └─ … 6 Text
   ├─ _Counter-[<'counter'>] ‹count: 2›                7×1
   │  └─ Text ‹"count 2"›                              7×1
   └─ SizedBox ‹additionalConstraints: 0..∞×1›        30×1
      └─ _Panel ‹pen: $pen›                              30×1  ◆

◆ repaint boundary''',
    ]);
  });

  test('debugDumpRenderTree prints the render tree from its root', () {
    final context = _find<_Panel>(view.root);
    expect(_printed(() => debugDumpRenderTree(context)), [
      '''
RenderFlex ‹vertical, constraints: tight›                                                         30×12 ◇
├─ RenderParagraph ‹"agent", offset: 12,0, constraints: 0..30×0..12›                               5×1
├─ RenderDecoratedBox ‹border: rounded, padding: 0 1, flex: 1, offset: 8,1, constraints: 0..30×9› 13×9
│  └─ RenderFlex ‹vertical, offset: 2,1, constraints: 0..26×7›                                     9×7
│     └─ … 6 RenderParagraph
├─ RenderParagraph ‹"count 2", offset: 11,10, constraints: 0..30×0..12›                            7×1
└─ RenderConstrainedBox ‹additionalConstraints: 0..∞×1, offset: 0,11, constraints: 0..30×0..12›   30×1
   └─ RenderBox ‹pen: $pen, constraints: 0..30×1›                                                    30×1  ◆ ◇

◆ repaint boundary, ◇ relayout boundary''',
    ]);
  });

  test('the dumps show what is to be built, laid out and painted', () {
    final counter = _find<_Counter>(view.root) as StatefulElement;
    (counter.state as _CounterState).increment();
    final dump = _printed(() => debugDumpTree(counter)).single;
    expect(
      dump.split('\n'),
      contains(
        matches(r"^   ├─ _Counter-\[<'counter'>\] ‹count: 3› + 7×1  ✱$"),
      ),
    );
    expect(dump, endsWith('\n\n◆ repaint boundary, ✱ needs build'));
    view.frame();
    final text = view.root.describe().children.single.children[2].children;
    expect('${text.single}', 'Text ‹"count 3"›');
    expect(text.single.flags, isEmpty);
    expect(
      _printed(() => debugDumpRenderTree(counter)).single,
      isNot(contains('⟳')),
    );
  });
}

/// The element of the only widget of type [W] below [root].
Element _find<W extends Widget>(Element root) {
  final found = <Element>[];
  void visit(Element e) {
    if (e.widget is W) {
      found.add(e);
    }
    e.visitChildren(visit);
  }

  visit(root);
  return found.single;
}

/// What [body] prints.
List<String> _printed(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

/// Shows [title]; described by it.
final class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(title);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('title', title);
  }
}

/// Shows a count, described by it.
final class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

final class _CounterState extends State<_Counter> {
  var _count = 2;

  void increment() => setState(() => _count++);

  @override
  Widget build(BuildContext context) => Text('count $_count');

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('count', _count);
  }
}

/// A repaint boundary filled with [pen].
final class _Panel extends LeafRenderObjectWidget {
  const _Panel(this.pen);

  final int pen;

  @override
  RenderBox createRenderObject(BuildContext context) =>
      RenderBox(pen: pen, boundary: true);
}
