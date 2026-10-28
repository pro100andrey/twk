// Tabs: the bar's labels and the selected one, clicks, the keys while it
// has the focus and their hints, scrolling when the labels do not fit;
// the view keeping each tab's state, the hidden ones not laid out, painted
// or hit, their nodes out of the focus, which moves with the tab shown.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

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

/// Counts in its state; shows [label] and the count.
final class Counter extends StatefulWidget {
  const Counter(this.label, {super.key});

  final String label;

  @override
  State<Counter> createState() => CounterState();
}

final class CounterState extends State<Counter> {
  var count = 0;

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('${widget.label} $count');
}

/// A [Focus] named [label] that shows it, after `>` while it has the
/// primary focus.
final class Field extends StatelessWidget {
  const Field(this.label, {this.node, super.key});

  final String label;
  final FocusNode? node;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    debugLabel: label,
    child: Builder(
      (context) =>
          Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label'),
    ),
  );
}

final class Builder extends StatelessWidget {
  const Builder(this.builder, {super.key});

  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// The times each [Probe] was laid out and painted, by name.
final Map<String, int> layouts = {};
final Map<String, int> paints = {};

/// [text] on one row, counting its layouts and paints under [name].
final class Probe extends LeafRenderObjectWidget {
  const Probe(this.name, this.text, {super.key});

  final String name;
  final String text;

  @override
  RenderProbe createRenderObject(BuildContext context) =>
      RenderProbe(name, text);

  @override
  void updateRenderObject(BuildContext context, RenderProbe renderObject) {
    if (renderObject.text != text) {
      renderObject
        ..text = text
        ..markNeedsLayout();
    }
  }
}

final class RenderProbe extends RenderObject {
  RenderProbe(this.name, this.text);

  final String name;
  String text;

