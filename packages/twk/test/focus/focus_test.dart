// The focus tree in an app: Tab and Shift+Tab, scopes, keys bubbling up
// from the primary focus, autofocus, and the focus kept across rebuilds
// and moved off removed nodes.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not.
final class Field extends StatelessWidget {
  const Field(
    this.label, {
    this.node,
    this.autofocus = false,
    this.onKeyEvent,
    this.canRequestFocus,
    this.skipTraversal,
    super.key,
  });

  final String label;
  final FocusNode? node;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;
  final bool? canRequestFocus;
  final bool? skipTraversal;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    autofocus: autofocus,
    onKeyEvent: onKeyEvent,
    canRequestFocus: canRequestFocus,
    skipTraversal: skipTraversal,
    debugLabel: label,
    child: _Mark(label),
  );
}

/// [label] after whether the nearest focus node has the primary focus.
final class _Mark extends StatelessWidget {
  const _Mark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
}

/// Shows what [builder] builds from its state, which changes it.
final class Host extends StatefulWidget {
  const Host(this.builder, {super.key});

  final Widget Function(HostState state) builder;

  @override
  State<Host> createState() => HostState();
}

final class HostState extends State<Host> {
  /// What the builder may show.
  var step = 0;

  /// Rebuilds with [step] set to [to].
  void change(int to) => setState(() => step = to);

  @override
  Widget build(BuildContext context) => widget.builder(this);
}

/// [children] one below another at their left edge, the column as tall
/// as they are.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

final host = GlobalKey<HostState>();

/// The label of the node with the primary focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses each key of [keys] and pumps a frame after it; the labels
/// focused after each.
Future<List<String?>> tab(TwkTester t, String keys) async => [
  for (final key in keys.split(' '))
    await t.press(key).then((_) => t.pump()).then((_) => focused(t)),
];

