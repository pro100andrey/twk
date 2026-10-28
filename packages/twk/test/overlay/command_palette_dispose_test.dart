// A CommandPalette that leaves the tree while its palette is open — the
// widget removed, or the subtree it is in replaced — closes the palette,
// after the build: with no controller, with one (whose listeners learn it
// is closed, after the build), and with one disposed along with it. One
// built in its place with its controller goes on with the palette open
// (controller_handover_test.dart).
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The root of a test's tree: what [build] makes of the generation, which
/// [RootState.next] moves on.
final class Root extends StatefulWidget {
  const Root(this.build, {super.key});

  final Widget Function(int generation) build;

  @override
  State<Root> createState() => RootState();
}

final class RootState extends State<Root> {
  var generation = 0;

  void next() => setState(() => generation++);

  /// Marks the root to build again: called during a build, it fails an
  /// assert, and the test.
  void poke() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => widget.build(generation);
}

/// A [CommandPalette] of [build] with a controller of its own, disposed
/// with it.
final class _OwnsPalette extends StatefulWidget {
  const _OwnsPalette(this.build, {required this.opened});

  final Widget Function(CommandPaletteController controller) build;

  /// Given the controller once built.
  final void Function(CommandPaletteController controller) opened;

  @override
  State<_OwnsPalette> createState() => _OwnsPaletteState();
}

final class _OwnsPaletteState extends State<_OwnsPalette> {
  final _controller = CommandPaletteController();

  @override
  void initState() {
    super.initState();
    widget.opened(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.build(_controller);
}

Widget palette({CommandPaletteController? controller, Key? key}) =>
    CommandPalette(
      key: key,
      controller: controller,
      look: PanelLook.bordered,
      commands: [Command('Print', onSelected: () {})],
      child: const Focus(autofocus: true, child: Text('app')),
    );

String screen(TwkTester t) => t.lines.join('\n');

/// Fails on an error the app logged.
void noErrors(TwkTester t) => expect([
  for (final r in t.logs.records)
    if (r.level == LogLevel.error) r.message,
], isEmpty);

/// Starts the app with a [Root] of [build]; returns its state.
Future<RootState> start(
  TwkTester t,
  Widget Function(int generation) build,
) async {
  final key = GlobalKey<RootState>();
  await t.pumpWidget(Root(build, key: key), size: (40, 12));
  return key.currentState!;
}

void main() {
  for (final (how, after) in <(String, Widget Function(Widget))>[
    ('removed', (_) => const Text('gone')),
    // the palette's parent of another type: a palette anew in its place
    (
      'its subtree replaced',
      (p) => Padding(padding: EdgeInsets.zero, child: p),
    ),
  ]) {
    testTwk('$how while open, with no controller, it closes the palette', (
      t,
    ) async {
      final root = await start(
        t,
        (g) => Overlay(
          child: g == 0
              ? Align(alignment: Alignment.topLeft, child: palette())
              : after(palette()),
        ),
      );
      await t.press('ctrl+p');
      await t.pump();
      expect(screen(t), contains('Print'));
      root.next();
      await t.pumpUntilIdle();
      expect(screen(t), isNot(contains('Print')));
      noErrors(t);
    });
  }

  testTwk('removed while open, its controller says it is closed, told '
      'after the build, and the palette closes', (t) async {
    final c = CommandPaletteController();
    addTearDown(c.dispose);
    late RootState root;
    final seen = <bool>[];
    void listener() {
      seen.add(c.isOpen);
      root.poke();
    }

    c.addListener(listener);
    addTearDown(() => c.removeListener(listener));
    root = await start(
      t,
      (g) => Overlay(
        child: g == 0 ? palette(controller: c) : const Text('gone'),
      ),
    );
    c.open();
    await t.pump();
    expect(screen(t), contains('Print'));
    root.next();
    await t.pumpUntilIdle();
    expect(c.isOpen, isFalse);
    expect(seen, [true, false]);
    expect(screen(t), isNot(contains('Print')));
    noErrors(t);
  });

  testTwk('removed while open with a controller disposed along with it, '
      'the palette closes, and no assert fails', (t) async {
    late CommandPaletteController c;
    final root = await start(
      t,
      (g) => Overlay(
        child: g == 0
            ? _OwnsPalette(
                (c) => palette(controller: c),
                opened: (controller) => c = controller,
              )
            : const Text('gone'),
      ),
    );
    c.open();
    await t.pump();
    expect(screen(t), contains('Print'));
    root.next();
    await t.pumpUntilIdle();
    expect(screen(t), isNot(contains('Print')));
    noErrors(t);
  });
}
