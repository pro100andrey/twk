// Keys bound to what they do: KeyBindings, Shortcuts and Actions as layers
// of the focus tree, the nearest the focus first; keys passed on by
// bindings that are disabled; the keys of an app or a scope with no node
// focused, and of the layers below the focused node from the moment it has
// the focus; typos named.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The counter of the plan: `up` counts, `q` quits.
final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => setState(() => _n++),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Box(
      border: const Border.all(type: BorderType.rounded),
      padding: const EdgeInsets.all(1),
      child: Text.rich(['Count: '.dim, '$_n'.bold.fg(Color.green)]),
    ),
  );
}

/// A [Focus] that shows its [label].
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

final class Save extends Intent {
  const Save();
}

final class Close extends Intent {
  const Close();
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

/// Hands its context to [found] as it builds.
final class Probe extends StatelessWidget {
  const Probe(this.found, {super.key});

  final void Function(BuildContext context) found;

  @override
  Widget build(BuildContext context) {
    found(context);
    return const Text('x');
  }
}

/// What a key that no node handles leaves in [seen].
InputListener listener(List<String> seen, Widget child) => InputListener(
  onEvent: (e) {
    if (e is KeyEvent) {
      seen.add('listener ${KeyCombo.fromEvent(e)}');
    }
    return false;
  },
  child: child,
);

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

void main() {
  testTwk('the counter of the plan: a KeyBindings above an app with no node '
      'to focus gets its keys', (t) async {
    await t.pumpWidget(const Counter(), size: (14, 5));
    expect(focused(t), isNull);
    expect(t.lines, [
      '╭────────────╮',
      '│            │',
      '│ Count: 0   │',
      '│            │',
      '╰────────────╯',
    ]);
    await t.press('up up');
    await t.pump();
    expect(t.lines[2], '│ Count: 2   │');
    expect(t.cell(9, 2).fg, Color.green);
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  testTwk('a key goes to the focused node, then to the layers above it, the '
      'nearest first; one that none of them binds goes on to the '
      'InputListeners, Tab and Ctrl+C', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    final other = FocusNode();
    addTearDown(other.dispose);
    await t.pumpWidget(
      listener(
        seen,
        KeyBindings(
          {'a': on('app a'), 'b': on('app b'), 'ctrl+c': on('app ctrl+c')},
          child: Column(
            children: [
              KeyBindings(
                {'a': on('list a'), 'c': on('list c'), 'tab': on('list tab')},
                child: Focus(
                  autofocus: true,
                  debugLabel: 'list',
                  onKeyEvent: (node, event) => event.char == 'x'
                      ? KeyEventResult.handled
                      : KeyEventResult.ignored,
                  child: const Text('list'),
                ),
              ),
              Field('other', node: other),
            ],
          ),
        ),
      ),
    );
    await t.press('x a b c d tab ctrl+c');
    expect(seen, [
      'list a',
      'app b',
      'list c',
      'listener d',
      'list tab',
      'app ctrl+c',
    ]);
    expect(focused(t), 'list');
    expect(t.isRunning, isTrue);
    other.requestFocus();
    seen.clear();
    await t.press('a c tab');
    expect(seen, ['app a', 'listener c', 'listener tab']);
    await t.pump();
    expect(focused(t), 'list');
  });

  testTwk('with no node focused, a key starts at the deepest node all the '
      'others are below: the layers around the whole app get it, the nearest '
      'first, and those around a part do not', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    final left = FocusNode();
    addTearDown(left.dispose);
    await t.pumpWidget(
      listener(
        seen,
        KeyBindings(
          debugLabel: 'app',
          {'a': on('app a'), 'b': on('app b')},
          child: KeyBindings(
            debugLabel: 'all',
            {'a': on('all a')},
            child: Row(
              children: [
                KeyBindings(
                  debugLabel: 'part',
                  {'b': on('part b'), 'c': on('part c')},
                  child: Field('left', node: left),
                ),
                const Field('right'),
              ],
            ),
          ),
        ),
      ),
    );
    final manager = t.binding.focusManager;
    expect(manager.primaryFocus, isNull);
    expect(
      [for (final n in manager.keyPath) n.debugLabel],
      [
        'all',
        'app',
        'root',
      ],
    );
    await t.press('a b c');
    expect(seen, ['all a', 'app b', 'listener c']);
    left.requestFocus();
    seen.clear();
    await t.press('a b c');
    expect(seen, ['all a', 'part b', 'part c']);
    left.unfocus();
    expect(manager.primaryFocus, same(manager.rootScope));
    expect(manager.keyPath.first.debugLabel, 'all');
  });

  testTwk('with no node focused, a node that can take the focus gets no '
      'key, below the layers around the app or beside them; once focused and '
      'unfocused, none again', (t) async {
    final seen = <String>[];
    KeyEventResult record(FocusNode node, KeyEvent event) {
      seen.add('${node.debugLabel} ${KeyCombo.fromEvent(event)}');
      return KeyEventResult.handled;
    }

    final field = FocusNode(debugLabel: 'field', onKeyEvent: record);
    addTearDown(field.dispose);
    await t.pumpWidget(
      KeyBindings(
        {'up': () => seen.add('app up')},
        child: Column(
          children: [
            const Text('count'),
            Focus(focusNode: field, child: const Text('field')),
          ],
        ),
      ),
    );
    await t.press('up x');
    field.requestFocus();
    await t.press('x');
    field.unfocus();
    await t.press('up x');
    expect(seen, ['app up', 'field x', 'app up']);
    await t.pumpWidget(
      KeyBindings(
        {'up': () => seen.add('app up')},
        child: Column(
          children: [
            Focus(
              debugLabel: 'layer',
              canRequestFocus: false,
              onKeyEvent: record,
              child: const Text('layer'),
            ),
            Focus(focusNode: field, child: const Text('field')),
          ],
        ),
      ),
    );
    seen.clear();
    await t.press('up x');
    expect(seen, ['app up']);
  });

  testTwk('a scope that has the focus itself starts its keys at the deepest '
      'node all of its own are below', (t) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    final dialog = FocusScopeNode(debugLabel: 'dialog');
    addTearDown(dialog.dispose);
    await t.pumpWidget(
      KeyBindings(
        {'n': on('new'), 'y': on('app y')},
        child: Column(
          children: [
            const Field('editor', autofocus: true),
            FocusScope(
              node: dialog,
              child: KeyBindings({'n': on('no')}, child: const Text('Delete?')),
            ),
          ],
        ),
      ),
    );
    await t.press('n');
    dialog.requestFocus();
    await t.press('n y');
    expect(seen, ['new', 'no', 'app y']);
    expect(focused(t), 'dialog');
  });

