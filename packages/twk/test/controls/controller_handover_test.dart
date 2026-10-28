// A controller given to a widget built in place of another (its key
// changed) goes over to the new one, which goes on with what the
// controller holds: a tooltip shown stays shown, a palette or a menu open
// stays open, a navigator's observers observe the new navigator, a popup
// open stays open; no assert, no listener told during the build, and
// what the controller is asked afterwards reaches the new widget alone.
// The old widget leaves first as an only child, the new one starts first
// among children: both orders. A LogController given to another view
// searches its own lines, not the other's window. A Select or a
// DatePicker disabled while open closes, and the controller it no longer
// has says it is closed. A FilePickerController whose picker leaves with
// none built in its place tells its listeners it shows nothing, after the
// build; disposed with its picker, it tells nothing.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Where the widget built anew is: the only child of its parent, which
/// lets the old one go before the new one starts, or one of its children,
/// whose new one starts first.
enum Order {
  alone,
  among;

  Widget wrap(Widget child) => switch (this) {
    alone => Align(alignment: Alignment.topLeft, child: child),
    among => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [child],
    ),
  };
}

/// The root of a test's tree: what [build] makes of the generation, which
/// [SwapperState.swap] moves on, so that a widget keyed by it is built in
/// place of the one before.
final class Swapper extends StatefulWidget {
  const Swapper(this.build, {super.key});

  final Widget Function(int generation) build;

  @override
  State<Swapper> createState() => SwapperState();
}

final class SwapperState extends State<Swapper> {
  var generation = 0;

  void swap() => setState(() => generation++);

  /// Marks the root to build again: called during a build, which rebuilt
  /// the root first, it fails an assert, and the test. Nothing once the
  /// app has ended.
  void poke() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => widget.build(generation);
}

/// Starts the app with a [Swapper] of [build] on a terminal of [size];
/// returns its state.
Future<SwapperState> start(
  TwkTester t,
  Widget Function(int generation) build, {
  (int, int) size = (40, 10),
}) async {
  final key = GlobalKey<SwapperState>();
  await t.pumpWidget(Swapper(build, key: key), size: size);
  return key.currentState!;
}

/// Adds a listener to [listenable] that adds what [read] says to the list
/// it returns, and pokes [root]: told during a build, the test fails.
List<T> told<T>(
  Listenable listenable,
  SwapperState Function() root,
  T Function() read,
) {
  final seen = <T>[];
  void listener() {
    seen.add(read());
    root().poke();
  }

  listenable.addListener(listener);
  addTearDown(() => listenable.removeListener(listener));
  return seen;
}

/// Fails on an error the app logged.
void noErrors(TwkTester t) => expect([
  for (final r in t.logs.records)
    if (r.level == LogLevel.error) r.message,
], isEmpty);

T disposed<T extends ChangeNotifier>(T notifier) {
  addTearDown(notifier.dispose);
  return notifier;
}

String screen(TwkTester t) => t.lines.join('\n');

