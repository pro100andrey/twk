// Menus: the menu bar by the keys (F10, the arrows, Enter, Escape, Alt
// and the mnemonics) and by the mouse (clicks, the mouse over titles and
// entries, a press dragged to an item); submenus opening toward free
// space; the keys shown on items as the bindings bind them, a sequence
// whole, and the intents done from the focused node; disabled and
// checkable items; context menus at the mouse and at the focused widget,
// kept on the overlay; menus rebuilt, removed or opening a dialog; no
// Overlay. Most of them in the bordered look; the raised look, its idle
// highlight, shadow and fade at the end.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not.
final class Field extends StatelessWidget {
  const Field(this.label, {this.autofocus = false, super.key});

  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: autofocus, debugLabel: label, child: _Mark(label));
}

final class _Mark extends StatelessWidget {
  const _Mark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
}

/// The label of the node with the primary focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses [keys] and pumps a frame.
Future<void> press(TwkTester t, String keys) async {
  await t.press(keys);
  await t.pump();
}

/// Moves the mouse to [x], [y] and pumps a frame.
Future<void> move(TwkTester t, int x, int y) async {
  await t.mouse(MouseKind.move, x, y);
  await t.pump();
}

/// Clicks [x], [y] and pumps a frame.
Future<void> click(TwkTester t, int x, int y, {int button = 0}) async {
  await t.click(x, y, button: button);
  await t.pump();
}

/// The text of each run of highlighted cells, on the selection's
/// background, under the first row, top to bottom and left to right:
/// the entries highlighted.
List<String> highlighted(TwkTester t) {
  final runs = <String>[];
  for (var y = 1; y < t.terminal.height; y++) {
    final run = StringBuffer();
    for (var x = 0; x <= t.terminal.width; x++) {
      final cell = x < t.terminal.width ? t.cell(x, y) : null;
      if (cell != null && cell.bg == const Color.indexed(237).value) {
        run.write(cell.text);
      } else if (run.isNotEmpty) {
        runs.add('$run'.trim());
        run.clear();
      }
    }
  }
  return runs;
}

/// File, Edit and View, each item adding its name to [log].
List<Menu> menus(List<String> log) {
  MenuItem item(String label, String name, {bool? checked}) =>
      MenuItem(label, onSelected: () => log.add(name), checked: checked);
  return [
    Menu(
      '&File',
      items: [
        item('&New', 'new'),
        item('&Open', 'open'),
        const MenuDivider(),
        Menu('&Recent', items: [item('&a.txt', 'a'), item('&b.txt', 'b')]),
        item('&Quit', 'quit'),
      ],
    ),
    Menu(
      '&Edit',
      items: [
        item('Cu&t', 'cut'),
        item('&Copy', 'copy'),
        const MenuItem('&Paste', enabled: false),
        item('&Print', 'print'),
        item('&Preview', 'preview'),
        item('Save && &quit', 'save'),
      ],
    ),
    Menu(
      '&View',
      items: [
        item('&Wrap', 'wrap', checked: true),
        item('&Numbers', 'numbers', checked: false),
      ],
    ),
  ];
}

/// [menus] over the fields `editor`, focused, and `notes`; `z` adds `z`
/// to [log] from above the overlay.
Widget app(List<String> log, {Widget? below}) => KeyBindings(
  {'z': () => log.add('z')},
  child: Overlay(
    child: MenuBar(
      look: PanelLook.bordered,
      menus: menus(log),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Field('editor', autofocus: true),
          const Field('notes'),
          ?below,
        ],
      ),
    ),
  ),
);

const closed = ' File  Edit  View\n>editor\n notes';

/// Saves.
final class Save extends Intent {
  const Save();
}

/// Prints, which nothing does.
final class Print extends Intent {
  const Print();
}

/// Adds what its methods do to [log]: the same function each time they
/// are torn off.
final class Doc {
  Doc(this.log);

  final List<String> log;

  void open() => log.add('open');

  void quit() => log.add('quit');
}

/// Shows what [builder] builds from its step, which [HostState.change]
/// sets.
final class Host extends StatefulWidget {
  const Host(this.builder, {super.key});

  final Widget Function(int step) builder;

  @override
  State<Host> createState() => HostState();
}

final class HostState extends State<Host> {
  var _step = 0;

  void change(int step) => setState(() => _step = step);

  @override
  Widget build(BuildContext context) => widget.builder(_step);
}

/// Cut, Copy and Paste, each adding its name to [log].
List<MenuEntry> edits(List<String> log) => [
  MenuItem('Cu&t', onSelected: () => log.add('cut')),
  MenuItem('&Copy', onSelected: () => log.add('copy')),
  MenuItem('&Paste', onSelected: () => log.add('paste')),
];

