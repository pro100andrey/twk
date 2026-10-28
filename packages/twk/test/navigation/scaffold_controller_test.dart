// The scaffold's controller: the sidebar shown, hidden and toggled by the
// app, its width set and read back after a drag or a key, the zones
// focused by it; and the keys that resize the sidebar while it has the
// focus.
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

/// An app in a scaffold of every part, as scaffold_test.dart's.
Widget app({
  ScaffoldController? controller,
  int sidebarWidth = 24,
  SidebarSide side = SidebarSide.left,
  bool resizable = false,
  int? collapsedBelow,
  void Function(int width)? onResized,
  Widget? body,
}) => Theme(
  data: ThemeData.dark,
  child: Scaffold(
    controller: controller,
    header: field('title'),
    sidebar: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [field('inbox'), field('sent')],
    ),
    body:
        body ??
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [field('message'), field('reply')],
        ),
    statusBar: StatusBar(left: field('ready'), right: const Text('12:00')),
    sidebarWidth: sidebarWidth,
    sidebarSide: side,
    resizableSidebar: resizable,
    collapsedBelow: collapsedBelow,
    onSidebarResized: onResized,
  ),
);

/// Whether row 1 shows the sidebar [width] columns wide, a divider after
/// it when [divider].
Matcher shows(int width, {bool divider = false}) =>
    startsWith('${'inbox'.padRight(width)}${divider ? '│' : ''}message');

