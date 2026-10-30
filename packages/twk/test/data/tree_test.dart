// A TreeView in an app: the nodes expanded showing their children below
// them, joined by guides (ASCII where box drawing is two columns wide) or
// not, with their expanders; children in a future loaded with a spinner
// row, kept by key until reloaded, a failed load shown and asked again;
// the keys moving the selection, expanding and collapsing (arrows, +, -,
// *), only with the focus, those that do nothing going on; the mouse
// selecting and expanding; the expansion and the labels' State kept by key
// across a new tree; and of a hundred thousand nodes only those in view
// built.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

/// A node of the trees of the tests: its name, its key, and its children.
final class N {
  const N(this.name, [this.children = const []]);

  final String name;
  final List<N> children;
}

const files = [
  N('src', [
    N('data', [N('table.dart'), N('tree.dart')]),
    N('widgets', [N('button.dart')]),
  ]),
  N('test', [N('tree_test.dart')]),
  N('readme.md'),
];

/// A [TreeView] of [roots], keyed by name, labelled with it.
TreeView<N> tree(
  List<N> roots, {
  TreeController? controller,
  FutureOr<List<N>> Function(N node)? children,
  bool Function(N node)? hasChildren,
  Widget Function(BuildContext context, TreeEntry<N> entry)? label,
  void Function(N node)? onActivated,
  bool showGuides = true,
  bool autofocus = false,
  bool? canRequestFocus,
  FocusNode? focusNode,
  Style? selectedStyle,
  Style? unfocusedSelectedStyle,
}) => TreeView<N>(
  roots: roots,
  children: children ?? (n) => n.children,
  hasChildren: hasChildren,
  nodeKey: (n) => n.name,
  label: label ?? (context, entry) => Text(entry.node.name),
  controller: controller,
  onActivated: onActivated,
  showGuides: showGuides,
  autofocus: autofocus,
  canRequestFocus: canRequestFocus,
  focusNode: focusNode,
  selectedStyle: selectedStyle,
  unfocusedSelectedStyle: unfocusedSelectedStyle,
);

const red = Color.rgb(255, 0, 0);

/// The rows of the screen, a frame of a spinner in them as `@`.
List<String> spun(TwkTester t) => [
  for (final line in t.lines)
    SpinnerFrames.dots.frames.fold(line, (l, f) => l.replaceAll(f, '@')),
];

/// The rows of the screen whose first cell is on [bg].
List<String> rowsOn(TwkTester t, Color bg) => [
  for (var y = 0; y < t.vt.height; y++)
    if (hasBg(bg).matches(t.cell(0, y), {})) t.lines[y],
];

/// Shows the label its State was made with; logs `+<label>` when its
/// State is made and `-<label>` when it is disposed.
final class Tally extends StatefulWidget {
  const Tally(this.label, this.log, {super.key});

  final String label;
  final List<String> log;

  @override
  State<Tally> createState() => _TallyState();
}

final class _TallyState extends State<Tally> {
  late final String _made = widget.label;

  @override
  void initState() {
    super.initState();
    widget.log.add('+${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('-${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_made);
}

void main() {
  group('TreeController', () {
    test('toggle expands a node collapsed and collapses one expanded, '
        'notifying each time', () {
      var notified = 0;
      final c = TreeController()
        ..addListener(() => notified++)
        ..toggle('a');
      expect((c.isExpanded('a'), notified), (true, 1));
      c.toggle('a');
      expect((c.isExpanded('a'), notified), (false, 2));
    });

    test('collapseAll collapses the nodes given, or every node, notifying '
        'only when one was expanded', () {
      var notified = 0;
      final c = TreeController(expanded: ['a', 'b', 'c'])
        ..addListener(() => notified++)
        ..collapseAll(['a', 'x']);
      expect(c.expanded, {'b', 'c'});
      expect(notified, 1);
      c.collapseAll(['x']);
      expect(notified, 1);
      c.collapseAll();
      expect(c.expanded, isEmpty);
      expect(notified, 2);
      c.collapseAll();
      expect(notified, 2);
    });
  });

  group('rows', () {
    testTwk('the children of a node expanded show below it, guides joining '
        'them to it, its expander open; a collapsed node shows none', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            files,
            controller: TreeController(expanded: ['src', 'data', 'widgets']),
          ),
        ),
        size: (24, 9),
      );
      expect(t.lines, [
        '▾ src',
        '├─▾ data',
        '│ ├── table.dart',
        '│ └── tree.dart',
        '└─▾ widgets',
        '  └── button.dart',
        '▸ test',
        '  readme.md',
        '',
      ]);
    });

