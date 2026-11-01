// The hand over everything a click presses, by one rule (ThemeData.
// handPointer: off, auto, on): each tap target shows it over the cells it
// presses and not beside them; the three modes, and what each has the
// terminal report of the mouse; the shape written as it changes, not as
// the mouse moves. Read off the tester's terminal, which shows pointer
// shapes when asked to.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show MouseTracking, MouseTrackingBackend;
import 'package:twk_test/twk_test.dart';

Widget themed(HandPointer mode, Widget child) => Theme(
  data: const ThemeData.terminal(
    Brightness.dark,
  ).copyWith(handPointer: mode),
  child: child,
);

MouseTracking tracking(TwkTester t) =>
    (t.binding.twkApp.terminal as MouseTrackingBackend).mouseTracking;

/// The shape after the mouse moved to [x], [y].
Future<PointerShape?> shapeAt(TwkTester t, int x, int y) async {
  await t.mouse(MouseKind.move, x, y);
  await t.pump();
  return t.pointerShape;
}

/// How many times the app wrote a pointer shape (OSC 22).
int shapesWritten(TwkTester t, {int since = 0}) =>
    RegExp('\x1b\\]22;').allMatches(t.written(since: since)).length;

final class Probe extends StatefulWidget {
  const Probe(this.onInit, {super.key});

  final void Function() onInit;

  @override
  State<Probe> createState() => _ProbeState();
}

final class _ProbeState extends State<Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}

