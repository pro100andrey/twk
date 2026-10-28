// The scaffold: its parts laid out at 120 × 36 and 80 × 24 in the theme's
// tones; a zone of the focus per part, Tab within one, F6 and Shift+F6
// between them, Ctrl+B to the sidebar and back; the sidebar collapsed
// below a width, shown and hidden by Ctrl+B and the header's toggle; its
// divider dragged; the key hints.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] named [label] that shows it.
Widget field(String label) => Focus(debugLabel: label, child: Text(label));

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

/// An app in a scaffold of every part: a header and a status bar of one
/// field each, a sidebar of two fields and a body of two.
Widget app({
  int sidebarWidth = 24,
  SidebarSide side = SidebarSide.left,
  bool resizable = false,
  int? collapsedBelow,
  bool keyHints = true,
  void Function(int width)? onResized,
}) => Theme(
  data: ThemeData.dark,
  child: Scaffold(
    header: field('title'),
    sidebar: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [field('inbox'), field('sent')],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [field('message'), field('reply')],
    ),
    statusBar: StatusBar(left: field('ready'), right: const Text('12:00')),
    sidebarWidth: sidebarWidth,
    sidebarSide: side,
    resizableSidebar: resizable,
    collapsedBelow: collapsedBelow,
    keyHints: keyHints,
    onSidebarResized: onResized,
  ),
);

Color bg(Style s) => s.bg!;

final Color chrome = bg(ThemeData.dark.chrome);
final Color background = bg(ThemeData.dark.background);