    testTwk('without showGuides, the nodes are only indented', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            files,
            showGuides: false,
            controller: TreeController(expanded: ['src', 'data']),
          ),
        ),
        size: (24, 6),
      );
      expect(t.lines, [
        '▾ src',
        '  ▾ data',
        '      table.dart',
        '      tree.dart',
        '  ▸ widgets',
        '▸ test',
      ]);
    });

    test(
      'the guides are ASCII where box drawing is two columns wide',
      () async {
        final app = await WideApp.start(
          tree(files, controller: TreeController(expanded: ['src', 'data'])),
          width: 20,
          height: 4,
        );
        await app.quit();
        final vt = Vt(20, 4, segmenter: TextSegmenter(ambiguousWidth: 2));
        app.terminal.frames.forEach(vt.feed);
        expect(
          [
            for (var y = 0; y < 4; y++)
              [for (var x = 0; x < 20; x++) vt.cell(x, y).text]
                  .join()
                  .trimRight(),
          ],
          ['▾ src', '+-▾ data', '| +-- table.dart', '| +-- tree.dart'],
        );
      },
    );

    testTwk('a label is built from the entry of its node: its key, depth, '
        'whether it has children, is expanded and is selected', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            files,
            controller: TreeController(selectedKey: 'data', expanded: ['src']),
            label: (context, e) => Text(
              '${e.key} ${e.depth}'
              '${e.hasChildren ? ' has' : ''}'
              '${e.expanded ? ' open' : ''}'
              '${e.selected ? ' selected' : ''}',
            ),
          ),
        ),
        size: (30, 5),
      );
      expect(t.lines, [
        '▾ src 0 has open',
        '├─▸ data 1 has selected',
        '└─▸ widgets 1 has',
        '▸ test 0 has',
        '  readme.md 0',
      ]);
    });

    testTwk('the row of the node selected is in the selected style, its '
        'guides and label too', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            files,
            controller: TreeController(selectedKey: 'data', expanded: ['src']),
            selectedStyle: const Style(bg: red),
          ),
        ),
        size: (20, 5),
      );
      expect(rowsOn(t, red), ['├─▸ data']);
      expect(t.cell(19, 1), hasBg(red));
      expect(t.cell(5, 1), hasBg(red));
      // the theme's idle selection, the view not focused: the label's
      // text on it too
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            files,
            controller: TreeController(selectedKey: 'data', expanded: ['src']),
          ),
        ),
      );
      for (final x in [0, 2, 5, 19]) {
        expect(t.cell(x, 1), hasBg(const Color.indexed(235)));
      }
      expect(t.cell(5, 0), isNot(hasBg(const Color.indexed(235))));
    });

    testTwk("the row of the node selected is in the theme's selectionIdle "
        'while the view has not the focus, its selection while it has; '
        'unfocusedSelectedStyle in place of the first', (t) async {
      const theme = ThemeData.dark;
      final node = FocusNode();
      addTearDown(node.dispose);
      Widget view({Style? unfocused}) => Theme(
        data: theme,
        child: tree(
          files,
          controller: TreeController(selectedKey: 'data', expanded: ['src']),
          focusNode: node,
          unfocusedSelectedStyle: unfocused,
        ),
      );
      await t.pumpWidget(Theme.terminal(child: view()), size: (20, 5));
      final idle = theme.selectionIdle.bg!;
      expect(idle, isNot(theme.selection.bg));
      expect(rowsOn(t, idle), ['├─▸ data']);
      expect(t.cell(19, 1), hasBg(idle));
      node.requestFocus();
      await t.pump();
      expect(rowsOn(t, theme.selection.bg!), ['├─▸ data']);
      await t.pumpWidget(
        Theme.terminal(
          child: view(unfocused: const Style(bg: red)),
        ),
      );
      node.unfocus();
      await t.pump();
      expect(rowsOn(t, red), ['├─▸ data']);
    });
  });

  group('lazy children', () {
    testTwk('reload of a node asks again for its children alone, reload '
        'without one for those of every node', (t) async {
      final asked = <String>[];
      final controller = TreeController(expanded: ['a', 'b']);
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            const [N('a'), N('b')],
            controller: controller,
            hasChildren: (n) => n.name.length == 1,
            children: (n) {
              asked.add(n.name);
              return Future.value([N('${n.name}1')]);
            },
          ),
        ),
        size: (20, 4),
      );
      await t.pump();
      expect(t.lines, ['▾ a', '└── a1', '▾ b', '└── b1']);
      expect(asked, ['a', 'b']);
      controller.reload('b');
      await t.pump();
      await t.pump();
      expect(asked, ['a', 'b', 'b']);
      controller.reload();
      await t.pump();
      await t.pump();
      expect(asked, ['a', 'b', 'b', 'a', 'b']);
      expect(t.lines, ['▾ a', '└── a1', '▾ b', '└── b1']);
    });

    testTwk('children in a future show a spinner row below their node '
        'until it ends, which the keys pass over; they are kept until '
        'reloaded', (t) async {
      final asked = <String>[];
      final controller = TreeController(selectedKey: 'remote');
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            const [N('remote'), N('local')],
            controller: controller,
            autofocus: true,
            hasChildren: (n) => n.name == 'remote',
            children: (n) {
              asked.add(n.name);
              return Future.delayed(
                const Duration(seconds: 1),
                () => const [N('a'), N('b')],
              );
            },
          ),
        ),
        size: (20, 4),
      );
      expect(t.lines, ['▸ remote', '  local', '', '']);
      // nothing asked before it is expanded
      expect(asked, isEmpty);
      controller.expand('remote');
      await t.pump();
      expect(spun(t), ['▾ remote', '└─@', '  local', '']);
      final first = t.lines[1];
      await t.pump(const Duration(milliseconds: 500));
      expect(spun(t), ['▾ remote', '└─@', '  local', '']);
      expect(t.lines[1], isNot(first), reason: 'the spinner turns');
      await t.press('down');
      expect(controller.selectedKey, 'local');
      await t.press('up');
      expect(controller.selectedKey, 'remote');
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      expect(t.lines, ['▾ remote', '├── a', '└── b', '  local']);
      controller.collapse('remote');
      await t.pump();
      controller.expand('remote');
      await t.pump();
      expect(t.lines, ['▾ remote', '├── a', '└── b', '  local']);
      expect(asked, ['remote']);
      controller.reload('remote');
      await t.pump();
      expect(spun(t), ['▾ remote', '└─@', '  local', '']);
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(t.lines, ['▾ remote', '├── a', '└── b', '  local']);
      expect(asked, ['remote', 'remote']);
    });

    testTwk('a load that fails shows its error below the node; collapsed '
        'and expanded again, the node asks again', (t) async {
      var fail = true;
      final controller = TreeController(expanded: ['remote']);
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            const [N('remote')],
            controller: controller,
            hasChildren: (n) => n.name == 'remote',
            children: (n) async {
              await Future<void>.delayed(const Duration(seconds: 1));
              if (fail) {
                throw const FormatException('no access');
              }
              return const [N('a')];
            },
          ),
        ),
        size: (40, 3),
      );
      expect(spun(t), ['▾ remote', '└─@', '']);
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(t.lines, ['▾ remote', '└── FormatException: no access', '']);
      expect(t.cell(4, 1), hasFg(Color.red));
      fail = false;
      controller.collapse('remote');
      await t.pump();
      expect(t.lines, ['▸ remote', '', '']);
      controller.expand('remote');
      await t.pump();
      expect(spun(t), ['▾ remote', '└─@', '']);
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(t.lines, ['▾ remote', '└── a', '']);
    });

    testTwk('without hasChildren, the children of a node are asked for as '
        'it shows: a node with none shows no expander', (t) async {
      final asked = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            const [N('full'), N('empty')],
            children: (n) {
              asked.add(n.name);
              return Future.value(n.name == 'full' ? const [N('a')] : const []);
            },
          ),
        ),
        size: (20, 2),
      );
      expect(asked, ['full', 'empty']);
      await t.pump();
      expect(t.lines, ['▸ full', '  empty']);
    });

    testTwk('* expands the node selected and every node below it, those '
        'whose children come in a future as they come', (t) async {
      final controller = TreeController(selectedKey: 'r');
      const later = {
        'r': [N('a'), N('b')],
        'a': [N('a1')],
        'b': <N>[],
        'a1': <N>[],
      };
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            const [N('r')],
            controller: controller,
            autofocus: true,
            children: (n) => Future.delayed(
              const Duration(seconds: 1),
              () => later[n.name]!,
            ),
          ),
        ),
        size: (20, 5),
      );
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(t.lines, ['▸ r', '', '', '', '']);
      await t.press('*');
      await t.pump();
      expect(spun(t), ['▾ r', '├─▾ a', '│ └─@', '└─▾ b', '  └─@']);
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      // b has none; a's child is asked for in turn
      expect(spun(t), ['▾ r', '├─▾ a', '│ └─▾ a1', '│   └─@', '└── b']);
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(t.lines, ['▾ r', '├─▾ a', '│ └── a1', '└── b', '']);
    });
  });

  group('keys', () {
    testTwk('Up and Down select the node above and below, Right expands a '
        'node or selects its first child, Left collapses it or selects '
        'its parent, + and - expand and collapse it, * all below it, Home '
        'and End the first and the last; a key that does nothing goes on', (
      t,
    ) async {
      final controller = TreeController();
      final passed = <String>[];
      final activated = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              passed.add(KeyCombo.fromEvent(event).toString());
              return KeyEventResult.ignored;
            },
            child: tree(
              files,
              controller: controller,
              autofocus: true,
              onActivated: (n) => activated.add(n.name),
            ),
          ),
        ),
        size: (24, 9),
      );
      final steps = <String>[];
      for (final key in [
        'down',
        'right',
        'right',
        'right',
        'down',
        'down',
        'left',
        'left',
        'left',
        '-',
        '-',
        '+',
        '+',
        'end',
        'right',
        'left',
        'down',
        'home',
        'up',
        '*',
        'enter',
      ]) {
        await t.press(key);
        await t.pump();
        final open = [...controller.expanded]..sort();
        steps.add('$key: ${controller.selectedKey} ${open.join(',')}');
      }
      expect(steps, [
        'down: src ',
        'right: src src',
        'right: data src',
        'right: data data,src',
        'down: table.dart data,src',
        'down: tree.dart data,src',
        'left: data data,src',
        'left: data src',
        'left: src src',
        '-: src ',
        '-: src ',
        '+: src src',
        '+: src src',
        'end: readme.md src',
        'right: readme.md src',
        'left: readme.md src',
        'down: readme.md src',
        'home: src src',
        'up: src src',
        '*: src data,src,widgets',
        'enter: src data,src,widgets',
      ]);
      expect(passed, ['-', '+', 'right', 'left', 'down', 'up']);
      expect(activated, ['src']);
      expect(t.lines, [
        '▾ src',
        '├─▾ data',
        '│ ├── table.dart',
        '│ └── tree.dart',
        '└─▾ widgets',
        '  └── button.dart',
        '▸ test',
        '  readme.md',
        '',
      ]);
    });

    testTwk('Enter expands and collapses the node selected without '
        'onActivated', (t) async {
      final controller = TreeController(selectedKey: 'test');
      await t.pumpWidget(
        Theme.terminal(
          child: tree(files, controller: controller, autofocus: true),
        ),
        size: (24, 4),
      );
      await t.press('enter');
      expect(controller.expanded, {'test'});
      await t.press('enter');
      expect(controller.expanded, isEmpty);
    });

    testTwk('the keys do nothing while it does not have the focus, nor in '
        'one that takes none, where the keys start at it', (t) async {
      final controller = TreeController();
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Focus(autofocus: true, child: Text('other')),
              Expanded(child: tree(files, controller: controller)),
            ],
          ),
        ),
        size: (24, 5),
      );
      await t.press('down');
      await t.press('right');
      expect(controller.selectedKey, isNull);
      await t.pumpWidget(
        Theme.terminal(
          child: tree(files, controller: controller, canRequestFocus: false),
        ),
      );
      await t.press('down');
      await t.press('right');
      expect(controller.selectedKey, isNull);
      expect(controller.expanded, isEmpty);
    });

    testTwk('Page Up and Page Down select a window of rows away, the view '
        'scrolled the least that shows the node selected', (t) async {
      final controller = TreeController(expanded: ['r']);
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            [
              N('r', [for (var i = 0; i < 20; i++) N('n$i')]),
            ],
            controller: controller,
            autofocus: true,
            showGuides: false,
            selectedStyle: const Style(bg: red),
          ),
        ),
        size: (20, 5),
      );
      final shown = <String>[];
      for (final key in ['down', 'pagedown', 'pagedown', 'pageup', 'end']) {
        await t.press(key);
        await t.pump();
        shown.add(
          '${rowsOn(t, red).single.trim()}: '
          '${t.lines.first.trim()} to ${t.lines.last.trim()}',
        );
      }
      expect(shown, [
        '▾ r: ▾ r to n3',
        'n4: n0 to n4',
        'n9: n5 to n9',
        'n4: n4 to n8',
        'n19: n15 to n19',
      ]);
      // the controller selects one out of view
      controller.selectedKey = 'n2';
      await t.pump();
      expect(t.lines.first.trim(), 'n2');
    });

    testTwk('the view is mounted showing the node its controller selects, '
        'the least scrolled', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            [for (var i = 0; i < 21; i++) N('n$i')],
            controller: TreeController(selectedKey: 'n18'),
            selectedStyle: const Style(bg: red),
          ),
        ),
        size: (20, 6),
      );
      expect(t.lines.map((l) => l.trim()), [
        for (var i = 13; i < 19; i++) 'n$i',
      ]);
      expect(rowsOn(t, red).single.trim(), 'n18');
    });

    testTwk("the hidden cursor rests on the selected node's label as it "
        'moves and the view scrolls', (t) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            files,
            controller: TreeController(selectedKey: 'data', expanded: ['src']),
            focusNode: node,
          ),
        ),
        size: (20, 3),
      );
      node.requestFocus();
      await t.pump();
      expect(t.cursorVisible, isFalse);
      // after the guides and the expander
      expect(t.cursor, (4, 1));
      await t.press('down');
      await t.pump();
      expect(t.cursor, (4, 2));
      // scrolled: the last node is on the last row
      await t.press('end');
      await t.pump();
      expect(t.lines.last, '  readme.md');
      expect(t.cursor, (2, 2));
    });
  });

  group('mouse', () {
    testTwk('a click on an expander expands or collapses its node, one '
        'elsewhere selects the node and gives the view the focus', (
      t,
    ) async {
      final controller = TreeController();
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Focus(autofocus: true, child: Text('other')),
              Expanded(child: tree(files, controller: controller)),
            ],
          ),
        ),
        size: (24, 6),
      );
      // the expander of src
      await t.click(0, 1);
      await t.pump();
      expect(controller.expanded, {'src'});
      expect(controller.selectedKey, isNull);
      expect(t.lines.sublist(1), [
        '▾ src',
        '├─▸ data',
        '└─▸ widgets',
        '▸ test',
        '  readme.md',
      ]);
      // the expander of widgets, then its child
      await t.click(3, 3);
      await t.pump();
      await t.click(8, 4);
      await t.pump();
      expect(controller.selectedKey, 'button.dart');
      await t.press('up');
      expect(controller.selectedKey, 'widgets');
      await t.press('down');
      // a click collapses src: the node selected was below it
      await t.click(0, 1);
      await t.pump();
      expect(controller.selectedKey, 'src');
      expect(controller.expanded, {'widgets'});
      expect(t.lines.sublist(1), ['▸ src', '▸ test', '  readme.md', '', '']);
    });
  });

  group('keys of nodes', () {
    testTwk('a new tree keeps the nodes expanded and the labels State by '
        'key', (t) async {
      final log = <String>[];
      final controller = TreeController(expanded: ['src', 'data']);
      Widget view(List<N> roots) => tree(
        roots,
        controller: controller,
        label: (context, e) =>
            Tally(e.node.name, log, key: ValueKey(e.node.name)),
      );
      await t.pumpWidget(Theme.terminal(child: view(files)), size: (24, 8));
      expect(log, hasLength(7));
      log.clear();
      // src last, after a new root, with a new child of data
      await t.pumpWidget(
        Theme.terminal(
          child: view(const [
            N('new'),
            N('readme.md'),
            N('test', [N('tree_test.dart')]),
            N('src', [
              N('data', [N('added'), N('table.dart'), N('tree.dart')]),
              N('widgets', [N('button.dart')]),
            ]),
          ]),
        ),
      );
      expect(t.lines, [
        '  new',
        '  readme.md',
        '▸ test',
        '▾ src',
        '├─▾ data',
        '│ ├── added',
        '│ ├── table.dart',
        '│ └── tree.dart',
      ]);
      expect(log, ['+new', '+added']);
    });

    testTwk('of a hundred thousand nodes only those in view and a few rows '
        'past them are built', (t) async {
      var built = 0;
      final roots = [
        N('r', [for (var i = 0; i < 100000; i++) N('n$i')]),
      ];
      await t.pumpWidget(
        Theme.terminal(
          child: tree(
            roots,
            controller: TreeController(expanded: ['r']),
            autofocus: true,
            label: (context, e) {
              built++;
              return Text(e.node.name);
            },
          ),
        ),
        size: (20, 5),
      );
      expect(built, 8);
      expect(t.lines.first, '▾ r');
      built = 0;
      await t.press('end');
      await t.pump();
      expect(t.lines.last, '└── n99999');
      expect(built, lessThan(20));
    });
  });
}