void main() {
  testTwk('F10 opens the first menu under its title, its first item '
      'highlighted; Up and Down highlight the items before and after, '
      'past dividers and from the last to the first and back; Enter '
      'chooses one, and the menus close and give the focus back', (t) async {
    final log = <String>[];
    await t.pumpWidget(Theme.terminal(child: app(log)), size: (30, 10));
    expect(t, matchesScreen(closed));
    await press(t, 'f10');
    expect(focused(t), 'menu');
    expect(
      t,
      matchesScreen(styles: true, '''
[on indexed(237)] [/][underline on indexed(237)]F[/][on indexed(237)]ile [/][on indexed(234)] [/][underline on indexed(234)]E[/][on indexed(234)]dit  [/][underline on indexed(234)]V[/][on indexed(234)]iew             [/]
[indexed(240) on indexed(234)]┌───────────┐[/]
[indexed(240) on indexed(234)]│[/][on indexed(237)] [/][underline on indexed(237)]N[/][on indexed(237)]ew       [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]O[/][on indexed(234)]pen      [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]├───────────┤[/]
[indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]R[/][on indexed(234)]ecent  ▸ [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]Q[/][on indexed(234)]uit      [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]└───────────┘[/]'''),
    );
    await press(t, 'up');
    expect(highlighted(t), ['Quit']);
    await press(t, 'down');
    expect(highlighted(t), ['New']);
    await press(t, 'down');
    await press(t, 'down');
    expect(highlighted(t), ['Recent  ▸']);
    await press(t, 'up');
    expect(highlighted(t), ['Open']);
    await press(t, 'end');
    expect(highlighted(t), ['Quit']);
    await press(t, 'home');
    await press(t, 'down');
    await press(t, 'enter');
    expect(log, ['open']);
    expect(focused(t), 'editor');
    expect(t, matchesScreen(closed));
  });

  testTwk('Right and Left open the next and the previous menu of the bar, '
      'and a submenu beside its menu, its first item highlighted, and '
      'close it; Escape closes the innermost menu, F10 them all', (t) async {
    final log = <String>[];
    await t.pumpWidget(Theme.terminal(child: app(log)), size: (30, 10));
    await press(t, 'f10');
    await press(t, 'right');
    expect(t, hasTextAt(6, 1, '┌─────────────┐'));
    expect(highlighted(t), ['Cut']);
    expect(t, styleAt(7, 0, hasBg(const Color.indexed(237))));
    expect(t, styleAt(1, 0, isNot(hasBg(const Color.indexed(237)))));
    await press(t, 'right');
    expect(highlighted(t), ['✓ Wrap']);
    await press(t, 'right');
    expect(highlighted(t), ['New']);
    await press(t, 'left');
    expect(highlighted(t), ['✓ Wrap']);
    await press(t, 'right');
    await press(t, 'down');
    await press(t, 'down');
    await press(t, 'right');
    expect(highlighted(t), ['Recent  ▸', 'a.txt']);
    expect(
      t,
      matchesScreen('''
 File  Edit  View
┌───────────┐
│ New       │
│ Open      │
├───────────┤┌───────┐
│ Recent  ▸ ││ a.txt │
│ Quit      ││ b.txt │
└───────────┘└───────┘'''),
    );
    await press(t, 'down');
    expect(highlighted(t), ['Recent  ▸', 'b.txt']);
    await press(t, 'left');
    expect(highlighted(t), ['Recent  ▸']);
    expect(t, hasTextAt(13, 4, ' '));
    await press(t, 'enter');
    expect(highlighted(t), ['Recent  ▸', 'a.txt']);
    await press(t, 'escape');
    expect(highlighted(t), ['Recent  ▸']);
    await press(t, 'escape');
    expect(t, matchesScreen(closed));
    expect(focused(t), 'editor');
    await press(t, 'f10');
    await press(t, 'down');
    await press(t, 'down');
    await press(t, 'right');
    await press(t, 'f10');
    expect(t, matchesScreen(closed));
    expect(focused(t), 'editor');
    expect(log, isEmpty);
  });

  testTwk('Alt and a mnemonic opens its menu; a mnemonic, in either case, '
      'chooses an item or opens a submenu, or highlights the next of the '
      'items that share it; other letters go no further', (t) async {
    final log = <String>[];
    await t.pumpWidget(Theme.terminal(child: app(log)), size: (30, 12));
    await press(t, 'alt+e');
    expect(highlighted(t), ['Cut']);
    expect(
      t,
      matchesScreen(styles: true, '''
[on indexed(234)] [/][underline on indexed(234)]F[/][on indexed(234)]ile [/][on indexed(237)] [/][underline on indexed(237)]E[/][on indexed(237)]dit [/][on indexed(234)] [/][underline on indexed(234)]V[/][on indexed(234)]iew             [/]
 edito[indexed(240) on indexed(234)]┌─────────────┐[/]
 notes[indexed(240) on indexed(234)]│[/][on indexed(237)] Cu[/][underline on indexed(237)]t[/][on indexed(237)]         [/][indexed(240) on indexed(234)]│[/]
      [indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]C[/][on indexed(234)]opy        [/][indexed(240) on indexed(234)]│[/]
      [indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline indexed(245) on indexed(234)]P[/][indexed(245) on indexed(234)]aste[/][on indexed(234)]       [/][indexed(240) on indexed(234)]│[/]
      [indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]P[/][on indexed(234)]rint       [/][indexed(240) on indexed(234)]│[/]
      [indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]P[/][on indexed(234)]review     [/][indexed(240) on indexed(234)]│[/]
      [indexed(240) on indexed(234)]│[/][on indexed(234)] Save & [/][underline on indexed(234)]q[/][on indexed(234)]uit [/][indexed(240) on indexed(234)]│[/]
      [indexed(240) on indexed(234)]└─────────────┘[/]'''),
    );
    await press(t, 'z');
    await press(t, 'C');
    expect(log, ['copy']);
    expect(focused(t), 'editor');
    await press(t, 'alt+e');
    await press(t, 'p');
    expect(highlighted(t), ['Print']);
    await press(t, 'alt+v');
    expect(highlighted(t), ['✓ Wrap']);
    await press(t, 'alt+e');
    await press(t, 'p');
    await press(t, 'p');
    expect(highlighted(t), ['Preview']);
    await press(t, 'P');
    expect(highlighted(t), ['Print']);
    await press(t, 'q');
    expect(log, ['copy', 'save']);
    await press(t, 'alt+f');
    await press(t, 'r');
    expect(highlighted(t), ['Recent  ▸', 'a.txt']);
    await press(t, 'b');
    expect(log, ['copy', 'save', 'b']);
    await press(t, 'z');
    expect(log, ['copy', 'save', 'b', 'z']);
  });

  testTwk('the mouse: a click on a title opens its menu, the mouse over '
      'another title opens that one, over an entry highlights it and opens '
      'its menu; a click chooses an item; a click on the open title or '
      'outside the menus closes them and reaches nothing under them', (
    t,
  ) async {
    final log = <String>[];
    final below = Listener(
      behavior: HitTestBehavior.opaque,
      onDown: (_) => log.add('below'),
      child: const SizedBox(width: 30, height: 6),
    );
    await t.pumpWidget(
      Theme.terminal(child: app(log, below: below)),
      size: (30, 10),
    );
    await click(t, 8, 0);
    expect(highlighted(t), isEmpty);
    expect(t, hasTextAt(6, 1, '┌─────────────┐'));
    await move(t, 2, 0);
    expect(t, hasTextAt(0, 1, '┌───────────┐'));
    await move(t, 3, 3);
    expect(highlighted(t), ['Open']);
    await move(t, 3, 4);
    expect(highlighted(t), isEmpty);
    await move(t, 3, 5);
    expect(highlighted(t), ['Recent  ▸']);
    expect(t, hasTextAt(13, 4, '┌───────┐'));
    await move(t, 15, 6);
    expect(highlighted(t), ['Recent  ▸', 'b.txt']);
    await click(t, 15, 6);
    expect(log, ['b']);
    expect(t, matchesScreen(closed));
    await click(t, 2, 0);
    await click(t, 2, 0);
    expect(t, matchesScreen(closed));
    await click(t, 2, 0);
    await click(t, 20, 8);
    expect(t, matchesScreen(closed));
    expect(log, ['b']);
    await click(t, 20, 8);
    expect(log, ['b', 'below']);
    await click(t, 8, 0);
    await move(t, 8, 4);
    await click(t, 8, 4);
    expect(log, ['b', 'below']);
    expect(highlighted(t), isEmpty);
    expect(focused(t), 'menu');
  });

  testTwk('a press on a title held down to an item and released there '
      'chooses it', (t) async {
    final log = <String>[];
    await t.pumpWidget(Theme.terminal(child: app(log)), size: (30, 10));
    await t.mouse(MouseKind.down, 2, 0);
    await t.pump();
    await t.mouse(MouseKind.drag, 2, 1);
    await t.mouse(MouseKind.drag, 3, 3);
    await t.pump();
    expect(highlighted(t), ['Open']);
    await t.mouse(MouseKind.up, 3, 3);
    await t.pump();
    expect(log, ['open']);
    expect(t, matchesScreen(closed));
  });

  testTwk('an item shows the first key the layers above the focused node '
      'take for its intent or its callback, one a nearer layer passes on '
      'too and not one it binds to another, and does its intent from that '
      'node; one whose intent no action does cannot be chosen', (t) async {
    final log = <String>[];
    final doc = Doc(log);
    await t.pumpWidget(
      Theme.terminal(
        child: Shortcuts(
          const {'ctrl+s': Save(), 'f2': Save(), 'ctrl+p': Print()},
          hints: const {'ctrl+s': 'save'},
          child: KeyBindings(
            {'ctrl+o': doc.open, 'ctrl+q': doc.quit},
            child: Actions(
              {Save: CallbackAction<Save>(onInvoke: (_) => log.add('save'))},
              child: Overlay(
                child: MenuBar(
                  look: PanelLook.bordered,
                  menus: [
                    Menu(
                      '&File',
                      items: [
                        const MenuItem('&Save', intent: Save()),
                        MenuItem('&Open', onSelected: doc.open),
                        const MenuItem('&Print', intent: Print()),
                        MenuItem('&Close', onSelected: () => log.add('close')),
                        MenuItem('&Quit', onSelected: doc.quit),
                      ],
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const KeyBindings(
                        {'ctrl+o': null},
                        child: Field('editor', autofocus: true),
                      ),
                      Actions(
                        {
                          Save: CallbackAction<Save>(
                            onInvoke: (_) => log.add('save notes'),
                          ),
                        },
                        child: KeyBindings({
                          'ctrl+s': () => log.add('other'),
                        }, child: const Field('notes')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      size: (30, 10),
    );
    await press(t, 'f10');
    expect(
      t,
      matchesScreen(styles: true, '''
[on indexed(237)] [/][underline on indexed(237)]F[/][on indexed(237)]ile [/][on indexed(234)]                        [/]
[indexed(240) on indexed(234)]┌───────────────┐[/]
[indexed(240) on indexed(234)]│[/][on indexed(237)] [/][underline on indexed(237)]S[/][on indexed(237)]ave   [/][indexed(245) on indexed(237)]ctrl+s[/][on indexed(237)] [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]O[/][on indexed(234)]pen   [/][indexed(245) on indexed(234)]ctrl+o[/][on indexed(234)] [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline indexed(245) on indexed(234)]P[/][indexed(245) on indexed(234)]rint[/][on indexed(234)]         [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]C[/][on indexed(234)]lose         [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]│[/][on indexed(234)] [/][underline on indexed(234)]Q[/][on indexed(234)]uit   [/][indexed(245) on indexed(234)]ctrl+q[/][on indexed(234)] [/][indexed(240) on indexed(234)]│[/]
[indexed(240) on indexed(234)]└───────────────┘[/]'''),
    );
    await press(t, 'down');
    await press(t, 'down');
    expect(highlighted(t), ['Close']);
    await click(t, 3, 4);
    expect(highlighted(t), ['Close']);
    await press(t, 'home');
    await press(t, 'enter');
    expect(log, ['save']);
    await press(t, 'tab');
    expect(focused(t), 'notes');
    await press(t, 'f10');
    expect(t, hasTextAt(1, 2, ' Save       f2 '));
    await press(t, 'enter');
    expect(log, ['save', 'save notes']);
  });

  testTwk('keyLabel names the keys', (t) async {
    final doc = Doc([]);
    await t.pumpWidget(
      Theme.terminal(
        child: KeyBindings(
          {'ctrl+q': doc.quit},
          child: Overlay(
            child: MenuBar(
              look: PanelLook.bordered,
              keyLabel: (combo) => '^${combo.char.toUpperCase()}',
              menus: [
                Menu('&File', items: [MenuItem('&Quit', onSelected: doc.quit)]),
              ],
              child: const Field('editor', autofocus: true),
            ),
          ),
        ),
      ),
      size: (20, 5),
    );
    await press(t, 'f10');
    expect(t, hasTextAt(0, 2, '│ Quit  ^Q │'));
  });

  testTwk('an item shows a sequence bound to what it does whole, each key '
      'named as keyLabel names it', (t) async {
    final doc = Doc([]);
    Widget app({String Function(KeyCombo combo)? keyLabel}) => KeyBindings(
      {'ctrl+k q': doc.quit},
      child: Shortcuts(
        const {'ctrl+x ctrl+s': Save()},
        child: Actions(
          {Save: CallbackAction<Save>(onInvoke: (_) {})},
          child: Overlay(
            child: MenuBar(
              look: PanelLook.bordered,
              keyLabel: keyLabel,
              menus: [
                Menu(
                  '&File',
                  items: [
                    const MenuItem('&Save', intent: Save()),
                    MenuItem('&Quit', onSelected: doc.quit),
                  ],
                ),
              ],
              child: const Field('editor', autofocus: true),
            ),
          ),
        ),
      ),
    );
    await t.pumpWidget(Theme.terminal(child: app()), size: (30, 6));
    await press(t, 'f10');
    expect(t, hasTextAt(0, 2, '│ Save  ctrl+x ctrl+s │'));
    expect(t, hasTextAt(0, 3, '│ Quit       ctrl+k q │'));
    await press(t, 'f10');
    await t.pumpWidget(
      Theme.terminal(
        child: app(keyLabel: (combo) => '^${combo.char.toUpperCase()}'),
      ),
      size: (30, 6),
    );
    await press(t, 'f10');
    expect(t, hasTextAt(0, 2, '│ Save  ^X ^S │'));
  });

  testTwk('a checkable item shows its check mark while checked, the app '
      'flipping it', (t) async {
    var wrap = true;
    final host = GlobalKey<HostState>();
    await t.pumpWidget(
      Theme.terminal(
        child: Host(
          key: host,
          (_) => Overlay(
            child: MenuBar(
              look: PanelLook.bordered,
              menus: [
                Menu(
                  '&View',
                  items: [
                    MenuItem(
                      '&Wrap',
                      checked: wrap,
                      onSelected: () => host.currentState!.change(
                        (wrap = !wrap) ? 1 : 0,
                      ),
                    ),
                    const MenuItem('&Numbers', checked: false),
                  ],
                ),
              ],
              child: const Field('editor', autofocus: true),
            ),
          ),
        ),
      ),
      size: (20, 6),
    );
    await press(t, 'f10');
    expect(
      t,
      matchesScreen('''
 View
┌───────────┐
│ ✓ Wrap    │
│   Numbers │
└───────────┘'''),
    );
    await press(t, 'enter');
    await press(t, 'f10');
    expect(t, hasTextAt(0, 2, '│   Wrap    │'));
  });

  testTwk('a right click opens a context menu with its top left at the '
      'mouse, on the left of it and above it near the edges; the release '
      'chooses nothing, a click does', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Overlay(
          child: ContextMenu(
            look: PanelLook.bordered,
            items: edits(log),
            child: const Field('a', autofocus: true),
          ),
        ),
      ),
      size: (30, 10),
    );
    await click(t, 5, 2, button: 2);
    expect(
      t,
      matchesScreen('''
 a

     ┌───────┐
     │ Cut   │
     │ Copy  │
     │ Paste │
     └───────┘'''),
    );
    expect(highlighted(t), isEmpty);
    expect(focused(t), 'menu');
    await press(t, 'escape');
    expect(t, matchesScreen('>a'));
    expect(focused(t), 'a');
    await click(t, 27, 8, button: 2);
    expect(t, hasTextAt(19, 4, '┌───────┐'));
    expect(t, hasTextAt(19, 8, '└───────┘'));
    await click(t, 22, 6);
    expect(log, ['copy']);
    expect(t, matchesScreen('>a'));
    expect(log, ['copy']);
  });

  testTwk('Shift+F10 opens a context menu under the first row of the '
      'focused widget, above it near the bottom, its first item '
      'highlighted', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Overlay(
          child: ContextMenu(
            look: PanelLook.bordered,
            items: edits(log),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 3),
                  child: Field('a', autofocus: true),
                ),
                Spacer(),
                Padding(
                  padding: EdgeInsets.only(left: 25),
                  child: Field('b'),
                ),
              ],
            ),
          ),
        ),
      ),
      size: (30, 10),
    );
    await press(t, 'shift+f10');
    expect(highlighted(t), ['Cut']);
    expect(t, hasTextAt(3, 1, '┌───────┐'));
    await press(t, 'enter');
    expect(log, ['cut']);
    await press(t, 'tab');
    await press(t, 'shift+f10');
    expect(highlighted(t), ['Cut']);
    expect(t, hasTextAt(18, 4, '┌───────┐'));
    expect(t, hasTextAt(18, 8, '└───────┘'));
  });

  testTwk('a submenu opens on the right of its menu, on the left where '
      'there is no room on the right, and with its last item level with '
      'the entry it opens from where there is no room below; a menu of the '
      'bar ends at its title near the right edge', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Overlay(
          child: ContextMenu(
            look: PanelLook.bordered,
            items: [
              const MenuItem('&One'),
              const Menu(
                '&Translate',
                items: [MenuItem('English'), MenuItem('French')],
              ),
              Menu(
                '&More',
                items: [for (var i = 1; i <= 6; i++) MenuItem('Item $i')],
              ),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
      size: (40, 12),
    );
    await click(t, 2, 5, button: 2);
    await move(t, 4, 7);
    expect(highlighted(t), ['Translate  ▸']);
    expect(t, hasTextAt(18, 6, '┌─────────┐'));
    expect(t, hasTextAt(18, 7, '│ English │'));
    await move(t, 4, 8);
    expect(
      t,
      matchesScreen('''


                  ┌────────┐
                  │ Item 1 │
                  │ Item 2 │
  ┌──────────────┐│ Item 3 │
  │ One          ││ Item 4 │
  │ Translate  ▸ ││ Item 5 │
  │ More       ▸ ││ Item 6 │
  └──────────────┘└────────┘'''),
    );
    await press(t, 'escape');
    await press(t, 'escape');
    await click(t, 22, 5, button: 2);
    await move(t, 24, 7);
    expect(t, hasTextAt(11, 6, '┌─────────┐'));
    expect(t, hasTextAt(11, 7, '│ English │'));
    await press(t, 'escape');
    await press(t, 'escape');
    await t.pumpWidget(Theme.terminal(child: app(log)), size: (20, 10));
    await press(t, 'alt+v');
    expect(t, hasTextAt(5, 1, '┌───────────┐'));
    expect(t, hasTextAt(5, 2, '│ ✓ Wrap    │'));
  });

  testTwk('a KeyHintsBar lists F10 of the menu bar and Shift+F10 of a '
      'context menu, and while a menu is open its keys', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Overlay(
          child: MenuBar(
            look: PanelLook.bordered,
            menus: menus(log),
            child: ContextMenu(
              look: PanelLook.bordered,
              items: edits(log),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Field('editor', autofocus: true),
                  Spacer(),
                  KeyHintsBar(),
                ],
              ),
            ),
          ),
        ),
      ),
      size: (40, 12),
    );
    expect(t.lines[11], 'shift+f10 menu   f10 menu');
    await press(t, 'f10');
    expect(t.lines[11], 'enter select   esc close');
    await press(t, 'escape');
    await press(t, 'shift+f10');
    expect(t.lines[11], 'enter select   esc close');
  });

  testTwk('the menus open follow the bar built with other menus, and close '
      'with it; an item that shows a dialog gives it the focus, which goes '
      'back to the node focused before the menus', (t) async {
    final host = GlobalKey<HostState>();
    final editor = GlobalKey();
    await t.pumpWidget(
      Theme.terminal(
        child: Host(
          key: host,
          (step) => Overlay(
            child: step == 2
                ? const Text('gone')
                : MenuBar(
                    look: PanelLook.bordered,
                    menus: [
                      Menu(
                        '&File',
                        items: [
                          MenuItem(step == 0 ? '&New' : '&Create'),
                          MenuItem(
                            '&Find',
                            onSelected: () => unawaited(
                              showDialog<void>(
                                editor.currentContext!,
                                (_) => const Dialog(child: Field('find')),
                                fadeIn: Duration.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    child: Field('editor', key: editor, autofocus: true),
                  ),
          ),
        ),
      ),
      size: (30, 8),
    );
    await press(t, 'f10');
    expect(t, hasTextAt(0, 2, '│ New  │'));
    host.currentState!.change(1);
    await t.pump();
    await t.pump();
    expect(t, hasTextAt(0, 2, '│ Create │'));
    await press(t, 'f');
    expect(focused(t), 'dialog');
    expect(t, containsLine(endsWith(' find')));
    await press(t, 'escape');
    expect(focused(t), 'editor');
    await press(t, 'f10');
    host.currentState!.change(2);
    await t.pump();
    expect(t, matchesScreen('gone'));
    expect(t.logs.records.where((r) => r.level == LogLevel.error), isEmpty);
  });

  testTwk('the context menu open follows the ContextMenu built with other '
      'items, an item checked and another enabled, and closes with it', (
    t,
  ) async {
    final host = GlobalKey<HostState>();
    await t.pumpWidget(
      Theme.terminal(
        child: Host(
          key: host,
          (step) => Overlay(
            child: step == 2
                ? const Text('gone')
                : ContextMenu(
                    look: PanelLook.bordered,
                    items: [
                      MenuItem('&Wrap', onSelected: () {}, checked: step == 1),
                      MenuItem('&Save', onSelected: () {}, enabled: step == 1),
                    ],
                    child: const Field('a', autofocus: true),
                  ),
          ),
        ),
      ),
      size: (20, 6),
    );
    await press(t, 'shift+f10');
    expect(highlighted(t), ['Wrap']);
    expect(t, hasTextAt(0, 2, '│   Wrap │'));
    expect(t, styleAt(4, 3, hasFg(const Color.indexed(245))));
    host.currentState!.change(1);
    await t.pump();
    await t.pump();
    expect(t, hasTextAt(0, 2, '│ ✓ Wrap │'));
    expect(t, styleAt(4, 3, isNot(hasFg(const Color.indexed(245)))));
    await press(t, 'down');
    expect(highlighted(t), ['Save']);
    host.currentState!.change(2);
    await t.pump();
    expect(t, matchesScreen('gone'));
    expect(focused(t), isNot('menu'));
  });

  testTwk('a bar built with other entries while a submenu is open shows '
      'them in the menus open, as far as the entries still open them; a '
      'highlight past the entries left goes', (t) async {
    final host = GlobalKey<HostState>();
    await t.pumpWidget(
      Theme.terminal(
        child: Host(
          key: host,
          (step) => Overlay(
            child: MenuBar(
              look: PanelLook.bordered,
              menus: [
                Menu(
                  '&File',
                  items: [
                    MenuItem('&New', onSelected: () {}),
                    if (step < 2)
                      Menu(
                        '&Recent',
                        items: [
                          MenuItem('&a.txt', onSelected: () {}),
                          if (step == 0) MenuItem('&b.txt', onSelected: () {}),
                        ],
                      ),
                  ],
                ),
              ],
              child: const Field('editor', autofocus: true),
            ),
          ),
        ),
      ),
      size: (30, 8),
    );
    await press(t, 'f10');
    await press(t, 'down');
    await press(t, 'enter');
    await press(t, 'down');
    expect(highlighted(t), ['Recent  ▸', 'b.txt']);
    host.currentState!.change(1);
    await t.pump();
    await t.pump();
    expect(t, containsLine(contains('a.txt')));
    expect(t, isNot(containsLine(contains('b.txt'))));
    expect(highlighted(t), ['Recent  ▸'], reason: 'b.txt is gone');
    host.currentState!.change(2);
    await t.pump();
    await t.pump();
    expect(t, isNot(containsLine(contains('a.txt'))));
    expect(t, containsLine(contains('New')));
    expect(highlighted(t), isEmpty);
  });

  testTwk('a ContextMenu built with no items while its menu is open closes '
      'it; built with another controller, that one says it is open', (
    t,
  ) async {
    final host = GlobalKey<HostState>();
    final first = MenuController();
    final second = MenuController();
    await t.pumpWidget(
      Theme.terminal(
        child: Host(
          key: host,
          (step) => Overlay(
            child: ContextMenu(
              look: PanelLook.bordered,
              controller: step == 0 ? first : second,
              items: step == 2 ? const [] : const [MenuItem('&Wrap')],
              child: const Field('a', autofocus: true),
            ),
          ),
        ),
      ),
      size: (20, 6),
    );
    await press(t, 'shift+f10');
    expect(first.isOpen, isTrue);
    host.currentState!.change(1);
    await t.pump();
    expect(second.isOpen, isTrue);
    expect(second.path, isEmpty);
    expect(first.isOpen, isFalse);
    host.currentState!.change(2);
    await t.pump();
    await t.pump();
    expect(t, matchesScreen('>a'));
    expect(second.isOpen, isFalse);
    expect(focused(t), 'a');
  });

  testTwk('a MenuBar and a ContextMenu moved in the tree with a GlobalKey '
      'open again there the menus their controller says are open', (
    t,
  ) async {
    final host = GlobalKey<HostState>();
    final bar = GlobalKey();
    final context = GlobalKey();
    final menusOpen = MenuController();
    final contextOpen = MenuController();
    final log = <String>[];
    Widget widgets() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 4,
          child: MenuBar(
            key: bar,
            look: PanelLook.bordered,
            controller: menusOpen,
            menus: menus(log),
            child: const Field('editor', autofocus: true),
          ),
        ),
        ContextMenu(
          key: context,
          look: PanelLook.bordered,
          controller: contextOpen,
          items: edits(log),
          child: const Field('notes'),
        ),
      ],
    );
    await t.pumpWidget(
      Theme.terminal(
        child: Host(
          key: host,
          (step) => Overlay(
            child: step == 0
                ? widgets()
                : Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: widgets(),
                  ),
          ),
        ),
      ),
      size: (30, 10),
    );
    menusOpen.open([1]);
    await t.pump();
    expect(t, containsLine(contains('Cut')));
    host.currentState!.change(1);
    await t.pump();
    await t.pump();
    expect(menusOpen.isOpen, isTrue);
    expect(menusOpen.path, [1]);
    expect(t, containsLine(contains('Cut')));
    menusOpen.close();
    contextOpen.open();
    await t.pump();
    host.currentState!.change(0);
    await t.pump();
    await t.pump();
    expect(contextOpen.isOpen, isTrue);
    expect(t, containsLine(contains('Paste')));
  });

  testTwk('a MenuBar or a ContextMenu without an Overlay above fails to '
      'build, and showContextMenu without one throws, saying where to '
      'place one', (t) async {
    String failed(String widget) =>
        'Column → $widget failed to build: Bad state: $widget: no Overlay '
        'above it: place an Overlay above it, as around the whole app: '
        'Overlay(child: …)';
    await t.pumpWidget(
      const Column(
        children: [
          MenuBar(look: PanelLook.bordered, menus: [], child: Text('a')),
          ContextMenu(look: PanelLook.bordered, items: [], child: Text('b')),
        ],
      ),
    );
    expect(
      [
        for (final r in t.logs.records)
          if (r.level == LogLevel.error) '${r.message}: ${r.error}',
      ],
      [failed('MenuBar'), failed('ContextMenu')],
    );
    final key = GlobalKey();
    await t.pumpWidget(
      Theme.terminal(child: SizedBox(key: key, width: 1, height: 1)),
    );
    expect(
      () => showContextMenu(key.currentContext!, const [MenuItem('a')]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'showContextMenu: no Overlay above SizedBox: place an Overlay '
              'above it, as around the whole app: Overlay(child: …)',
        ),
      ),
    );
  });

  testTwk('showContextMenu shows a menu at a cell of the widget of the '
      'context, or with no cell under the focused widget, its first item '
      'highlighted; with no items, none', (t) async {
    final log = <String>[];
    final key = GlobalKey();
    await t.pumpWidget(
      Theme.terminal(
        child: Overlay(
          child: Padding(
            padding: const EdgeInsets.only(left: 2, top: 1),
            child: SizedBox(
              key: key,
              width: 20,
              height: 6,
              child: const Field('a', autofocus: true),
            ),
          ),
        ),
      ),
      size: (30, 10),
    );
    final context = key.currentContext!;
    showContextMenu(context, edits(log), at: (4, 1), look: PanelLook.bordered);
    await t.pump();
    expect(t, hasTextAt(6, 2, '┌───────┐'));
    expect(highlighted(t), isEmpty);
    await press(t, 'down');
    await press(t, 'enter');
    expect(log, ['cut']);
    showContextMenu(context, edits(log), look: PanelLook.bordered);
    await t.pump();
    expect(t, hasTextAt(2, 2, '┌───────┐'), reason: 'under the field');
    expect(highlighted(t), ['Cut']);
    await press(t, 'escape');
    showContextMenu(context, const []);
    await t.pump();
    expect(t, matchesScreen('\n  >a'));
  });

  group('raised menus', () {
    const theme = ThemeData.dark;
    final surface = theme.surface.bg!;
    final selection = theme.selection.bg!;
    Color mix(Color a, Color b, double k) => Color.rgb(
      (a.r + (b.r - a.r) * k).round(),
      (a.g + (b.g - a.g) * k).round(),
      (a.b + (b.b - a.b) * k).round(),
    );
    Color shaded(Color c) => Color.rgb(
      (c.r * (255 - 140) / 255).round(),
      (c.g * (255 - 140) / 255).round(),
      (c.b * (255 - 140) / 255).round(),
    );

    /// [menus] over a focused field, in the dark theme, raised.
    Widget raised(List<String> log) => Theme(
      data: theme,
      child: Box(
        style: theme.background,
        child: Overlay(
          child: MenuBar(
            menus: menus(log),
            child: const Field('editor', autofocus: true),
          ),
        ),
      ),
    );

    /// Opens File by F10 and waits out its fade.
    Future<void> openFile(TwkTester t) async {
      await press(t, 'f10');
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
    }

    testTwk('a menu is a raised panel: no outline, a cell of room, the '
        'highlighted entry lit across it with a primary ▎, a quiet divider, '
        'the shadow', (t) async {
      await t.pumpWidget(Theme.terminal(child: raised([])), size: (30, 10));
      await openFile(t);
      expect(t.lines.sublist(1, 8), [
        '',
        '▎ New',
        '  Open',
        ' ───────────',
        '  Recent  ▸',
        '  Quit',
        '',
      ]);
      expect(
        t,
        styleAt(0, 2, allOf(hasFg(theme.primary.fg!), hasBg(selection))),
      );
      expect(t, styleAt(12, 2, hasBg(selection)));
      expect(t, styleAt(0, 1, hasBg(surface)));
      expect(t, styleAt(12, 7, hasBg(surface)));
      expect(t, styleAt(1, 4, hasFg(mix(surface, theme.border.fg!, 0.8))));
      final background = theme.background.bg!;
      expect(t, styleAt(13, 2, hasBg(shaded(background))));
      expect(t, styleAt(14, 8, hasBg(shaded(background))));
      expect(t, styleAt(13, 1, hasBg(background)));
    });

    testTwk('a menu with a submenu open from its highlighted entry shows '
        'that entry idle: the unfocused selection, the ▎ muted', (t) async {
      await t.pumpWidget(Theme.terminal(child: raised([])), size: (30, 10));
      await openFile(t);
      await press(t, 'down down right');
      // the submenu beside the menu, the shadow left out
      expect(t, hasTextAt(13, 5, '▎ a.txt'));
      expect(
        t,
        styleAt(
          0,
          5,
          allOf(hasFg(theme.muted.fg!), hasBg(theme.selectionIdle.bg!)),
        ),
      );
      expect(t, styleAt(13, 5, hasFg(theme.primary.fg!)));
      await press(t, 'left');
      expect(
        t,
        styleAt(0, 5, allOf(hasFg(theme.primary.fg!), hasBg(selection))),
      );
    });

    testTwk('the menu fades in over 90 ms as the menus open', (t) async {
      await t.pumpWidget(Theme.terminal(child: raised([])), size: (30, 10));
      await press(t, 'f10');
      expect(t, styleAt(5, 2, isNot(hasBg(selection))));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      expect(t, styleAt(5, 2, hasBg(selection)));
    });

    testTwk('the shadow is outside the menu: the mouse there is outside', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(Theme.terminal(child: raised(log)), size: (30, 10));
      await openFile(t);
      await move(t, 5, 3);
      expect(t, hasTextAt(0, 3, '▎ Open'));
      await click(t, 13, 3);
      expect(t.lines.sublist(1, 4), ['>editor', '', '']);
      expect(log, isEmpty);
    });
  });
}
