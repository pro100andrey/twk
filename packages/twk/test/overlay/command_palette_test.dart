// The command palette: opened by Ctrl+P over the app, it lists the
// commands that can be done from the focused node and the keys hinted
// there, each with its key; what is typed filters and ranks them, its
// characters standing out; the keys move the highlight, Enter runs it
// from the focused node once closed, Escape and a click outside close it;
// those run last come first; a sequence shown whole; no Overlay.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Saves.
final class Save extends Intent {
  const Save();
}

/// Prints, which nothing does.
final class Print extends Intent {
  const Print();
}

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not.
final class Field extends StatelessWidget {
  const Field(this.label, {this.autofocus = false, super.key});

  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: autofocus, debugLabel: label, child: _Mark(label));
}

final class _Mark extends StatelessWidget {
  const _Mark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
}

/// An app with a palette of [commands], each command done added to [log];
/// Save done by an action above the palette, and the editor's own Save
/// below it.
Widget app(
  List<String> log, {
  List<Command>? commands,
  int rows = 10,
  PanelLook look = PanelLook.bordered,
}) => Overlay(
  child: Shortcuts(
    const {'ctrl+s': Save(), 'ctrl+o': Print()},
    hints: const {'ctrl+s': 'save', 'ctrl+o': 'print'},
    child: Actions(
      {Save: CallbackAction<Save>(onInvoke: (_) => log.add('save'))},
      child: CommandPalette(
        rows: rows,
        look: look,
        commands:
            commands ??
            [
              Command('Open file', onSelected: () => log.add('open')),
              const Command('Save file', intent: Save()),
              const Command('Print', intent: Print()),
            ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyBindings(
              {
                'ctrl+r': () => log.add('reload'),
                'ctrl+x': () => log.add('cut'),
              },
              hints: const {'ctrl+r': 'reload'},
              child: Actions(
                {
                  Save: CallbackAction<Save>(
                    onInvoke: (_) => log.add('save editor'),
                  ),
                },
                child: const Field('editor', autofocus: true),
              ),
            ),
            const Field('notes'),
            const Spacer(),
            const KeyHintsBar(),
          ],
        ),
      ),
    ),
  ),
);

/// The label of the node with the primary focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// The rows highlighted (on the selection's background) at column 1.
List<String> highlighted(TwkTester t) => [
  for (var y = 0; y < t.terminal.height; y++)
    if (t.cell(1, y).bg == const Color.indexed(237).value) t.lines[y],
];

/// The characters drawn in bold on row [y].
String bold(TwkTester t, int y) => [
  for (var x = 0; x < t.terminal.width; x++)
    if (t.cell(x, y).attrs & Attr.bold != 0) t.cell(x, y).text,
].join();

Future<void> press(TwkTester t, String keys) async {
  await t.press(keys);
  await t.pump();
}

Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pump();
}

