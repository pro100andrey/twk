// Keys pressed one after another bound as one: a layer holds the first
// keys of a sequence, which go to it first until the sequence is done, its
// time runs out or a key does not go on with it; a binding of the first
// keys alone done once the next key or the time tells; the keys that can
// follow listed while it holds them; held keys nothing takes dropped or
// replayed; the leader; an active key labelled by all its keys.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final class Save extends Intent {
  const Save();
}

/// Saves [what] into [seen] while [enabled].
final class SaveAction extends Action<Save> {
  SaveAction(this.what, this.seen);

  final String what;
  final List<String> seen;
  var enabled = true;

  @override
  bool isEnabled(Save intent) => enabled;

  @override
  void invoke(Save intent) => seen.add('save $what');
}

/// A [Focus] named [label] that takes the characters of [takes], each
/// noted in [seen].
final class Field extends StatelessWidget {
  const Field(
    this.label,
    this.seen, {
    this.takes = '',
    this.node,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final List<String> seen;
  final String takes;
  final FocusNode? node;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    autofocus: autofocus,
    debugLabel: label,
    onKeyEvent: (node, event) {
      if (event.char.isNotEmpty &&
          event.modifiers == 0 &&
          takes.contains(event.char)) {
        seen.add('$label ${event.char}');
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
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

/// What a key that no node takes leaves in [seen].
InputListener listener(List<String> seen, Widget child) => InputListener(
  onEvent: (e) {
    if (e is KeyEvent) {
      seen.add('listener ${KeyCombo.fromEvent(e)}');
    }
    return false;
  },
  child: child,
);

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

const second = Duration(seconds: 1);

void main() {
  testTwk('a sequence is done by its last key; the keys before it do nothing '
      'on their own, and the next go to its layer first, past the focused '
      'node', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    await t.pumpWidget(
      listener(
        seen,
        KeyBindings(
          {
            'g g': on('top'),
            'ctrl+x ctrl+s': on('save'),
            'ctrl+x s': on('save some'),
            'q': on('quit'),
          },
          child: Field('field', seen, takes: 's', autofocus: true),
        ),
      ),
    );
    await t.press('g');
    expect(seen, isEmpty);
    await t.press('g ctrl+x ctrl+s q ctrl+x s s');
    expect(seen, ['top', 'save', 'quit', 'save some', 'field s']);
  });

  testTwk('the keys a layer holds are let go once its sequenceTimeout passes '
      'without a key: dropped by default, replayed to the layers above with '
      'UnmatchedKeys.replay; without a timeout they wait', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    Widget app({
      UnmatchedKeys unmatched = UnmatchedKeys.drop,
      Duration? timeout = second,
    }) => listener(
      seen,
      KeyBindings(
        {'g': on('outer g')},
        child: KeyBindings(
          {'g g': on('top')},
          unmatched: unmatched,
          sequenceTimeout: timeout,
          child: Field('field', seen, autofocus: true),
        ),
      ),
    );
    await t.pumpWidget(app());
    await t.press('g');
    await t.pump(const Duration(milliseconds: 999));
    await t.press('g');
    expect(seen, ['top']);
    await t.press('g');
    await t.pump(second);
    await t.press('g');
    expect(seen, ['top']);
    await t.pump(second);
    expect(seen, ['top']);
    await t.pumpWidget(app(unmatched: UnmatchedKeys.replay));
    await t.press('g');
    await t.pump(second);
    expect(seen, ['top', 'outer g']);
    await t.pumpWidget(app(timeout: null));
    await t.press('g');
    await t.pump(const Duration(hours: 1));
    await t.press('g');
    expect(seen, ['top', 'outer g', 'top']);
  });

  testTwk('a key that does not go on with the keys held drops them and '
      'itself by default, Escape too; with replay the held keys go on to the '
      'layers above as keys bound alone, and the key is pressed anew, the '
      'focused node first', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    Widget app(UnmatchedKeys unmatched) => listener(
      seen,
      KeyBindings(
        {'g': on('outer g'), 'escape': on('outer escape')},
        child: KeyBindings(
          {'g g': on('top'), 'x': on('inner x')},
          unmatched: unmatched,
          child: Field('field', seen, takes: 'y', autofocus: true),
        ),
      ),
    );
    await t.pumpWidget(app(UnmatchedKeys.drop));
    await t.press('g x g escape g a y');
    expect(seen, ['field y']);
    seen.clear();
    await t.pumpWidget(app(UnmatchedKeys.replay));
    await t.press('g x g y g a');
    expect(seen, [
      'outer g',
      'inner x',
      'outer g',
      'field y',
      'outer g',
      'listener a',
    ]);
  });

  testTwk('a binding of the first keys of a sequence alone waits for the '
      'next key: one that goes on does the sequence, another does the '
      'binding and is pressed anew, as the time running out does the '
      'binding', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    await t.pumpWidget(
      listener(
        seen,
        KeyBindings(
          {
            'g': on('g'),
            'g g': on('top'),
            'd': on('delete'),
            'd d d': on('delete all'),
            'x': on('x'),
          },
          child: Field('field', seen, autofocus: true),
        ),
      ),
    );
    await t.press('g');
    expect(seen, isEmpty);
    await t.press('g');
    expect(seen, ['top']);
    await t.press('g x');
    expect(seen, ['top', 'g', 'x']);
    await t.press('g');
    await t.pump(second);
    expect(seen, ['top', 'g', 'x', 'g']);
    seen.clear();
    await t.press('d d x');
    expect(seen, ['delete', 'delete', 'x']);
    seen.clear();
    await t.press('d d');
    await t.pump(second);
    expect(seen, ['delete']);
    await t.pump(second);
    expect(seen, ['delete', 'delete']);
    seen.clear();
    await t.press('d d d');
    expect(seen, ['delete all']);
  });

  testTwk('a sequence bound to null is not taken: its keys are unmatched, '
      'the binding of the first alone done', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    await t.pumpWidget(
      KeyBindings(
        {'g': on('g'), 'g g': null, 'g e': on('end')},
        child: Field('field', seen, autofocus: true),
      ),
    );
    expect(keys(t), ['g', 'g e']);
    await t.press('g g');
    expect(seen, ['g']);
    await t.press('e');
    expect(seen, ['g', 'end']);
  });

