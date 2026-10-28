// The keys the layers on the key path handle now, with what they are bound
// to and their hints: the nearest layer's first, a key passed on by one
// listed from the next; the signal that they may have changed, told when
// the focus moves or a layer on the path changes and not otherwise, nor
// for a key bound to another callback alone; hints of keys not bound named.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final class Save extends Intent {
  const Save();
}

final class Open extends Intent {
  const Open();
}

/// Saves while [enabled].
final class SaveAction extends Action<Save> {
  var enabled = true;

  @override
  bool isEnabled(Save intent) => enabled;

  @override
  void invoke(Save intent) {}
}

/// A [Focus] named [label] that shows it.
final class Field extends StatelessWidget {
  const Field(this.label, {this.node, this.autofocus = false, super.key});

  final String label;
  final FocusNode? node;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    autofocus: autofocus,
    debugLabel: label,
    child: Text(label),
  );
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

final host = GlobalKey<HostState>();

void nothing() {}

void cut() {}

void quit() {}

/// The active keys of the app [t] runs, as text.
List<String> keys(TwkTester t) => [
  for (final key in t.binding.focusManager.activeKeys) '$key',
];

/// Counts the times the app's [FocusManager.keysChanged] is told.
int Function() countChanges(TwkTester t) {
  var count = 0;
  void listener() => count++;
  t.binding.focusManager.keysChanged.addListener(listener);
  addTearDown(
    () => t.binding.focusManager.keysChanged.removeListener(listener),
  );
  return () {
    final n = count;
    count = 0;
    return n;
  };
}

