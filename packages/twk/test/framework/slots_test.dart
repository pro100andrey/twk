// Slots: a Slot shows the entries of its name in the registry of the
// SlotScope above it, in order, built again only when they change; each
// entry keyed by its id, keeping its state as the entries move, and what
// its builder throws shown in its place only.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'harness.dart';

/// An entry of [slot] that shows a [Leaf] of [label], its [id] when not
/// given, and logs each build into [log].
SlotEntry leaf(
  String slot,
  String id, {
  int order = 0,
  String? label,
  List<String>? log,
}) => SlotEntry(
  slot: slot,
  id: id,
  order: order,
  builder: (context) {
    log?.add(id);
    return Leaf(label ?? id);
  },
);

/// A [Slot] of [name] whose entries are the children of a [Multi], [log]
/// told each time it lays them out.
Slot slot(String name, {List<String>? log, Widget? placeholder}) => Slot(
  name,
  layout: (context, children) {
    log?.add('$name layout');
    return Multi(children);
  },
  placeholder: placeholder,
);

/// The labels of the render objects below [multi], a [TestMulti].
List<String> labels(RenderObject? multi) => [
  for (final child in (multi! as TestMulti).children) '$child',
];

void main() {
  test('entries come by their order, those of an equal one as they were '
      'registered, also among many; one registered again under its id '
      'keeps its place', () {
    final registry = SlotRegistry()
      ..register(leaf('bar', 'late', order: 1))
      ..register(leaf('bar', 'a'))
      ..register(leaf('bar', 'b'))
      ..register(leaf('bar', 'early', order: -1));
    final tree = Tree()
      ..pump(SlotScope(registry: registry, child: slot('bar')));
    expect(labels(tree.host.child), ['early', 'a', 'b', 'late']);

    registry.register(leaf('bar', 'a', label: 'a again'));
    tree.frame();
    expect(labels(tree.host.child), ['early', 'a again', 'b', 'late']);

    final many = SlotRegistry();
    for (var i = 0; i < 60; i++) {
      many.register(leaf('bar', '$i', order: i % 3));
    }
    expect(
      [for (final e in many.entriesOf('bar')) e.id],
      [
        for (final order in [0, 1, 2])
          for (var i = order; i < 60; i += 3) '$i',
      ],
    );
  });

  test('an entry unregistered leaves its slot, which shows its placeholder '
      'once it has none; one it does not have changes nothing', () {
    var notified = 0;
    final registry = SlotRegistry()
      ..register(leaf('bar', 'a'))
      ..register(leaf('bar', 'b'))
      ..addListener(() => notified++);
    final tree = Tree()
      ..pump(
        SlotScope(
          registry: registry,
          child: Single(child: slot('bar', placeholder: const Leaf('none'))),
        ),
      );
    final shown = (tree.host.child! as TestSingle).child;
    expect(labels(shown), ['a', 'b']);

    expect(registry.unregister('bar', 'a'), isTrue);
    tree.frame();
    expect(labels((tree.host.child! as TestSingle).child), ['b']);
    expect(registry.unregister('bar', 'a'), isFalse);
    expect(registry.unregister('other', 'b'), isFalse);
    expect(notified, 1);

    expect(registry.unregister('bar', 'b'), isTrue);
    tree.frame();
    expect(registry.entriesOf('bar'), isEmpty);
    expect((tree.host.child! as TestSingle).child.toString(), 'none');
  });

  test('a change to the entries of one slot builds that slot again, and of '
      'its entries only the one registered: not another slot', () {
    final log = <String>[];
    final registry = SlotRegistry()
      ..register(leaf('left', 'a', log: log))
      ..register(leaf('right', 'b', log: log));
    final tree = Tree()
      ..pump(
        SlotScope(
          registry: registry,
          child: Multi([
            slot('left', log: log),
            slot('right', log: log),
          ]),
        ),
      );
    expect(log, ['left layout', 'a', 'right layout', 'b']);

    log.clear();
    registry.register(leaf('left', 'c', log: log));
    tree.frame();
    expect(log, ['left layout', 'c']);
    final [left, right] = (tree.host.child! as TestMulti).children;
    expect(labels(left), ['a', 'c']);
    expect(labels(right), ['b']);

    log.clear();
    registry.unregister('right', 'b');
    tree.frame();
    expect(log, ['right layout']);
  });

  test('an entry that moves among the others keeps its element and state, '
      'its render object moved', () {
    final log = <String>[];
    SlotEntry probe(String id, int order) => SlotEntry(
      slot: 'bar',
      id: id,
      order: order,
      builder: (context) => Probe(id, log, child: Leaf(id)),
    );
    final registry = SlotRegistry()
      ..register(probe('a', 0))
      ..register(probe('b', 1));
    final tree = Tree()
      ..pump(SlotScope(registry: registry, child: slot('bar')));
    final [a, b] = tree.probes;
    expect(labels(tree.host.child), ['a', 'b']);

    log.clear();
    registry.register(probe('a', 2));
    tree.frame();
    expect(labels(tree.host.child), ['b', 'a']);
    expect(tree.probes, [same(b), same(a)]);
    expect(a.widget.name, 'a');
    expect(log, ['a didUpdateWidget 0 to 0', 'a build']);
    expect((tree.host.child! as TestMulti).log.last, 'move a after b');
  });

  testTwk('an entry whose builder throws shows an ErrorWidget in its place, '
      'the others shown as ever, until it is registered anew', (t) async {
    SlotEntry text(String id, String text, {int order = 0}) => SlotEntry(
      slot: 'status',
      id: id,
      order: order,
      builder: (context) => Text(text),
    );
    final registry = SlotRegistry()
      ..register(text('a', 'left'))
      ..register(
        SlotEntry(
          slot: 'status',
          id: 'bad',
          order: 1,
          builder: (context) => throw StateError('boom'),
        ),
      )
      ..register(text('c', 'right', order: 2));
    await t.pumpWidget(
      SlotScope(
        registry: registry,
        child: Slot(
          'status',
          layout: (context, children) => Row(gap: 1, children: children),
        ),
      ),
      size: (40, 2),
    );
    expect(t.lines.first, 'left Bad state: boom right');
    final [error] = [
      for (final r in t.logs.records)
        if (r.level == LogLevel.error) r.error,
    ];
    expect(error, isA<StateError>());

    registry.register(text('bad', 'fixed', order: 1));
    await t.pump();
    expect(t.lines.first, 'left fixed right');
  });

  test('slots of one name show the same entries, each in elements of its '
      'own, and both change with them', () {
    final log = <String>[];
    SlotEntry probe(String id) => SlotEntry(
      slot: 'bar',
      id: id,
      builder: (context) => Probe(id, log, child: Leaf(id)),
    );
    final registry = SlotRegistry()..register(probe('a'));
    final tree = Tree()
      ..pump(
        SlotScope(
          registry: registry,
          child: Multi([slot('bar'), slot('bar')]),
        ),
      );
    registry.register(probe('b'));
    tree.frame();
    final [first, second] = (tree.host.child! as TestMulti).children;
    expect(labels(first), ['a', 'b']);
    expect(labels(second), ['a', 'b']);
    expect(tree.probes.toSet(), hasLength(4));
  });

  test('without a SlotScope a slot has no entries; under a new registry it '
      'shows the entries of that one, and listens to it alone until it is '
      'removed', () {
    final old = SlotRegistry()..register(leaf('bar', 'old'));
    final next = SlotRegistry()..register(leaf('bar', 'next'));
    final tree = Tree()..pump(slot('bar', placeholder: const Leaf('none')));
    expect(tree.host.child.toString(), 'none');

    tree.pump(SlotScope(registry: old, child: slot('bar')));
    expect(labels(tree.host.child), ['old']);
    tree.pump(SlotScope(registry: next, child: slot('bar')));
    expect(labels(tree.host.child), ['next']);
    expect(SlotScope.of(tree.elementOf<Slot>()), same(next));
    expect(old.hasListeners, isFalse);
    expect(next.hasListeners, isTrue);

    tree.pump(const Leaf('gone'));
    expect(next.hasListeners, isFalse);
  });

  test('SlotScope.of without a SlotScope above is a StateError naming the '
      'widget that asked', () {
    final tree = Tree()..pump(slot('bar'));
    expect(
      () => SlotScope.of(tree.elementOf<Slot>()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'no SlotScope above Slot',
        ),
      ),
    );
  });

  test('a slot is described by its name, an entry by its slot and id', () {
    final tree = Tree()..pump(slot('status'));
    expect('${tree.elementOf<Slot>().describe()}', 'Slot ‹"status"›');
    expect('${leaf('status', 'clock')}', 'SlotEntry(status, clock)');
  });
}
