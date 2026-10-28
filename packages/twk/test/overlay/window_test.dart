// Floating windows in a WindowLayer: frames over the layer's child, the
// one in front painted last; brought to the front by a press and by the
// focus, Tab going through them in their order; moved by the title bar,
// resized by the edges and corners, both by the keys too; minimised to the
// strip, maximised, closed; kept in the layer as it shrinks; their state
// kept; what repaints alone behind a window; a decoration around each.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../gestures/shape_run.dart';
import 'windows_closed.dart';

/// Counts what [CounterState.bump] adds, shown as `n=<count>`.
final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => CounterState();
}

final class CounterState extends State<Counter> {
  var count = 0;

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('n=$count');
}

/// Presses and releases each of [keys], apart by spaces, a frame after
/// each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

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

/// Pumps until the windows on their way, maximised, restored or
/// minimised, are where they go.
Future<void> arrive(TwkTester t) => t.pump(const Duration(milliseconds: 200));

/// Where [c] asks its window to be.
(int, int, int, int) rect(WindowController c) =>
    (c.left, c.top, c.width, c.height);

void main() {
  // windows_closed.dart, run in a VM of its own, compiled once
  late String closed;
  setUpAll(
    () async => closed = await compiledProgram(
      'test/overlay/windows_closed.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  testTwk('the windows show over the child in frames, the title on the '
      'top edge and the buttons at its right; the last one in front', (
    t,
  ) async {
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(
              title: 'Alpha',
              controller: WindowController(
                left: 2,
                top: 1,
                width: 20,
                height: 5,
              ),
              onClose: () {},
              child: const Text('alpha body'),
            ),
            Window(
              title: 'Beta',
              controller: WindowController(
                left: 10,
                top: 3,
                width: 20,
                height: 9,
              ),
              maximisable: false,
              child: const Text('beta body'),
            ),
            Window(
              title: 'A long title cut off',
              controller: WindowController(left: 31, width: 9, height: 3),
              minWidth: 3,
              minimisable: false,
              maximisable: false,
              child: const Text('c'),
            ),
          ],
          child: const Text('app'),
        ),
      ),
      size: (40, 12),
    );
    expect(t.lines, [
      'app                            ┌ A lon…┐',
      '  ┌ Alpha ──── _ □ × ┐         │c      │',
      '  │alpha body        │         └───────┘',
      '  │       ┌ Beta ───────── _ ┐',
      '  │       │beta body         │',
      '  └───────│                  │',
      '          │                  │',
      '          │                  │',
      '          │                  │',
      '          │                  │',
      '          │                  │',
      '          └──────────────────┘',
    ]);
  });

  testTwk('a press in a window brings it to the front and gives its title '
      'bar the focus, unless the focus is in it; its border shows it', (
    t,
  ) async {
    final inner = FocusNode();
    final b = WindowController(left: 10, top: 3, width: 20, height: 5);
    addTearDown(inner.dispose);
    addTearDown(b.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(
              title: 'Alpha',
              controller: WindowController(
                left: 2,
                top: 1,
                width: 20,
                height: 5,
              ),
              child: Focus(focusNode: inner, child: const Text('alpha')),
            ),
            Window(title: 'Beta', controller: b, child: const Text('beta')),
          ],
          child: const Text('app'),
        ),
      ),
      size: (40, 12),
    );
    // Beta is in front where they overlap
    expect(t, hasTextAt(10, 3, '┌ Beta'));
    expect(t, styleAt(2, 1, isNot(hasFg(Color.blue))));
    await t.click(5, 4);
    await t.pump();
    expect(t, hasTextAt(10, 3, '           │'));
    expect(t, hasTextAt(2, 1, '┌ Alpha'));
    expect(t, styleAt(2, 1, hasFg(Color.blue)));
    expect(t, styleAt(3, 1, hasBg(const Color.indexed(237))));
    expect(t, styleAt(10, 7, isNot(hasFg(Color.blue))));
    await t.click(25, 6);
    await t.pump();
    expect(t, hasTextAt(10, 3, '┌ Beta'));
    expect(t, styleAt(10, 7, hasFg(Color.blue)));
    expect(t, styleAt(2, 1, isNot(hasFg(Color.blue))));
    inner.requestFocus();
    await t.pump();
    expect(t, hasTextAt(10, 3, '           │'));
    // Beta restored comes to the front, the focus left in Alpha
    b.minimised = true;
    await t.pump();
    b.minimised = false;
    await arrive(t);
    expect(t, hasTextAt(10, 3, '┌ Beta'));
    expect(inner.hasPrimaryFocus, isTrue);
    // Alpha pressed comes to the front, the focus left where it is
    await t.click(3, 3);
    await t.pump();
    expect(t, hasTextAt(10, 3, '           │'));
    expect(inner.hasPrimaryFocus, isTrue);
    expect(t, styleAt(3, 1, isNot(hasBg(const Color.indexed(237)))));
  });

  testTwk('the border of the window the focus is in is merged with the '
      'focused style', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          focusedStyle: const Style(fg: Color.red),
          windows: [
            Window(
              title: 'Alpha',
              controller: WindowController(width: 20, height: 5),
              child: const Text('alpha'),
            ),
          ],
          child: const Text('app'),
        ),
      ),
      size: (30, 8),
    );
    expect(t, styleAt(19, 4, isNot(hasFg(Color.red))));
    await press(t, 'tab');
    expect(t, styleAt(19, 4, hasFg(Color.red)));
  });

  testTwk("a window without a controller has one of the layer's, at the "
      'top left, 40 by 12, kept as the layer is built again, until it is '
      'given one; one that is not resizable is not', (t) async {
    Widget layer() => const WindowLayer(
      windows: [
        Window(title: 'Alpha', resizable: false, child: Text('alpha')),
      ],
      child: Text('app'),
    );
    await t.pumpWidget(Theme.terminal(child: layer()), size: (50, 14));
    expect(t, hasTextAt(0, 0, '┌ Alpha'));
    expect(t, hasTextAt(39, 11, '┘'));
    await drag(t, 4, 0, [(6, 1)]);
    await t.pumpWidget(Theme.terminal(child: layer()));
    expect(t, hasTextAt(2, 1, '┌ Alpha'));
    expect(t, hasTextAt(41, 12, '┘'));
    // neither its edges nor Shift and the arrows resize it
    await drag(t, 41, 12, [(45, 13)]);
    await drag(t, 2, 5, [(0, 5)]);
    expect(t, hasTextAt(2, 1, '┌ Alpha'));
    expect(t, hasTextAt(41, 12, '┘'));
    await press(t, 'shift+right shift+up');
    expect(t, hasTextAt(41, 12, '┘'));
    expect(
      [for (final k in t.binding.focusManager.activeKeys) '$k'],
      isNot(contains('shift+right wider')),
    );
    final c = WindowController(left: 5, top: 2, width: 20, height: 5);
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(title: 'Alpha', controller: c, child: const Text('alpha')),
          ],
          child: const Text('app'),
        ),
      ),
    );
    expect(t, hasTextAt(5, 2, '┌ Alpha'));
    c.moveTo(7, 3);
    await t.pump();
    expect(t, hasTextAt(7, 3, '┌ Alpha'));
  });

  testTwk('Tab goes through the windows in their order whatever is in '
      'front, the title bar first; each comes to the front as the focus '
      'goes in', (t) async {
    final app = FocusNode();
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(app.dispose);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(
              title: 'Alpha',
              controller: WindowController(
                left: 2,
                top: 1,
                width: 20,
                height: 5,
              ),
              child: Focus(focusNode: a, child: const Text('a')),
            ),
            Window(
              title: 'Beta',
              controller: WindowController(
                left: 10,
                top: 3,
                width: 20,
                height: 5,
              ),
              child: Focus(focusNode: b, child: const Text('b')),
            ),
          ],
          child: Focus(focusNode: app, child: const Text('app')),
        ),
      ),
      size: (40, 12),
    );
    bool alphaInFront() => !t.lines[3].contains('┌ Beta');
    await press(t, 'tab');
    expect(app.hasPrimaryFocus, isTrue);
    expect(alphaInFront(), isFalse);
    await press(t, 'tab');
    // Alpha's title bar
    expect(t, styleAt(3, 1, hasBg(const Color.indexed(237))));
    expect(alphaInFront(), isTrue);
    await press(t, 'tab');
    expect(a.hasPrimaryFocus, isTrue);
    await press(t, 'tab');
    expect(t, styleAt(11, 3, hasBg(const Color.indexed(237))));
    expect(alphaInFront(), isFalse);
    await press(t, 'tab');
    expect(b.hasPrimaryFocus, isTrue);
    await press(t, 'tab');
    expect(app.hasPrimaryFocus, isTrue);
    // Beta in front, Tab still goes to Alpha first
    await press(t, 'tab');
    expect(alphaInFront(), isTrue);
    expect(t, styleAt(3, 1, hasBg(const Color.indexed(237))));
    await press(t, 'shift+tab');
    expect(app.hasPrimaryFocus, isTrue);
    await press(t, 'shift+tab');
    expect(b.hasPrimaryFocus, isTrue);
    expect(alphaInFront(), isFalse);
    await press(t, 'shift+tab shift+tab');
    expect(a.hasPrimaryFocus, isTrue);
    expect(alphaInFront(), isTrue);
  });

  testTwk('the title bar dragged moves the window, kept in the layer', (
    t,
  ) async {
    final c = WindowController(left: 2, top: 1, width: 20, height: 5);
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(title: 'Alpha', controller: c, child: const Text('alpha')),
          ],
          child: const Text('app'),
        ),
      ),
      size: (40, 12),
    );
    await drag(t, 8, 1, [(9, 1), (12, 3)]);
    expect(rect(c), (6, 3, 20, 5));
    expect(t, hasTextAt(6, 3, '┌ Alpha'));
    expect(t, hasTextAt(7, 4, 'alpha'));
    // the window moved under the mouse: the drag goes on from where it is
    await drag(t, 12, 3, [(39, 11)]);
    expect(rect(c), (20, 7, 20, 5));
    expect(t, hasTextAt(20, 7, '┌ Alpha'));
    await drag(t, 30, 7, [(0, 0)]);
    expect(rect(c), (0, 0, 20, 5));
  });

  testTwk('an edge or a corner dragged resizes the window from it, within '
      'its least size and the layer', (t) async {
    final c = WindowController(left: 10, top: 3, width: 16, height: 6);
    addTearDown(c.dispose);
    final layer = WindowLayer(
      windows: [
        Window(title: 'Alpha', controller: c, child: const Text('alpha')),
      ],
      child: const Text('app'),
    );
    await t.pumpWidget(Theme.terminal(child: layer), size: (40, 12));
    Future<(int, int, int, int)> from(int x, int y, int toX, int toY) async {
      c
        ..moveTo(10, 3)
        ..resizeTo(16, 6);
      await t.pump();
      await drag(t, x, y, [(toX, toY)]);
      return rect(c);
    }

    // the cells of the window: 10..25 across, 3..8 down
    expect(await from(10, 5, 8, 6), (8, 3, 18, 6));
    expect(await from(25, 5, 28, 4), (10, 3, 19, 6));
    expect(await from(15, 8, 14, 10), (10, 3, 16, 8));
    expect(await from(10, 3, 12, 4), (12, 4, 14, 5));
    expect(await from(25, 3, 27, 2), (10, 2, 18, 7));
    expect(await from(10, 8, 9, 9), (9, 3, 17, 7));
    expect(await from(25, 8, 29, 10), (10, 3, 20, 8));
    expect(t, hasTextAt(10, 3, '┌ Alpha'));
    expect(t, hasTextAt(29, 10, '┘'));
    // the least size: 12 by 3 by default
    expect(await from(25, 5, 0, 5), (10, 3, 12, 6));
    expect(await from(10, 3, 39, 11), (14, 6, 12, 3));
    // the layer's edges
    expect(await from(25, 8, 39, 11), (10, 3, 30, 9));
    expect(await from(10, 3, 0, 0), (0, 0, 26, 9));
    // those of a layer smaller than the screen
    await t.pumpWidget(
      Theme.terminal(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 30, height: 10, child: layer),
        ),
      ),
    );
    expect(await from(25, 8, 39, 11), (10, 3, 20, 7));
  });

  testTwk('the keys on the title bar move the window, resize it, maximise '
      'and restore it, minimise and close it', (t) async {
    final c = WindowController(left: 2, top: 1, width: 20, height: 5);
    addTearDown(c.dispose);
    var closed = 0;
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(
              title: 'Alpha',
              controller: c,
              onClose: () => closed++,
              child: const Text('alpha'),
            ),
          ],
          child: const Text('app'),
        ),
      ),
      size: (40, 12),
    );
    await press(t, 'tab');
    expect(
      [for (final k in t.binding.focusManager.activeKeys) '$k'],
      [
        'left window left',
        'right window right',
        'up window up',
        'down window down',
        'shift+left narrower',
        'shift+right wider',
        'shift+up shorter',
        'shift+down taller',
        'enter maximise',
        'm minimise',
        'x close',
      ],
    );
    await press(t, 'right down down');
    expect(rect(c), (3, 3, 20, 5));
    await press(t, 'shift+right shift+down shift+up shift+up');
    expect(rect(c), (3, 3, 21, 4));
    await press(t, 'shift+left');
    expect(rect(c), (3, 3, 20, 4));
    // keys in one read move on from where the one before left it
    await t.input(utf8.encode('\x1b[D\x1b[D\x1b[D'));
    await t.pump();
    expect(rect(c), (0, 3, 20, 4));
    await press(t, 'left up up up up');
    expect(rect(c), (0, 0, 20, 4));
    await press(t, 'right right down');
    expect(rect(c), (2, 1, 20, 4));
    await press(t, 'enter');
    await arrive(t);
    expect(c.maximised, isTrue);
    expect(t, hasTextAt(0, 0, '┌ Alpha'));
    expect(t, hasTextAt(39, 11, '┘'));
    expect(
      [for (final k in t.binding.focusManager.activeKeys) '$k'],
      contains('enter restore'),
    );
    // a maximised window does not move nor resize
    await press(t, 'right shift+left');
    expect(rect(c), (2, 1, 20, 4));
    await press(t, 'enter');
    await arrive(t);
    expect(c.maximised, isFalse);
    expect(t, hasTextAt(2, 1, '┌ Alpha'));
    expect(t, hasTextAt(21, 4, '┘'));
    await press(t, 'x');
    expect(closed, 1);
    await press(t, 'm');
    await arrive(t);
    expect(c.minimised, isTrue);
    expect(t, isNot(containsLine(contains('┌ Alpha'))));
  });

  testTwk('the buttons minimise, maximise, restore and close the window; a '
      'double click on the title bar maximises and restores it', (t) async {
    final c = WindowController(left: 2, top: 1, width: 20, height: 5);
    addTearDown(c.dispose);
    var closed = 0;
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(
              title: 'Alpha',
              controller: c,
              onClose: () => closed++,
              child: const Text('alpha'),
            ),
          ],
          child: const Text('app'),
        ),
      ),
      size: (40, 12),
    );
    // ┌ Alpha ──── _ □ × ┐ from column 2: the buttons at 15, 17 and 19
    expect(t, hasTextAt(14, 1, ' _ □ × ┐'));
    await t.click(19, 1);
    await t.pump();
    expect(closed, 1);
    await t.click(17, 1);
    await arrive(t);
    expect(c.maximised, isTrue);
    expect(t, hasTextAt(0, 0, '┌ Alpha'));
    expect(t, hasTextAt(32, 0, ' _ ▣ × ┐'));
    await t.click(35, 0);
    await arrive(t);
    expect(c.maximised, isFalse);
    expect(t, hasTextAt(2, 1, '┌ Alpha'));
    await t.click(8, 1);
    await t.click(8, 1);
    await arrive(t);
    expect(c.maximised, isTrue);
    // a maximised window does not move nor resize
    await drag(t, 8, 0, [(12, 3)]);
    await drag(t, 39, 11, [(30, 8)]);
    expect(rect(c), (2, 1, 20, 5));
    await t.click(8, 0);
    await t.click(8, 0);
    await arrive(t);
    expect(c.maximised, isFalse);
    await t.click(15, 1);
    await t.pump();
    expect(c.minimised, isTrue);
    expect(closed, 1);
  });

  testTwk('a minimised window is a chip in the strip, not shown, hit nor '
      'focusable, its state kept; the chip restores it to the front, its '
      'title bar focused', (t) async {
    final a = WindowController(left: 2, top: 1, width: 20, height: 5);
    final b = WindowController(left: 10, top: 3, width: 20, height: 9);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final counter = GlobalKey<CounterState>();
    final app = FocusNode();
    addTearDown(app.dispose);
    var pressed = 0;
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(
              title: 'Alpha',
              controller: a,
              child: Counter(key: counter),
            ),
            Window(title: 'Beta', controller: b, child: const Text('beta')),
          ],
          child: Listener(
            onDown: (_) => pressed++,
            behavior: HitTestBehavior.opaque,
            child: Focus(focusNode: app, child: const SizedBox.expand()),
          ),
        ),
      ),
      size: (40, 12),
    );
    final state = counter.currentState!..bump();
    await t.pump();
    a.minimised = true;
    await arrive(t);
    expect(t, isNot(containsLine(contains('Alpha ─'))));
    expect(t.lines.last, ' Alpha');
    // Beta, in the room above the strip, is moved up a row
    expect(t, hasTextAt(10, 2, '┌ Beta'));
    expect(rect(b), (10, 3, 20, 9));
    await t.click(3, 1);
    await t.pump();
    expect(pressed, 1);
    await press(t, 'tab');
    expect(app.hasPrimaryFocus, isTrue);
    await press(t, 'tab');
    // Beta's title bar: Alpha is passed by
    expect(t, styleAt(11, 2, hasBg(const Color.indexed(237))));
    await press(t, 'tab');
    expect(t, styleAt(0, 11, hasBg(const Color.indexed(237))));
    await press(t, 'enter');
    await arrive(t);
    expect(a.minimised, isFalse);
    expect(t, hasTextAt(2, 1, '┌ Alpha'));
    expect(t, styleAt(3, 1, hasBg(const Color.indexed(237))));
    expect(t, hasTextAt(3, 2, 'n=1'));
    expect(identical(counter.currentState, state), isTrue);
    // in front of Beta
    expect(t, hasTextAt(10, 3, '           │'));
    b.minimised = true;
    a.minimised = true;
    await arrive(t);
    expect(t.lines.last, ' Beta   Alpha');
    await t.click(9, 11);
    await arrive(t);
    expect(a.minimised, isFalse);
    expect(t.lines.last, ' Beta');
    expect(t, styleAt(3, 1, hasBg(const Color.indexed(237))));
  });

  testTwk('the layer getting smaller moves and shrinks the windows into it; '
      'bigger, it shows them where they were', (t) async {
    final c = WindowController(left: 25, top: 6, width: 15, height: 6);
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(title: 'Alpha', controller: c, child: const Text('alpha')),
          ],
          child: const Text('app'),
        ),
      ),
      size: (40, 12),
    );
    expect(t, hasTextAt(25, 6, '┌ Alpha'));
    await t.resize(30, 10);
    await t.pump();
    expect(t, hasTextAt(15, 4, '┌ Alpha'));
    expect(t, hasTextAt(29, 9, '┘'));
    await t.resize(12, 5);
    await t.pump();
    expect(t.lines, [
      '┌ Alp… _ □ ┐',
      '│alpha     │',
      '│          │',
      '│          │',
      '└──────────┘',
    ]);
    await t.resize(40, 12);
    await t.pump();
    expect(t, hasTextAt(25, 6, '┌ Alpha'));
    expect(rect(c), (25, 6, 15, 6));
  });

  testTwk("a window's state is kept as it moves, comes to the front, is "
      'maximised and as the windows change around it, one added coming to '
      'the front; its child moves out of it by a GlobalKey', (t) async {
    final a = WindowController(left: 2, top: 1, width: 20, height: 5);
    final b = WindowController(left: 10, top: 3, width: 20, height: 5);
    final c = WindowController(left: 6, top: 2, width: 20, height: 5);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(c.dispose);
    Window alpha([Widget child = const Counter()]) => Window(
      key: const ValueKey('a'),
      title: 'Alpha',
      controller: a,
      child: child,
    );
    Window beta() => Window(
      key: const ValueKey('b'),
      title: 'Beta',
      controller: b,
      child: const Text('beta'),
    );
    Widget layer(List<Window> windows, [Widget child = const Text('app')]) =>
        WindowLayer(windows: windows, child: child);
    CounterState counter() => t.state<CounterState>(find.byType(Counter));
    await t.pumpWidget(
      Theme.terminal(child: layer([alpha(), beta()])),
      size: (40, 12),
    );
    final state = counter()..bump();
    await drag(t, 8, 1, [(9, 2)]);
    a.maximised = true;
    await t.pump();
    a.maximised = false;
    await t.click(25, 5);
    await arrive(t);
    expect(t, hasTextAt(4, 3, 'n=1'));
    expect(identical(counter(), state), isTrue);
    // a window added comes to the front, one taken out goes
    await t.pumpWidget(
      Theme.terminal(
        child: layer([
          beta(),
          Window(
            key: const ValueKey('c'),
            title: 'Gamma',
            controller: c,
            child: const Text('gamma'),
          ),
          alpha(),
        ]),
      ),
    );
    expect(t, hasTextAt(6, 2, '┌ Gamma'));
    expect(t, hasTextAt(7, 3, 'gamma'));
    expect(identical(counter(), state), isTrue);
    await t.pumpWidget(Theme.terminal(child: layer([alpha()])));
    expect(t, isNot(containsLine(contains('Beta'))));
    expect(t, isNot(containsLine(contains('Gamma'))));
    expect(t, hasTextAt(4, 3, 'n=1'));
    expect(identical(counter(), state), isTrue);
    final moved = GlobalKey<CounterState>();
    await t.pumpWidget(
      Theme.terminal(child: layer([alpha(Counter(key: moved))])),
    );
    final kept = moved.currentState!..bump();
    await t.pumpWidget(Theme.terminal(child: layer([], Counter(key: moved))));
    expect(identical(moved.currentState, kept), isTrue);
    expect(t.lines.first, 'n=1');
  });

  testTwk(
    'keyed windows closed by their buttons and opened again',
    closeAndReopen,
  );

  test('the layer keeps its windows without asserts, as an app runs', () async {
    final run = await runProcess(Platform.resolvedExecutable, [closed]);
    expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
  });

  testTwk('what repaints on its own in a window is painted over by the '
      'windows in front of it, and not seen once it is minimised', (t) async {
    final alpha = WindowController(width: 6, height: 3);
    addTearDown(alpha.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(title: 'Alpha', controller: alpha, child: const Spinner()),
            Window(
              title: 'Beta',
              controller: WindowController(
                left: 1,
                top: 1,
                width: 14,
                height: 4,
              ),
              child: const Text('beta'),
            ),
          ],
          // a spinner in sight, so that frames are written
          child: const Align(
            alignment: Alignment.bottomRight,
            child: Spinner(),
          ),
        ),
      ),
      size: (20, 6),
    );
    expect(t, hasTextAt(0, 0, '┌'));
    expect(t, hasTextAt(1, 1, '┌ Beta'));
    final frames = t.terminal.frames.length;
    await t.pump(const Duration(milliseconds: 500));
    expect(t.terminal.frames.length, greaterThan(frames));
    expect(t, hasTextAt(1, 1, '┌ Beta'));
    // minimised, it repaints out of sight
    alpha.minimised = true;
    await t.pump(const Duration(milliseconds: 500));
    expect(t, hasTextAt(1, 1, '┌ Beta'));
  });

  testTwk('decorate builds what each window is shown in, over its cells '
      'and the margin; the mouse goes through the margin to what is under '
      'it', (t) async {
    var pressed = 0;
    final c = WindowController(left: 2, top: 1, width: 12, height: 3);
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          margin: const EdgeInsets.only(right: 1, bottom: 1),
          decorate: (context, window) => Stack(
            children: [
              Positioned(
                left: 1,
                top: 1,
                right: 0,
                bottom: 0,
                child: Text('#' * 39, wrap: TextWrap.grapheme),
              ),
              Positioned.fill(child: window),
            ],
          ),
          windows: [
            Window(title: 'Alpha', controller: c, child: const Text('alpha')),
          ],
          child: Listener(
            onDown: (_) => pressed++,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
      ),
      size: (20, 6),
    );
    expect(t.lines.sublist(0, 5), [
      '',
      '  ┌ Alp… _ □ ┐',
      '  │alpha     │#',
      '  └──────────┘#',
      '   ############',
    ]);
    await t.click(14, 1);
    await t.pump();
    expect(pressed, 1);
    await drag(t, 6, 1, [(7, 1)]);
    expect(rect(c), (3, 1, 12, 3));
    expect(pressed, 1);
  });

  group('the pointer', () {
    /// A layer with a window of [c], 14 × 4 cells, its title bar between
    /// columns 3 and 9 of the top row, its buttons after it.
    Widget layer(WindowController c, {bool pointerShapes = true}) =>
        WindowLayer(
          windows: [
            Window(
              title: 'w',
              controller: c,
              pointerShapes: pointerShapes,
              child: const Text('body'),
            ),
          ],
          child: const SizedBox(),
        );

    test('grab over the title bar, grabbing while it moves the window, '
        'the resize shapes over the edges and the corners; none while it '
        'is maximised', () async {
      final c = WindowController(left: 2, top: 1, width: 14, height: 4);
      final run = ShapeRun(layer(c), width: 30, height: 8);
      await run.settle();
      final shapes = <String>[];
      for (final (x, y) in [
        (5, 1),
        (2, 2),
        (2, 4),
        (6, 4),
        (15, 4),
        (15, 3),
        (15, 1),
        (2, 1),
        (6, 2),
        (12, 1),
        (5, 1),
      ]) {
        await run.move(x, y);
        shapes.add(run.shapes().join(' '));
      }
      expect(shapes, [
        'grab',
        'ew-resize',
        'nesw-resize',
        'ns-resize',
        'nwse-resize',
        'ew-resize',
        'nesw-resize',
        'nwse-resize',
        // the body, and the buttons
        '',
        '',
        'grab',
      ]);
      await run.press(5, 1);
      await run.drag(6, 1);
      expect(rect(c), (3, 1, 14, 4));
      expect(run.shapes(), ['grabbing']);
      await run.release(6, 1);
      expect(run.shapes(), ['grab']);
      await run.act(() => c.maximised = true);
      expect(run.shapes(), ['']);
      await run.move(5, 0);
      await run.move(0, 3);
      expect(run.shapes(), isEmpty);
      await run.quit();
      c.dispose();
    });

    test('left alone with pointerShapes false', () async {
      final c = WindowController(left: 2, top: 1, width: 14, height: 4);
      final run = ShapeRun(
        layer(c, pointerShapes: false),
        width: 30,
        height: 8,
      );
      await run.settle();
      for (final (x, y) in [(5, 1), (2, 2), (6, 4), (15, 4)]) {
        await run.move(x, y);
      }
      await run.quit();
      expect(run.written(), isNot(contains('\x1b]22;')));
      c.dispose();
    });
  });

  group('a raised frame', () {
    const dark = ThemeData.dark;
    // the dark theme's surface 0.08 of the way to its text
    const bar = Color.rgb(50, 53, 59);
    final surface = dark.surface.bg!;
    final muted = dark.muted.fg!;
    final primary = dark.primary.fg!;
    final text = dark.text.fg!;
    final error = dark.error.fg!;
    final selection = dark.selection.bg!;

    /// Alpha at 2, 1, 20 × 5, closed by [onClose], its child a node of
    /// its own, [inner]; under [theme].
    Widget layer(
      WindowController c,
      FocusNode inner, {
      ThemeData theme = dark,
      WindowFrame? frame,
    }) => Theme(
      data: theme,
      child: WindowLayer(
        frame: frame,
        windows: [
          Window(
            title: 'Alpha',
            controller: c,
            onClose: () {},
            child: Focus(focusNode: inner, child: const Text('alpha')),
          ),
        ],
        child: const Text('app'),
      ),
    );

    testTwk('is the surface without an outline, the title bar raised, the '
        'title bold and muted, primary while the focus is in the window; '
        'the bar the selection with a mark while it has the focus', (
      t,
    ) async {
      final c = WindowController(left: 2, top: 1, width: 20, height: 5);
      final inner = FocusNode();
      addTearDown(c.dispose);
      addTearDown(inner.dispose);
      await t.pumpWidget(
        Theme.terminal(child: layer(c, inner)),
        size: (40, 12),
      );
      expect(t.lines.take(6), [
        'app',
        '    Alpha      ─ □ ×',
        '   alpha',
        '',
        '',
        '',
      ]);
      for (final x in [2, 3, 10, 14, 20, 21]) {
        expect(t, styleAt(x, 1, hasBg(bar)));
      }
      for (final (x, y) in [(2, 2), (21, 3), (10, 5), (21, 5)]) {
        expect(t, styleAt(x, y, hasBg(surface)));
      }
      expect(t, styleAt(4, 1, allOf(hasFg(muted), hasAttr(Attr.bold))));
      expect(t, styleAt(19, 1, allOf(hasFg(muted), isNot(hasAttr(Attr.bold)))));
      // the title bar focused
      await press(t, 'tab');
      expect(t, hasTextAt(2, 1, '▎ Alpha'));
      expect(t, styleAt(2, 1, allOf(hasFg(primary), hasBg(selection))));
      expect(t, styleAt(4, 1, allOf(hasFg(primary), hasBg(selection))));
      expect(t, styleAt(15, 1, allOf(hasFg(text), hasBg(selection))));
      // the focus in the window, not on its title bar
      await press(t, 'tab');
      expect(inner.hasPrimaryFocus, isTrue);
      expect(t, hasTextAt(2, 1, '  Alpha'));
      expect(t, styleAt(2, 1, hasBg(bar)));
      expect(t, styleAt(4, 1, allOf(hasFg(primary), hasAttr(Attr.bold))));
      expect(t, styleAt(15, 1, hasFg(text)));
    });

    testTwk('is the default where the theme is RGB; bordered where it is '
        'not, and where it is asked for', (t) async {
      final c = WindowController(left: 2, top: 1, width: 20, height: 5);
      final inner = FocusNode();
      addTearDown(c.dispose);
      addTearDown(inner.dispose);
      await t.pumpWidget(
        Theme.terminal(child: layer(c, inner, frame: WindowFrame.bordered)),
        size: (40, 12),
      );
      expect(t, hasTextAt(2, 1, '┌ Alpha ──── _ □ × ┐'));
      expect(t, styleAt(10, 1, hasFg(dark.border.fg!)));
      await t.pumpWidget(
        Theme.terminal(
          child: layer(
            c,
            inner,
            theme: const ThemeData.terminal(Brightness.dark),
          ),
        ),
      );
      expect(t, hasTextAt(2, 1, '┌ Alpha ──── _ □ × ┐'));
      await t.pumpWidget(
        Theme.terminal(
          child: layer(
            c,
            inner,
            theme: const ThemeData.terminal(Brightness.dark),
            frame: WindowFrame.raised,
          ),
        ),
      );
      expect(t, hasTextAt(2, 1, '  Alpha      ─ □ ×'));
    });

    testTwk('a button is lit while the mouse is over it, × in the error '
        'colour; an edge or a corner that resizes the window while the '
        'mouse is over it', (t) async {
      final c = WindowController(left: 2, top: 1, width: 20, height: 5);
      final inner = FocusNode();
      addTearDown(c.dispose);
      addTearDown(inner.dispose);
      await t.pumpWidget(
        Theme.terminal(child: layer(c, inner)),
        size: (40, 12),
      );
      // the bar 0.16 of the way to the error colour, and to the text
      const towardsError = Color.rgb(83, 62, 67);
      const towardsText = Color.rgb(79, 82, 87);
      await t.mouse(MouseKind.move, 19, 1);
      await t.pump();
      expect(
        t,
        styleAt(
          19,
          1,
          allOf(hasFg(error), hasAttr(Attr.bold), hasBg(towardsError)),
        ),
      );
      expect(t, styleAt(18, 1, hasBg(towardsError)));
      expect(t, styleAt(20, 1, hasBg(towardsError)));
      expect(t, styleAt(17, 1, allOf(hasFg(muted), hasBg(bar))));
      await t.mouse(MouseKind.move, 15, 1);
      await t.pump();
      expect(
        t,
        styleAt(
          15,
          1,
          allOf(hasFg(text), hasAttr(Attr.bold), hasBg(towardsText)),
        ),
      );
      for (final x in [14, 16]) {
        expect(t, styleAt(x, 1, hasBg(towardsText)));
      }
      for (final x in [17, 18, 19, 20]) {
        expect(t, styleAt(x, 1, hasBg(bar)));
      }
      // the left edge
      await t.mouse(MouseKind.move, 2, 3);
      await t.pump();
      for (final x in [14, 15, 16]) {
        expect(t, styleAt(x, 1, hasBg(bar)));
      }
      for (var y = 2; y <= 5; y++) {
        expect(t, hasTextAt(2, y, '▏'));
        expect(t, styleAt(2, y, allOf(hasFg(primary), hasBg(surface))));
      }
      expect(t, hasTextAt(21, 3, ' '));
      // the bottom right corner
      await t.mouse(MouseKind.move, 21, 5);
      await t.pump();
      expect(t, hasTextAt(2, 5, '${'▁' * 19}▕'));
      expect(t, hasTextAt(21, 2, '▕'));
      expect(t, hasTextAt(2, 3, ' '));
      // the top left corner
      await t.mouse(MouseKind.move, 2, 1);
      await t.pump();
      expect(t, hasTextAt(2, 1, '▛'));
      expect(t, styleAt(2, 1, allOf(hasFg(primary), hasBg(bar))));
      expect(t, hasTextAt(2, 4, '▏'));
      // lit while it drags the edge, and no more after
      await t.mouse(MouseKind.move, 30, 8);
      await t.pump();
      expect(t, hasTextAt(2, 1, '  Alpha'));
      await drag(t, 21, 3, [(22, 3), (24, 3)]);
      expect(rect(c), (2, 1, 23, 5));
      await t.mouse(MouseKind.move, 30, 8);
      await t.pump();
      expect(t, hasTextAt(24, 3, ' '));
      // dragged down past the window, the right edge stays lit
      await t.mouse(MouseKind.down, 24, 3);
      await t.pump();
      await t.mouse(MouseKind.drag, 30, 9);
      await t.pump();
      expect(rect(c), (2, 1, 29, 5));
      expect(t, hasTextAt(30, 3, '▕'));
      await t.mouse(MouseKind.up, 30, 9);
      await t.pump();
      expect(t, hasTextAt(30, 3, ' '));
      // a maximised window lights none
      c.maximised = true;
      await arrive(t);
      await t.mouse(MouseKind.move, 0, 4);
      await t.pump();
      expect(t, hasTextAt(0, 4, ' '));
    });
  });

  testTwk('minimising the window the focus is in gives its chip the focus, '
      'from its title bar or from inside it; the other windows stay where '
      'they are', (t) async {
    final a = WindowController(left: 2, top: 1, width: 20, height: 5);
    final b = WindowController(left: 10, top: 3, width: 20, height: 5);
    final inner = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(inner.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          windows: [
            Window(
              title: 'Alpha',
              controller: a,
              child: Focus(focusNode: inner, child: const Text('alpha')),
            ),
            Window(title: 'Beta', controller: b, child: const Text('beta')),
          ],
          child: const Text('app'),
        ),
      ),
      size: (40, 12),
    );
    List<String> keys() => [
      for (final k in t.binding.focusManager.activeKeys) '$k',
    ];
    inner.requestFocus();
    await t.pump();
    // Alpha in front
    expect(t, hasTextAt(10, 3, '           │'));
    a.minimised = true;
    await t.pump();
    expect(keys(), ['enter restore', 'space restore']);
    expect(t, styleAt(0, 11, hasBg(const Color.indexed(237))));
    expect(inner.hasFocus, isFalse);
    await arrive(t);
    expect(keys(), ['enter restore', 'space restore']);
    // restored, its title bar focused; minimised from it by `m`
    await press(t, 'enter');
    await arrive(t);
    expect(a.minimised, isFalse);
    expect(t, styleAt(3, 1, hasBg(const Color.indexed(237))));
    await press(t, 'm');
    expect(a.minimised, isTrue);
    expect(keys(), ['enter restore', 'space restore']);
    await arrive(t);
    expect(t, hasTextAt(10, 3, '┌ Beta'));
    expect(t, styleAt(10, 3, isNot(hasFg(Color.blue))));
    // minimised while the focus is elsewhere, it leaves it there
    await press(t, 'enter');
    await arrive(t);
    inner.requestFocus();
    await t.pump();
    b.minimised = true;
    await arrive(t);
    expect(inner.hasPrimaryFocus, isTrue);
  });

  group('maximising and minimising', () {
    /// The column of the top right corner of the frame on row [y], -1 for
    /// none.
    int corner(TwkTester t, int y) => t.lines[y].indexOf('┐');

    Widget layer(WindowController c, {Duration? duration}) => WindowLayer(
      duration: duration ?? const Duration(milliseconds: 160),
      windows: [
        Window(title: 'Alpha', controller: c, child: const Text('alpha')),
      ],
      child: const Text('app'),
    );

    testTwk('the window grows to the layer and back over the duration, '
        'and shrinks into its chip; the mouse goes through it on its way', (
      t,
    ) async {
      final c = WindowController(left: 2, top: 2, width: 20, height: 5);
      addTearDown(c.dispose);
      await t.pumpWidget(Theme.terminal(child: layer(c)), size: (40, 12));
      expect(corner(t, 2), 21);
      c.maximised = true;
      await t.pump();
      await t.pump();
      // on its way: neither where it was nor at the layer's edges
      final top = t.lines.indexWhere((l) => l.contains('┐'));
      expect(top, inInclusiveRange(0, 2));
      final right = corner(t, top);
      expect(right, allOf(greaterThan(21), lessThan(39)));
      await arrive(t);
      expect(corner(t, 0), 39);
      expect(t, hasTextAt(39, 11, '┘'));
      c.maximised = false;
      await t.pump();
      await t.pump();
      expect(corner(t, 0), -1);
      final back = t.lines.indexWhere((l) => l.contains('┐'));
      expect(corner(t, back), allOf(greaterThan(21), lessThan(39)));
      await arrive(t);
      expect(corner(t, 2), 21);
      // minimised, it shrinks into its chip at the bottom left
      c.minimised = true;
      await t.pump();
      expect(t.lines.last, ' Alpha');
      expect(t.lines.take(11).join(), contains('┐'));
      await arrive(t);
      expect(t.lines.take(11).join(), isNot(contains('┐')));
      // restored, it grows out of it
      c.minimised = false;
      await t.pump();
      await t.pump();
      final out = t.lines.indexWhere((l) => l.contains('┐'));
      expect(out, greaterThan(2));
      await arrive(t);
      expect(corner(t, 2), 21);
    });

    testTwk('the mouse goes through a window on its way', (t) async {
      final c = WindowController(left: 2, top: 2, width: 20, height: 5);
      addTearDown(c.dispose);
      var pressed = 0;
      await t.pumpWidget(
        Theme.terminal(
          child: WindowLayer(
            duration: const Duration(seconds: 1),
            windows: [
              Window(title: 'Alpha', controller: c, child: const Text('alpha')),
            ],
            child: Listener(
              onDown: (_) => pressed++,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        size: (40, 12),
      );
      await t.click(10, 4);
      await t.pump();
      expect(pressed, 0);
      c.maximised = true;
      await t.pump(const Duration(milliseconds: 100));
      await t.click(10, 4);
      await t.pump();
      expect(pressed, 1);
      await t.pump(const Duration(seconds: 1));
      await t.click(10, 4);
      await t.pump();
      expect(pressed, 1);
    });

    testTwk('a duration of zero shows each change at once', (t) async {
      final c = WindowController(left: 2, top: 2, width: 20, height: 5);
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(child: layer(c, duration: Duration.zero)),
        size: (40, 12),
      );
      c.maximised = true;
      await t.pump();
      expect(corner(t, 0), 39);
      c.minimised = true;
      await t.pump();
      expect(t.lines.take(11).join(), isNot(contains('┐')));
    });
  });

  testTwk('a click on the buttons of a raised frame minimises, maximises '
      'and closes the window', (t) async {
    final c = WindowController(left: 2, top: 1, width: 20, height: 5);
    var closed = 0;
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: Theme(
          data: ThemeData.dark,
          child: WindowLayer(
            duration: Duration.zero,
            windows: [
              Window(
                title: 'Alpha',
                controller: c,
                onClose: () => closed++,
                child: const Text('alpha'),
              ),
            ],
            child: const Text('app'),
          ),
        ),
      ),
      size: (40, 12),
    );
    expect(t.lines[1], '    Alpha      ─ □ ×');
    await t.click(16, 1);
    await t.pump();
    expect(c.minimised, isTrue);
    c.minimised = false;
    await t.pump();
    await t.click(18, 1);
    await t.pump();
    expect(c.maximised, isTrue);
    c.maximised = false;
    await t.pump();
    await t.click(20, 1);
    await t.pump();
    expect(closed, 1);
  });

  testTwk('Space on a chip restores its window; a chip whose window is '
      'restored by its controller, or taken from the layer, leaves the '
      'focus to the layer', (t) async {
    final a = WindowController(left: 2, top: 1, width: 20, height: 5);
    final b = WindowController(left: 10, top: 3, width: 20, height: 5);
    final inner = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(inner.dispose);
    Widget layer({bool both = true}) => WindowLayer(
      duration: Duration.zero,
      windows: [
        Window(
          title: 'Alpha',
          key: const ValueKey('a'),
          controller: a,
          child: Focus(focusNode: inner, child: const Text('alpha')),
        ),
        if (both)
          Window(
            title: 'Beta',
            key: const ValueKey('b'),
            controller: b,
            child: const Text('beta'),
          ),
      ],
      child: const Text('app'),
    );
    await t.pumpWidget(Theme.terminal(child: layer()), size: (40, 12));
    inner.requestFocus();
    await t.pump();
    a.minimised = true;
    await t.pump();
    expect(inner.hasFocus, isFalse);
    await press(t, 'space');
    expect(a.minimised, isFalse);
    expect(
      t,
      styleAt(3, 1, hasBg(const Color.indexed(237))),
      reason: 'its title bar',
    );
    // minimised from inside, then restored by the app: the chip it gave
    // the focus to is gone
    inner.requestFocus();
    await t.pump();
    a.minimised = true;
    await t.pump();
    a.minimised = false;
    await t.pump();
    expect(a.minimised, isFalse);
    expect(t.lines[11], isNot(contains('Alpha')));
    // minimised from inside, then taken from the layer with its chip
    inner.requestFocus();
    await t.pump();
    b.minimised = false;
    a.minimised = true;
    await t.pump();
    await t.pumpWidget(
      Theme.terminal(
        child: WindowLayer(
          duration: Duration.zero,
          windows: [
            Window(
              title: 'Beta',
              key: const ValueKey('b'),
              controller: b,
              child: const Text('beta'),
            ),
          ],
          child: const Text('app'),
        ),
      ),
    );
    expect(t.lines[11], isNot(contains('Alpha')));
    expect(t.logs.records.where((r) => r.level == LogLevel.error), isEmpty);
  });

  testTwk('the layer built with another margin lays the decorations out '
      'by it; its intrinsic size is its child', (t) async {
    final c = WindowController(left: 2, top: 1, width: 12, height: 3);
    addTearDown(c.dispose);
    Widget layer(EdgeInsets margin) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicWidth(
          child: IntrinsicHeight(
            child: WindowLayer(
              margin: margin,
              decorate: (context, window) => Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Color.red)),
                  Positioned.fill(child: window),
                ],
              ),
              windows: [
                Window(
                  title: 'Alpha',
                  controller: c,
                  child: const Text('alpha'),
                ),
              ],
              child: const SizedBox(width: 20, height: 6),
            ),
          ),
        ),
        const Text('end'),
      ],
    );
    await t.pumpWidget(
      Theme.terminal(child: layer(EdgeInsets.zero)),
      size: (30, 8),
    );
    expect(t.rect(find.byType(WindowLayer)), (
      x: 0,
      y: 0,
      width: 20,
      height: 6,
    ));
    expect(t.lines[6], 'end');
    expect(t, styleAt(14, 2, isNot(hasBg(Color.red))));
    await t.pumpWidget(
      Theme.terminal(child: layer(const EdgeInsets.only(right: 1))),
    );
    expect(t, styleAt(14, 2, hasBg(Color.red)));
  });
}