  testTwk('across layers the nearest goes first: a key it binds alone hides '
      'the sequences above that start with it; a sequence of its own holds '
      'the key from the bindings above, which a replay reaches, a sequence '
      'there too', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    Widget app(int step) => listener(
      seen,
      KeyBindings(
        step == 0
            ? {'g g': on('outer top'), 'e': on('outer e')}
            : {'g': on('outer g'), 'e': on('outer e'), 'g x': on('outer g x')},
        child: KeyBindings(
          step == 0 ? {'g': on('near g')} : {'g g': on('near top')},
          unmatched: step == 2 ? UnmatchedKeys.replay : UnmatchedKeys.drop,
          child: Field('field', seen, autofocus: true),
        ),
      ),
    );
    await t.pumpWidget(app(0));
    expect(keys(t), ['g', 'e']);
    await t.press('g g e');
    expect(seen, ['near g', 'near g', 'outer e']);
    seen.clear();
    await t.pumpWidget(app(1));
    expect(keys(t), ['g g', 'e']);
    await t.press('g e g g');
    expect(seen, ['near top']);
    seen.clear();
    await t.pumpWidget(app(2));
    await t.press('g e g x');
    expect(seen, ['outer g', 'outer e', 'outer g x']);
  });

  testTwk('while a layer holds keys, activeKeys lists what can follow them, '
      'and only that, which KeyHintsBar shows; keysChanged is told as it '
      'starts holding, holds more and lets go, not for a sequence done in '
      'one read', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    await t.pumpWidget(
      KeyBindings(
        {'q': on('quit')},
        hints: const {'q': 'quit'},
        child: KeyBindings(
          {
            'space f f': on('find'),
            'space f g': on('grep'),
            'space b': on('buffers'),
            'z': on('z'),
          },
          hints: const {
            'space f f': 'find',
            'space f g': 'grep',
            'space b': 'buffers',
          },
          child: Column(
            children: [
              Field('field', seen, autofocus: true),
              const KeyHintsBar(),
            ],
          ),
        ),
      ),
      size: (30, 2),
    );
    final changes = countChanges(t);
    expect(keys(t), [
      'space f f find',
      'space f g grep',
      'space b buffers',
      'z',
      'q quit',
    ]);
    await t.press('space');
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['f f find', 'f g grep', 'b buffers']);
    await t.press('f');
    await t.pump();
    expect(changes(), 1);
    expect(keys(t), ['f find', 'g grep']);
    expect(t.lines[1].trim(), 'f find   g grep');
    final manager = t.binding.focusManager;
    expect([for (final k in manager.activeKeys) k.then], [isEmpty, isEmpty]);
    final f = KeyCombo.char('f');
    expect(
      ActiveKey(f, binding: seen.add, then: [f]),
      isNot(ActiveKey(f, binding: seen.add)),
    );
    await t.press('g');
    await t.pump();
    expect(changes(), 1);
    expect(seen, ['grep']);
    expect(keys(t).last, 'q quit');
    expect(manager.activeKeys.first.then, [
      KeyCombo.char('f'),
      KeyCombo.char('f'),
    ]);
    await t.type(' b');
    await t.pump();
    expect(seen, ['grep', 'buffers']);
    expect(changes(), 0);
  });

  testTwk('Shortcuts bind sequences too: the action is found from the '
      'focused node, while the keys are held as well', (t) async {
    final seen = <String>[];
    final save = SaveAction('mine', seen);
    await t.pumpWidget(
      listener(
        seen,
        Shortcuts(
          const {'ctrl+x ctrl+s': Save()},
          hints: const {'ctrl+x ctrl+s': 'save'},
          child: Actions(
            {Save: save},
            child: Field('field', seen, autofocus: true),
          ),
        ),
      ),
    );
    expect(keys(t), ['ctrl+x ctrl+s save']);
    await t.press('ctrl+x');
    expect(keys(t), ['ctrl+s save']);
    await t.press('ctrl+s');
    expect(seen, ['save mine']);
    save.enabled = false;
    expect(keys(t), isEmpty);
    await t.press('ctrl+x');
    expect(seen, ['save mine', 'listener ctrl+x']);
  });

  testTwk('the keys held are dropped when the focus moves', (t) async {
    final seen = <String>[];
    final other = FocusNode();
    addTearDown(other.dispose);
    await t.pumpWidget(
      KeyBindings(
        {'g g': () => seen.add('top')},
        child: Row(
          children: [
            Field('a', seen, autofocus: true),
            Field('b', seen, node: other),
          ],
        ),
      ),
    );
    await t.press('g');
    other.requestFocus();
    await t.press('g');
    expect(seen, isEmpty);
    await t.press('g');
    expect(seen, ['top']);
  });

  testTwk('leader in a sequence stands for the key the LeaderKey above '
      'names, space without one', (t) async {
    final seen = <String>[];
    Widget layer() => KeyBindings(
      {'leader w': () => seen.add('write')},
      hints: const {'leader w': 'write'},
      child: Field('field', seen, autofocus: true),
    );
    await t.pumpWidget(
      listener(
        seen,
        Host(
          key: host,
          (step) => step == 0
              ? layer()
              : LeaderKey(step == 1 ? ',' : 'ctrl+a', child: layer()),
        ),
      ),
    );
    expect(keys(t), ['space w write']);
    await t.press('space w');
    expect(seen, ['write']);
    host.currentState!.change(1);
    await t.pump();
    expect(keys(t), [', w write']);
    await t.press(', w space');
    expect(seen, ['write', 'write', 'listener space']);
    host.currentState!.change(2);
    await t.pump();
    expect(keys(t), ['ctrl+a w write']);
  });

  test('an active key is labelled by all its keys, each named as keyLabel '
      'names it, apart by a space', () {
    final keys = KeyCombo.parseSequence('ctrl+x ctrl+s');
    final save = ActiveKey(
      keys.first,
      then: keys.sublist(1),
      binding: const Save(),
      hint: 'save',
    );
    expect(save.label(), 'ctrl+x ctrl+s');
    expect(save.label((combo) => '^${combo.char.toUpperCase()}'), '^X ^S');
    expect('$save', 'ctrl+x ctrl+s save');
    expect(ActiveKey(keys.last, binding: const Save()).label(), 'ctrl+s');
  });

  testTwk('a sequence or a hint that is not one fails the build of its '
      'layer, named in the log', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          // the failure is what is tested
          // ignore: twk_lints/key_names
          KeyBindings({'g gg': () {}}, child: const Text('a')),
          KeyBindings(
            {'g g': () {}},
            // the failure is what is tested
            // ignore: twk_lints/key_names
            hints: const {'g e': 'end'},
            child: const Text('b'),
          ),
          const Shortcuts({
            'G g': Save(),
            // the failure is what is tested
            // ignore: twk_lints/key_names
            'shift+g g': Save(),
          }, child: Text('c')),
          LeaderKey(
            // the failure is what is tested
            // ignore: twk_lints/key_names
            'g g',
            child: KeyBindings({'leader a': () {}}, child: const Text('d')),
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
          contains('"gg" in "gg" is neither one character nor a key'),
        ),
        allOf(
          startsWith('Column → KeyBindings failed to build'),
          contains('"g e" has a hint but is not bound'),
        ),
        allOf(
          startsWith('Column → Shortcuts failed to build'),
          contains('"G g" and "shift+g g" are the same keys'),
        ),
        allOf(
          startsWith('Column → LeaderKey → KeyBindings failed to build'),
          contains('"g g" is 2 keys; one is meant'),
        ),
      ],
    );
  });
}
