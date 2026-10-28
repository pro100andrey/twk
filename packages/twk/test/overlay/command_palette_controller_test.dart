// A command palette's controller and its provider: the controller opens
// the palette with a query typed, sets the query of the open one, closes
// it, and says whether it is open and what is typed, telling its
// listeners; the provider is asked for commands as the query changes, at
// once or in a future, an answer to a query typed over dropped, and what
// it gives is listed after the palette's own commands, in its order.
import 'dart:async';

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

/// An app with a palette of [commands] and those [provider] gives, each
/// command done added to [log], opened by [controller].
Widget app(
  List<String> log, {
  CommandPaletteController? controller,
  List<Command>? commands,
  FutureOr<Iterable<Command>> Function(String query)? provider,
}) => Overlay(
  child: Actions(
    {Save: CallbackAction<Save>(onInvoke: (_) => log.add('save'))},
    child: CommandPalette(
      controller: controller,
      commandsFor: provider,
      look: PanelLook.bordered,
      commands:
          commands ??
          [
            Command('Open file', onSelected: () => log.add('open')),
            const Command('Save file', intent: Save()),
            Command('Settings', onSelected: () => log.add('settings')),
          ],
      child: const Focus(
        autofocus: true,
        debugLabel: 'editor',
        child: Text('editor'),
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
  group('CommandPaletteController', () {
    testTwk('open(query:) opens the palette with the query typed, the '
        'commands filtered by it; isOpen and query say so, and its '
        'listeners are told', (t) async {
      final log = <String>[];
      final controller = CommandPaletteController();
      var told = 0;
      controller.addListener(() => told++);
      await t.pumpWidget(
        Theme.terminal(child: app(log, controller: controller)),
        size: (40, 9),
      );
      expect(controller.isOpen, isFalse);
      expect(controller.query, '');
      controller.open(query: 'se');
      expect(controller.isOpen, isTrue);
      expect(controller.query, 'se');
      expect(told, 1);
      await t.pump();
      expect(
        t,
        matchesScreen('''
editor
┌──────────────────────────────────────┐
│ > se                                 │
│ Settings                             │
│ Save file                            │
└──────────────────────────────────────┘'''),
      );
      expect(focused(t), isNot('editor'));
      // typed on from the end of the query
      await type(t, 't');
      expect(controller.query, 'set');
      expect(told, 2);
      expect(t.lines.sublist(2, 5), [
        '│ > set                                │',
        '│ Settings                             │',
        '└──────────────────────────────────────┘',
      ]);
      await press(t, 'enter');
      expect(log, ['settings']);
      expect(controller.isOpen, isFalse);
      expect(told, 3);
      // what was typed last, kept
      expect(controller.query, 'set');
      expect(focused(t), 'editor');
    });

    testTwk('open on the open palette sets its query; close closes it, '
        'running nothing, and gives the focus back', (t) async {
      final log = <String>[];
      final controller = CommandPaletteController();
      await t.pumpWidget(
        Theme.terminal(child: app(log, controller: controller)),
        size: (40, 9),
      );
      controller.open();
      await t.pump();
      expect(t.lines[2], '│ >                                    │');
      expect(t.lines.sublist(3, 6), [
        '│ Open file                            │',
        '│ Save file                            │',
        '│ Settings                             │',
      ]);
      controller.open(query: 'open');
      expect(controller.query, 'open');
      await t.pump();
      expect(t.lines.sublist(2, 5), [
        '│ > open                               │',
        '│ Open file                            │',
        '└──────────────────────────────────────┘',
      ]);
      await type(t, 'x');
      expect(controller.query, 'openx');
      controller.close();
      expect(controller.isOpen, isFalse);
      await t.pump();
      expect(t.lines.take(3), ['editor', '', '']);
      expect(focused(t), 'editor');
      expect(log, isEmpty);
      // closed, close does nothing; open again opens it anew
      controller
        ..close()
        ..open(query: 'save');
      await t.pump();
      await press(t, 'enter');
      expect(log, ['save']);
    });

    testTwk('open then close before a frame shows nothing; open twice '
        'before a frame types the last query', (t) async {
      final log = <String>[];
      final controller = CommandPaletteController();
      await t.pumpWidget(
        Theme.terminal(child: app(log, controller: controller)),
        size: (40, 9),
      );
      controller
        ..open(query: 'open')
        ..close();
      expect(controller.isOpen, isFalse);
      await t.pump();
      await t.pump();
      expect(t.lines.take(2), ['editor', '']);
      expect(focused(t), 'editor');
      controller
        ..open(query: 'open')
        ..open(query: 'set');
      expect(controller.query, 'set');
      await t.pump();
      expect(t.lines.sublist(2, 4), [
        '│ > set                                │',
        '│ Settings                             │',
      ]);
      await press(t, 'enter');
      expect(log, ['settings']);
    });

    testTwk('Ctrl+P, Escape and a click outside open and close it as the '
        'controller says', (t) async {
      final log = <String>[];
      final controller = CommandPaletteController();
      await t.pumpWidget(
        Theme.terminal(child: app(log, controller: controller)),
        size: (40, 9),
      );
      await press(t, 'ctrl+p');
      expect(controller.isOpen, isTrue);
      expect(controller.query, '');
      await type(t, 'op');
      expect(controller.query, 'op');
      await press(t, 'escape');
      expect(controller.isOpen, isFalse);
      controller.open();
      await t.pump();
      expect(controller.isOpen, isTrue);
      await t.click(20, 8);
      await t.pump();
      expect(controller.isOpen, isFalse);
      expect(log, isEmpty);
    });

    testTwk('a controller given to a palette that is open says it is open, '
        'and tells its listeners after the build', (t) async {
      final log = <String>[];
      final controller = CommandPaletteController();
      var told = 0;
      controller.addListener(() => told++);
      await t.pumpWidget(Theme.terminal(child: app(log)), size: (40, 9));
      await press(t, 'ctrl+p');
      await t.pumpWidget(
        Theme.terminal(child: app(log, controller: controller)),
      );
      expect(controller.isOpen, isTrue);
      expect(told, 1);
      controller.close();
      await t.pump();
      expect(t.lines.first, 'editor');
    });

    testTwk('a controller given to no palette fails to open, saying so; '
        'given to another, the old palette no longer answers to it', (
      t,
    ) async {
      final log = <String>[];
      final controller = CommandPaletteController();
      expect(
        controller.open,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('given to no CommandPalette'),
          ),
        ),
      );
      final other = CommandPaletteController();
      await t.pumpWidget(
        Theme.terminal(child: app(log, controller: controller)),
        size: (40, 9),
      );
      await t.pumpWidget(
        Theme.terminal(child: app(log, controller: other)),
        size: (40, 9),
      );
      expect(controller.open, throwsStateError);
      other.open(query: 'open');
      await t.pump();
      expect(other.isOpen, isTrue);
      expect(controller.isOpen, isFalse);
    });
  });

  group('commandsFor', () {
    testTwk('is asked as the query changes; what it gives shows after the '
        "palette's own commands that match, in its order, the query's "
        'characters standing out where they are found; one chosen runs', (
      t,
    ) async {
      final log = <String>[];
      final asked = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: app(
            log,
            provider: (query) {
              asked.add(query);
              return [
                for (final file in ['src/main.dart', 'lib/settings.dart'])
                  Command('Go to $file', onSelected: () => log.add(file)),
              ];
            },
          ),
        ),
        size: (40, 12),
      );
      expect(asked, isEmpty);
      await press(t, 'ctrl+p');
      expect(asked, ['']);
      expect(t.lines.sublist(3, 9), [
        '│ Open file                            │',
        '│ Save file                            │',
        '│ Settings                             │',
        '│ Go to src/main.dart                  │',
        '│ Go to lib/settings.dart              │',
        '└──────────────────────────────────────┘',
      ]);
      await type(t, 'set');
      expect(asked, ['', 's', 'se', 'set']);
      expect(t.lines.sublist(3, 7), [
        '│ Settings                             │',
        '│ Go to src/main.dart                  │',
        '│ Go to lib/settings.dart              │',
        '└──────────────────────────────────────┘',
      ]);
      // marked where the query is found, listed where it is not
      expect([for (var y = 3; y < 6; y++) bold(t, y)], ['Set', '', 'set']);
      await press(t, 'down down');
      expect(highlighted(t), ['│ Go to lib/settings.dart              │']);
      await press(t, 'enter');
      expect(log, ['lib/settings.dart']);
    });

    testTwk('an answer in a future shows once it comes, those before it '
        'showing meanwhile; one to a query typed over does not show', (
      t,
    ) async {
      final log = <String>[];
      final answers = <String, Completer<Iterable<Command>>>{};
      Command go(String file) =>
          Command('Go to $file', onSelected: () => log.add(file));
      await t.pumpWidget(
        Theme.terminal(
          child: app(
            log,
            commands: const [],
            provider: (query) => (answers[query] = Completer()).future,
          ),
        ),
        size: (40, 9),
      );
      await press(t, 'ctrl+p');
      expect(t.lines[3], '│ no command matches                   │');
      answers['']!.complete([go('a.dart'), go('b.dart')]);
      await t.pump();
      expect(t.lines.sublist(3, 5), [
        '│ Go to a.dart                         │',
        '│ Go to b.dart                         │',
      ]);
      await type(t, 'b');
      await type(t, 'c');
      expect(answers.keys, ['', 'b', 'bc']);
      // shown still, marked by what is typed now
      expect(t.lines.sublist(3, 5), [
        '│ Go to a.dart                         │',
        '│ Go to b.dart                         │',
      ]);
      answers['bc']!.complete([go('bc.dart')]);
      await t.pump();
      answers['b']!.complete([go('b.dart')]);
      await t.pump();
      expect(t.lines.sublist(3, 5), [
        '│ Go to bc.dart                        │',
        '└──────────────────────────────────────┘',
      ]);
      await press(t, 'enter');
      expect(log, ['bc.dart']);
    });

    testTwk('an answer of fewer commands than the highlight is down moves '
        'it to the last of them', (t) async {
      final log = <String>[];
      final answers = <String, Completer<Iterable<Command>>>{};
      Command go(String file) =>
          Command('Go to $file', onSelected: () => log.add(file));
      await t.pumpWidget(
        Theme.terminal(
          child: app(
            log,
            commands: const [],
            provider: (query) => (answers[query] = Completer()).future,
          ),
        ),
        size: (40, 9),
      );
      await press(t, 'ctrl+p');
      answers['']!.complete([go('a'), go('b'), go('c')]);
      await t.pump();
      await type(t, 'x');
      await press(t, 'down');
      await press(t, 'down');
      expect(highlighted(t), ['│ Go to c                              │']);
      answers['x']!.complete([go('x'), go('y')]);
      await t.pump();
      expect(highlighted(t), ['│ Go to y                              │']);
      await press(t, 'enter');
      expect(log, ['y']);
    });

    testTwk('a command it gives whose intent nothing does there is left '
        'out; those it gives keep its order, run before or not', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: app(
            log,
            provider: (query) => [
              const Command('Print page', intent: Print()),
              const Command('Save page', intent: Save()),
            ],
          ),
        ),
        size: (40, 12),
      );
      await press(t, 'ctrl+p');
      expect(t.lines.sublist(3, 8), [
        '│ Open file                            │',
        '│ Save file                            │',
        '│ Settings                             │',
        '│ Save page                            │',
        '└──────────────────────────────────────┘',
      ]);
      await press(t, 'up');
      await press(t, 'enter');
      expect(log, ['save']);
      await press(t, 'ctrl+p');
      // the provider's in its order still
      expect(t.lines.sublist(3, 7), [
        '│ Open file                            │',
        '│ Save file                            │',
        '│ Settings                             │',
        '│ Save page                            │',
      ]);
    });
  });
}
