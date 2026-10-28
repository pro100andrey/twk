// The key hints bar: the keys of the layers from the focus up with their
// hints, following the focus and the layers in the frame that changes
// them; keys without a hint, names, separators, and a row too narrow; a
// sequence whole, and what can follow the keys held of one.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] named [label] that shows it.
final class Field extends StatelessWidget {
  const Field(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Focus(debugLabel: label, child: Text(label));
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

/// An app of two fields, each in a layer of its own, the bar below them.
Widget app({bool showUnhinted = false}) => KeyBindings(
  const {'q': nothing},
  hints: const {'q': 'quit'},
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const KeyBindings(
        {'ctrl+s': nothing},
        hints: {'ctrl+s': 'save'},
        child: Field('editor'),
      ),
      const KeyBindings(
        {'d': nothing, 'x': nothing},
        hints: {'d': 'delete'},
        child: Field('list'),
      ),
      KeyHintsBar(showUnhinted: showUnhinted),
    ],
  ),
);

void main() {
  testTwk('shows the keys of the layers from the focus up with their hints, '
      'the nearest first, and follows the focus in the frame that moves '
      'it', (t) async {
    await t.pumpWidget(Theme.terminal(child: app()), size: (30, 3));
    expect(t.lines[2], 'q quit');
    // the keys bold in the text color
    expect(t, styleAt(0, 2, hasAttr(Attr.bold)));
    expect(t, styleAt(0, 2, isNot(hasFg(Color.blue))));
    expect(t, styleAt(2, 2, hasFg(const Color.indexed(245))));
    final rows = <String>[];
    for (var i = 0; i < 3; i++) {
      await t.press('tab');
      await t.pump();
      rows.add(t.lines[2]);
    }
    expect(rows, [
      'ctrl+s save   q quit',
      'd delete   q quit',
      'ctrl+s save   q quit',
    ]);
  });

  testTwk('shows the keys without a hint by their names, when asked', (
    t,
  ) async {
    await t.pumpWidget(
      Theme.terminal(child: app(showUnhinted: true)),
      size: (30, 3),
    );
    await t.press('tab tab');
    await t.pump();
    expect(t.lines[2], 'd delete   x   q quit');
  });

  testTwk('follows a layer built with other keys, and an action enabled or '
      'disabled, with the focus where it was', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: Host(
          key: host,
          (step) => Shortcuts(
            const {'ctrl+s': Save()},
            hints: const {'ctrl+s': 'save'},
            child: KeyBindings(
              {'d': step == 1 ? null : nothing},
              hints: const {'d': 'delete'},
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Actions(
                    {
                      Save: CallbackAction<Save>(
                        onInvoke: (_) {},
                        enabled: step != 2,
                      ),
                    },
                    child: const Focus(autofocus: true, child: Text('field')),
                  ),
                  const KeyHintsBar(),
                ],
              ),
            ),
          ),
        ),
      ),
      size: (30, 2),
    );
    expect(t.lines[1], 'd delete   ctrl+s save');
    final rows = <String>[];
    for (var step = 1; step <= 3; step++) {
      host.currentState!.change(step);
      await t.pump();
      rows.add(t.lines[1]);
    }
    expect(rows, ['ctrl+s save', 'd delete', 'd delete   ctrl+s save']);
  });

  testTwk('names the arrows and Escape by their signs, Page Up and Down '
      'short, and shows keys of one family that share a hint as one', (
    t,
  ) async {
    const keys = {
      'up': 'move',
      'down': 'move',
      'left': 'move',
      'right': 'move',
      'pageup': 'a page',
      'pagedown': 'a page',
      'home': 'ends',
      'end': 'ends',
      'escape': 'back',
      'alt+up': 'raise',
      'alt+down': 'lower',
      'shift+tab': 'back',
      'enter': 'open',
    };
    await t.pumpWidget(
      Theme.terminal(
        child: KeyBindings(
          {for (final k in keys.keys) k: nothing},
          hints: keys,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Focus(autofocus: true, child: Text('field')),
              const KeyHintsBar(),
              // the names KeyCombo gives, each key on its own
              KeyHintsBar(keyLabel: (combo) => '$combo', joinKeys: false),
            ],
          ),
        ),
      ),
      size: (160, 3),
    );
    expect(
      t.lines[1].trimRight(),
      [
        '↑↓←→ move',
        'pgup pgdn a page',
        'home end ends',
        'esc back',
        'alt+↑ raise',
        'alt+↓ lower',
        'shift+tab back',
        'enter open',
      ].join('   '),
    );
    expect(t.lines[2], startsWith('up move   down move   left move   '));
    expect(t.lines[2], contains('   escape back   alt+up raise   '));
  });

  testTwk('keys of one family apart where their hints are', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: KeyBindings(
          {'up': nothing, 'q': nothing, 'down': nothing, 'pageup': nothing},
          hints: {'up': 'up', 'q': 'quit', 'down': 'down', 'pageup': 'up'},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Focus(autofocus: true, child: Text('field')),
              KeyHintsBar(),
            ],
          ),
        ),
      ),
      size: (40, 2),
    );
    expect(t.lines[1], '↑ up   q quit   ↓ down   pgup up');
  });

  testTwk('names the keys as keyLabel does, apart by the separator, and is '
      'cut off with "…" where the row ends', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: KeyBindings(
          const {'ctrl+s': nothing, 'q': nothing},
          hints: const {'ctrl+s': 'save', 'q': 'quit'},
          child: KeyHintsBar(
            keyLabel: (combo) => combo.toString().toUpperCase(),
            separator: ' · ',
          ),
        ),
      ),
      size: (14, 1),
    );
    expect(t.lines, ['CTRL+S save ·…']);
  });

  testTwk('shows a sequence whole, each key named as keyLabel names it, and '
      'while its first keys are held, the keys that can follow them', (
    t,
  ) async {
    await t.pumpWidget(
      Theme.terminal(
        child: KeyBindings(
          const {
            'ctrl+x ctrl+s': nothing,
            'space f f': nothing,
            'space f g': nothing,
            'q': nothing,
          },
          hints: const {
            'ctrl+x ctrl+s': 'save',
            'space f f': 'find',
            'space f g': 'grep',
            'q': 'quit',
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Focus(autofocus: true, child: Text('field')),
              const KeyHintsBar(),
              KeyHintsBar(keyLabel: (combo) => '$combo'.toUpperCase()),
            ],
          ),
        ),
      ),
      size: (64, 3),
    );
    expect(t.lines.skip(1), [
      'ctrl+x ctrl+s save   space f f find   space f g grep   q quit',
      'CTRL+X CTRL+S save   SPACE F F find   SPACE F G grep   Q quit',
    ]);
    final rows = <String>[];
    for (final key in ['space', 'f', 'escape']) {
      await t.press(key);
      await t.pump();
      rows.add(t.lines[1]);
    }
    expect(rows, [
      'f f find   f g grep',
      'f find   g grep',
      'ctrl+x ctrl+s save   space f f find   space f g grep   q quit',
    ]);
  });

  testTwk('keyStyle and separator give a plain look: the keys primary '
      'and bold, two blanks apart', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: KeyBindings(
          {'s': nothing, 'q': nothing},
          hints: {'s': 'save', 'q': 'quit'},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Focus(autofocus: true, child: Text('field')),
              // the theme's primary in bold
              KeyHintsBar(
                keyStyle: Style(fg: Color.blue, attrs: Attr.bold),
                separator: '  ',
              ),
            ],
          ),
        ),
      ),
      size: (30, 2),
    );
    expect(t.lines[1], 's save  q quit');
    expect(t, styleAt(0, 1, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
  });

  group('entries', () {
    void other() {}
    ActiveKey key(String keys, String? hint, [Object binding = nothing]) {
      final combos = KeyCombo.parseSequence(keys);
      return ActiveKey(
        combos.first,
        then: combos.skip(1).toList(),
        binding: binding,
        hint: hint,
      );
    }

    final keys = [
      key('up', 'move'),
      key('down', 'move', other),
      key('pageup', 'a window'),
      key('pagedown', 'a window'),
      key('alt+down', 'move'),
      key('f2', null),
      key('enter', 'restore'),
      key('space', 'restore'),
      key('enter', 'restore', other),
      key('g g', 'reset'),
      key(', r', 'reset'),
      key('g g', 'reset', other),
    ];

    test('join the keys of a family that share a hint, and list a key '
        'with its hint once', () {
      expect(KeyHintsBar.entries(keys), [
        ('↑↓', 'move'),
        ('pgup pgdn', 'a window'),
        ('alt+↓', 'move'),
        ('enter', 'restore'),
        ('space', 'restore'),
        ('g g', 'reset'),
        (', r', 'reset'),
      ]);
    });

    test('list the keys apart without joinKeys, by keyLabel, and those '
        'without a hint with showUnhinted', () {
      expect(
        KeyHintsBar.entries(
          keys.take(6),
          keyLabel: (c) => '$c',
          joinKeys: false,
          showUnhinted: true,
        ),
        [
          ('up', 'move'),
          ('down', 'move'),
          ('pageup', 'a window'),
          ('pagedown', 'a window'),
          ('alt+down', 'move'),
          ('f2', null),
        ],
      );
    });
  });
}

final class Save extends Intent {
  const Save();
}
