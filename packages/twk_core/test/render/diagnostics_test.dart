// Render objects describe themselves for debugging, only when asked: a
// tree of nodes with names, properties, sizes and flags, dumped as text
// with guides and a size column, or as JSON.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A render tree filling a whole screen.
final class View {
  View(this.width, this.height) : screen = Screen(width, height) {
    pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    owner = PipelineOwner(() {});
  }

  final int width;
  final int height;
  final Screen screen;
  late final int pen;
  late final PipelineOwner owner;

  void frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
  }
}

/// As big as it may be; counts the calls of [debugFillProperties].
final class Probe extends RenderObject {
  var described = 0;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {}

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    described++;
    properties.addTag('probe');
  }
}

/// A node of [name] with [size] and [flags].
DiagnosticsNode node(
  String name, {
  String? key,
  List<DiagnosticsProperty> properties = const [],
  (int, int)? size,
  List<DiagnosticsFlag> flags = const [],
  List<DiagnosticsNode> children = const [],
}) => DiagnosticsNode(
  name,
  key: key,
  properties: properties,
  size: size,
  flags: flags,
  children: children,
);

void main() {
  group('toStringDeep', () {
    test('guides, sizes aligned on the ×, flags and their legend', () {
      final tree = node(
        'App',
        properties: const [DiagnosticsProperty(null, 'fullscreen')],
        size: (120, 40),
        children: [
          node(
            'Column',
            size: (120, 40),
            children: [
              node(
                'Header',
                properties: const [DiagnosticsProperty('title', '"agent"')],
                size: (120, 1),
              ),
              node(
                'ListView',
                properties: const [DiagnosticsProperty('items', '214')],
                size: (120, 37),
                flags: const [DiagnosticsFlag.repaintBoundary],
                children: [
                  for (var i = 0; i < 19; i++)
                    node('MessageView', key: '[<$i>]', size: (120, 2)),
                ],
              ),
              node(
                'Box',
                key: "[<'input'>]",
                size: (120, 2),
                flags: const [DiagnosticsFlag.needsLayout],
                children: [
                  node(
                    'TextField',
                    properties: const [
                      DiagnosticsProperty(null, 'focused'),
                      DiagnosticsProperty(null, '"проверь прокрутку"'),
                    ],
                    size: (8, 1),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      expect(tree.toStringDeep(), '''
App ‹fullscreen›                                  120×40
└─ Column                                         120×40
   ├─ Header ‹title: "agent"›                     120×1
   ├─ ListView ‹items: 214›                       120×37 ◆
   │  └─ … 19 MessageView
   └─ Box-[<'input'>]                             120×2  ⟳
      └─ TextField ‹focused, "проверь прокрутку"›   8×1

◆ repaint boundary, ⟳ needs layout''');
    });

    test('a run of fewer siblings of a name than fold is not folded', () {
      DiagnosticsNode list(int n) => node(
        'List',
        children: [
          node('Header'),
          for (var i = 0; i < n; i++) node('Item'),
          node('Footer'),
        ],
      );
      expect(list(4).toStringDeep(), '''
List
├─ Header
├─ Item
├─ Item
├─ Item
├─ Item
└─ Footer''');
      expect(list(5).toStringDeep(), '''
List
├─ Header
├─ … 5 Item
└─ Footer''');
      expect(list(3).toStringDeep(fold: 3), '''
List
├─ Header
├─ … 3 Item
└─ Footer''');
      expect(list(9).toStringDeep(fold: 0).split('\n'), hasLength(12));
    });

    test('the column follows the widest line that has a size or flags', () {
      expect(
        node(
          'Root',
          children: [
            node('A', size: (3, 1)),
            node('LongerName'),
            node('B', flags: const [DiagnosticsFlag.error]),
          ],
        ).toStringDeep(),
        '''
Root
├─ A 3×1
├─ LongerName
└─ B     ✗

✗ error''',
      );
    });

    test('wide glyphs count two columns', () {
      expect(
        node(
          'Root',
          size: (4, 1),
          children: [
            node(
              'Text',
              properties: const [DiagnosticsProperty(null, '"日本"')],
              size: (4, 1),
            ),
          ],
        ).toStringDeep(),
        '''
Root             4×1
└─ Text ‹"日本"› 4×1''',
      );
    });
  });

  test('toString is the name, the key and the properties', () {
    final box = node(
      'Box',
      key: "[<'a'>]",
      properties: const [
        DiagnosticsProperty('padding', '0 1'),
        DiagnosticsProperty(null, 'sticky'),
      ],
    );
    expect('$box', "Box-[<'a'>] ‹padding: 0 1, sticky›");
    expect('${node('Box')}', 'Box');
  });

  test('toJson', () {
    expect(
      node(
        'List',
        key: '[<1>]',
        properties: const [
          DiagnosticsProperty('items', '2'),
          DiagnosticsProperty(null, 'sticky'),
        ],
        size: (10, 2),
        flags: const [DiagnosticsFlag.repaintBoundary],
        children: [node('Item')],
      ).toJson(),
      {
        'name': 'List',
        'key': '[<1>]',
        'properties': [
          {'name': 'items', 'value': '2'},
          {'value': 'sticky'},
        ],
        'size': {'width': 10, 'height': 2},
        'flags': ['repaintBoundary'],
        'children': [
          {
            'name': 'Item',
            'properties': <Object>[],
            'flags': <Object>[],
            'children': <Object>[],
          },
        ],
      },
    );
  });

  group('values', () {
    test('describeText quotes, escapes and cuts off after max columns', () {
      expect(describeText('agent'), '"agent"');
      expect(describeText(r'a "b" c\d'), r'"a \"b\" c\\d"');
      expect(
        describeText('one\r\ntwo\tthree\x1b'),
        r'"one\r\ntwo\tthree\u{1b}"',
      );
      expect(describeText('abcdefgh', max: 8), '"abcdefgh"');
      expect(describeText('abcdefghi', max: 8), '"abcdefg…"');
      // a wide glyph that doesn't fit before the ellipsis is left out
      expect(describeText('abcdef日本', max: 8), '"abcdef…"');
      expect(describeText('日本語の文', max: 8), '"日本語…"');
    });

    test('describePen in a few words', () {
      expect(describePen(const Pen()), 'plain');
      expect(
        describePen(const Pen(attrs: Attr.bold, fg: Color.red, bg: Color.blue)),
        'bold red on blue',
      );
      expect(
        describePen(
          const Pen(
            attrs: Attr.italic | Attr.curlyUnderline | Attr.strike,
            fg: Color.rgb(0x1e, 0x90, 0xff),
            bg: Color.indexed(236),
            bgAlpha: 128,
            underlineColor: Color.indexed(9),
            link: 'https://example.com',
          ),
        ),
        'italic curly-underline strike #1e90ff on color236/50% '
        'ul:brightRed link',
      );
      expect(
        describePen(const Pen(fg: Color.defaultColor, bg: Color.defaultColor)),
        'default on default',
      );
    });

    test('describeValue', () {
      expect(describeValue('x'), '"x"');
      expect(describeValue(TextWrap.none), 'none');
      expect(describeValue(const Pen(attrs: Attr.dim)), 'dim');
      expect(describeValue(3), '3');
      expect(describeValue(null), 'null');
    });

    test('constraints, insets and alignments', () {
      expect(describeConstraints(const BoxConstraints.tight(80, 24)), '80×24');
      expect(describeConstraints(const BoxConstraints(0, 80, 1, 1)), '0..80×1');
      expect(describeConstraints(const BoxConstraints.tightFor()), '0..∞×0..∞');
      expect(describeInsets(const EdgeInsets.all(1)), '1');
      expect(describeInsets(const EdgeInsets.x(1)), '0 1');
      expect(
        describeInsets(const EdgeInsets.only(top: 1, left: 2, right: 2)),
        '1 2 0',
      );
      expect(
        describeInsets(const EdgeInsets.only(top: 1, right: 2, left: 3)),
        '1 2 0 3',
      );
      expect(describeAlignment(Alignment.center), 'center');
      expect(describeAlignment(Alignment.bottomLeft), 'bottomLeft');
      expect(describeAlignment(Alignment.topRight), 'topRight');
    });
  });

  group('describe', () {
    test('a laid out tree: properties, sizes and boundaries', () {
      final view = View(30, 8);
      final pen = view.pen;
      final log = RenderLog(pen: pen, itemPen: (_, _) => pen)
        ..add('one')
        ..add('two');
      view.owner.root = RenderColumn([
        (RenderText('agent', pen), 1),
        (
          RenderDecoratedBox(
            border: const BoxBorder.all(type: BorderType.rounded),
            titles: const [BoxTitle('Files')],
            padding: const EdgeInsets.x(1),
            child: RenderPositionedBox(
              child: RenderParagraph([
                ('Hello, world', const Pen(attrs: Attr.bold, fg: Color.red)),
              ], maxLines: 2),
            ),
          ),
          null,
        ),
        (log, 3),
      ]);
      view.frame();
      expect(view.owner.root.describe().toStringDeep(), '''
RenderColumn ‹vertical, crossAxisAlignment: stretch, constraints: tight›                                        30×8 ◇
├─ RenderText ‹"agent", pen: $pen, extent: 1, constraints: tight›                                                  30×1 ◇
├─ RenderDecoratedBox ‹border: rounded, title: "Files", padding: 0 1, flex: 1, offset: 0,1, constraints: tight› 30×4 ◇
│  └─ RenderPositionedBox ‹alignment: center, offset: 2,1, constraints: tight›                                  26×2 ◇
│     └─ RenderParagraph ‹"Hello, world", pen: bold red, maxLines: 2, offset: 7,0, constraints: 0..26×0..2›     12×1
└─ RenderLog ‹lines: 2, sticky, pen: $pen, extent: 3, offset: 0,5, constraints: tight›                             30×3 ◆ ◇

◆ repaint boundary, ◇ relayout boundary''');
    });

    test('needs layout and needs paint until a frame', () {
      final view = View(10, 2);
      final probe = Probe();
      final root = RenderBox(pen: view.pen, child: probe);
      expect(root.describe().toStringDeep(), '''
RenderBox ‹pen: ${view.pen}› ⟳
└─ Probe ‹probe›   ⟳

⟳ needs layout''');
      view.owner.root = root;
      expect(root.describe().flags, [
        DiagnosticsFlag.needsLayout,
        DiagnosticsFlag.needsPaint,
      ]);
      view.frame();
      expect(root.describe().flags, [DiagnosticsFlag.relayoutBoundary]);
      probe.markNeedsPaint();
      expect(root.describe().flags, [
        DiagnosticsFlag.relayoutBoundary,
        DiagnosticsFlag.needsPaint,
      ]);
      probe.markNeedsLayout();
      expect(probe.describe().flags, [
        DiagnosticsFlag.relayoutBoundary,
        DiagnosticsFlag.needsLayout,
      ]);
    });

    test('a flex says what overflows it', () {
      final view = View(10, 4);
      view.owner.root = RenderColumn([
        (Probe(), 3),
        (Probe(), 3),
      ]);
      view.frame();
      final root = view.owner.root.describe();
      expect('$root', contains('overflow: 2 rows'));
      expect(root.flags, contains(DiagnosticsFlag.overflow));
      final row = RenderFlex(gap: 1, children: [Probe(), Probe()]);
      view.owner.root = RenderRow([(row, 5)]);
      row.visitChildren(
        (c) => (c.parentData as FlexParentData)
          ..flex = 1
          ..fit = FlexFit.loose,
      );
      view.frame();
      expect(
        '${row.describe()}',
        'RenderFlex ‹horizontal, gap: 1, extent: 5, constraints: tight›',
      );
      expect(
        '${row.describe().children.first}',
        'Probe ‹probe, flex: 1, fit: loose, constraints: 0..2×0..4›',
      );
    });

    test('properties of each kind of render object', () {
      final view = View(20, 6);
      final stack = RenderStack(
        alignment: Alignment.bottomRight,
        fit: StackFit.expand,
        children: [
          RenderPadding(padding: const EdgeInsets.all(1)),
          RenderConstrainedBox(
            additionalConstraints: const BoxConstraints.tightFor(width: 4),
          ),
          RenderDivider(
            direction: Axis.vertical,
            type: BorderType.double,
            pen: const Pen(fg: Color.green),
          ),
          RenderParagraph(
            [('a', const Pen()), ('b', const Pen(attrs: Attr.bold))],
            wrap: TextWrap.none,
            overflow: TextOverflow.ellipsis,
            align: TextAlign.right,
          ),
          RenderDecoratedBox(
            background: const Pen(bg: Color.blue),
            border: const BoxBorder(
              top: Pen(fg: Color.red),
              bottom: Pen(fg: Color.red),
            ),
            titles: const [BoxTitle('a'), BoxTitle('b')],
          ),
          RenderPositionedBox(widthFactor: 2),
        ],
      );
      final positioned = RenderBox(pen: view.pen, padX: 1);
      stack.add(positioned);
      (positioned.parentData as StackParentData)
        ..left = 1
        ..bottom = 0
        ..width = 3;
      view.owner.root = stack;
      view.frame();
      final children = [for (final c in stack.describe().children) '$c'];
      expect(children, hasLength(7));
      expect(children[0], 'RenderPadding ‹padding: 1, constraints: tight›');
      expect(
        children[1],
        'RenderConstrainedBox ‹additionalConstraints: 4×0..∞, constraints: '
        'tight›',
      );
      expect(
        children[2],
        'RenderDivider ‹direction: vertical, type: double, pen: green, '
        'constraints: tight›',
      );
      expect(
        children[3],
        'RenderParagraph ‹"ab", spans: 2, wrap: none, overflow: ellipsis, '
        'align: right, constraints: tight›',
      );
      expect(
        children[4],
        'RenderDecoratedBox ‹background: on blue, border: single top bottom '
        'red, titles: "a" "b", constraints: tight›',
      );
      expect(
        children[5],
        'RenderPositionedBox ‹alignment: center, widthFactor: 2, constraints: '
        'tight›',
      );
      expect(
        children[6],
        'RenderBox ‹pen: ${view.pen}, padX: 1, left: 1, bottom: 0, width: 3, '
        'offset: 1,0, constraints: 3×0..6›',
      );
      expect(
        '${stack.describe()}',
        'RenderStack ‹alignment: bottomRight, fit: expand, '
            'constraints: tight›',
      );
    });

    test('properties of the boxes that size their child by the room it '
        'gets or by what it would like', () {
      final view = View(20, 6);
      final boxes = [
        RenderFractionallySizedBox(
          widthFactor: 0.5,
          alignment: Alignment.topLeft,
        ),
        RenderIntrinsicWidth(stepWidth: 2),
        RenderIntrinsicHeight(),
      ];
      view.owner.root = RenderColumn([for (final b in boxes) (b, 2)]);
      view.frame();
      final described = [for (final b in boxes) '${b.describe()}'];
      expect(
        described[0],
        'RenderFractionallySizedBox ‹alignment: topLeft, widthFactor: 0.5, '
        'extent: 2, constraints: tight›',
      );
      expect(
        described[1],
        'RenderIntrinsicWidth ‹stepWidth: 2, extent: 2, offset: 0,2, '
        'constraints: tight›',
      );
      expect(
        described[2],
        'RenderIntrinsicHeight ‹extent: 2, offset: 0,4, constraints: tight›',
      );
    });

    test('frames never describe anything', () {
      final view = View(10, 2);
      final probe = Probe();
      view.owner.root = RenderColumn([(probe, null)]);
      for (var i = 0; i < 3; i++) {
        probe.markNeedsLayout();
        view.frame();
      }
      expect(probe.described, 0);
      view.owner.root.describe();
      expect(probe.described, 1);
    });
  });
}