void main() {
  group('over each tap target, in the on mode', () {
    Future<void> check(
      TwkTester t,
      Widget app, {
      required (int, int) over,
      required (int, int) beside,
      (int, int) size = (40, 6),
    }) async {
      await t.pumpWidget(
        themed(HandPointer.on, app),
        size: size,
        pointerShapes: true,
      );
      expect(await shapeAt(t, over.$1, over.$2), PointerShape.pointer);
      expect(await shapeAt(t, beside.$1, beside.$2), PointerShape.arrow);
    }

    testTwk('a tab, not the room beside the tabs', (t) async {
      final c = TabController(length: 3);
      addTearDown(c.dispose);
      await check(
        t,
        TabBar(controller: c, tabs: const ['One', 'Two', 'Three']),
        over: (2, 0),
        beside: (30, 0),
      );
    });

    testTwk('a title of the menu bar that opens, not the bar beside', (
      t,
    ) async {
      await check(
        t,
        Overlay(
          child: MenuBar(
            menus: [
              Menu('&File', items: [MenuItem('&New', onSelected: () {})]),
              const Menu('&Off', enabled: false, items: []),
            ],
            child: const Text('body'),
          ),
        ),
        over: (2, 0),
        beside: (30, 0),
      );
    });

    testTwk('an item of an open menu that can be chosen, not a disabled one '
        'or a divider', (t) async {
      await t.pumpWidget(
        themed(
          HandPointer.on,
          Overlay(
            child: MenuBar(
              look: PanelLook.bordered,
              menus: [
                Menu(
                  '&File',
                  items: [
                    MenuItem('&New', onSelected: () {}),
                    const MenuDivider(),
                    const MenuItem('&Gone', enabled: false),
                  ],
                ),
              ],
              child: const Focus(autofocus: true, child: Text('body')),
            ),
          ),
        ),
        size: (40, 8),
        pointerShapes: true,
      );
      await t.press('f10');
      await t.pump();
      final rows = t.lines;
      final item = rows.indexWhere((l) => l.contains('New'));
      final gone = rows.indexWhere((l) => l.contains('Gone'));
      expect(item, greaterThan(0));
      final x = rows[item].indexOf('New');
      expect(await shapeAt(t, x, item), PointerShape.pointer);
      expect(await shapeAt(t, x, gone), PointerShape.arrow);
      expect(await shapeAt(t, x, item + 1), PointerShape.arrow);
    });

    testTwk('the header of a step that can be clicked, not the current '
        'one', (t) async {
      await check(
        t,
        Stepper(
          linear: false,
          controller: StepperController(),
          steps: const [
            Step(title: 'One', content: Text('a')),
            Step(title: 'Two', content: Text('b')),
          ],
        ),
        over: (14, 0),
        beside: (2, 0),
      );
    });

    testTwk('the dismiss mark of a callout, not the callout', (t) async {
      await t.pumpWidget(
        themed(
          HandPointer.on,
          Callout.text('hello there', onDismissed: () {}),
        ),
        size: (30, 3),
        pointerShapes: true,
      );
      final x = t.lines.first.indexOf('[');
      expect(await shapeAt(t, x + 1, 0), PointerShape.pointer);
      expect(await shapeAt(t, 3, 1), PointerShape.arrow);
    });

    testTwk('the title of a column that sorts, not one that does not, nor '
        'the edge', (t) async {
      await check(
        t,
        Table<({String a, String b})>(
          rows: const [(a: 'x', b: 'y')],
          columns: [
            TableColumn(
              title: 'Aaaa',
              cell: (r) => TableCell(r.a),
              width: const GridTrack.fixed(8),
              compare: (p, q) => p.a.compareTo(q.a),
            ),
            TableColumn(
              title: 'Bbbb',
              cell: (r) => TableCell(r.b),
              width: const GridTrack.fixed(8),
            ),
          ],
        ),
        over: (2, 0),
        beside: (12, 0),
      );
    });

    testTwk('a key or a hint of a pressable key bar, not the gaps', (
      t,
    ) async {
      await check(
        t,
        KeyBindings(
          {'ctrl+s': () {}},
          hints: const {'ctrl+s': 'save'},
          child: const Focus(
            autofocus: true,
            child: KeyHintsBar(pressable: true),
          ),
        ),
        over: (2, 0),
        beside: (30, 0),
      );
    });

    testTwk('a phrase of a Span.tap, not the text around it', (t) async {
      await check(
        t,
        Text.rich([
          const Span('go to '),
          'docs'.tap(() {}),
          const Span(' now'),
        ]),
        over: (8, 0),
        beside: (2, 0),
      );
    });

    testTwk('a link of a Text with onLinkTap', (t) async {
      await check(
        t,
        Text.rich([
          const Span('see '),
          'the docs'.link('https://dart.dev'),
        ], onLinkTap: (_) {}),
        over: (6, 0),
        beside: (1, 0),
      );
    });
  });

  group('the modes', () {
    Widget checkbox(HandPointer mode, {Widget? beside}) => themed(
      mode,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: false, onChanged: (_) {}, label: 'ok'),
          ?beside,
        ],
      ),
    );

    // somewhere the app asks for the mouse's motion already
    final hover = MouseRegion(onHover: (_) {}, child: const Text('hover'));

    testTwk('off: no hand, whatever else asks for the motion', (t) async {
      await t.pumpWidget(
        checkbox(HandPointer.off, beside: hover),
        size: (20, 3),
        pointerShapes: true,
      );
      expect(tracking(t), MouseTracking.motion);
      expect(await shapeAt(t, 1, 0), PointerShape.arrow);
    });

    testTwk('auto: no hand, and no motion asked for, where nothing else '
        'asks', (t) async {
      await t.pumpWidget(
        checkbox(HandPointer.auto),
        size: (20, 3),
        pointerShapes: true,
      );
      expect(tracking(t), isNot(MouseTracking.motion));
      expect(await shapeAt(t, 1, 0), isNot(PointerShape.pointer));
    });

    testTwk('auto: the hand where something else asks for the motion, and '
        'asks for nothing more', (t) async {
      await t.pumpWidget(
        checkbox(HandPointer.auto, beside: hover),
        size: (20, 3),
        pointerShapes: true,
      );
      expect(tracking(t), MouseTracking.motion);
      expect(await shapeAt(t, 1, 0), PointerShape.pointer);
      expect(await shapeAt(t, 15, 0), PointerShape.arrow);
    });

    testTwk('auto is the default', (t) async {
      expect(
        const ThemeData.terminal(Brightness.dark).handPointer,
        HandPointer.auto,
      );
      await t.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: false, onChanged: (_) {}, label: 'ok'),
            hover,
          ],
        ),
        size: (20, 3),
        pointerShapes: true,
      );
      expect(await shapeAt(t, 1, 0), PointerShape.pointer);
    });

    testTwk('on: the hand everywhere, which has the motion reported', (
      t,
    ) async {
      await t.pumpWidget(
        checkbox(HandPointer.on),
        size: (20, 3),
        pointerShapes: true,
      );
      expect(tracking(t), MouseTracking.motion);
      expect(await shapeAt(t, 1, 0), PointerShape.pointer);
      expect(await shapeAt(t, 15, 0), PointerShape.arrow);
    });

    testTwk('the mode changing keeps the state of what it wraps', (t) async {
      final mode = ValueNotifier(HandPointer.off);
      addTearDown(mode.dispose);
      var inits = 0;
      await t.pumpWidget(
        ValueListenableBuilder(
          valueListenable: mode,
          builder: (_, m, _) => themed(
            m,
            Pressable(
              onTap: (_) {},
              builder: (_, _) => Probe(() => inits++),
            ),
          ),
        ),
        size: (20, 1),
        pointerShapes: true,
      );
      expect(inits, 1);
      mode.value = HandPointer.on;
      await t.pump();
      expect(tracking(t), MouseTracking.motion);
      mode.value = HandPointer.auto;
      await t.pump();
      expect(tracking(t), isNot(MouseTracking.motion));
      expect(inits, 1);
    });

    testTwk('the shape is written as it changes, not as the mouse moves', (
      t,
    ) async {
      await t.pumpWidget(
        checkbox(HandPointer.on),
        size: (20, 3),
        pointerShapes: true,
      );
      final from = t.terminal.frames.length;
      for (var x = 0; x < 6; x++) {
        await shapeAt(t, x, 0);
      }
      // the box and its label are one target: the hand once, in
      expect(shapesWritten(t, since: from), 1);
      for (var x = 6; x < 20; x++) {
        await shapeAt(t, x, 0);
      }
      // and the arrow once, out
      expect(shapesWritten(t, since: from), 2);
    });
  });
}