void main() {
  testTwk('Tab moves the focus through the nodes in the order of the tree, '
      'the first after the last; Shift+Tab the other way', (t) async {
    await t.pumpWidget(
      column([
        const Field('a'),
        const Row(gap: 1, children: [Field('b'), Field('c')]),
        const Field('d'),
      ]),
      size: (10, 3),
    );
    expect(focused(t), isNull);
    expect(await tab(t, 'tab'), ['a']);
    expect(t.lines, ['>a', ' b  c', ' d']);
    expect(await tab(t, 'tab tab tab tab'), ['b', 'c', 'd', 'a']);
    expect(t.lines, ['>a', ' b  c', ' d']);
    expect(await tab(t, 'shift+tab shift+tab shift+tab'), ['d', 'c', 'b']);
    expect(t.lines, [' a', '>b  c', ' d']);
  });

  testTwk('a node mounted after the others takes its place in the tree, not '
      'the last one', (t) async {
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          const Field('a', key: Key('a')),
          if (s.step == 1) const Field('b', key: Key('b')),
          const Field('c', key: Key('c')),
        ]),
      ),
    );
    expect(await tab(t, 'tab'), ['a']);
    host.currentState!.change(1);
    await t.pump();
    expect(await tab(t, 'tab tab tab'), ['b', 'c', 'a']);
  });

  testTwk('Tab passes by the nodes that skip traversal and those that cannot '
      'be focused; requestFocus focuses only the first', (t) async {
    final b = FocusNode();
    final c = FocusNode();
    await t.pumpWidget(
      column([
        const Field('a'),
        Field('b', node: b, skipTraversal: true),
        Field('c', node: c, canRequestFocus: false),
        const Field('d'),
      ]),
    );
    expect(await tab(t, 'tab tab tab'), ['a', 'd', 'a']);
    c.requestFocus();
    expect(focused(t), 'a');
    b.requestFocus();
    await t.pump();
    expect(focused(t), 'b');
    expect(t.lines.take(2), [' a', '>b']);
    expect(await tab(t, 'tab'), ['d']);
    expect(await tab(t, 'shift+tab'), ['a']);
  });

  testTwk('a node that can no longer be focused passes the focus to the '
      'next node of its scope, else the previous, else the scope, in the '
      'frame that disables it', (t) async {
    // the nodes that can be focused at each step
    const enabled = [
      {'a', 'b', 'c'},
      {'a', 'c'},
      {'a', 'b'},
      {'b'},
      <String>{},
    ];
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          for (final label in ['a', 'b', 'c'])
            Field(label, canRequestFocus: enabled[s.step].contains(label)),
        ]),
      ),
    );
    final manager = t.binding.focusManager;
    final frames = t.terminal.frames;
    expect(await tab(t, 'tab tab tab tab'), ['a', 'b', 'c', 'a']);
    expect(await tab(t, 'tab'), ['b']);
    final before = frames.length;
    host.currentState!.change(1);
    await t.pump();
    expect(focused(t), 'c', reason: 'the next, not the one focused before');
    expect(t.lines.take(3), [' a', ' b', '>c']);
    expect(frames, hasLength(before + 1));
    host.currentState!.change(2);
    await t.pump();
    expect(focused(t), 'b', reason: 'the last gives it to the previous');
    expect(t.lines.take(3), [' a', '>b', ' c']);
    host.currentState!.change(3);
    await t.pump();
    expect(focused(t), 'b');
    host.currentState!.change(4);
    await t.pump();
    expect(manager.primaryFocus, same(manager.rootScope));
    expect(t.lines.take(3), [' a', ' b', ' c']);
  });

  testTwk('a button disabled while it has the focus passes it to the next '
      'button', (t) async {
    final nodes = [
      for (final label in ['one', 'two', 'three']) FocusNode(debugLabel: label),
    ];
    for (final node in nodes) {
      addTearDown(node.dispose);
    }
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          Button('one', focusNode: nodes[0], onPressed: () {}),
          Button(
            'two',
            focusNode: nodes[1],
            onPressed: s.step == 0 ? () {} : null,
          ),
          Button('three', focusNode: nodes[2], onPressed: () {}),
        ]),
      ),
    );
    expect(await tab(t, 'tab tab'), ['one', 'two']);
    host.currentState!.change(1);
    await t.pump();
    expect(focused(t), 'three');
    expect(await tab(t, 'shift+tab tab'), ['one', 'three']);
  });

  testTwk('a scope keeps Tab among its nodes; Tab onto it from outside '
      'focuses the node it focused last, or its first', (t) async {
    final a = FocusNode();
    late BuildContext inside;
    await t.pumpWidget(
      column([
        Field('a', node: a),
        FocusScope(
          debugLabel: 's',
          child: column([
            const Field('x'),
            const Field('y'),
            Host((s) {
              inside = s.context;
              return const SizedBox.shrink();
            }),
          ]),
        ),
        const Field('b'),
      ]),
    );
    expect(await tab(t, 'tab tab tab tab'), ['a', 'x', 'y', 'x']);
    expect(await tab(t, 'shift+tab shift+tab'), ['y', 'x']);
    expect(FocusScope.of(inside).debugLabel, 's');
    a.requestFocus();
    expect(await tab(t, 'shift+tab'), ['b']);
    expect(await tab(t, 'shift+tab'), ['x']);
    a.requestFocus();
    await t.pump();
    expect(t.lines.take(3), ['>a', ' x', ' y']);
  });

  testTwk('a key goes to the primary focus, then up the nodes above it until '
      'one handles it, then to the InputListeners; one a node handles goes no '
      'further, Ctrl+C too', (t) async {
    final seen = <String>[];
    KeyEventResult Function(FocusNode, KeyEvent) handler(
      String name,
      String takes,
    ) => (node, event) {
      seen.add('$name ${event.char}');
      return takes.contains(event.char)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    };
    await t.pumpWidget(
      InputListener(
        onEvent: (e) {
          if (e is KeyEvent) {
            seen.add('listener ${e.char}');
          }
          return false;
        },
        child: Focus(
          onKeyEvent: handler('outer', 'bc'),
          child: Field(
            'inner',
            autofocus: true,
            onKeyEvent: handler('inner', 'a'),
          ),
        ),
      ),
    );
    await t.type('abd');
    expect(seen, [
      'inner a',
      'inner b',
      'outer b',
      'inner d',
      'outer d',
      'listener d',
    ]);
    seen.clear();
    await t.press('ctrl+c');
    expect(seen, ['inner c', 'outer c']);
    expect(t.isRunning, isTrue);
  });

  testTwk('a node that holds the keys gets them first, then the nodes above '
      'it; the hold ends with releaseKeys, when the focus moves, and when the '
      'node leaves the tree', (t) async {
    final seen = <String>[];
    KeyEventResult Function(FocusNode, KeyEvent) handler(String name) =>
        (node, event) {
          seen.add('$name ${event.char}');
          return KeyEventResult.ignored;
        };
    final holder = FocusNode(debugLabel: 'holder', canRequestFocus: false);
    final other = FocusNode();
    addTearDown(holder.dispose);
    addTearDown(other.dispose);
    await t.pumpWidget(
      Host(
        key: host,
        (state) => Focus(
          debugLabel: 'outer',
          onKeyEvent: handler('outer'),
          child: Column(
            children: [
              if (state.step == 0)
                Focus(
                  focusNode: holder..onKeyEvent = handler('holder'),
                  child: Field(
                    'inner',
                    autofocus: true,
                    onKeyEvent: handler('inner'),
                  ),
                ),
              Field('other', node: other),
            ],
          ),
        ),
      ),
    );
    final manager = t.binding.focusManager;
    final changes = <int>[];
    manager.keysChanged.addListener(() => changes.add(1));
    List<String?> path() => [for (final n in manager.keyPath) n.debugLabel];
    expect(path(), ['inner', 'holder', 'outer', 'root']);
    holder.holdKeys();
    expect(holder.holdsKeys, isTrue);
    expect(path(), ['holder', 'outer', 'root']);
    await t.type('a');
    expect(seen, ['holder a', 'outer a']);
    await t.pump();
    expect(changes, hasLength(1));
    holder.releaseKeys();
    expect(holder.holdsKeys, isFalse);
    await t.pump();
    expect(changes, hasLength(2));
    seen.clear();
    await t.type('b');
    expect(seen, ['inner b', 'holder b', 'outer b']);
    holder.holdKeys();
    other.requestFocus();
    expect(holder.holdsKeys, isFalse);
    expect(path(), ['other', 'outer', 'root']);
    holder.holdKeys();
    host.currentState!.change(1);
    await t.pump();
    expect(holder.holdsKeys, isFalse);
    expect(path(), ['other', 'outer', 'root']);
    other.holdKeys();
    final unattached = FocusNode();
    addTearDown(unattached.dispose);
    unattached.holdKeys();
    expect(unattached.holdsKeys, isFalse);
    expect(other.holdsKeys, isTrue);
  });

  testTwk('Tab moves the focus only when no node and no InputListener takes '
      'it', (t) async {
    var listenerTakes = true;
    await t.pumpWidget(
      InputListener(
        onEvent: (e) => listenerTakes && e is KeyEvent,
        child: Focus(
          skipTraversal: true,
          onKeyEvent: (node, event) =>
              event.shift ? KeyEventResult.handled : KeyEventResult.ignored,
          child: column([const Field('a'), const Field('b')]),
        ),
      ),
    );
    expect(await tab(t, 'tab'), [null]);
    listenerTakes = false;
    expect(await tab(t, 'tab tab shift+tab'), ['a', 'b', 'b']);
  });

  testTwk('Tab released moves nothing', (t) async {
    await t.pumpWidget(
      column([const Field('a'), const Field('b')]),
      kittyKeyboard: true,
    );
    await t.input('\x1b[9;1:3u'.codeUnits);
    await t.pump();
    expect(focused(t), isNull);
    await t.input('\x1b[9;1:2u'.codeUnits);
    await t.pump();
    expect(focused(t), 'a');
  });

  testTwk('the first node mounted with autofocus in a scope without focus '
      'gets it, shown in the frame that mounts it', (t) async {
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          const Field('a'),
          const Field('b', autofocus: true),
          const Field('c', autofocus: true),
          if (s.step >= 1) const Field('d', autofocus: true),
          if (s.step >= 2) const FocusScope(child: Field('e', autofocus: true)),
        ]),
      ),
      duration: Duration.zero,
    );
    expect(focused(t), 'b');
    expect(t.lines.take(3), [' a', '>b', ' c']);
    host.currentState!.change(1);
    await t.pump();
    expect(focused(t), 'b');
    host.currentState!.change(2);
    await t.pump();
    expect(focused(t), 'e');
    expect(t.lines.take(5), [' a', ' b', ' c', ' d', '>e']);
  });

  testTwk('the focus stays on a node whose widgets are rebuilt, and moves '
      'with one a GlobalKey moves', (t) async {
    final key = GlobalKey();
    final told = <String>[];
    final left = FocusNode(debugLabel: 'left');
    final right = FocusNode(debugLabel: 'right');
    for (final node in [left, right]) {
      node.addListener(() => told.add('${node.debugLabel} ${node.hasFocus}'));
    }
    await t.pumpWidget(
      Host(key: host, (s) {
        final b = Field(
          'b',
          key: key,
          onKeyEvent: (_, _) => KeyEventResult.ignored,
        );
        return column([
          Focus(
            focusNode: left,
            skipTraversal: true,
            child: column([const Field('a'), if (s.step != 1) b]),
          ),
          Focus(
            focusNode: right,
            skipTraversal: true,
            child: column([const Field('c'), if (s.step == 1) b]),
          ),
        ]);
      }),
    );
    expect(await tab(t, 'tab tab'), ['a', 'b']);
    final b = t.binding.focusManager.primaryFocus!;
    expect(told, ['left true']);
    host.currentState!.change(2);
    await t.pump();
    expect(t.binding.focusManager.primaryFocus, same(b));
    expect(told, ['left true']);
    host.currentState!.change(1);
    await t.pump();
    expect(t.binding.focusManager.primaryFocus, same(b));
    expect(b.parent, same(right));
    expect(told, ['left true', 'left false', 'right true']);
    expect(t.lines.take(3), [' a', ' c', '>b']);
    expect(await tab(t, 'tab'), ['a']);
  });

  testTwk('another focusNode takes the place of the one before, with the '
      'focus', (t) async {
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    await t.pumpWidget(
      Host(
        key: host,
        (s) => Focus(
          focusNode: s.step == 0 ? first : second,
          skipTraversal: true,
          child: const Field('a', autofocus: true),
        ),
      ),
    );
    final a = t.binding.focusManager.primaryFocus!;
    expect(a.debugLabel, 'a');
    expect(a.parent, same(first));
    host.currentState!.change(1);
    await t.pump();
    expect(a.parent, same(second));
    expect(first.context, isNull);
    expect(second.hasFocus, isTrue);
    expect(await tab(t, 'tab'), ['a']);
    second.requestFocus();
    host.currentState!.change(0);
    await t.pump();
    expect(first.hasPrimaryFocus, isTrue);
    expect(second.context, isNull);
  });

  testTwk('the focus moves off a node removed from the tree to the next '
      'node of its scope, else the previous, else the scope, in the frame '
      'that removes it', (t) async {
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          if (s.step < 3) const Field('a', key: Key('a')),
          if (s.step < 1) const Field('b', key: Key('b')),
          if (s.step < 2) const Field('c', key: Key('c')),
          const Field('d', key: Key('d'), canRequestFocus: false),
        ]),
      ),
    );
    expect(await tab(t, 'tab tab'), ['a', 'b']);
    final manager = t.binding.focusManager;
    final frames = t.terminal.frames;
    final before = frames.length;
    host.currentState!.change(1);
    await t.pump();
    expect(focused(t), 'c', reason: 'the next, not the one focused before');
    expect(t.lines.take(3), [' a', '>c', ' d']);
    expect(frames, hasLength(before + 1));
    host.currentState!.change(2);
    await t.pump();
    expect(focused(t), 'a', reason: 'the last gives it to the previous');
    expect(t.lines.take(2), ['>a', ' d']);
    expect(frames, hasLength(before + 2));
    host.currentState!.change(3);
    await t.pump();
    expect(manager.primaryFocus, same(manager.rootScope));
    expect(t.lines.first, ' d');
    expect(frames, hasLength(before + 3));
  });

  testTwk('a node removed with what is around it passes the focus to the '
      'node that took its place, else to the next after where it was', (
    t,
  ) async {
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          const Field('a', key: Key('a')),
          if (s.step < 2)
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: s.step == 0
                  ? const Field('b', key: Key('b'))
                  : const Field('b2', key: Key('b2')),
            )
          else
            const Field('x', key: Key('x')),
          const Field('c', key: Key('c')),
        ]),
      ),
    );
    expect(await tab(t, 'tab tab'), ['a', 'b']);
    host.currentState!.change(1);
    await t.pump();
    expect(focused(t), 'b2', reason: 'b2 took the place of b');
    expect(t.lines.take(3), [' a', ' >b2', ' c']);
    host.currentState!.change(2);
    await t.pump();
    expect(focused(t), 'x', reason: 'x is after a, where the Padding was');
    expect(t.lines.take(3), [' a', '>x', ' c']);
  });

  testTwk('a scope removed gives the focus back to the node focused before '
      'it', (t) async {
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          const Field('a', autofocus: true),
          if (s.step == 1) const FocusScope(child: Field('x', autofocus: true)),
        ]),
      ),
    );
    expect(focused(t), 'a');
    host.currentState!.change(1);
    await t.pump();
    expect(focused(t), 'x');
    expect(await tab(t, 'tab'), ['x']);
    host.currentState!.change(0);
    await t.pump();
    expect(focused(t), 'a');
    expect(t.lines.first, '>a');
  });

  testTwk('a scope removed while it has the focus itself gives it back to '
      'the node focused before it, not to a neighbour', (t) async {
    final scope = FocusScopeNode(debugLabel: 'scope');
    addTearDown(scope.dispose);
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          const Field('a', autofocus: true),
          const Field('b'),
          if (s.step == 1) FocusScope(node: scope, child: const Text('x')),
        ]),
      ),
    );
    expect(focused(t), 'a');
    host.currentState!.change(1);
    await t.pump();
    scope.requestFocus();
    await t.pump();
    expect(focused(t), 'scope');
    host.currentState!.change(0);
    await t.pump();
    expect(focused(t), 'a');
  });

  testTwk('requestFocus and unfocus move the focus at once; the listeners of '
      'the nodes whose focus changed are told before the next build', (
    t,
  ) async {
    final told = <String>[];
    final a = FocusNode(debugLabel: 'a');
    final outer = FocusNode(debugLabel: 'outer');
    for (final node in [a, outer]) {
      node.addListener(
        () => told.add(
          '${node.debugLabel} ${node.hasFocus} ${node.hasPrimaryFocus}',
        ),
      );
    }
    await t.pumpWidget(
      Focus(
        focusNode: outer,
        child: column([Field('a', node: a), const Field('b')]),
      ),
    );
    a.requestFocus();
    expect(a.hasPrimaryFocus, isTrue);
    expect(outer.hasFocus, isTrue);
    expect(told, isEmpty);
    await t.pump();
    expect(told, ['a true true', 'outer true false']);
    expect(t.lines.first, '>a');
    told.clear();
    a.unfocus();
    expect(
      t.binding.focusManager.primaryFocus,
      t.binding.focusManager.rootScope,
    );
    await t.pump();
    expect(told, ['a false false', 'outer false false']);
    expect(t.lines.first, ' a');
    told.clear();
    outer.requestFocus();
    await t.pump();
    expect(told, ['outer true true']);
  });

  testTwk('unfocus gives the focus to the nearest scope above that can '
      'take it, past one that cannot', (t) async {
    final a = FocusNode(debugLabel: 'a');
    addTearDown(a.dispose);
    final closed = FocusScopeNode(debugLabel: 'closed', canRequestFocus: false);
    addTearDown(closed.dispose);
    await t.pumpWidget(
      FocusScope(
        node: closed,
        child: column([Field('a', node: a)]),
      ),
    );
    a.requestFocus();
    expect(focused(t), 'a');
    a.unfocus();
    expect(
      t.binding.focusManager.primaryFocus,
      same(t.binding.focusManager.rootScope),
    );
  });

  testTwk('a Focus sets whether the nodes below its own can be focused', (
    t,
  ) async {
    final pane = FocusNode(debugLabel: 'pane');
    addTearDown(pane.dispose);
    await t.pumpWidget(
      Focus(
        focusNode: pane,
        descendantsAreFocusable: false,
        child: const Field('a'),
      ),
    );
    expect(pane.descendantsAreFocusable, isFalse);
  });

  test('a node describes itself by its kind and its label', () {
    final named = FocusNode(debugLabel: 'name');
    final scope = FocusScopeNode(debugLabel: 'dialog');
    final plain = FocusNode();
    addTearDown(() {
      for (final n in [named, scope, plain]) {
        n.dispose();
      }
    });
    expect('$named', 'FocusNode(name)');
    expect('$scope', 'FocusScopeNode(dialog)');
    expect('$plain', 'FocusNode');
  });

  testTwk('an onKeyEvent that throws ends the app with the error and the '
      'path of its Focus', (t) async {
    await t.pumpWidget(
      column([
        Focus(
          autofocus: true,
          onKeyEvent: (_, _) => throw StateError('boom'),
          child: const Text('x'),
        ),
      ]),
    );
    await expectLater(
      t.press('a'),
      throwsA(
        isA<WidgetError>()
            .having((e) => e.path, 'path', 'Column → Focus')
            .having((e) => e.error, 'error', isA<StateError>()),
      ),
    );
  });

  testTwk('the nodes below one whose descendants are not focusable cannot '
      'be focused: Tab passes them by, requestFocus and autofocus focus none '
      'of them, and the one that has the focus passes it to the next node of '
      'its scope; the node itself still can', (t) async {
    final b = FocusNode();
    addTearDown(b.dispose);
    await t.pumpWidget(
      Host(
        key: host,
        (s) => column([
          const Field('a'),
          Focus(
            descendantsAreFocusable: s.step != 1,
            debugLabel: 'pane',
            child: column([Field('b', node: b), const Field('c')]),
          ),
          Focus(
            descendantsAreFocusable: false,
            canRequestFocus: false,
            child: column([const Field('e', autofocus: true)]),
          ),
          const Field('d'),
        ]),
      ),
    );
    expect(focused(t), isNull);
    expect(await tab(t, 'tab tab tab tab tab'), ['a', 'pane', 'b', 'c', 'd']);
    b.requestFocus();
    await t.pump();
    expect(focused(t), 'b');
    host.currentState!.change(1);
    await t.pump();
    expect(focused(t), 'd', reason: 'the next node after the pane');
    expect(t.lines.take(3), [' a', ' b', ' c']);
    expect(await tab(t, 'tab tab tab tab'), ['a', 'pane', 'd', 'a']);
    b.requestFocus();
    await t.pump();
    expect(focused(t), 'a');
    host.currentState!.change(0);
    await t.pump();
    b.requestFocus();
    await t.pump();
    expect(focused(t), 'b');
  });

  testTwk('a scope does not give the focus back to a node below one whose '
      'descendants are not focusable, and a key with no node focused does '
      'not start below it', (t) async {
    final seen = <String>[];
    final scope = FocusScopeNode(debugLabel: 'scope');
    final b = FocusNode();
    addTearDown(scope.dispose);
    addTearDown(b.dispose);
    await t.pumpWidget(
      Host(
        key: host,
        (s) => FocusScope(
          node: scope,
          child: Focus(
            descendantsAreFocusable: s.step != 1,
            canRequestFocus: false,
            child: KeyBindings(
              {'x': () => seen.add('x')},
              child: column([Field('b', node: b)]),
            ),
          ),
        ),
      ),
    );
    b.requestFocus();
    await t.pump();
    await t.press('x');
    expect(seen, ['x']);
    host.currentState!.change(1);
    await t.pump();
    expect(t.binding.focusManager.primaryFocus, same(scope));
    scope.requestFocus();
    await t.pump();
    expect(t.binding.focusManager.primaryFocus, same(scope));
    await t.press('x');
    expect(seen, ['x']);
  });

  test('outside an app a Focus attaches its node to no focus tree', () {
    final node = FocusNode();
    final owner = BuildOwner();
    late BuildContext below;
    RootWidget(
      child: Focus(
        focusNode: node,
        child: Host((s) {
          below = s.context;
          return const SizedBox.shrink();
        }),
      ),
    ).attach(owner);
    expect(Focus.of(below), same(node));
    expect(() => FocusScope.of(below), throwsStateError);
    node.requestFocus();
    expect(node.hasFocus, isFalse);
    expect(node.nextFocus(), isFalse);
  });

  test('Focus.of without a Focus above is a StateError that says where', () {
    late BuildContext below;
    RootWidget(
      child: Host((s) {
        below = s.context;
        return const SizedBox.shrink();
      }),
    ).attach(BuildOwner());
    expect(Focus.maybeOf(below), isNull);
    expect(
      () => Focus.of(below),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'no Focus above Host: an app puts one above it',
        ),
      ),
    );
  });
}