void main() {
  testTwk('the app shows, hides and toggles the sidebar; the focus leaves '
      'it hidden', (t) async {
    final c = ScaffoldController();
    var told = 0;
    c.addListener(() => told++);
    await t.pumpWidget(app(controller: c), size: (120, 36));
    await t.pump();
    expect(c.sidebarOpen, isTrue);
    expect(t.lines[1], shows(24));

    await press(t, 'tab ctrl+b');
    expect(focused(t), 'inbox');
    c.sidebarOpen = false;
    await t.pump();
    expect(told, 1);
    expect(t.lines[1], startsWith('message'));
    // back where it came from
    expect(focused(t), 'reply');
    // hidden, it is no zone of F6's
    await press(t, 'f6 f6 f6');
    expect(focused(t), 'reply');

    c.toggleSidebar();
    await t.pump();
    expect(c.sidebarOpen, isTrue);
    expect(told, 2);
    expect(t.lines[1], shows(24));
    // set as it is, nothing changes
    c.sidebarOpen = true;
    expect(told, 2);
  });

  testTwk('hidden with the focus it had first, the sidebar leaves it to the '
      'body', (t) async {
    final c = ScaffoldController();
    await t.pumpWidget(
      Scaffold(
        controller: c,
        sidebar: field('inbox'),
        body: const Text('nothing to focus'),
      ),
      size: (60, 10),
    );
    await t.pump();
    expect(focused(t), 'inbox');
    c.sidebarOpen = false;
    await t.pump();
    expect(c.focusedZone, ScaffoldZone.body);
  });

  testTwk("the header's toggle and Ctrl+B tell the controller; Ctrl+B's way "
      'back hides again a sidebar the user hid', (t) async {
    final c = ScaffoldController();
    final open = <bool>[];
    c.addListener(() => open.add(c.sidebarOpen));
    await t.pumpWidget(app(controller: c), size: (120, 36));
    await t.pump();
    await t.click(2, 0);
    await t.pump();
    expect(open, [false]);
    expect(t.lines[1], startsWith('message'));

    await press(t, 'ctrl+b');
    expect(focused(t), 'inbox');
    expect(c.sidebarOpen, isTrue);
    expect(t.lines[1], shows(24));
    await press(t, 'ctrl+b');
    expect(focused(t), 'message');
    expect(c.sidebarOpen, isFalse);
    expect(t.lines[1], startsWith('message'));
    expect(open, [false, true, false]);
  });

  testTwk('with collapsedBelow: closed while narrow, opened by the app, and '
      'put back as the width has it when it crosses the threshold, which '
      'the listeners are told', (t) async {
    final c = ScaffoldController();
    final open = <bool>[];
    c.addListener(() => open.add(c.sidebarOpen));
    await t.pumpWidget(app(controller: c, collapsedBelow: 100), size: (80, 24));
    await t.pump();
    expect(c.sidebarOpen, isFalse);
    expect(open, isEmpty);

    c.sidebarOpen = true;
    await t.pump();
    expect(t.lines[1], shows(24));
    await t.resize(120, 24);
    await t.pump();
    await t.pump();
    expect(c.sidebarOpen, isTrue);
    expect(open, [true]);
    await t.resize(80, 24);
    await t.pump();
    await t.pump();
    expect(c.sidebarOpen, isFalse);
    expect(open, [true, false]);
    expect(t.lines[1], startsWith('message'));
  });

  testTwk('a controller made open shows the sidebar on a narrow screen '
      'from the first frame', (t) async {
    final c = ScaffoldController(sidebarOpen: true, sidebarWidth: 12);
    await t.pumpWidget(app(controller: c, collapsedBelow: 100), size: (80, 24));
    await t.pump();
    expect(c.sidebarOpen, isTrue);
    expect(t.lines[1], shows(12));
  });

  testTwk("the controller's width is the sidebar's: set by the app, and by a "
      'drag, for the app to keep', (t) async {
    final c = ScaffoldController(sidebarWidth: 10);
    final widths = <int>[];
    c.addListener(() => widths.add(c.sidebarWidth));
    await t.pumpWidget(
      app(controller: c, resizable: true, sidebarWidth: 30),
      size: (80, 24),
    );
    await t.pump();
    // the controller's, not sidebarWidth
    expect(t.lines[1], shows(10, divider: true));

    c.sidebarWidth = 16;
    await t.pump();
    expect(t.lines[1], shows(16, divider: true));
    await t.mouse(MouseKind.down, 16, 10);
    await t.mouse(MouseKind.drag, 20, 10);
    await t.mouse(MouseKind.up, 20, 10);
    await t.pump();
    expect(c.sidebarWidth, 20);
    expect(t.lines[1], shows(20, divider: true));
    expect(widths, [16, 20]);

    // wider than the screen, cut to it
    c.sidebarWidth = 200;
    await t.pump();
    expect(c.sidebarWidth, 200);
    expect(t.lines[2], '${'sent'.padRight(79)}│');
    expect(() => c.sidebarWidth = -1, throwsRangeError);
  });

  testTwk('without a controller a new sidebarWidth still resets the width', (
    t,
  ) async {
    await t.pumpWidget(app(resizable: true), size: (80, 24));
    await t.pump();
    await t.mouse(MouseKind.down, 24, 10);
    await t.mouse(MouseKind.drag, 28, 10);
    await t.mouse(MouseKind.up, 28, 10);
    await t.pump();
    expect(t.lines[1], shows(28, divider: true));
    await t.pumpWidget(app(resizable: true, sidebarWidth: 12));
    await t.pump();
    expect(t.lines[1], shows(12, divider: true));
  });

  testTwk('a controller swapped for another: the new one is the one obeyed', (
    t,
  ) async {
    final a = ScaffoldController(sidebarWidth: 10);
    final b = ScaffoldController(sidebarWidth: 14);
    await t.pumpWidget(app(controller: a), size: (80, 24));
    await t.pump();
    await t.pumpWidget(app(controller: b));
    await t.pump();
    expect(t.lines[1], shows(14));
    a.sidebarOpen = false;
    await t.pump();
    expect(t.lines[1], shows(14));
    expect(a.focusZone(ScaffoldZone.header), isFalse);
    b.sidebarOpen = false;
    await t.pump();
    expect(t.lines[1], startsWith('message'));
  });

  testTwk('focusZone focuses a zone, showing a hidden sidebar as Ctrl+B '
      'does; focusedZone says which has the focus', (t) async {
    final c = ScaffoldController();
    expect(c.focusZone(ScaffoldZone.body), isFalse);
    expect(c.focusedZone, isNull);
    await t.pumpWidget(app(controller: c, collapsedBelow: 100), size: (80, 24));
    await t.pump();
    expect(c.focusedZone, ScaffoldZone.body);

    expect(c.focusZone(ScaffoldZone.statusBar), isTrue);
    await t.pump();
    expect(focused(t), 'ready');
    expect(c.focusedZone, ScaffoldZone.statusBar);
    expect(c.focusZone(ScaffoldZone.header), isTrue);
    await t.pump();
    expect(focused(t), 'title');

    expect(c.focusZone(ScaffoldZone.sidebar), isTrue);
    await t.pump();
    expect(focused(t), 'inbox');
    expect(c.focusedZone, ScaffoldZone.sidebar);
    expect(t.lines[1], shows(24));
    // Ctrl+B's way back, to the header and the sidebar hidden again
    await press(t, 'ctrl+b');
    expect(focused(t), 'title');
    expect(t.lines[1], startsWith('message'));

    // a zone the scaffold does not have
    await t.pumpWidget(
      Scaffold(controller: c, body: field('list')),
      size: (40, 5),
    );
    await t.pump();
    expect(c.focusZone(ScaffoldZone.header), isFalse);
    expect(c.focusZone(ScaffoldZone.sidebar), isFalse);
  });

  testTwk('Alt+, and Alt+. move the divider of a resizable sidebar while it '
      'has the focus, between 4 columns and all but 10; the hints name '
      'them', (t) async {
    final widths = <int>[];
    await t.pumpWidget(
      app(resizable: true, sidebarWidth: 6, onResized: widths.add),
      size: (80, 24),
    );
    await t.pump();
    // the body has the focus: no keys of the sidebar's
    expect(t.lines[23], '  f6 next pane   ctrl+b sidebar');
    await press(t, 'alt+.');
    expect(t.lines[1], shows(6, divider: true));

    await press(t, 'ctrl+b');
    expect(
      t.lines[23],
      '  f6 next pane   ctrl+b back   alt+, narrower   alt+. wider',
    );
    await press(t, 'alt+. alt+.');
    expect(t.lines[1], shows(8, divider: true));
    await press(t, 'alt+, alt+, alt+, alt+, alt+,');
    expect(t.lines[1], startsWith('inbo│message'));
    expect(widths, [7, 8, 7, 6, 5, 4]);
    for (var i = 0; i < 70; i++) {
      await t.press('alt+.');
    }
    await t.pump();
    expect(t.lines[2], '${'sent'.padRight(69)}│reply');
    expect(widths.last, 69);
    expect(widths, hasLength(71));
  });

  testTwk('on the right, Alt+, widens the sidebar and Alt+. narrows it', (
    t,
  ) async {
    final c = ScaffoldController(sidebarWidth: 20);
    await t.pumpWidget(
      app(controller: c, resizable: true, side: SidebarSide.right),
      size: (80, 24),
    );
    await t.pump();
    await press(t, 'ctrl+b');
    expect(
      t.lines[23],
      '  f6 next pane   ctrl+b back   alt+, wider   alt+. narrower',
    );
    await press(t, 'alt+, alt+,');
    expect(c.sidebarWidth, 22);
    expect(t.lines[1], '${'message'.padRight(57)}│inbox');
    await press(t, 'alt+.');
    expect(c.sidebarWidth, 21);
  });

  testTwk('a sidebar not resizable takes no Alt+, or Alt+.: they reach the '
      'layers around the scaffold', (t) async {
    final keys = <String>[];
    await t.pumpWidget(
      KeyBindings(
        {'alt+,': () => keys.add(','), 'alt+.': () => keys.add('.')},
        child: app(),
      ),
      size: (80, 24),
    );
    await t.pump();
    await press(t, 'ctrl+b alt+, alt+.');
    expect(focused(t), 'inbox');
    expect(keys, [',', '.']);
    expect(t.lines[1], shows(24));
    expect(t.lines[23], '  f6 next pane   ctrl+b back');
  });

  testTwk('a text field in the sidebar keeps Ctrl+Left and Alt+Left', (
    t,
  ) async {
    final text = TextEditingController(text: 'two words');
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: Scaffold(
          sidebar: TextField(controller: text),
          body: field('message'),
          resizableSidebar: true,
        ),
      ),
      size: (80, 24),
    );
    await t.pump();
    await press(t, 'ctrl+b end ctrl+left');
    expect(text.selection.baseOffset, 4);
    await press(t, 'alt+left');
    expect(text.selection.baseOffset, 0);
    // and Alt+. resizes it still
    await press(t, 'alt+.');
    expect(t.lines[0], startsWith('${'two words'.padRight(25)}│'));
  });

  testTwk('a controller taken away leaves the scaffold one of its own, of '
      'its sidebarWidth; focusZone(body) focuses the body', (t) async {
    final c = ScaffoldController(sidebarWidth: 10);
    await t.pumpWidget(app(controller: c), size: (80, 24));
    await t.pump();
    expect(t.lines[1], shows(10));
    expect(c.focusZone(ScaffoldZone.header), isTrue);
    await t.pump();
    expect(c.focusZone(ScaffoldZone.body), isTrue);
    await t.pump();
    expect(focused(t), 'message');
    await t.pumpWidget(app(sidebarWidth: 16));
    await t.pump();
    expect(t.lines[1], shows(16));
    expect(c.focusZone(ScaffoldZone.header), isFalse);
  });

  testTwk('a sidebar Ctrl+B showed on a narrow screen, taken away, leaves '
      'the controller as it was before Ctrl+B', (t) async {
    final c = ScaffoldController();
    await t.pumpWidget(app(controller: c, collapsedBelow: 100), size: (80, 24));
    await t.pump();
    expect(c.sidebarOpen, isFalse);
    await press(t, 'ctrl+b');
    expect(c.sidebarOpen, isTrue);
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: Scaffold(
          controller: c,
          collapsedBelow: 100,
          body: field('message'),
        ),
      ),
    );
    await t.pump();
    expect(c.sidebarOpen, isFalse);
  });
}