  testTwk('a key starts at the deepest layer below the focused node that '
      'all of its nodes are below, from the moment it has the focus: a key '
      'right after Tab reaches the layers below the node Tab focused', (
    t,
  ) async {
    final seen = <String>[];
    VoidCallback on(String name) =>
        () => seen.add(name);
    await t.pumpWidget(
      Column(
        children: [
          const Field('a', autofocus: true),
          Focus(
            debugLabel: 'b',
            child: KeyBindings(
              debugLabel: 'b keys',
              {'enter': on('b enter'), 'x': on('b x'), 'y': on('b y')},
              child: KeyBindings(
                debugLabel: 'b all',
                {'x': on('b all x')},
                child: Column(
                  children: [
                    KeyBindings({'y': on('part y')}, child: const Text('one')),
                    KeyBindings({'y': on('part y')}, child: const Text('two')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    await t.press('tab');
    await t.press('enter');
    expect(seen, ['b enter']);
    expect(
      [for (final n in t.binding.focusManager.keyPath) n.debugLabel],
      ['b all', 'b keys', 'b', 'root'],
    );
    await t.press('x y');
    expect(seen, ['b enter', 'b all x', 'b y']);
    seen.clear();
    await t.type('\x1b[Z\r\t\r\x1b[Zx\tx');
    expect(seen, ['b enter', 'b all x']);
    expect(focused(t), 'b');
  });

  testTwk('keys typed in one read across several Tabs each reach the layers '
      'below the node focused then', (t) async {
    final seen = <String>[];
    Widget field(String name, {bool autofocus = false}) => Focus(
      debugLabel: name,
      autofocus: autofocus,
      child: KeyBindings({'x': () => seen.add('$name x')}, child: Text(name)),
    );
    await t.pumpWidget(
      listener(
        seen,
        KeyBindings(
          {'x': () => seen.add('app x'), 'enter': () => seen.add('app enter')},
          child: Column(
            children: [field('a', autofocus: true), field('b'), field('c')],
          ),
        ),
      ),
    );
    await t.type('x\tx\tx\tx\x1b[Zx\ry');
    expect(seen, [
      'a x',
      'listener tab',
      'b x',
      'listener tab',
      'c x',
      'listener tab',
      'a x',
      'listener shift+tab',
      'c x',
      'app enter',
      'listener y',
    ]);
    await t.pump();
    expect(focused(t), 'c');
  });

  testTwk('Shortcuts bind keys to intents, which the nearest enabled action '
      'for them in the Actions above the focused node does; with none '
      'enabled, the key passes on', (t) async {
    final seen = <String>[];
    final mine = SaveAction('a', seen);
    final all = SaveAction('all', seen);
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await t.pumpWidget(
      listener(
        seen,
        KeyBindings(
          {'ctrl+s': () => seen.add('outer ctrl+s')},
          child: Shortcuts(
            const {'ctrl+s': Save(), 'escape': Close()},
            child: Actions(
              {Save: all},
              child: Column(
                children: [
                  Actions({Save: mine}, child: Field('a', node: a)),
                  Field('b', node: b),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    a.requestFocus();
    await t.press('ctrl+s');
    b.requestFocus();
    await t.press('ctrl+s');
    a.requestFocus();
    mine.enabled = false;
    await t.press('ctrl+s');
    all.enabled = false;
    await t.press('ctrl+s escape');
    expect(seen, [
      'save a',
      'save all',
      'save all',
      'outer ctrl+s',
      'listener escape',
    ]);
  });

  testTwk('Actions find the enabled action for an intent from a context up; '
      'invoke does it', (t) async {
    final seen = <String>[];
    final inner = SaveAction('inner', seen)..enabled = false;
    late BuildContext context;
    await t.pumpWidget(
      Actions(
        {Save: SaveAction('outer', seen)},
        child: Actions(
          {Save: inner},
          child: Probe((c) => context = c),
        ),
      ),
    );
    expect(Actions.maybeFind(context, const Save()), isA<SaveAction>());
    expect(Actions.maybeFind(context, const Close()), isNull);
    expect(Actions.maybeInvoke(context, const Save()), isTrue);
    expect(Actions.maybeInvoke(context, const Close()), isFalse);
    inner.enabled = true;
    expect(Actions.maybeInvoke(context, const Save()), isTrue);
    expect(seen, ['save outer', 'save inner']);
  });

  testTwk('an action that does not say when it is enabled always is', (
    t,
  ) async {
    final seen = <String>[];
    await t.pumpWidget(
      Shortcuts(
        const {'ctrl+s': Save()},
        child: Actions(
          {Save: _Always(seen)},
          child: const Field('f', autofocus: true),
        ),
      ),
    );
    await t.press('ctrl+s');
    expect(seen, ['saved']);
  });

  testTwk('a CallbackAction calls its callback with the intent while it is '
      'enabled; disabled, the key passes on', (t) async {
    final seen = <String>[];
    Widget app({required bool enabled}) => KeyBindings(
      {'ctrl+s': () => seen.add('passed on')},
      child: Shortcuts(
        const {'ctrl+s': Save()},
        child: Actions(
          {
            Save: CallbackAction<Save>(
              onInvoke: (intent) => seen.add('$intent'),
              enabled: enabled,
            ),
          },
          child: const Field('f', autofocus: true),
        ),
      ),
    );
    await t.pumpWidget(app(enabled: true));
    await t.press('ctrl+s');
    await t.pumpWidget(app(enabled: false));
    await t.press('ctrl+s');
    expect(seen, ["Instance of 'Save'", 'passed on']);
  });

  testTwk('a key a KeyBindings binds to null passes on', (t) async {
    final seen = <String>[];
    await t.pumpWidget(
      KeyBindings(
        {'q': () => seen.add('quit')},
        child: KeyBindings(
          {'q': null, 'w': () => seen.add('w')},
          child: const Field('f', autofocus: true),
        ),
      ),
    );
    await t.press('q w');
    expect(seen, ['quit', 'w']);
  });

  testTwk('typed combos bind keys as the specs do', (t) async {
    final seen = <String>[];
    await t.pumpWidget(
      Actions(
        {Save: SaveAction('s', seen)},
        child: KeyBindings.combos(
          {
            const KeyCombo(KeyCode.up): () => seen.add('up'),
            KeyCombo.char('q', modifiers: Mod.ctrl): () => seen.add('ctrl+q'),
          },
          child: Shortcuts.combos({
            KeyCombo.char('s'): const Save(),
          }, child: const Text('x')),
        ),
      ),
    );
    await t.press('up ctrl+q s');
    expect(seen, ['up', 'ctrl+q', 'save s']);
  });

  testTwk('a spec that is not one, or two specs of the same key, fail the '
      'build of their layer, named in the log', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          // the failure is what is tested
          // ignore: twk_lints/key_names
          KeyBindings({'ctlr+s': () {}}, child: const Text('a')),
          const Shortcuts({
            'A': Save(),
            // the failure is what is tested
            // ignore: twk_lints/key_names
            'shift+a': Close(),
          }, child: Text('b')),
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
          contains('"ctlr" in "ctlr+s" is not a modifier'),
        ),
        allOf(
          startsWith('Column → Shortcuts failed to build'),
          contains('"A" and "shift+a" are the same key'),
        ),
      ],
    );
  });
}

/// Saves into [seen], enabled as an [Action] is by default.
final class _Always extends Action<Save> {
  _Always(this.seen);

  final List<String> seen;

  @override
  void invoke(Save intent) => seen.add('saved');
}