void main() {
  for (final order in Order.values) {
    group('built in place ($order):', () {
      testTwk('a shown tooltip stays shown, isShown true; hide and show '
          'reach the new one', (t) async {
        final c = disposed(TooltipController());
        late SwapperState root;
        final seen = told(c, () => root, () => c.isShown);
        root = await start(
          t,
          (g) => Overlay(
            child: order.wrap(
              Tooltip(
                key: ValueKey(g),
                message: 'Opens help',
                controller: c,
                showOnHover: false,
                showOnFocus: false,
                fadeIn: Duration.zero,
                child: const Text('Help'),
              ),
            ),
          ),
        );
        c.show();
        await t.pump();
        expect(t.lines[1].trim(), 'Opens help');
        root.swap();
        await t.pump();
        await t.pump();
        expect(c.isShown, isTrue);
        expect(t.lines[1].trim(), 'Opens help');
        expect(seen, [true]);
        c.hide();
        await t.pump();
        expect(t.lines[1].trim(), isEmpty);
        expect(seen, [true, false]);
        c.show();
        await t.pump();
        expect(t.lines[1].trim(), 'Opens help');
        noErrors(t);
      });

      testTwk('an open command palette stays open with what is typed; '
          'typing, close and open reach the new one', (t) async {
        final c = disposed(CommandPaletteController());
        final ran = <String>[];
        late SwapperState root;
        final seen = told(c, () => root, () => '${c.isOpen} ${c.query}');
        root = await start(
          t,
          (g) => Overlay(
            child: order.wrap(
              CommandPalette(
                key: ValueKey(g),
                controller: c,
                look: PanelLook.bordered,
                commands: [
                  Command('Print', onSelected: () => ran.add('print')),
                  Command('Open', onSelected: () => ran.add('open')),
                ],
                child: const Focus(autofocus: true, child: Text('app')),
              ),
            ),
          ),
          size: (40, 12),
        );
        c.open(query: 'pr');
        await t.pump();
        expect(screen(t), contains('Print'));
        expect(seen, ['true pr']);
        root.swap();
        await t.pump();
        await t.pump();
        expect(c.isOpen, isTrue);
        expect(c.query, 'pr');
        expect(screen(t), contains('Print'));
        expect(seen, ['true pr']);
        await t.type('i');
        await t.pump();
        expect(c.query, 'pri');
        await t.press('enter');
        await t.pump();
        expect(ran, ['print']);
        expect(c.isOpen, isFalse);
        expect(seen, ['true pr', 'true pri', 'false pri']);
        c.open();
        await t.pump();
        expect(c.isOpen, isTrue);
        c.close();
        await t.pump();
        expect(c.isOpen, isFalse);
        expect(screen(t), isNot(contains('Print')));
        noErrors(t);
      });

      testTwk("a menu bar's open menu stays open along its path; close and "
          'open reach the new bar', (t) async {
        final c = disposed(MenuController());
        late SwapperState root;
        final seen = told(c, () => root, () => '${c.path}');
        root = await start(
          t,
          (g) => Overlay(
            child: order.wrap(
              MenuBar(
                key: ValueKey(g),
                look: PanelLook.bordered,
                controller: c,
                menus: [
                  Menu('&File', items: [MenuItem('New', onSelected: () {})]),
                  Menu('&View', items: [MenuItem('Wrap', onSelected: () {})]),
                ],
                child: const Focus(autofocus: true, child: Text('editor')),
              ),
            ),
          ),
        );
        c.open([1]);
        await t.pump();
        expect(screen(t), contains('Wrap'));
        root.swap();
        await t.pump();
        await t.pump();
        expect(c.isOpen, isTrue);
        expect(c.path, [1]);
        expect(screen(t), contains('Wrap'));
        expect(seen, ['[1]']);
        c.close();
        await t.pump();
        expect(screen(t), isNot(contains('Wrap')));
        expect(seen, ['[1]', '[]']);
        c.open([0]);
        await t.pump();
        expect(screen(t), contains('New'));
        noErrors(t);
      });

      testTwk("a context menu's open menu stays open; close reaches the "
          'new one', (t) async {
        final c = disposed(MenuController());
        late SwapperState root;
        final seen = told(c, () => root, () => '${c.isOpen}');
        root = await start(
          t,
          (g) => Overlay(
            child: order.wrap(
              ContextMenu(
                key: ValueKey(g),
                look: PanelLook.bordered,
                controller: c,
                items: [MenuItem('Copy', onSelected: () {})],
                child: const Focus(autofocus: true, child: Text('editor')),
              ),
            ),
          ),
        );
        c.open();
        await t.pump();
        expect(screen(t), contains('Copy'));
        root.swap();
        await t.pump();
        await t.pump();
        expect(c.isOpen, isTrue);
        expect(screen(t), contains('Copy'));
        expect(seen, ['true']);
        c.close();
        await t.pump();
        expect(screen(t), isNot(contains('Copy')));
        expect(seen, ['true', 'false']);
        noErrors(t);
      });

      testTwk("a selection area's controller goes over to the new area: "
          'its Texts are new, so nothing is selected, told after the '
          'build; what it selects then the controller reads', (t) async {
        final c = disposed(SelectionAreaController());
        late SwapperState root;
        final seen = told(c, () => root, () => c.hasSelection);
        root = await start(
          t,
          (g) => order.wrap(
            SelectionArea(
              key: ValueKey(g),
              controller: c,
              child: const Text('hello world'),
            ),
          ),
          size: (20, 3),
        );
        await t.mouse(MouseKind.down, 0, 0);
        await t.mouse(MouseKind.drag, 4, 0);
        await t.mouse(MouseKind.up, 4, 0);
        await t.pump();
        expect(c.text, 'hello');
        root.swap();
        await t.pump();
        expect(c.hasSelection, isFalse);
        expect(seen, [true, false]);
        await t.mouse(MouseKind.down, 6, 0);
        await t.mouse(MouseKind.drag, 10, 0);
        await t.mouse(MouseKind.up, 10, 0);
        await t.pump();
        expect(c.text, 'world');
        c.clear();
        await t.pump();
        expect(c.hasSelection, isFalse);
        expect(seen, [true, false, true, false]);
        noErrors(t);
      });

      testTwk("a navigator's observers observe the new navigator", (
        t,
      ) async {
        final observer = NavigatorObserver();
        final root = await start(
          t,
          (g) => order.wrap(
            Navigator(
              key: ValueKey(g),
              observers: [observer],
              home: Text('home $g'),
            ),
          ),
        );
        root.swap();
        await t.pump();
        expect(observer.navigator, isNotNull);
        unawaited(
          observer.navigator!.push(
            PageRoute<void>(builder: (_) => const Text('next')),
          ),
        );
        await t.pump();
        expect(t.lines.first, 'next');
        noErrors(t);
      });

      for (final (name, shows, make)
          in <(String, String, Widget Function(Key, PopupController))>[
            (
              'Select',
              'Banana',
              (key, c) => Select<String>(
                key: key,
                choices: const [Choice('a', 'Apple'), Choice('b', 'Banana')],
                value: null,
                onChanged: (_) {},
                controller: c,
              ),
            ),
            (
              'DatePicker',
              'October 2026',
              (key, c) => SizedBox(
                key: key,
                width: 16,
                child: DatePicker(
                  value: DateTime(2026, 10, 19),
                  onChanged: (_) {},
                  controller: c,
                ),
              ),
            ),
          ]) {
        testTwk("an open $name stays open, its keys the new one's; close "
            'and open reach the new one', (t) async {
          final c = disposed(PopupController());
          late SwapperState root;
          final seen = told(c, () => root, () => c.isOpen);
          root = await start(
            t,
            (g) => Overlay(child: order.wrap(make(ValueKey(g), c))),
            size: (30, 12),
          );
          c.open();
          await t.pumpUntilIdle();
          expect(screen(t), contains(shows));
          root.swap();
          await t.pumpUntilIdle();
          expect(c.isOpen, isTrue);
          expect(screen(t), contains(shows));
          await t.press('escape');
          await t.pumpUntilIdle();
          expect(c.isOpen, isFalse);
          expect(screen(t), isNot(contains(shows)));
          c.open();
          await t.pumpUntilIdle();
          expect(screen(t), contains(shows));
          c.close();
          await t.pumpUntilIdle();
          expect(screen(t), isNot(contains(shows)));
          expect(seen, [true, false, true, false]);
          noErrors(t);
        });
      }

      testTwk('a LogController searches from the window of the new view', (
        t,
      ) async {
        final c = LogController();
        for (var i = 0; i < 30; i++) {
          c.add(i % 10 == 3 ? 'line $i hit' : 'line $i');
        }
        final root = await start(
          t,
          (g) => order.wrap(
            SizedBox(
              height: 5,
              child: LogView(
                key: ValueKey(g),
                controller: c,
                showTime: false,
                showLevel: false,
              ),
            ),
          ),
          size: (30, 5),
        );
        root.swap();
        await t.pump();
        c.query = 'hit';
        expect(c.nextMatch(), isTrue);
        await t.pump();
        await t.pump();
        // from the top of the window, line 25 on, round to line 3
        expect(c.match?.text, 'line 3 hit');
        expect(t.lines.first, startsWith('line 3 hit'));
        noErrors(t);
      });
    });
  }

  testTwk('a LogController taken from its view to another searches its own '
      'lines from the start, not from the window of the view now showing '
      'another', (t) async {
    final a = LogController();
    final b = LogController();
    for (var i = 0; i < 100; i++) {
      a.add(i == 5 || i == 95 ? 'a $i hit' : 'a $i');
      b.add('b $i');
    }
    Widget view(LogController c) =>
        LogView(controller: c, showTime: false, showLevel: false);
    await t.pumpWidget(view(a), size: (30, 10));
    await t.pumpWidget(view(b));
    expect(t.lines.first, 'b 90');
    a.query = 'hit';
    expect(a.nextMatch(), isTrue);
    expect(a.match?.text, 'a 5 hit');
    expect(b.match, isNull);
  });

  group('a Select and a DatePicker', () {
    Widget select(PopupController? c, {bool enabled = true}) => Overlay(
      child: Select<String>(
        choices: const [Choice('a', 'Apple'), Choice('b', 'Banana')],
        value: null,
        onChanged: enabled ? (_) {} : null,
        controller: c,
      ),
    );

    Widget date(PopupController? c, {bool enabled = true}) => Overlay(
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 16,
          child: DatePicker(
            value: DateTime(2026, 10, 19),
            onChanged: enabled ? (_) {} : null,
            controller: c,
          ),
        ),
      ),
    );

    for (final (name, make, shows) in [
      ('Select', select, 'Banana'),
      ('DatePicker', date, 'October 2026'),
    ]) {
      testTwk('$name: disabled while open, it closes, and so does its '
          'controller, told after the build', (t) async {
        final c = disposed(PopupController());
        final key = GlobalKey<SwapperState>();
        final seen = told(c, () => key.currentState!, () => c.isOpen);
        await t.pumpWidget(
          Swapper((_) => make(c), key: key),
          size: (30, 12),
        );
        c.open();
        await t.pumpUntilIdle();
        expect(screen(t), contains(shows));
        await t.pumpWidget(
          Swapper((_) => make(c, enabled: false), key: key),
        );
        await t.pumpUntilIdle();
        expect(screen(t), isNot(contains(shows)));
        expect(c.isOpen, isFalse);
        expect(seen, [true, false]);
        noErrors(t);
      });

      testTwk('$name: given another controller, or none, while open, the '
          'one it had says it is closed, told after the build', (t) async {
        final c = disposed(PopupController());
        final key = GlobalKey<SwapperState>();
        final seen = told(c, () => key.currentState!, () => c.isOpen);
        await t.pumpWidget(
          Swapper((_) => make(c), key: key),
          size: (30, 12),
        );
        c.open();
        await t.pumpUntilIdle();
        expect(screen(t), contains(shows));
        await t.pumpWidget(Swapper((_) => make(null), key: key));
        await t.pumpUntilIdle();
        expect(c.isOpen, isFalse);
        expect(seen, [true, false]);
        expect(screen(t), isNot(contains(shows)));
        noErrors(t);
      });
    }
  });

  group('a FilePickerController', () {
    final files = PickerFileSystem.memory(
      ['/home/docs/b.md', '/home/a.txt'],
      currentDirectory: '/home',
    );

    Widget picker(FilePickerController c) => FilePicker(
      onPicked: (_) {},
      controller: c,
      fileSystem: files,
    );

    testTwk('whose picker leaves with none in its place tells its '
        'listeners it shows nothing, after the build', (t) async {
      final c = disposed(FilePickerController());
      final key = GlobalKey<SwapperState>();
      final seen = told(
        c,
        () => key.currentState!,
        () => '${c.directory} ${c.highlighted}',
      );
      await t.pumpWidget(
        Swapper(
          (g) => Overlay(child: g == 0 ? picker(c) : const Text('gone')),
          key: key,
        ),
        size: (30, 10),
      );
      await t.pumpUntilIdle();
      expect(c.highlighted, '/home/docs');
      expect(seen.last, '/home /home/docs');
      final before = seen.length;
      key.currentState!.swap();
      await t.pumpUntilIdle();
      expect(t.lines.first, 'gone');
      expect(c.directory, isNull);
      expect(c.highlighted, isNull);
      expect(seen.sublist(before), ['null null']);
      noErrors(t);
    });

    testTwk('disposed with its picker, it tells nothing, and fails no '
        'assert', (t) async {
      final key = GlobalKey<SwapperState>();
      await t.pumpWidget(
        Swapper(
          (g) => Overlay(
            child: g == 0 ? _OwnsPicker(picker) : const Text('gone'),
          ),
          key: key,
        ),
        size: (30, 10),
      );
      await t.pumpUntilIdle();
      key.currentState!.swap();
      await t.pumpUntilIdle();
      expect(t.lines.first, 'gone');
      noErrors(t);
    });
    // its file system's paths are POSIX ones, which the picker resolves
    // in Windows' form on Windows (paths_test.dart)
  }, testOn: '!windows');
}

/// A [FilePicker] of [build] with a controller of its own, disposed with it.
final class _OwnsPicker extends StatefulWidget {
  const _OwnsPicker(this.build);

  final Widget Function(FilePickerController controller) build;

  @override
  State<_OwnsPicker> createState() => _OwnsPickerState();
}

final class _OwnsPickerState extends State<_OwnsPicker> {
  final _controller = FilePickerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.build(_controller);
}
