// Docking in a DockArea: the layout's groups in splits, a tab bar over
// each; a tab dragged over a group showing its targets and docking on
// each, or floating its panel when released elsewhere; a window's title
// bar dragged onto a target docking its panel; the panels' state kept as
// they move; the layout saved to JSON and read back; what the controller
// does to the tree; dividers and windows setting the layout; panels the
// area has not; a drag whose release was lost.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Counts what [CounterState.bump] adds, shown as `n=<count>`; each state
/// made is added to [states].
final class Counter extends StatefulWidget {
  const Counter(this.states, {super.key});

  final List<CounterState> states;

  @override
  State<Counter> createState() => CounterState();
}

final class CounterState extends State<Counter> {
  var count = 0;

  @override
  void initState() {
    super.initState();
    widget.states.add(this);
  }

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('n=$count');
}

/// Panels `a` to `d`, titled `A` to `D`, each showing `<id> body`.
List<DockPanel> panels() => [
  for (final id in ['a', 'b', 'c', 'd'])
    DockPanel(id: id, title: id.toUpperCase(), child: Text('$id body')),
];

/// Groups `a`, `b` and `c` side by side.
DockLayout twoGroups() => DockLayout(
  root: DockSplit(Axis.horizontal, [
    DockTabs(['a', 'b']),
    DockTabs(['c']),
  ]),
);

/// Presses the left button at [x], [y], drags it to each of [to] and
/// releases it at the last, a frame after each.
Future<void> drag(TwkTester t, int x, int y, List<(int, int)> to) async {
  await t.mouse(MouseKind.down, x, y);
  await t.pump();
  for (final (dx, dy) in to) {
    await t.mouse(MouseKind.drag, dx, dy);
    await t.pump();
  }
  final (ux, uy) = to.isEmpty ? (x, y) : to.last;
  await t.mouse(MouseKind.up, ux, uy);
  await t.pump();
}

/// Presses the left button at [x], [y] and drags it to each of [to], a
/// frame after each, holding it.
Future<void> hold(TwkTester t, int x, int y, List<(int, int)> to) async {
  await t.mouse(MouseKind.down, x, y);
  await t.pump();
  for (final (dx, dy) in to) {
    await t.mouse(MouseKind.drag, dx, dy);
    await t.pump();
  }
}

/// Shows [panels] of [c] in an area of 40 × 12.
Future<void> show(TwkTester t, DockController c, [List<DockPanel>? of]) =>
    t.pumpWidget(
      Theme.terminal(
        child: DockArea(controller: c, panels: of ?? panels()),
      ),
      size: (40, 12),
    );

