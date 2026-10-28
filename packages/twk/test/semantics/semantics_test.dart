// The semantics of a tree: a node's line of its role, label, value and
// state; the tree as lines, depth first; what SemanticsNode.of reads below
// a context (Semantics, the text of Texts, BlockSemantics,
// ExcludeSemantics, explicit nodes, what is off the stage left out) and
// which node the focus is on; the roles of the controls that have one.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [children] one below another at their left edge.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

/// The lines the app reads as now.
List<String> read(TwkTester t) => t.binding.semantics.lines;

void main() {
  group('a node', () {
    test("reads as its role's word, its label, its value and its state", () {
      const lines = [
        SemanticsNode(role: SemanticsRole.button, label: 'OK'),
        SemanticsNode(
          role: SemanticsRole.checkbox,
          label: 'Remember me',
          state: SemanticsState(checked: true),
        ),
        SemanticsNode(
          role: SemanticsRole.checkbox,
          label: 'Spam me',
          state: SemanticsState(checked: false, disabled: true),
        ),
        SemanticsNode(
          role: SemanticsRole.toggle,
          label: 'Wi-Fi',
          state: SemanticsState(checked: true),
        ),
        SemanticsNode(
          role: SemanticsRole.toggle,
          state: SemanticsState(checked: false),
        ),
        SemanticsNode(
          role: SemanticsRole.textBox,
          label: 'Name',
          value: 'anna',
        ),
        SemanticsNode(role: SemanticsRole.progressBar, value: '40%'),
        SemanticsNode(
          role: SemanticsRole.tab,
          label: 'Files',
          state: SemanticsState(selected: true),
        ),
        SemanticsNode(
          role: SemanticsRole.menuItem,
          label: 'Recent',
          state: SemanticsState(expanded: false),
        ),
        SemanticsNode(
          role: SemanticsRole.menuItem,
          label: 'Open',
          state: SemanticsState(expanded: true),
        ),
        SemanticsNode(label: 'just text'),
        SemanticsNode(value: '3 left'),
      ];
      expect(
        [for (final n in lines) n.line],
        [
          'button OK',
          'checkbox Remember me, checked',
          'checkbox Spam me, not checked, disabled',
          'switch Wi-Fi, on',
          'switch, off',
          'textbox Name: anna',
          'progressbar 40%',
          'tab Files, selected',
          'menuitem Recent, collapsed',
          'menuitem Open, expanded',
          'just text',
          '3 left',
        ],
      );
    });

    test('reads its hint last, after its state', () {
      expect(
        const SemanticsNode(
          role: SemanticsRole.button,
          label: 'Save',
          state: SemanticsState(disabled: true),
          hint: 'Writes the file',
        ).line,
        'button Save, disabled, Writes the file',
      );
      expect(
        const SemanticsNode(label: 'Help', hint: 'Opens help').line,
        'Help, Opens help',
      );
      // a hint alone has no line
      expect(const SemanticsNode(hint: 'Opens help').line, '');
    });

    test('has no line of its own with neither role, label nor value, nor '
        'with a role that holds nothing and nodes but neither label nor '
        'value; a container has one without a label', () {
      const item = SemanticsNode(role: SemanticsRole.button, label: 'OK');
      expect(const SemanticsNode(children: [item]).line, '');
      expect(
        const SemanticsNode(
          role: SemanticsRole.listItem,
          children: [item],
        ).line,
        '',
      );
      expect(
        const SemanticsNode(role: SemanticsRole.listItem).line,
        'listitem',
      );
      expect(
        const SemanticsNode(role: SemanticsRole.list, children: [item]).line,
        'list',
      );
      expect(
        const SemanticsNode(
          role: SemanticsRole.listItem,
          label: 'row',
          children: [item],
        ).line,
        'listitem row',
      );
    });
  });

  test('a tree reads as the lines of its nodes depth first, those of '
      'nodes without one left out, a text on several lines a line apiece; '
      "the focused line is the focused node's first", () {
    const tree = SemanticsNode(
      children: [
        SemanticsNode(
          role: SemanticsRole.dialog,
          label: 'Quit',
          children: [
            SemanticsNode(label: 'Unsaved work\nwill be lost'),
            SemanticsNode(
              children: [
                SemanticsNode(role: SemanticsRole.button, label: 'Yes'),
                SemanticsNode(
                  role: SemanticsRole.button,
                  label: 'No',
                  focused: true,
                ),
              ],
            ),
          ],
        ),
        SemanticsNode(label: 'after'),
      ],
    );
    expect(tree.lines, [
      'dialog Quit',
      'Unsaved work',
      'will be lost',
      'button Yes',
      'button No',
      'after',
    ]);
    expect(tree.focusedLine, 4);
    expect(const SemanticsNode(label: 'none').focusedLine, isNull);
  });

  test('states of equal fields are equal and hash alike', () {
    // made at run time, not the same constant
    final checked = SemanticsState(checked: [true].single);
    expect(checked, const SemanticsState(checked: true));
    expect(checked.hashCode, const SemanticsState(checked: true).hashCode);
    const others = [
      SemanticsState(checked: false),
      SemanticsState(selected: true),
      SemanticsState(expanded: true),
      SemanticsState(disabled: true),
      SemanticsState(),
    ];
    for (final (i, a) in others.indexed) {
      expect(a, isNot(checked), reason: '$i');
      for (final b in others.skip(i + 1)) {
        expect(a, isNot(b), reason: '$i');
      }
    }
    expect({
      checked,
      const SemanticsState(checked: true),
      ...others,
    }, hasLength(6));
  });

  testTwk('a Semantics is described by what it gives, an ExcludeSemantics '
      'by whether it excludes when it does not', (t) async {
    final semantics = GlobalKey();
    final excluded = GlobalKey();
    final included = GlobalKey();
    await t.pumpWidget(
      column([
        Semantics(
          key: semantics,
          role: SemanticsRole.toggle,
          label: 'Wi-Fi',
          state: const SemanticsState(checked: true),
          hint: 'Turns it on',
          nodes: const [SemanticsNode(label: 'on')],
          child: const Text('x'),
        ),
        ExcludeSemantics(key: included, child: const Text('z')),
        ExcludeSemantics(
          excluding: false,
          key: excluded,
          child: const Text('w'),
        ),
      ]),
    );
    String described(GlobalKey key) =>
        '${(key.currentContext! as Element).describe()}';
    expect(
      described(semantics),
      'Semantics-$semantics ‹role: "switch", label: "Wi-Fi", '
      'state: "on", hint: "Turns it on", nodes: 1›',
    );
    expect(described(included), 'ExcludeSemantics-$included');
    expect(
      described(excluded),
      'ExcludeSemantics-$excluded ‹excluding: false›',
    );
  });

  group('SemanticsNode.of', () {
    testTwk('reads the texts of the Texts in order, and a Semantics with '
        'the texts below it as its label, or its label in their place', (
      t,
    ) async {
      await t.pumpWidget(
        column([
          const Text('Settings  '),
          const Semantics(role: SemanticsRole.heading, child: Text('Look')),
          const Semantics(
            role: SemanticsRole.link,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('see '),
                Text.rich([Span('docs')]),
              ],
            ),
          ),
          const Semantics(
            role: SemanticsRole.status,
            label: 'saved',
            child: Text('✓'),
          ),
          const Text('   '),
        ]),
      );
      expect(read(t), [
        'Settings',
        'heading Look',
        'link see docs',
        'status saved',
      ]);
      final link = SemanticsNode.of(t.element(find.byType(Row)));
      expect(link.lines, ['see', 'docs']);
    });

    testTwk('reads the texts below a node that has nodes below it as nodes '
        'of their own, in their places', (t) async {
      await t.pumpWidget(
        Semantics(
          role: SemanticsRole.dialog,
          label: 'Quit',
          child: column([
            const Text('Unsaved work will be lost'),
            Button('Yes', onPressed: () {}),
            const Text('or'),
            Button('No', onPressed: () {}),
          ]),
        ),
      );
      expect(read(t), [
        'dialog Quit',
        'Unsaved work will be lost',
        'button Yes',
        'or',
        'button No',
      ]);
    });

    testTwk('leaves out what was read before a BlockSemantics in the node '
        'it is in, and what is not laid out: a page of a TabView not shown', (
      t,
    ) async {
      final tabs = TabController(length: 2);
      addTearDown(tabs.dispose);
      await t.pumpWidget(
        column([
          const Text('above'),
          Semantics(
            role: SemanticsRole.list,
            child: column([
              const Text('covered'),
              const BlockSemantics(child: Text('barrier')),
              const Text('over it'),
            ]),
          ),
          SizedBox(
            height: 1,
            child: TabView(
              controller: tabs,
              children: const [Text('first page'), Text('second page')],
            ),
          ),
        ]),
      );
      expect(read(t), ['above', 'list', 'barrier', 'over it', 'first page']);
      tabs.index = 1;
      await t.pump();
      expect(read(t), ['above', 'list', 'barrier', 'over it', 'second page']);
    });

    testTwk('leaves out what is below an ExcludeSemantics, its Semantics and '
        'its texts, a label of the texts too; reads it while not excluding, '
        'and a node focused there reads as the node above with a line', (
      t,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      Widget app({required bool excluding}) => Semantics(
        role: SemanticsRole.dialog,
        label: 'Find',
        child: column([
          const Text('above'),
          ExcludeSemantics(
            excluding: excluding,
            child: Semantics(
              role: SemanticsRole.button,
              child: Focus(focusNode: node, child: const Text('Go')),
            ),
          ),
          Semantics(
            role: SemanticsRole.button,
            child: Row(
              children: [
                const Text('OK'),
                ExcludeSemantics(
                  excluding: excluding,
                  child: const Text('(enter)'),
                ),
              ],
            ),
          ),
        ]),
      );
      await t.pumpWidget(app(excluding: true));
      node.requestFocus();
      await t.pump();
      final semantics = t.binding.semantics;
      expect(semantics.lines, ['dialog Find', 'above', 'button OK']);
      expect(semantics.focusedLine, 0, reason: 'the dialog');
      await t.pumpWidget(app(excluding: false));
      expect(read(t), [
        'dialog Find',
        'above',
        'button Go',
        'button OK (enter)',
      ]);
      expect(t.binding.semantics.focusedLine, 2);
    });

    testTwk('reads the nodes a Semantics gives in place of what is below it', (
      t,
    ) async {
      await t.pumpWidget(
        const Semantics(
          role: SemanticsRole.tabList,
          nodes: [
            SemanticsNode(role: SemanticsRole.tab, label: 'One'),
            SemanticsNode(
              role: SemanticsRole.tab,
              label: 'Two',
              state: SemanticsState(selected: true),
            ),
          ],
          child: Text('One  Two'),
        ),
      );
      expect(read(t), ['tablist', 'tab One', 'tab Two, selected']);
    });

    testTwk('focuses the nearest Semantics with a line above the primary '
        "focus's widget, or the first node below it when none is above", (
      t,
    ) async {
      final inner = FocusNode();
      final outer = FocusNode();
      addTearDown(inner.dispose);
      addTearDown(outer.dispose);
      await t.pumpWidget(
        column([
          const Text('title'),
          Semantics(
            role: SemanticsRole.listItem,
            label: 'row',
            child: Semantics(
              child: Focus(focusNode: inner, child: const SizedBox()),
            ),
          ),
          Focus(
            focusNode: outer,
            child: column([const Text('first'), const Text('second')]),
          ),
        ]),
      );
      SemanticsNode semantics() => t.binding.semantics;
      expect(semantics().focusedLine, isNull);
      inner.requestFocus();
      await t.pump();
      expect(semantics().lines, ['title', 'listitem row', 'first', 'second']);
      expect(semantics().focusedLine, 1);
      outer.requestFocus();
      await t.pump();
      expect(semantics().focusedLine, 2);
    });

    testTwk('focuses the node a Semantics gives that is focused while the '
        'Semantics is, and none of them elsewhere', (t) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      const nodes = [
        SemanticsNode(role: SemanticsRole.tab, label: 'One'),
        SemanticsNode(role: SemanticsRole.tab, label: 'Two', focused: true),
      ];
      await t.pumpWidget(
        column([
          Semantics(
            role: SemanticsRole.tabList,
            nodes: nodes,
            child: Focus(focusNode: node, child: const Text('bar')),
          ),
          Button('Go', onPressed: () {}, autofocus: true),
        ]),
      );
      expect(read(t), ['tablist', 'tab One', 'tab Two', 'button Go']);
      expect(t.binding.semantics.focusedLine, 3);
      node.requestFocus();
      await t.pump();
      expect(t.binding.semantics.focusedLine, 2);
    });
    testTwk('gives the hint of a Semantics with nothing else to the first '
        'node with a line below it, focused or not, or reads it after the '
        'texts it is the label of', (t) async {
      await t.pumpWidget(
        column([
          Semantics(
            hint: 'Writes the file',
            child: column([
              const Text('  '),
              Button('Save', onPressed: () {}, autofocus: true),
              const Text('then'),
            ]),
          ),
          const Semantics(hint: 'Opens help', child: Text('Help')),
          const Semantics(
            hint: 'outer',
            child: Semantics(
              role: SemanticsRole.link,
              hint: 'inner',
              child: Text('docs'),
            ),
          ),
          const Semantics(hint: 'of nothing', child: Text(' ')),
        ]),
      );
      expect(read(t), [
        'button Save, Writes the file',
        'then',
        'Help, Opens help',
        'link docs, inner, outer',
      ]);
      expect(t.binding.semantics.focusedLine, 0);
    });
  });

  group('the controls', () {
    testTwk('read as their roles, labels and states', (t) async {
      await t.pumpWidget(
        column([
          Button('OK', onPressed: () {}),
          const Button('Later', onPressed: null),
          Checkbox(value: true, onChanged: (_) {}, label: 'Remember me'),
          Checkbox(value: false, onChanged: (_) {}),
          const Switch(value: false, onChanged: null, label: 'Wi-Fi'),
          SizedBox(
            height: 3,
            child: ListView(
              children: [
                const Text('README.md'),
                Checkbox(value: true, onChanged: (_) {}, label: 'done'),
              ],
            ),
          ),
          SizedBox(
            height: 1,
            child: ListView(children: const [Text('alone')]),
          ),
        ]),
      );
      expect(read(t), [
        'button OK',
        'button Later, disabled',
        'checkbox Remember me, checked',
        'checkbox, not checked',
        'switch Wi-Fi, off, disabled',
        'list 2 items',
        'listitem README.md',
        'checkbox done, checked',
        'list 1 item',
        'listitem alone',
      ]);
    });

    testTwk('a radio group reads as its choices, the one that shows the '
        'focus focused; a link as its text, a slider as its value', (t) async {
      await t.pumpWidget(
        column([
          RadioGroup<int>(
            choices: const [
              Choice(1, 'one'),
              Choice(2, 'two'),
              Choice(3, 'three', enabled: false),
            ],
            value: 2,
            onChanged: (_) {},
            autofocus: true,
          ),
          const Link('https://dart.dev', text: 'Dart'),
          const Link('https://pub.dev'),
          SizedBox(
            width: 10,
            child: Slider(value: 0.25, onChanged: (_) {}),
          ),
          const SizedBox(
            width: 10,
            child: Slider(value: 7.2, max: 10, divisions: 10, onChanged: null),
          ),
        ]),
      );
      expect(read(t), [
        'radio one, not checked',
        'radio two, checked',
        'radio three, not checked, disabled',
        'link Dart',
        'link https://pub.dev',
        'slider 0.25',
        'slider 7, disabled',
      ]);
      expect(t.binding.semantics.focusedLine, 1);
      await t.press('tab');
      await t.pump();
      expect(t.binding.semantics.focusedLine, 5);
    });

    testTwk('a menu bar reads as its menus, the one open expanded, and the '
        'open menu as its entries, the highlighted one focused', (t) async {
      await t.pumpWidget(
        Overlay(
          child: MenuBar(
            menus: [
              Menu(
                '&File',
                items: [
                  MenuItem('&New', onSelected: () {}),
                  const MenuDivider(),
                  MenuItem('Word &wrap', checked: true, onSelected: () {}),
                  const MenuItem('&Print'),
                  Menu(
                    '&Recent',
                    items: [MenuItem('a.txt', onSelected: () {})],
                  ),
                ],
              ),
              const Menu('&Help', items: []),
            ],
            child: const Text('body'),
          ),
        ),
        size: (40, 10),
      );
      expect(read(t), [
        'menubar',
        'menuitem File',
        'menuitem Help, disabled',
        'body',
      ]);
      await t.press('f10');
      await t.pump();
      expect(read(t), [
        'menubar',
        'menuitem File, expanded',
        'menuitem Help, disabled',
        'body',
        'menu File',
        'menuitem New',
        'menuitem Word wrap, checked',
        'menuitem Print, disabled',
        'menuitem Recent, collapsed',
      ]);
      expect(t.binding.semantics.focusedLine, 5);
      await t.press('up');
      await t.press('right');
      await t.pump();
      expect(read(t).sublist(8), [
        'menuitem Recent, expanded',
        'menu Recent',
        'menuitem a.txt',
      ]);
      expect(t.binding.semantics.focusedLine, 10);
    });

    testTwk('a dialog over a modal barrier leaves out what it covers', (
      t,
    ) async {
      await t.pumpWidget(
        const Overlay(
          child: _Ask(),
        ),
      );
      expect(read(t), ['page', 'button Ask']);
      await t.press('enter');
      await t.pump();
      expect(read(t), ['Sure?', 'button Yes']);
      expect(t.binding.semantics.focusedLine, 1);
    });
  });
}

/// A page with a button that asks in a dialog.
final class _Ask extends StatelessWidget {
  const _Ask();

  @override
  Widget build(BuildContext context) => column([
    const Text('page'),
    Button(
      'Ask',
      autofocus: true,
      onPressed: () => showDialog<void>(
        context,
        (_) => column([
          const Text('Sure?'),
          Button('Yes', autofocus: true, onPressed: () {}),
        ]),
      ),
    ),
  ]);
}
