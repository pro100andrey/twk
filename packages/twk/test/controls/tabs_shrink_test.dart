// Tabs whose number changes: a TabView with fewer children than its
// controller's index, the controller told before or after, and with more
// again, or none; a TabBar with fewer labels; the focus and the state of
// the children as those around them go; a DockArea's group, whose view
// is the same one as its panels go.
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
  const Field(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Focus(
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

final host = GlobalKey<HostState>();

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// The first row of each frame written since the [from]th.
List<String> firstRows(TwkTester t, int from) => [
  for (final f in t.frames.skip(from)) f.lines.first,
];

/// A [TabView] of [c] over a child for each of [labels].
Widget view(TabController c, Iterable<String> labels) =>
    TabView(controller: c, children: [for (final l in labels) Text(l)]);

void main() {
  test('a TabController set to as many tabs as its index or fewer selects '
      'the last, its listeners notified once; set to none, it is a '
      'RangeError', () {
    var told = 0;
    final c = TabController(length: 3, initialIndex: 2)
      ..addListener(() => told++)
      ..length = 2;
    expect((c.length, c.index, told), (2, 1, 1));
    c.length = 4;
    expect((c.length, c.index, told), (4, 1, 2));
    c.length = 4;
    expect(told, 2);
    expect(() => c.length = 0, throwsRangeError);
    expect((c.length, c.index, told), (4, 1, 2));
  });

  test('a TabController asserts that it has a tab and that the tab it '
      'starts with is one of them', () {
    expect(
      () => TabController(length: 2, initialIndex: 2),
      throwsA(
        isA<AssertionError>().having(
          (e) => e.message,
          'message',
          'initialIndex out of 0..1',
        ),
      ),
    );
    expect(() => TabController(length: 0), throwsA(isA<AssertionError>()));
  });

  group('TabView', () {
    testTwk('a new controller of fewer tabs with fewer children, as a '
        'DockArea makes one, shows the tab it selects', (t) async {
      final three = TabController(length: 3, initialIndex: 2);
      final two = TabController(length: 2, initialIndex: 1);
      await t.pumpWidget(
        Host(
          key: host,
          (step) =>
              view(step == 0 ? three : two, 'abc'.split('').take(3 - step)),
        ),
        size: (6, 1),
      );
      expect(t.lines, ['c']);
      final from = t.frames.length;
      host.currentState!.change(1);
      await t.pump();
      expect(t.lines, ['b']);
      expect(firstRows(t, from), ['b']);
    });

    testTwk('fewer children than the index of a controller told first: '
        'the last shown in each frame, the controller notified once', (
      t,
    ) async {
      final c = TabController(length: 3, initialIndex: 2);
      var told = 0;
      c.addListener(() => told++);
      await t.pumpWidget(
        Host(key: host, (step) => view(c, 'abc'.split('').take(3 - step))),
        size: (6, 1),
      );
      final from = t.frames.length;
      c.length = 2;
      await t.pump();
      expect(t.lines, ['b']);
      host.currentState!.change(1);
      await t.pump();
      expect(t.lines, ['b']);
      expect(firstRows(t, from), everyElement('b'));
      expect((c.index, told), (1, 1));
    });

    testTwk('fewer children than the index of a controller told after: the '
        'last shown, then selected, the controller notified once', (t) async {
      final c = TabController(length: 3, initialIndex: 2);
      var told = 0;
      c.addListener(() => told++);
      await t.pumpWidget(
        Host(key: host, (step) => view(c, 'abc'.split('').take(3 - step))),
        size: (6, 1),
      );
      final from = t.frames.length;
      host.currentState!.change(1);
      await t.pump();
      expect(t.lines, ['b']);
      expect(c.index, 2);
      c.length = 2;
      await t.pump();
      expect(t.lines, ['b']);
      expect(firstRows(t, from), everyElement('b'));
      expect((c.index, told), (1, 1));
    });

    testTwk('more children again: the tab of the controller shown, told or '
        'not', (t) async {
      final c = TabController(length: 3, initialIndex: 2);
      await t.pumpWidget(
        Host(key: host, (step) => view(c, 'abc'.split('').take(3 - step))),
        size: (6, 1),
      );
      host.currentState!.change(1);
      await t.pump();
      expect(t.lines, ['b']);
      host.currentState!.change(0);
      await t.pump();
      expect(t.lines, ['c']);
      host.currentState!.change(1);
      c.length = 2;
      await t.pump();
      expect(t.lines, ['b']);
      host.currentState!.change(0);
      c
        ..length = 3
        ..index = 2;
      await t.pump();
      expect(t.lines, ['c']);
    });

    testTwk('no children: nothing shown, the room filled; then the child of '
        "the controller's tab", (t) async {
      final c = TabController(length: 2, initialIndex: 1);
      await t.pumpWidget(
        Host(
          key: host,
          (step) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: view(c, step == 1 ? const [] : const ['a', 'b'])),
              const Text('end'),
            ],
          ),
        ),
        size: (6, 3),
      );
      expect(t.lines, ['b', '', 'end']);
      host.currentState!.change(1);
      await t.pump();
      expect(t.lines, ['', '', 'end']);
      host.currentState!.change(2);
      await t.pump();
      expect(t.lines, ['b', '', 'end']);
    });

    testTwk('a child with a key keeps its state and the focus as one before '
        'it goes; the focus in the child shown as it goes moves to the one '
        'shown after it', (t) async {
      final c = TabController(length: 3, initialIndex: 2);
      final counter = GlobalKey<CounterState>();
      await t.pumpWidget(
        Host(
          key: host,
          (step) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Field('before'),
              Expanded(
                child: TabView(
                  controller: c,
                  children: [
                    if (step < 1) const Field('a', key: ValueKey('a')),
                    const Column(
                      key: ValueKey('b'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Field('b1'), Field('b2')],
                    ),
                    if (step < 2)
                      Column(
                        key: const ValueKey('c'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Counter('c', key: counter),
                          const Field('c1'),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        size: (10, 3),
      );
      for (var i = 0; i < 2; i++) {
        await t.press('tab');
        await t.pump();
      }
      counter.currentState!.bump();
      await t.pump();
      expect(focused(t), 'c1');
      expect(t.lines, [' before', 'c 1', '>c1']);
      host.currentState!.change(1);
      await t.pump();
      expect(t.lines, [' before', 'c 1', '>c1']);
      c.length = 2;
      await t.pump();
      expect(c.index, 1);
      expect(t.lines, [' before', 'c 1', '>c1']);
      host.currentState!.change(2);
      await t.pump();
      expect(focused(t), 'b1');
      expect(t.lines, [' before', '>b1', ' b2']);
    });
  });

  testTwk('a group of a DockArea as its panels go: one before the selected '
      'one, kept with its state; the selected one, the tab the layout '
      'selects shown', (t) async {
    final c = DockController(
      DockLayout(root: DockTabs(['a', 'b', 'c'], selected: 2)),
    );
    addTearDown(c.dispose);
    final counter = GlobalKey<CounterState>();
    await t.pumpWidget(
      DockArea(
        controller: c,
        panels: [
          for (final id in ['a', 'b'])
            DockPanel(id: id, title: id.toUpperCase(), child: Text(id)),
          DockPanel(
            id: 'c',
            title: 'C',
            child: Counter('c', key: counter),
          ),
        ],
      ),
      size: (12, 2),
    );
    expect(t.lines, [' A  B  C', 'c 0']);
    counter.currentState!.bump();
    c.remove('a');
    await t.pump();
    expect(t.lines, [' B  C', 'c 1']);
    final from = t.frames.length;
    c.remove('c');
    await t.pump();
    expect(t.lines, [' B', 'b']);
    expect(
      [for (final f in t.frames.skip(from)) f.lines],
      [
        [' B', 'b'],
      ],
    );
  });

  group('TabBar', () {
    testTwk('with fewer labels than its controller has tabs, it marks the '
        'last for a tab past them; with more, those past the tabs are not '
        'selected; the keys select the tabs both have', (t) async {
      final c = TabController(length: 3, initialIndex: 2);
      final node = FocusNode();
      addTearDown(node.dispose);
      await t.pumpWidget(
        Host(
          key: host,
          (step) => TabBar(
            controller: c,
            focusNode: node,
            autofocus: true,
            tabs: ['One', 'Two', 'Three', 'Four'].take(2 + step).toList(),
          ),
        ),
        size: (24, 1),
      );
      expect(t.lines, [' One  Two']);
      expect(t, styleAt(6, 0, hasBg(Color.blue)));
      final indices = <int>[];
      for (final key in ['right', 'right', 'end', 'left', 'home']) {
        await t.press(key);
        await t.pump();
        indices.add(c.index);
      }
      expect(indices, [0, 1, 1, 0, 0]);
      host.currentState!.change(2);
      await t.pump();
      expect(t.lines, [' One  Two  Three  Four']);
      await t.click(19, 0);
      await t.pump();
      expect(c.index, 0);
      await t.press('end');
      await t.pump();
      expect(c.index, 2);
      expect(t, styleAt(12, 0, hasBg(Color.blue)));
    });
  });
}