void main() {
  testTwk('lays out the header on top, the sidebar beside the body, the '
      'status bar and the hints at the bottom, at 120 x 36', (t) async {
    await t.pumpWidget(app(), size: (120, 36));
    await t.pump();
    expect(t.lines[0], '  ≡  title');
    expect(t.lines[1], startsWith('inbox${' ' * 19}message'));
    expect(t.lines[2], startsWith('sent${' ' * 20}reply'));
    expect(t.lines[34], 'ready${' ' * 110}12:00');
    expect(t.lines[35], '  f6 next pane   ctrl+b sidebar');
    for (var y = 3; y < 34; y++) {
      expect(t.lines[y], '', reason: 'row $y');
    }
    // the header, the sidebar and the hints on the chrome, the body on
    // the background, the status bar on the surface
    expect(t, styleAt(119, 0, hasBg(chrome)));
    expect(t, styleAt(23, 20, hasBg(chrome)));
    expect(t, styleAt(24, 20, hasBg(background)));
    expect(t, styleAt(119, 20, hasBg(background)));
    expect(t, styleAt(60, 34, hasBg(bg(ThemeData.dark.surface))));
    expect(t, styleAt(119, 35, hasBg(chrome)));
  });

  testTwk('at 80 x 24 the sidebar keeps its width, on the right too', (
    t,
  ) async {
    await t.pumpWidget(app(sidebarWidth: 20), size: (80, 24));
    await t.pump();
    expect(t.lines[1], startsWith('inbox${' ' * 15}message'));
    expect(t.lines[22], 'ready${' ' * 70}12:00');
    expect(t.lines[23], '  f6 next pane   ctrl+b sidebar');
    expect(t, styleAt(19, 10, hasBg(chrome)));
    expect(t, styleAt(20, 10, hasBg(background)));

    await t.pumpWidget(app(sidebarWidth: 20, side: SidebarSide.right));
    await t.pump();
    expect(t.lines[0], '  title${' ' * 70}≡');
    expect(t.lines[1], 'message${' ' * 53}inbox');
    expect(t, styleAt(59, 10, hasBg(background)));
    expect(t, styleAt(60, 10, hasBg(chrome)));
  });

  testTwk('focuses the body first; Tab and Shift+Tab stay in a zone', (
    t,
  ) async {
    await t.pumpWidget(app(), size: (120, 36));
    await t.pump();
    expect(focused(t), 'message');
    await press(t, 'tab');
    expect(focused(t), 'reply');
    await press(t, 'tab');
    expect(focused(t), 'message');
    await press(t, 'shift+tab');
    expect(focused(t), 'reply');
  });

  // A node beside the scaffold that asked for the focus keeps it: the
  // scaffold gives its body the focus only when nothing has it. Built in
  // the layout (a LayoutBuilder, as a lazy list builds its items), the
  // node is mounted after the first build's flush and asks for the focus
  // on the next.
  for (final (name, lazy) in [
    ('built', false),
    ('built in the layout', true),
  ]) {
    testTwk('leaves the focus to an autofocus node beside it, $name', (
      t,
    ) async {
      const list = Focus(
        debugLabel: 'list',
        autofocus: true,
        child: Text('list'),
      );
      await t.pumpWidget(
        Row(
          children: [
            SizedBox(
              width: 10,
              child: lazy ? LayoutBuilder(builder: (_, _) => list) : list,
            ),
            Expanded(child: app()),
          ],
        ),
        size: (120, 36),
      );
      await t.pump();
      await t.pump();
      expect(focused(t), 'list');
    });
  }

  testTwk('leaves the focus to an autofocus node of its body', (t) async {
    await t.pumpWidget(
      Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field('message'),
            const Focus(
              debugLabel: 'reply',
              autofocus: true,
              child: Text('reply'),
            ),
          ],
        ),
      ),
      size: (40, 5),
    );
    await t.pump();
    await t.pump();
    expect(focused(t), 'reply');
  });

  testTwk('leaves the focus where the app put it after the first frame', (
    t,
  ) async {
    final node = FocusNode(debugLabel: 'list');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Row(
        children: [
          SizedBox(
            width: 10,
            child: Focus(focusNode: node, child: const Text('list')),
          ),
          Expanded(child: app()),
        ],
      ),
      size: (120, 36),
    );
    node.requestFocus();
    await t.pump();
    await t.pump();
    expect(focused(t), 'list');
  });

  testTwk('F6 goes to the next zone in the order on the screen, Shift+F6 '
      'to the one before, each back where it was', (t) async {
    await t.pumpWidget(app(), size: (120, 36));
    await t.pump();
    final order = <String?>[];
    for (var i = 0; i < 4; i++) {
      await press(t, 'f6');
      order.add(focused(t));
    }
    expect(order, ['ready', 'title', 'inbox', 'message']);
    await press(t, 'shift+f6');
    expect(focused(t), 'inbox');
    await press(t, 'tab f6 shift+f6');
    expect(focused(t), 'sent');

    // on the right the body comes before the sidebar
    await t.pumpWidget(app(side: SidebarSide.right));
    await t.pump();
    await press(t, 'shift+f6');
    expect(focused(t), 'message');
    await press(t, 'f6');
    expect(focused(t), 'sent');
  });

  testTwk('Ctrl+B goes to the sidebar and back to the zone the focus came '
      'from; the hint says which', (t) async {
    await t.pumpWidget(app(), size: (120, 36));
    await t.pump();
    await press(t, 'tab ctrl+b');
    expect(focused(t), 'inbox');
    expect(t.lines[35], '  f6 next pane   ctrl+b back');
    await press(t, 'ctrl+b');
    expect(focused(t), 'reply');
    expect(t.lines[35], '  f6 next pane   ctrl+b sidebar');
    // from the header, back to the header
    await press(t, 'f6 f6 ctrl+b');
    expect(focused(t), 'inbox');
    await press(t, 'ctrl+b');
    expect(focused(t), 'title');
  });

  testTwk('collapses the sidebar below a width; Ctrl+B shows it and its '
      'way back hides it again', (t) async {
    await t.pumpWidget(app(collapsedBelow: 100), size: (80, 24));
    await t.pump();
    expect(t.lines[1], startsWith('message'));
    expect(t, styleAt(0, 10, hasBg(background)));
    // not among the zones while collapsed
    await press(t, 'f6 f6 f6');
    expect(focused(t), 'message');

    await press(t, 'ctrl+b');
    expect(focused(t), 'inbox');
    expect(t.lines[1], startsWith('inbox${' ' * 19}message'));
    await press(t, 'tab');
    expect(focused(t), 'sent');
    await press(t, 'ctrl+b');
    expect(focused(t), 'message');
    expect(t.lines[1], startsWith('message'));

    // shown again, it kept its state: the focus where it was
    await press(t, 'ctrl+b');
    expect(focused(t), 'sent');

    // wide, it is shown; narrow again, collapsed
    await t.resize(120, 24);
    await t.pump();
    expect(t.lines[1], startsWith('inbox${' ' * 19}message'));
    await t.resize(80, 24);
    await t.pump();
    expect(t.lines[1], startsWith('message'));
    expect(focused(t), 'message');
  });

  testTwk("the header's toggle hides a shown sidebar and shows a hidden one", (
    t,
  ) async {
    await t.pumpWidget(app(), size: (120, 36));
    await t.pump();
    await press(t, 'ctrl+b');
    expect(focused(t), 'inbox');
    await t.click(2, 0);
    await t.pump();
    expect(t.lines[1], startsWith('message'));
    // the focus left the sidebar
    expect(focused(t), 'message');
    await t.click(2, 0);
    await t.pump();
    expect(t.lines[1], startsWith('inbox${' ' * 19}message'));
    expect(focused(t), 'message');
  });

  testTwk('a resizable sidebar: its divider dragged with the left button '
      'resizes it, between 4 columns and all but 10', (t) async {
    final widths = <int>[];
    await t.pumpWidget(
      app(resizable: true, onResized: widths.add),
      size: (80, 24),
    );
    await t.pump();
    expect(t.lines[1], startsWith('inbox${' ' * 19}│message'));
    expect(t, styleAt(24, 10, hasFg(ThemeData.dark.faint.fg!)));

    await t.mouse(MouseKind.down, 24, 10);
    await t.pump();
    expect(t, styleAt(24, 10, hasFg(ThemeData.dark.primary.fg!)));
    await t.mouse(MouseKind.drag, 30, 10);
    await t.pump();
    expect(t.lines[1], startsWith('inbox${' ' * 25}│message'));
    await t.mouse(MouseKind.up, 30, 10);
    await t.pump();
    expect(widths, [30]);

    await t.mouse(MouseKind.down, 30, 5);
    await t.mouse(MouseKind.drag, 0, 5);
    await t.mouse(MouseKind.up, 0, 5);
    await t.pump();
    expect(t.lines[3], startsWith('sent│'));
    await t.mouse(MouseKind.down, 4, 5);
    await t.mouse(MouseKind.drag, 79, 5);
    await t.mouse(MouseKind.up, 79, 5);
    await t.pump();
    expect(t.lines[2], '${'sent'.padRight(69)}│reply');
    expect(widths, [30, 4, 69]);

    // a right button drags nothing
    await t.mouse(MouseKind.down, 69, 5, button: 2);
    await t.mouse(MouseKind.drag, 40, 5, button: 2);
    await t.mouse(MouseKind.up, 40, 5, button: 2);
    await t.pump();
    expect(t.lines[2], '${'sent'.padRight(69)}│reply');
  });

  testTwk('a sidebar not resizable has no divider', (t) async {
    await t.pumpWidget(app(), size: (80, 24));
    await t.pump();
    await t.mouse(MouseKind.down, 24, 10);
    await t.mouse(MouseKind.drag, 30, 10);
    await t.mouse(MouseKind.up, 30, 10);
    await t.pump();
    expect(t.lines[1], startsWith('inbox${' ' * 19}message'));
  });

  testTwk("the hints show the keys of the focus, then the frame's; none "
      'without keyHints', (t) async {
    await t.pumpWidget(
      Scaffold(
        body: KeyBindings(
          const {'d': _nothing},
          hints: const {'d': 'delete'},
          child: field('list'),
        ),
      ),
      size: (40, 5),
    );
    await t.pump();
    expect(focused(t), 'list');
    // one zone and no sidebar: no keys of the frame's
    expect(t.lines[4], '  d delete');

    await t.pumpWidget(app(keyHints: false), size: (80, 24));
    await t.pump();
    expect(t.lines[23], 'ready${' ' * 70}12:00');
  });
}

void _nothing() {}