  @override
  void performLayout(BoxConstraints c) {
    layouts[name] = (layouts[name] ?? 0) + 1;
    width = c.constrainW(text.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    paints[name] = (paints[name] ?? 0) + 1;
    ctx.canvas.text(0, 0, text, ctx.canvas.styles.pen(const Pen()));
  }
}

final host = GlobalKey<HostState>();

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

void main() {
  group('TabBar', () {
    testTwk('shows the labels in a row, the selected one in the primary '
        'color, bold; a tab clicked is selected', (t) async {
      final c = TabController(length: 3, initialIndex: 1);
      await t.pumpWidget(
        Theme.terminal(
          child: TabBar(controller: c, tabs: const ['One', 'Two', 'Three']),
        ),
        size: (20, 1),
      );
      expect(t.lines, [' One  Two  Three']);
      expect(t, styleAt(6, 0, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
      expect(t, styleAt(1, 0, isNot(hasAttr(Attr.bold))));
      expect(t, styleAt(1, 0, hasFg(const Color.indexed(245))));
      await t.click(12, 0);
      await t.pump();
      expect(c.index, 2);
      expect(t, styleAt(12, 0, hasAttr(Attr.bold)));
      await t.click(0, 0);
      await t.pump();
      expect(c.index, 0);
      await t.click(18, 0);
      await t.pump();
      expect(c.index, 0);
    });

    testTwk('while it has the focus, Left and Right select the tab before and '
        'after, round, Home and End the first and the last; hinted, and '
        'the selected tab reversed', (t) async {
      final c = TabController(length: 3);
      final node = FocusNode(debugLabel: 'bar');
      addTearDown(node.dispose);
      final seen = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: InputListener(
            onEvent: (e) {
              if (e is KeyEvent && e.kind == KeyKind.press) {
                seen.add(KeyCombo.fromEvent(e).toString());
              }
              return false;
            },
            child: TabBar(
              controller: c,
              focusNode: node,
              tabs: const ['One', 'Two', 'Three'],
            ),
          ),
        ),
        size: (20, 1),
      );
      await press(t, 'right');
      expect(c.index, 0);
      expect(seen, ['right']);
      expect(t.binding.focusManager.activeKeys, isEmpty);
      node.requestFocus();
      await t.pump();
      expect(t, styleAt(1, 0, hasBg(Color.blue)));
      expect(
        [for (final k in t.binding.focusManager.activeKeys) '$k'],
        [
          'left previous tab',
          'right next tab',
          'home',
          'end',
        ],
      );
      final indices = <int>[];
      for (final key in ['right', 'right', 'right', 'left', 'end', 'home']) {
        await press(t, key);
        indices.add(c.index);
      }
      expect(indices, [1, 2, 0, 2, 2, 0]);
      expect(seen, ['right']);
    });

    testTwk('its keys from the moment it has the focus: Right typed right '
        'after the Tab that focuses it, in one read', (t) async {
      final c = TabController(length: 3);
      final a = FocusNode();
      addTearDown(a.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            children: [
              Field('a', node: a),
              TabBar(controller: c, tabs: const ['One', 'Two', 'Three']),
            ],
          ),
        ),
        size: (20, 2),
      );
      a.requestFocus();
      await t.pump();
      await t.type('\t\x1b[C\x1b[C\x1b[Z\x1b[C');
      await t.pump();
      expect(c.index, 2);
      expect(focused(t), 'a');
    });

    testTwk('scrolls to show the selected tab whole when the labels do not '
        'fit, marking the edges where tabs are cut off', (t) async {
      final c = TabController(length: 4);
      await t.pumpWidget(
        Theme.terminal(
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: c,
                  tabs: const ['One', 'Two', 'Three', 'Four'],
                ),
              ),
            ],
          ),
        ),
        size: (12, 1),
      );
      expect(t.lines, [' One  Two  ›']);
      expect(t, styleAt(11, 0, hasFg(const Color.indexed(245))));
      c.index = 2;
      await t.pump();
      expect(t.lines, ['‹wo  Three ›']);
      c.index = 3;
      await t.pump();
      expect(t.lines, ['‹hree  Four']);
      c.index = 0;
      await t.pump();
      expect(t.lines, [' One  Two  ›']);
    });

    testTwk('a mark clicked scrolls the tab it is over into view, and the '
        'wheel scrolls the row; neither selects', (t) async {
      final c = TabController(length: 4);
      await t.pumpWidget(
        Theme.terminal(
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: c,
                  tabs: const ['One', 'Two', 'Three', 'Four'],
                ),
              ),
            ],
          ),
        ),
        size: (12, 1),
      );
      await t.click(11, 0);
      await t.pump();
      expect(t.lines, ['‹wo  Three ›']);
      await t.click(11, 0);
      await t.pump();
      expect(t.lines, ['‹hree  Four']);
      await t.click(0, 0);
      await t.pump();
      expect(t.lines, ['‹ Three  Fo›']);
      final rows = <String>[];
      for (final kind in [
        MouseKind.wheelUp,
        MouseKind.wheelUp,
        MouseKind.wheelUp,
        MouseKind.wheelDown,
      ]) {
        await t.mouse(kind, 5, 0);
        await t.pump();
        rows.add(t.lines.first);
      }
      expect(rows, [
        '‹wo  Three ›',
        '‹  Two  Thr›',
        ' One  Two  ›',
        '‹  Two  Thr›',
      ]);
      expect(c.index, 0);
    });
  });

  group('TabView', () {
    testTwk("shows the selected tab's child and keeps the state of the "
        'others', (t) async {
      final c = TabController(length: 2);
      final first = GlobalKey<CounterState>();
      final second = GlobalKey<CounterState>();
      await t.pumpWidget(
        Theme.terminal(
          child: TabView(
            controller: c,
            children: [
              Counter('first', key: first),
              Counter('second', key: second),
            ],
          ),
        ),
        size: (10, 2),
      );
      expect(t.lines, ['first 0', '']);
      first.currentState!.bump();
      await t.pump();
      expect(t.lines.first, 'first 1');
      c.index = 1;
      await t.pump();
      expect(t.lines.first, 'second 0');
      second.currentState!
        ..bump()
        ..bump();
      c.index = 0;
      await t.pump();
      expect(t.lines.first, 'first 1');
      c.index = 1;
      await t.pump();
      expect(t.lines.first, 'second 2');
    });

    testTwk('a hidden tab is not laid out, painted or described, nor does '
        'what changes in it lay out or paint the tab shown; the mouse does '
        'not hit it, and hits the tab shown', (t) async {
      final view = GlobalKey();
      final c = TabController(length: 2);
      final downs = <String>[];
      final entered = <String>[];
      layouts.clear();
      paints.clear();
      await t.pumpWidget(
        Theme.terminal(
          child: Host(
            key: host,
            (step) => TabView(
              key: view,
              controller: c,
              children: [
                Listener(
                  onDown: (e) => downs.add('shown ${e.x}'),
                  behavior: HitTestBehavior.opaque,
                  child: const Probe('shown', 'shown'),
                ),
                MouseRegion(
                  onEnter: (e) => entered.add('hidden ${e.x}'),
                  child: Listener(
                    onDown: (e) => downs.add('hidden ${e.x}'),
                    behavior: HitTestBehavior.opaque,
                    child: Probe('hidden', 'hidden $step'),
                  ),
                ),
              ],
            ),
          ),
        ),
        size: (10, 2),
      );
      expect(layouts, {'shown': 1});
      expect(paints, {'shown': 1});
      final tree = view.currentContext!
          .findRenderObject()!
          .describe()
          .toStringDeep();
      expect(tree, contains('RenderListener'));
      expect(tree, isNot(contains('RenderMouseRegion')));
      c.index = 1;
      await t.pump();
      expect(t.lines.first, 'hidden 0');
      await t.click(1, 0);
      expect(downs, ['hidden 1']);
      expect(entered, ['hidden 1']);
      c.index = 0;
      await t.pump();
      expect(t.lines.first, 'shown');
      final laidOut = Map.of(layouts);
      final painted = Map.of(paints);
      final frames = t.terminal.frames.length;
      for (var step = 1; step <= 3; step++) {
        host.currentState!.change(step);
        await t.pump();
      }
      await t.mouse(MouseKind.move, 2, 0);
      await t.click(2, 0);
      await t.pump();
      expect(downs, ['hidden 1', 'shown 2']);
      expect(entered, ['hidden 1']);
      expect(layouts, laidOut);
      expect(paints, painted);
      expect(t.terminal.frames.length, frames);
      c.index = 1;
      await t.pump();
      expect(t.lines.first, 'hidden 3');
    });

    testTwk("Tab passes by the hidden tabs' nodes; selecting another tab "
        'while the focus is in the one shown moves it to the node the new '
        'one had it on, or its first', (t) async {
      final c = TabController(length: 3);
      final b2 = FocusNode();
      addTearDown(b2.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Field('before'),
              Expanded(
                child: TabView(
                  controller: c,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Field('a1'), Field('a2')],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Field('b1'),
                        Field('b2', node: b2),
                      ],
                    ),
                    const Text('nothing to focus'),
                  ],
                ),
              ),
              const Field('after'),
            ],
          ),
        ),
        size: (20, 5),
      );
      final order = <String?>[];
      for (var i = 0; i < 4; i++) {
        await press(t, 'tab');
        order.add(focused(t));
      }
      expect(order, ['before', 'a1', 'a2', 'after']);
      await press(t, 'shift+tab');
      expect(focused(t), 'a2');
      c.index = 1;
      await t.pump();
      expect(focused(t), 'b1');
      expect(t.lines.take(3), [' before', '>b1', ' b2']);
      b2.requestFocus();
      c.index = 0;
      await t.pump();
      expect(focused(t), 'a2');
      c.index = 1;
      await t.pump();
      expect(focused(t), 'b2');
      c.index = 2;
      await t.pump();
      expect(focused(t), 'after');
      c.index = 0;
      await t.pump();
      expect(focused(t), 'after');
    });

    testTwk('with a TabBar: its keys switch the tabs the view shows', (
      t,
    ) async {
      final c = TabController(length: 2);
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                controller: c,
                autofocus: true,
                tabs: const ['Inbox', 'Sent'],
              ),
              Expanded(
                child: TabView(
                  controller: c,
                  children: const [Text('3 new'), Text('none')],
                ),
              ),
            ],
          ),
        ),
        size: (14, 2),
      );
      expect(t.lines, [' Inbox  Sent', '3 new']);
      await press(t, 'right');
      expect(t.lines, [' Inbox  Sent', 'none']);
      expect(t, styleAt(8, 0, hasBg(Color.blue)));
    });
  });

  testTwk('TabBar.strip draws the row on the surface, the selected tab in '
      'the background colour, primary, filled primary while focused', (
    t,
  ) async {
    const dark = ThemeData.dark;
    final c = TabController(length: 2);
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: Theme(
          data: dark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar.strip(controller: c, tabs: const ['Inbox', 'Sent']),
              const Text('none'),
            ],
          ),
        ),
      ),
      size: (20, 2),
    );
    expect(t.lines, [' Inbox  Sent', 'none']);
    final surface = dark.surface.bg!;
    final background = dark.background.bg!;
    final primary = dark.primary.fg!;
    expect(t, styleAt(15, 0, hasBg(surface)));
    expect(t, styleAt(8, 0, allOf(hasFg(dark.muted.fg!), hasBg(surface))));
    for (final x in [0, 1, 6]) {
      expect(
        t,
        styleAt(x, 0, allOf(hasFg(primary), hasBg(background))),
      );
    }
    expect(t, styleAt(1, 0, hasAttr(Attr.bold)));
    await t.press('tab');
    await t.pump();
    expect(
      t,
      styleAt(
        1,
        0,
        allOf(
          hasFg(dark.onPrimary.fg!),
          hasBg(primary),
          hasAttr(Attr.bold),
          isNot(hasAttr(Attr.reverse)),
        ),
      ),
    );
    expect(t, styleAt(15, 0, hasBg(surface)));
  });
}