void main() {
  testTwk('the groups show in their splits, a tab bar over each and its '
      'selected panel under it; a tab clicked is selected in the layout', (
    t,
  ) async {
    final c = DockController(
      DockLayout(
        root: DockSplit(
          Axis.horizontal,
          [
            DockTabs(['a', 'b']),
            DockSplit(Axis.vertical, [
              DockTabs(['c']),
              DockTabs(['d']),
            ]),
          ],
          fractions: [1, 1],
        ),
      ),
    );
    addTearDown(c.dispose);
    await show(t, c);
    expect(t.lines, [
      ' A  B               │ C',
      'a body              │c body',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '                    ├───────────────────',
      '                    │ D',
      '                    │d body',
      '                    │',
      '                    │',
      '                    │',
    ]);
    await t.click(4, 0);
    await t.pump();
    expect(t, hasTextAt(0, 1, 'b body'));
    expect(
      (c.layout.root! as DockSplit).children.first,
      DockTabs(['a', 'b'], selected: 1),
    );
  });

  testTwk('a tab dragged over another group shows its targets in its '
      'middle, the one under the mouse marked and the cells the panel '
      'would take outlined; a chip with its title follows the mouse', (
    t,
  ) async {
    final c = DockController(twoGroups());
    addTearDown(c.dispose);
    await show(t, c);
    // over the group it is dragged from, which has another panel
    await hold(t, 1, 0, [(3, 2)]);
    expect(t.lines, [
      ' A  B               │ C',
      'a body              │c body',
      '                    │',
      '     A              │',
      '                    │',
      '          ▲         │',
      '       ◀  ■  ▶      │',
      '          ▼         │',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
    ]);
    expect(t, styleAt(5, 3, hasBg(const Color.indexed(237))));
    // over the target for the left side of the group of c
    await t.mouse(MouseKind.drag, 27, 6);
    await t.pump();
    expect(t.lines, [
      ' A  B               │╔ A ════╗',
      'a body              │║ body  ║',
      '                    │║       ║',
      '                    │║       ║',
      '                    │║       ║',
      '                    │║        ▲',
      '                    │║     ◀  ■  ▶',
      '                    │║        ▼',
      '                    │║       ║',
      '                    │║       ║',
      '                    │║       ║',
      '                    │╚═══════╝',
    ]);
    for (final x in [26, 27, 28]) {
      expect(t, styleAt(x, 6, hasBg(Color.blue)));
    }
    expect(t, styleAt(30, 6, hasFg(Color.blue)));
    expect(t, styleAt(30, 6, isNot(hasAttr(Attr.reverse))));
    await t.mouse(MouseKind.up, 27, 6);
    await t.pump();
  });

  group('a tab dropped on a target of another group docks its panel', () {
    // the targets of the group of c, from the middle of its cells
    final cases = {
      DockSide.left: (
        (27, 6),
        DockSplit(
          Axis.horizontal,
          [
            DockTabs(['b']),
            DockTabs(['a']),
            DockTabs(['c']),
          ],
          fractions: [0.5, 0.25, 0.25],
        ),
      ),
      DockSide.right: (
        (33, 6),
        DockSplit(
          Axis.horizontal,
          [
            DockTabs(['b']),
            DockTabs(['c']),
            DockTabs(['a']),
          ],
          fractions: [0.5, 0.25, 0.25],
        ),
      ),
      DockSide.top: (
        (30, 5),
        DockSplit(Axis.horizontal, [
          DockTabs(['b']),
          DockSplit(Axis.vertical, [
            DockTabs(['a']),
            DockTabs(['c']),
          ]),
        ]),
      ),
      DockSide.bottom: (
        (30, 7),
        DockSplit(Axis.horizontal, [
          DockTabs(['b']),
          DockSplit(Axis.vertical, [
            DockTabs(['c']),
            DockTabs(['a']),
          ]),
        ]),
      ),
      DockSide.center: (
        (30, 6),
        DockSplit(Axis.horizontal, [
          DockTabs(['b']),
          DockTabs(['c', 'a'], selected: 1),
        ]),
      ),
    };
    for (final MapEntry(key: side, value: ((x, y), root)) in cases.entries) {
      testTwk(side.name, (t) async {
        final c = DockController(twoGroups());
        addTearDown(c.dispose);
        await show(t, c);
        await drag(t, 1, 0, [(3, 2), (x, y)]);
        expect(c.layout, DockLayout(root: root));
        expect(t, containsLine(contains('a body')));
      });
    }
  });

  testTwk('a panel docked on a side of a group shares its cells; one among '
      'its tabs shows selected', (t) async {
    final c = DockController(twoGroups());
    addTearDown(c.dispose);
    await show(t, c);
    await drag(t, 1, 0, [(3, 2), (30, 7)]);
    expect(t.lines, [
      ' B                  │ C',
      'b body              │c body',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '                    ├───────────────────',
      '                    │ A',
      '                    │a body',
      '                    │',
      '                    │',
      '                    │',
    ]);
    await drag(t, 22, 0, [(20, 3), (9, 6)]);
    expect(t.lines, [
      ' B  C               │ A',
      'c body              │a body',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
    ]);
  });

  testTwk('a tab released over no target floats its panel in a window half '
      'the area, its title bar under the mouse; a lone panel shows no '
      'targets over its own group', (t) async {
    final c = DockController(twoGroups());
    addTearDown(c.dispose);
    await show(t, c);
    await drag(t, 1, 0, [(3, 2), (5, 9)]);
    expect(
      c.layout,
      DockLayout(
        root: DockSplit(Axis.horizontal, [
          DockTabs(['b']),
          DockTabs(['c']),
        ]),
        windows: [const DockWindow('a', left: 4, top: 9, width: 20, height: 6)],
      ),
    );
    // the layer moves it in from the bottom edge
    expect(t.lines, [
      ' B                  │ C',
      'b body              │c body',
      '                    │',
      '                    │',
      '                    │',
      '                    │',
      '    ┌ A ────────── _ □ ┐',
      '    │a body            │',
      '    │                  │',
      '    │                  │',
      '    │                  │',
      '    └──────────────────┘',
    ]);
    await hold(t, 22, 0, [(24, 2), (30, 3)]);
    expect(t.lines.take(6), [
      ' B                  │ C',
      'b body              │c body',
      '                    │',
      '                    │',
      '                    │           C',
      '                    │',
    ]);
    await t.mouse(MouseKind.up, 30, 3);
    await t.pump();
    expect(c.layout.windows.map((w) => w.panel), ['a', 'c']);
    expect(c.layout.root, DockTabs(['b']));
  });

  testTwk('a window dragged by its title bar shows the targets of the group '
      'under the mouse and docks on one; moved elsewhere or resized, it '
      'floats where it went, as big as it was made', (t) async {
    final c = DockController(
      DockLayout(
        root: DockTabs(['a']),
        windows: [const DockWindow('b', left: 2, top: 2, width: 16, height: 5)],
      ),
    );
    addTearDown(c.dispose);
    await show(t, c);
    expect(t.lines.take(4), [
      ' A',
      'a body',
      '  ┌ B ────── _ □ ┐',
      '  │b body        │',
    ]);
    await drag(t, 5, 2, [(6, 3), (9, 4)]);
    expect(c.layout.windows, [
      const DockWindow('b', left: 6, top: 4, width: 16, height: 5),
    ]);
    // resized by its bottom right corner, which shows no targets
    await hold(t, 21, 8, [(22, 9), (23, 9)]);
    expect(t, isNot(containsLine(contains('■'))));
    await t.mouse(MouseKind.up, 23, 9);
    await t.pump();
    expect(c.layout.windows, [
      const DockWindow('b', left: 6, top: 4, width: 18, height: 6),
    ]);
    // over the target for the right side of the group of a
    await hold(t, 9, 4, [(12, 5), (24, 6)]);
    expect(t.lines, [
      ' A                  ╔ B ═══════════════╗',
      'a body              ║                  ║',
      '                    ║                  ║',
      '                    ║                  ║',
      '                    ║                  ║',
      '                    ▲                  ║',
      '                 ◀  ■  ▶ ──────── _ □ ┐║',
      '                    ▼ b body          │║',
      '                    ║│                │║',
      '                    ║│                │║',
      '                    ║│                │║',
      '                    ╚══════════════════╝',
    ]);
    expect(t, styleAt(23, 6, hasBg(Color.blue)));
    expect(t, styleAt(17, 6, isNot(hasBg(Color.blue))));
    await t.mouse(MouseKind.up, 24, 6);
    await t.pump();
    expect(
      c.layout,
      DockLayout(
        root: DockSplit(Axis.horizontal, [
          DockTabs(['a']),
          DockTabs(['b']),
        ]),
      ),
    );
    expect(t, hasTextAt(20, 0, '│ B'));
  });

  testTwk('a panel keeps its state as it moves to another group, into a '
      'window and back, and while its tab is not selected', (t) async {
    final states = <CounterState>[];
    final c = DockController(twoGroups());
    addTearDown(c.dispose);
    await show(t, c, [
      DockPanel(id: 'a', title: 'A', child: Counter(states)),
      ...panels().skip(1),
    ]);
    states.single.bump();
    await t.pump();
    expect(t, hasTextAt(0, 1, 'n=1'));
    // dragged to the group of c
    await drag(t, 1, 0, [(3, 2), (30, 6)]);
    expect(t, hasTextAt(21, 1, 'n=1'));
    // floated while its tab is not selected
    await t.click(22, 0);
    await t.pump();
    expect(t, hasTextAt(21, 1, 'c body'));
    c.float('a', left: 2, top: 2, width: 16, height: 5);
    await t.pump();
    expect(t, hasTextAt(2, 3, '│n=1'));
    // its window dragged by the title bar onto the group of b
    await drag(t, 5, 2, [(6, 3), (10, 6)]);
    expect(c.layout.root, isA<DockSplit>());
    expect(c.layout.windows, isEmpty);
    expect(t, hasTextAt(0, 1, 'n=1'));
    // its tab dragged out into a window
    await drag(t, 4, 0, [(5, 2), (30, 1)]);
    expect(c.layout.windows.single.panel, 'a');
    expect(t, containsLine(contains('│n=1')));
    expect(states, hasLength(1));
  });

  testTwk('the layout saves to JSON and reads back as it was; an area shows '
      'the layout read back as it showed the one saved', (t) async {
    final layout = DockLayout(
      root: DockSplit(
        Axis.horizontal,
        [
          DockTabs(['a', 'b'], selected: 1),
          DockSplit(
            Axis.vertical,
            [
              DockTabs(['c']),
              DockTabs(['d']),
            ],
            fractions: [1, 2],
          ),
        ],
        fractions: [2, 1],
      ),
      windows: [const DockWindow('e', left: 3, top: 4, width: 20, height: 6)],
    );
    final json = jsonEncode(layout.toJson());
    expect(
      json,
      '{"root":{"split":"horizontal","fractions":[0.6666666666666666,'
      '0.3333333333333333],"children":[{"tabs":["a","b"],"selected":1},'
      '{"split":"vertical","fractions":[0.3333333333333333,'
      '0.6666666666666666],"children":[{"tabs":["c"],"selected":0},'
      '{"tabs":["d"],"selected":0}]}]},"windows":[{"panel":"e","left":3,'
      '"top":4,"width":20,"height":6}]}',
    );
    final read = DockLayout.fromJson(
      jsonDecode(json) as Map<String, Object?>,
    );
    expect(read, layout);
    expect(DockLayout.fromJson(read.toJson()), layout);
    final all = [
      ...panels(),
      const DockPanel(id: 'e', title: 'E', child: Text('e body')),
    ];
    final saved = DockController(layout);
    final restored = DockController(read);
    addTearDown(saved.dispose);
    addTearDown(restored.dispose);
    await show(t, saved, all);
    final lines = t.lines;
    await t.pumpWidget(
      Theme.terminal(
        child: DockArea(key: UniqueKey(), controller: restored, panels: all),
      ),
    );
    expect(t.lines, lines);
  });

  test('JSON that is not a layout is a FormatException', () {
    for (final json in <Map<String, Object?>>[
      {},
      {'root': null},
      {'root': 'a', 'windows': <Object?>[]},
      {
        'root': {'tabs': <Object?>[], 'selected': 0},
        'windows': <Object?>[],
      },
      {
        'root': {
          'tabs': ['a'],
          'selected': 1,
        },
        'windows': <Object?>[],
      },
      {
        'root': {
          'tabs': [1],
          'selected': 0,
        },
        'windows': <Object?>[],
      },
      {
        'root': {
          'split': 'diagonal',
          'fractions': [1, 1],
          'children': [
            {
              'tabs': ['a'],
              'selected': 0,
            },
            {
              'tabs': ['b'],
              'selected': 0,
            },
          ],
        },
        'windows': <Object?>[],
      },
      {
        'root': {
          'split': 'vertical',
          'fractions': [1],
          'children': [
            {
              'tabs': ['a'],
              'selected': 0,
            },
          ],
        },
        'windows': <Object?>[],
      },
      {
        'root': {
          'tabs': ['a'],
          'selected': 0,
        },
        'windows': [
          {'panel': 'a', 'left': 0, 'top': 0, 'width': 4, 'height': 4},
        ],
      },
      {
        'root': null,
        'windows': [
          {'panel': 'a', 'left': 0, 'top': 0, 'width': -1, 'height': 4},
        ],
      },
    ]) {
      expect(
        () => DockLayout.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });

  group('the controller', () {
    test('docks a panel on a side of all of the panels, as the first '
        "group's last tab, and as the only group of a layout with none", () {
      final c = DockController()..dock('a');
      expect(c.layout.root, DockTabs(['a']));
      c
        ..dock('b', side: DockSide.left)
        ..dock('c', side: DockSide.right)
        ..dock('d', side: DockSide.top);
      expect(
        c.layout.root,
        DockSplit(Axis.vertical, [
          DockTabs(['d']),
          DockSplit(
            Axis.horizontal,
            [
              DockTabs(['b']),
              DockTabs(['a']),
              DockTabs(['c']),
            ],
            fractions: [1, 1, 1],
          ),
        ]),
      );
      c.dock('e');
      expect(
        (c.layout.root! as DockSplit).children.first,
        DockTabs(['d', 'e'], selected: 1),
      );
      // below the group it is in
      c.dock('e', beside: 'd', side: DockSide.bottom);
      expect(
        c.layout.root,
        DockSplit(
          Axis.vertical,
          [
            DockTabs(['d']),
            DockTabs(['e']),
            DockSplit(Axis.horizontal, [
              DockTabs(['b']),
              DockTabs(['a']),
              DockTabs(['c']),
            ]),
          ],
          fractions: [0.25, 0.25, 0.5],
        ),
      );
      c.dispose();
    });

    test('takes a panel out of where it was: its group without it, the tab '
        'after it selected; a group left with none gone, a split left with '
        'one child that child, a split in one along the same axis among its '
        'children', () {
      final c = DockController(
        DockLayout(
          root: DockSplit(
            Axis.horizontal,
            [
              DockTabs(['a', 'b', 'c'], selected: 1),
              DockSplit(
                Axis.vertical,
                [
                  DockTabs(['d']),
                  DockSplit(Axis.horizontal, [
                    DockTabs(['e']),
                    DockTabs(['f']),
                  ]),
                ],
                fractions: [1, 3],
              ),
            ],
            fractions: [1, 1],
          ),
          windows: [const DockWindow('g')],
        ),
      )..remove('b');
      final root = c.layout.root! as DockSplit;
      expect(root.children.first, DockTabs(['a', 'c'], selected: 1));
      c.remove('c');
      expect((c.layout.root! as DockSplit).children.first, DockTabs(['a']));
      c.remove('d');
      expect(
        c.layout.root,
        DockSplit(
          Axis.horizontal,
          [
            DockTabs(['a']),
            DockTabs(['e']),
            DockTabs(['f']),
          ],
          fractions: [0.5, 0.25, 0.25],
        ),
      );
      c
        ..remove('e')
        ..remove('f')
        ..remove('g');
      expect(c.layout, DockLayout(root: DockTabs(['a'])));
      c
        ..remove('a')
        ..remove('nothing');
      expect(c.layout, DockLayout());
      c.dispose();
    });

    test('floats a panel in front, selects a tab, docks one among the tabs '
        'of its own group by selecting it; tells its listeners of each '
        'change and of none else', () {
      final c = DockController(
        DockLayout(
          root: DockTabs(['a', 'b']),
          windows: [const DockWindow('c')],
        ),
      );
      var told = 0;
      c
        ..addListener(() => told++)
        ..float('a', left: 1, top: 2, width: 30, height: 8);
      expect(
        c.layout,
        DockLayout(
          root: DockTabs(['b']),
          windows: [
            const DockWindow('c'),
            const DockWindow('a', left: 1, top: 2, width: 30, height: 8),
          ],
        ),
      );
      c
        ..dock('a', beside: 'b')
        ..select('b');
      expect(c.layout.root, DockTabs(['b', 'a']));
      c
        ..dock('a', beside: 'b')
        ..select('c')
        ..layout = DockLayout(
          root: DockTabs(['b', 'a'], selected: 1),
          windows: [const DockWindow('c')],
        );
      expect(c.layout.root, DockTabs(['b', 'a'], selected: 1));
      expect(told, 4);
      expect(() => c.dock('a', beside: 'a'), throwsArgumentError);
      expect(() => c.dock('a', beside: 'c'), throwsArgumentError);
      expect(() => c.dock('a', beside: 'z'), throwsArgumentError);
      c.dispose();
    });

    test('a layout is made of groups of one panel or more, splits of two '
        'children or more with shares for each, and no panel twice', () {
      expect(
        () => DockTabs([]),
        throwsA(
          isA<ArgumentError>().having((e) => e.message, 'message', 'no panel'),
        ),
      );
      expect(() => DockTabs(['a'], selected: 1), throwsRangeError);
      expect(
        () => DockSplit(Axis.vertical, [
          DockTabs(['a']),
        ]),
        throwsArgumentError,
      );
      for (final fractions in [
        [1.0],
        [-1.0, 2.0],
        [double.nan, 1.0],
        [0.0, 0.0],
      ]) {
        expect(
          () => DockSplit(Axis.vertical, [
            DockTabs(['a']),
            DockTabs(['b']),
          ], fractions: fractions),
          throwsArgumentError,
        );
      }
      expect(
        DockSplit(
          Axis.vertical,
          [
            DockTabs(['a']),
            DockTabs(['b']),
          ],
          fractions: [1, 3],
        ).fractions,
        [0.25, 0.75],
      );
      expect(
        () => DockLayout(
          root: DockTabs(['a']),
          windows: [const DockWindow('a')],
        ),
        throwsArgumentError,
      );
    });

    // the window made at run time, not one constant for both layouts
    DockLayout saved({int left = 2}) => DockLayout(
      root: DockSplit(
        Axis.horizontal,
        [
          DockTabs(['a', 'b'], selected: 1),
          DockTabs(['c']),
        ],
        fractions: [1, 3],
      ),
      windows: [DockWindow('d', left: left, top: 1, width: 30, height: 8)],
    );

    test('equal layouts, made apart, are equal and hash alike', () {
      expect(saved(), saved());
      expect(saved().hashCode, saved().hashCode);
      expect(
        saved(),
        isNot(DockLayout(root: saved().root, windows: [const DockWindow('d')])),
      );
    });

    test('a layout prints as its tree and its windows', () {
      expect(
        '${saved()}',
        'DockLayout(DockSplit(horizontal, '
            '[DockTabs([a, b], selected: 1), DockTabs([c], selected: 0)], '
            '[0.25, 0.75]), [DockWindow(d, 2, 1, 30 × 8)])',
      );
    });
  });

  testTwk('a divider dragged sets the shares of its split in the layout, '
      'and shares set in the layout move it', (t) async {
    final c = DockController(twoGroups());
    addTearDown(c.dispose);
    await show(t, c);
    await drag(t, 20, 5, [(25, 5)]);
    expect(
      (c.layout.root! as DockSplit).fractions,
      [25 / 39, 14 / 39],
    );
    expect(t, hasTextAt(25, 0, '│ C'));
    c.layout = DockLayout(
      root: DockSplit(
        Axis.horizontal,
        [
          DockTabs(['a', 'b']),
          DockTabs(['c']),
        ],
        fractions: [1, 3],
      ),
    );
    await t.pump();
    expect(t, hasTextAt(9, 0, ' │ C'));
  });

  testTwk('the panels of the layout that the area has not are taken out of '
      'it; one the layout has not is not shown until docked', (t) async {
    final c = DockController(twoGroups());
    addTearDown(c.dispose);
    await show(t, c, panels().where((p) => p.id != 'a').toList());
    expect(c.layout.root, isA<DockSplit>());
    expect(
      c.layout,
      DockLayout(
        root: DockSplit(Axis.horizontal, [
          DockTabs(['b']),
          DockTabs(['c']),
        ]),
      ),
    );
    expect(t, isNot(containsLine(contains('d body'))));
    c.dock('d', beside: 'c', side: DockSide.bottom);
    await t.pump();
    expect(t, containsLine(contains('│d body')));
    c.layout = DockLayout(root: DockTabs(['a', 'b']));
    await t.pump();
    expect(c.layout, DockLayout(root: DockTabs(['b'])));
  });

  testTwk('a drag whose release was lost docks and floats nothing', (
    t,
  ) async {
    final c = DockController(twoGroups());
    addTearDown(c.dispose);
    await show(t, c);
    final before = c.layout;
    await hold(t, 1, 0, [(3, 2), (30, 6)]);
    expect(t, containsLine(contains('■')));
    // the next press comes with no release before it
    await t.mouse(MouseKind.down, 10, 10);
    await t.pump();
    await t.mouse(MouseKind.up, 10, 10);
    await t.pump();
    expect(t, isNot(containsLine(contains('■'))));
    expect(c.layout, before);
  });

  testTwk('over an area with no group docked, a window dragged shows the '
      'middle target alone, and docks there', (t) async {
    final c = DockController(
      DockLayout(windows: [const DockWindow('a', width: 14, height: 4)]),
    );
    addTearDown(c.dispose);
    await show(t, c);
    await hold(t, 3, 0, [(4, 1), (20, 6)]);
    expect(t, containsLine(contains(' ■ ')));
    expect(t, isNot(containsLine(contains('◀'))));
    await t.mouse(MouseKind.up, 20, 6);
    await t.pump();
    expect(c.layout, DockLayout(root: DockTabs(['a'])));
  });

  testTwk('under an RGB theme the tabs are on a strip and the windows '
      'raised, without a shadow; tabStrip and windowFrame give a plain tab '
      'bar and a bordered window', (t) async {
    const dark = ThemeData.dark;
    final c = DockController(
      DockLayout(
        root: DockTabs(['a', 'b']),
        windows: [const DockWindow('c', left: 4, top: 4, width: 20, height: 5)],
      ),
    );
    addTearDown(c.dispose);
    Widget area({bool tabStrip = true, WindowFrame? windowFrame}) => Theme(
      data: dark,
      child: DockArea(
        controller: c,
        panels: panels(),
        tabStrip: tabStrip,
        windowFrame: windowFrame,
      ),
    );
    await t.pumpWidget(Theme.terminal(child: area()), size: (40, 12));
    final surface = dark.surface.bg!;
    final background = dark.background.bg!;
    expect(t, hasTextAt(0, 0, ' A  B '));
    expect(t, styleAt(1, 0, allOf(hasFg(dark.primary.fg!), hasBg(background))));
    expect(t, styleAt(4, 0, hasBg(surface)));
    expect(t, styleAt(30, 0, hasBg(surface)));
    // the window: no outline, its title bar raised, no shadow beside it
    expect(t, hasTextAt(4, 4, '  C            ─ □'));
    expect(t, styleAt(4, 4, hasBg(const Color.rgb(50, 53, 59))));
    expect(t, styleAt(4, 6, hasBg(surface)));
    final shade = dark.shade.bg!;
    for (final (x, y) in [(24, 6), (25, 6), (10, 9), (24, 9)]) {
      expect(t, styleAt(x, y, isNot(anyOf(hasBg(surface), hasBg(shade)))));
    }
    await t.pumpWidget(
      Theme.terminal(
        child: area(tabStrip: false, windowFrame: WindowFrame.bordered),
      ),
    );
    expect(t, styleAt(30, 0, isNot(hasBg(surface))));
    expect(t, styleAt(4, 0, isNot(hasBg(surface))));
    expect(t, hasTextAt(4, 4, '┌ C ────────── _ □ ┐'));
  });
}