void main() {
  testTwk('the keys of the layers from the focus up, the nearest first, a '
      'key once; those bound to null or to an intent no enabled action does '
      'pass on to the layers above', (t) async {
    final save = SaveAction();
    await t.pumpWidget(
      Actions(
        {Save: save},
        child: const KeyBindings(
          {'q': nothing, 'ctrl+s': nothing, 'x': nothing},
          hints: {'q': 'quit', 'ctrl+s': 'save all'},
          child: Shortcuts(
            {'ctrl+s': Save(), 'enter': Open()},
            hints: {'ctrl+s': 'save', 'enter': 'open'},
            child: KeyBindings(
              {'x': nothing, 'q': null, 'up': nothing},
              hints: {'x': 'cut', 'q': 'never'},
              child: Field('list', autofocus: true),
            ),
          ),
        ),
      ),
    );
    expect(keys(t), ['x cut', 'up', 'ctrl+s save', 'q quit']);
    save.enabled = false;
    expect(keys(t), ['x cut', 'up', 'q quit', 'ctrl+s save all']);
  });

  testTwk('a key carries what the layer that takes it binds it to: the '
      'callback or the intent', (t) async {
    final save = SaveAction();
    await t.pumpWidget(
      Actions(
        {Save: save},
        child: const KeyBindings(
          {'q': quit, 'ctrl+s': nothing},
          child: Shortcuts(
            {'ctrl+s': Save()},
            hints: {'ctrl+s': 'save'},
            child: KeyBindings(
              {'x': cut, 'q': null},
              child: Field('list', autofocus: true),
            ),
          ),
        ),
      ),
    );
    final x = KeyCombo.parse('x');
    final ctrlS = KeyCombo.parse('ctrl+s');
    final q = KeyCombo.parse('q');
    expect(t.binding.focusManager.activeKeys, [
      ActiveKey(x, binding: cut),
      ActiveKey(ctrlS, binding: const Save(), hint: 'save'),
      ActiveKey(q, binding: quit),
    ]);
    save.enabled = false;
    expect(t.binding.focusManager.activeKeys, [
      ActiveKey(x, binding: cut),
      ActiveKey(q, binding: quit),
      ActiveKey(ctrlS, binding: nothing),
    ]);
    expect(ActiveKey(x, binding: cut), isNot(ActiveKey(x, binding: quit)));
    expect(
      ActiveKey(x, binding: cut, then: [q]).hashCode,
      ActiveKey(x, binding: cut, then: [q]).hashCode,
    );
  });

  testTwk('the keys follow the focus: keysChanged is told once when it '
      'moves, and before the frame that shows it', (t) async {
    final left = FocusNode();
    final right = FocusNode();
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    await t.pumpWidget(
      KeyBindings(
        const {'q': nothing},
        hints: const {'q': 'quit'},
        child: Row(
          children: [
            KeyBindings(
              const {'d': nothing},
              hints: const {'d': 'delete'},
              child: Field('left', node: left),
            ),
            KeyBindings.combos(
              {const KeyCombo(KeyCode.enter): nothing},
              hints: {const KeyCombo(KeyCode.enter): 'open'},
              child: Field('right', node: right),
            ),
          ],
        ),
      ),
    );
    final changes = countChanges(t);
    expect(keys(t), ['q quit']);
    left.requestFocus();
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['d delete', 'q quit']);
    right.requestFocus();
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['enter open', 'q quit']);
    await t.pump();
    expect(changes(), 0);
  });

  testTwk('the layers below the focused node are listed from the moment it '
      'has the focus, the nearest first; one mounted below them later tells '
      'keysChanged', (t) async {
    final node = FocusNode(debugLabel: 'field');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Host(
        key: host,
        (step) => KeyBindings(
          const {'q': quit},
          hints: const {'q': 'quit'},
          child: Column(
            children: [
              const Field('other', autofocus: true),
              Focus(
                focusNode: node,
                child: KeyBindings(
                  const {'enter': nothing},
                  hints: const {'enter': 'open'},
                  child: step == 0
                      ? const Text('field')
                      : const KeyBindings(
                          {'d': cut},
                          hints: {'d': 'delete'},
                          child: Text('field'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final changes = countChanges(t);
    expect(keys(t), ['q quit']);
    node.requestFocus();
    expect(keys(t), ['enter open', 'q quit']);
    await t.pump();
    expect(changes(), 1);
    host.currentState!.change(1);
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['d delete', 'enter open', 'q quit']);
    host.currentState!.change(0);
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['enter open', 'q quit']);
  });

  testTwk('keysChanged is told when a layer on the key path is built with '
      'other keys or hints, or the Actions above it with other actions; not '
      'for the same keys, nor for a layer off the path', (t) async {
    final save = SaveAction();
    await t.pumpWidget(
      Host(
        key: host,
        (step) => Actions(
          step == 4 ? {Save: save} : const {},
          child: Shortcuts(
            const {'ctrl+s': Save()},
            child: Row(
              children: [
                KeyBindings(
                  {'a': nothing, if (step >= 1) 'b': nothing},
                  hints: {if (step >= 2) 'a': 'add'},
                  child: const Field('on', autofocus: true),
                ),
                KeyBindings(
                  {'c': nothing, if (step >= 3) 'd': nothing},
                  child: const Field('off'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final changes = countChanges(t);
    expect(keys(t), ['a']);
    host.currentState!.change(0);
    await t.pump();
    expect(changes(), 0);
    host.currentState!.change(1);
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['a', 'b']);
    host.currentState!.change(2);
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['a add', 'b']);
    host.currentState!.change(3);
    await t.pump();
    expect(changes(), 0);
    host.currentState!.change(4);
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['a add', 'b', 'ctrl+s']);
  });

  testTwk('keysChanged is not told for a layer built with a key bound to '
      'another callback alone, as a closure made in each build is; it is '
      'for a key bound to another intent', (t) async {
    final actions = <Type, Action<Intent>>{
      Save: SaveAction(),
      Open: CallbackAction<Open>(onInvoke: (_) {}),
    };
    await t.pumpWidget(
      Host(
        key: host,
        (step) => Actions(
          actions,
          child: Shortcuts(
            {'enter': step == 2 ? const Save() : const Open()},
            child: KeyBindings(
              {'a': () {}},
              child: const Field('on', autofocus: true),
            ),
          ),
        ),
      ),
    );
    final changes = countChanges(t);
    host.currentState!.change(1);
    await t.pump();
    expect(changes(), 0);
    host.currentState!.change(2);
    await t.pump();
    expect(changes(), 1);
    expect(t.binding.focusManager.activeKeys.last.binding, const Save());
  });

  testTwk('with no node focused, a layer mounted around the app is listed, '
      'and keysChanged told; not for a node the key path does not reach', (
    t,
  ) async {
    await t.pumpWidget(
      Host(
        key: host,
        (step) => step == 0
            ? const Text('none')
            : KeyBindings(
                const {'q': nothing},
                hints: const {'q': 'quit'},
                child: Column(
                  children: [
                    const Text('some'),
                    if (step == 2) const Field('field'),
                  ],
                ),
              ),
      ),
    );
    final changes = countChanges(t);
    expect(keys(t), isEmpty);
    host.currentState!.change(1);
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['q quit']);
    host.currentState!.change(2);
    await t.pump();
    expect(changes(), 0);
    host.currentState!.change(0);
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), isEmpty);
  });

  testTwk('a hint for a key the layer does not bind fails its build, named in '
      'the log', (t) async {
    await t.pumpWidget(
      const Column(
        children: [
          KeyBindings(
            {'q': nothing},
            // the failure is what is tested
            // ignore: twk_lints/key_names
            hints: {'ctrl+q': 'quit'},
            child: Text('a'),
          ),
          Shortcuts(
            {'enter': Open(), 'A': Open()},
            // the failure is what is tested
            // ignore: twk_lints/key_names
            hints: {'A': 'all', 'shift+a': 'all'},
            child: Text('b'),
          ),
        ],
      ),
    );
    expect(
      [
        for (final r in t.logs.records)
          if (r.level == LogLevel.error) '${r.message}: ${r.error}',
      ],
      [
        allOf(
          startsWith('Column → KeyBindings failed to build'),
          contains('"ctrl+q" has a hint but is not bound'),
        ),
        allOf(
          startsWith('Column → Shortcuts failed to build'),
          contains('"A" and "shift+a" are the same key'),
        ),
      ],
    );
  });
}