void main() {
  testTwk('Ctrl+P opens the palette over the app: the commands that can be '
      'done from the focused node, then the keys hinted there, each with '
      'its key; Enter runs the highlighted one from that node once closed', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(Theme.terminal(child: app(log)), size: (40, 9));
    expect(t.lines.last, 'ctrl+r reload   ctrl+p commands   ctrl+…');
    await press(t, 'ctrl+p');
    expect(
      t,
      matchesScreen('''
 editor
┌──────────────────────────────────────┐
│ >                                    │
│ Open file                            │
│ Save file                     ctrl+s │
│ reload                        ctrl+r │
└──────────────────────────────────────┘

enter run   esc close'''),
    );
    expect(highlighted(t), ['│ Open file                            │']);
    expect(focused(t), isNot('editor'));
    await press(t, 'down');
    await press(t, 'enter');
    expect(log, ['save editor']);
    expect(focused(t), 'editor');
    expect(t.lines.take(3), ['>editor', ' notes', '']);
    await press(t, 'ctrl+p');
    await press(t, 'down down');
    await press(t, 'enter');
    expect(log, ['save editor', 'reload']);
  });

  testTwk('a screen reader reads the query field as a textbox named '
      'Command, what is typed as its value', (t) async {
    await t.pumpWidget(Theme.terminal(child: app([])), size: (40, 9));
    await press(t, 'ctrl+p');
    await type(t, 'sa');
    expect(t.binding.semantics.lines, contains('textbox Command: sa'));
  });

  testTwk('what is typed filters the commands and ranks them, its '
      'characters standing out; Up and Down move the highlight round', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: app(
          log,
          commands: [
            for (final label in [
              'Close folder',
              'Search files',
              'Settings',
              'Show diff',
              'Save file',
            ])
              Command(label, onSelected: () => log.add(label)),
          ],
        ),
      ),
      size: (40, 12),
    );
    await press(t, 'ctrl+p');
    await type(t, 'sf');
    expect(t.lines.sublist(2, 8), [
      '│ > sf                                 │',
      '│ Search files                         │',
      '│ Save file                            │',
      '│ Close folder                         │',
      '│ Show diff                            │',
      '└──────────────────────────────────────┘',
    ]);
    expect([for (var y = 3; y < 7; y++) bold(t, y)], ['Sf', 'Sf', 'sf', 'Sf']);
    await press(t, 'up');
    expect(highlighted(t), ['│ Show diff                            │']);
    await press(t, 'down down');
    expect(highlighted(t), ['│ Save file                            │']);
    await type(t, 'x');
    expect(t.lines.sublist(2, 5), [
      '│ > sfx                                │',
      '│ no command matches                   │',
      '└──────────────────────────────────────┘',
    ]);
    await press(t, 'enter');
    expect(log, isEmpty);
    await press(t, 'backspace backspace backspace');
    await type(t, 'show');
    await press(t, 'enter');
    expect(log, ['Show diff']);
  });

  testTwk('with nothing typed the commands run before come first, the last '
      'first; typed, those run last come first of those that match alike', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: app(
          log,
          commands: [
            for (final label in ['Alpha', 'Beta', 'Gamma', 'Delta'])
              Command(label, onSelected: () => log.add(label)),
          ],
        ),
      ),
      size: (40, 12),
    );
    Future<void> run(String typed) async {
      await press(t, 'ctrl+p');
      await type(t, typed);
      await press(t, 'enter');
    }

    await run('gam');
    await run('del');
    await press(t, 'ctrl+p');
    expect(t.lines.sublist(3, 9), [
      '│ Delta                                │',
      '│ Gamma                                │',
      '│ Alpha                                │',
      '│ Beta                                 │',
      '│ reload                        ctrl+r │',
      '│ save                          ctrl+s │',
    ]);
    // a: 1 point in each but Alpha, which it starts
    await type(t, 'a');
    expect(t.lines.sublist(3, 7), [
      '│ Alpha                                │',
      '│ Delta                                │',
      '│ Gamma                                │',
      '│ Beta                                 │',
    ]);
    expect(log, ['Gamma', 'Delta']);
  });

  testTwk('at most rows commands show, the highlighted one among them', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: app(
          log,
          commands: [
            for (final label in ['One', 'Two', 'Three', 'Four'])
              Command(label, onSelected: () => log.add(label)),
          ],
          rows: 3,
        ),
      ),
      size: (40, 12),
    );
    await press(t, 'ctrl+p');
    List<String> shown() => [
      for (final line in t.lines.sublist(3, 6)) line.substring(2, 8).trim(),
    ];
    expect(shown(), ['One', 'Two', 'Three']);
    // Four, reload, save
    await press(t, 'up');
    expect(shown(), ['Four', 'reload', 'save']);
    expect(highlighted(t), [startsWith('│ save ')]);
    await press(t, 'down');
    expect(shown(), ['One', 'Two', 'Three']);
    await press(t, 'up');
    await press(t, 'up up');
    expect(shown(), ['Four', 'reload', 'save']);
    expect(highlighted(t), [startsWith('│ Four ')]);
    await press(t, 'up');
    expect(shown(), ['Three', 'Four', 'reload']);
  });

  testTwk('Escape and a click outside close the palette, running nothing, '
      'the focus back where it was', (t) async {
    final log = <String>[];
    await t.pumpWidget(Theme.terminal(child: app(log)), size: (40, 9));
    await press(t, 'tab');
    expect(focused(t), 'notes');
    await press(t, 'ctrl+p');
    await type(t, 'o');
    await press(t, 'escape');
    expect(t.lines.take(3), [' editor', '>notes', '']);
    await press(t, 'ctrl+p');
    await t.click(20, 7);
    await t.pump();
    expect(t.lines.take(3), [' editor', '>notes', '']);
    expect(log, isEmpty);
    // the commands are those of the notes: the editor's reload is not
    await press(t, 'ctrl+p');
    expect(t.lines.sublist(3, 6), [
      '│ Open file                            │',
      '│ Save file                     ctrl+s │',
      '└──────────────────────────────────────┘',
    ]);
    await press(t, 'down enter');
    expect(log, ['save']);
  });

  testTwk('a sequence shows whole, for a command and for a key hinted, each '
      'key named as keyLabel names it', (t) async {
    void top() {}
    Widget app({String Function(KeyCombo combo)? keyLabel}) => Overlay(
      child: Shortcuts(
        const {'ctrl+x ctrl+s': Save()},
        hints: const {'ctrl+x ctrl+s': 'save'},
        child: Actions(
          {Save: CallbackAction<Save>(onInvoke: (_) {})},
          child: CommandPalette(
            look: PanelLook.bordered,
            keyLabel: keyLabel,
            commands: const [Command('Save file', intent: Save())],
            child: KeyBindings(
              {'g g': top},
              hints: const {'g g': 'top'},
              child: const Field('editor', autofocus: true),
            ),
          ),
        ),
      ),
    );
    await t.pumpWidget(Theme.terminal(child: app()), size: (30, 6));
    await press(t, 'ctrl+p');
    expect(t.lines.sublist(3, 5), [
      '│ Save file    ctrl+x ctrl+s │',
      '│ top                    g g │',
    ]);
    await press(t, 'escape');
    await t.pumpWidget(
      Theme.terminal(child: app(keyLabel: (combo) => '$combo'.toUpperCase())),
    );
    await press(t, 'ctrl+p');
    expect(t.lines[3], '│ Save file    CTRL+X CTRL+S │');
  });

  testTwk('a CommandPalette without an Overlay above fails to build, saying '
      'where to place one', (t) async {
    await t.pumpWidget(
      const CommandPalette(child: Text('app')),
    );
    const failed =
        'CommandPalette failed to build: Bad state: CommandPalette: no '
        'Overlay above it: place an Overlay above it, as around the whole '
        'app: Overlay(child: …)';
    expect(
      [
        for (final r in t.logs.records)
          if (r.level == LogLevel.error) '${r.message}: ${r.error}',
      ],
      [failed],
    );
  });

  group('raised', () {
    const theme = ThemeData.dark;
    const ms = Duration(milliseconds: 1);
    Widget raised(List<String> log) => Theme(
      data: theme,
      child: Box(
        style: theme.background,
        child: app(log, look: PanelLook.raised),
      ),
    );

    /// Opens the palette and waits out its fade.
    Future<void> open(TwkTester t) async {
      await press(t, 'ctrl+p');
      await t.pump(ms * 200);
      await t.pump();
    }

    testTwk('the palette is a raised panel a row from the top: the field '
        'after >, the count at its right, the commands under it, the '
        'highlighted one on the selection; a shadow, no barrier', (t) async {
      await t.pumpWidget(Theme.terminal(child: raised([])), size: (44, 12));
      await open(t);
      // the panel 40 wide at column 2, centred with its shadow
      expect(t, hasTextAt(2, 1, '      '));
      expect(t, hasTextAt(2, 2, '  >'));
      expect(t, hasTextAt(34, 2, '3 of 3'));
      expect(t, styleAt(34, 2, hasFg(theme.dim.fg!)));
      expect(t, hasTextAt(3, 3, ' Open file'));
      expect(t, hasTextAt(3, 4, ' Save file'));
      expect(t, hasTextAt(34, 4, 'ctrl+s'));
      expect(t, styleAt(3, 3, hasBg(theme.selection.bg!)));
      expect(t, styleAt(40, 3, hasBg(theme.selection.bg!)));
      expect(t, styleAt(2, 3, hasBg(theme.surface.bg!)));
      expect(t, styleAt(41, 3, hasBg(theme.surface.bg!)));
      expect(t, styleAt(3, 4, hasBg(theme.surface.bg!)));
      expect(t, styleAt(2, 1, hasBg(theme.surface.bg!)));
      expect(t, styleAt(2, 6, hasBg(theme.surface.bg!)));
      final background = theme.background.bg!;
      expect(t, styleAt(0, 8, hasBg(background)), reason: 'no barrier');
      expect(t, styleAt(42, 3, isNot(hasBg(background))), reason: 'shadow');
      expect(t, styleAt(10, 7, isNot(hasBg(background))), reason: 'shadow');
      await type(t, 'sa');
      expect(t, hasTextAt(34, 2, '1 of 3'));
      await type(t, 'zz');
      expect(t, hasTextAt(34, 2, '0 of 3'));
      expect(t, hasTextAt(2, 3, '  no command matches'));
    });

    testTwk('the mouse moved onto a command highlights it, a click runs it, '
        'the wheel moves the highlight', (t) async {
      final log = <String>[];
      await t.pumpWidget(Theme.terminal(child: raised(log)), size: (44, 12));
      await open(t);
      await t.mouse(MouseKind.move, 10, 5);
      await t.pump();
      expect(t, styleAt(10, 5, hasBg(theme.selection.bg!)));
      expect(t, styleAt(10, 3, isNot(hasBg(theme.selection.bg!))));
      await t.mouse(MouseKind.wheelUp, 10, 5);
      await t.pump();
      expect(t, styleAt(10, 4, hasBg(theme.selection.bg!)));
      await t.click(10, 5);
      await t.pump();
      expect(log, ['reload']);
      expect(t.lines[3], isNot(contains('reload')));
    });

    testTwk('the palette fades in over 140 ms', (t) async {
      await t.pumpWidget(Theme.terminal(child: raised([])), size: (44, 12));
      await press(t, 'ctrl+p');
      expect(t, styleAt(10, 3, hasBg(theme.background.bg!)));
      await t.pump(ms * 60);
      expect(
        t,
        styleAt(
          10,
          3,
          isNot(anyOf(hasBg(theme.background.bg!), hasBg(theme.selection.bg!))),
        ),
      );
      await t.pump(ms * 100);
      await t.pump();
      expect(t, styleAt(10, 3, hasBg(theme.selection.bg!)));
    });
  });

  group('look', () {
    const theme = ThemeData.dark;
    const ms = Duration(milliseconds: 1);

    /// A palette of [commands] over a focus with one key hinted, given
    /// the look of [palette].
    Widget styled(
      List<Command> commands,
      CommandPalette Function(Widget child) palette,
    ) => Theme(
      data: theme,
      child: Box(
        style: theme.background,
        child: Overlay(
          child: palette(
            KeyBindings(
              {'ctrl+r': () {}},
              hints: const {'ctrl+r': 'reload'},
              child: const Focus(autofocus: true, child: Text('editor')),
            ),
          ),
        ),
      ),
    );

    testTwk('a prompt, a placeholder while nothing is typed, a rule under '
        'the field, a bar at the highlighted command and a detail of a '
        'command with no key', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: styled(
            const [],
            (child) => CommandPalette(
              look: PanelLook.bordered,
              prompt: ' ›',
              placeholder: 'Search',
              rule: true,
              bar: true,
              commands: const [
                Command('Open file', onSelected: _noop, detail: 'page'),
                Command('Save file', onSelected: _other),
              ],
              child: child,
            ),
          ),
        ),
        size: (30, 9),
      );
      await press(t, 'ctrl+p');
      expect(
        t,
        matchesScreen('''
editor
┌────────────────────────────┐
│ › Search                   │
│────────────────────────────│
│▎Open file             page │
│ Save file                  │
│ reload              ctrl+r │
└────────────────────────────┘'''),
      );
      await type(t, 'op');
      expect(t.lines[2], isNot(contains('Search')));
    });

    testTwk('an empty prompt leaves no gap before the field', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: styled(
            const [],
            (child) => CommandPalette(
              look: PanelLook.bordered,
              prompt: '',
              placeholder: 'Search',
              commands: const [Command('Open file', onSelected: _noop)],
              child: child,
            ),
          ),
        ),
        size: (30, 9),
      );
      await press(t, 'ctrl+p');
      expect(t.lines[2], startsWith('│Search '));
    });

    testTwk('hintedKeys: false leaves the hinted keys out', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: styled(
            const [],
            (child) => CommandPalette(
              look: PanelLook.bordered,
              hintedKeys: false,
              commands: const [Command('Quit', onSelected: _noop)],
              child: child,
            ),
          ),
        ),
        size: (30, 9),
      );
      await press(t, 'ctrl+p');
      expect(t.lines.join('\n'), contains('Quit'));
      expect(t.lines.join('\n'), isNot(contains('reload')));
    });

    /// Opens a palette made by [palette] and waits out the barrier's fade.
    Future<void> open(
      TwkTester t,
      CommandPalette Function(Widget child) palette,
    ) async {
      await t.pumpWidget(
        Theme.terminal(child: styled(const [], palette)),
        size: (30, 9),
      );
      await press(t, 'ctrl+p');
      await t.pump(ms * 200);
      await t.pump();
    }

    testTwk('barrierAlpha 0, the default, leaves what is under the palette '
        'as it is', (t) async {
      await open(t, (child) => CommandPalette(child: child));
      expect(t, styleAt(0, 8, hasBg(theme.background.bg!)));
    });

    testTwk("barrierAlpha null dims it by the theme's shade", (t) async {
      await open(
        t,
        (child) => CommandPalette(barrierAlpha: null, child: child),
      );
      expect(t, styleAt(0, 8, isNot(hasBg(theme.background.bg!))));
    });

    testTwk('barrierAlpha 255 covers it with the shade', (t) async {
      await open(t, (child) => CommandPalette(barrierAlpha: 255, child: child));
      expect(t, styleAt(0, 8, hasBg(theme.shade.bg!)));
    });

    test('barrierAlpha is asserted to be in 0..255', () {
      expect(
        () => CommandPalette(barrierAlpha: 256, child: const Text('')),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

void _noop() {}

void _other() {}
