// IgnorePointer and AbsorbPointer: the mouse passing a subtree by to what
// is under it, or stopping at it; the hover moved off it; each turned on
// and off at runtime.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../framework/harness.dart' show Tree;

/// What [log] is told, as `name kind x,y` with the cell in the coordinates
/// of the widget.
PointerEventListener record(List<String> log, String name) =>
    (e) => log.add('$name ${e.kind.name} ${e.x},${e.y}');

/// A [Listener] that tells [log] each event as [name], hit anywhere in its
/// bounds.
Widget listener(List<String> log, String name, {Widget? child}) {
  final r = record(log, name);
  return Listener(
    onDown: r,
    onUp: r,
    onMove: r,
    onDrag: r,
    onScroll: r,
    behavior: HitTestBehavior.opaque,
    child: child ?? const SizedBox.expand(),
  );
}

/// A [MouseRegion] that tells [log] each enter, exit and hover as [name].
Widget region(List<String> log, String name, {Widget? child}) => MouseRegion(
  onEnter: (e) => log.add('$name enter ${e.x},${e.y}'),
  onExit: (e) => log.add('$name exit ${e.x},${e.y}'),
  onHover: (e) => log.add('$name hover ${e.x},${e.y}'),
  child: child ?? const SizedBox.expand(),
);

/// Gives the [InputListener]s' mouse events to [log] as `input kind x,y`,
/// and takes them.
Widget inputs(List<String> log, Widget child) => InputListener(
  onEvent: (e) {
    if (e is MouseEvent) {
      log.add('input ${e.kind.name} ${e.x},${e.y}');
      return true;
    }
    return false;
  },
  child: child,
);

/// Shows what [builder] builds from its state, which changes it.
final class Host extends StatefulWidget {
  const Host(this.builder, {super.key});

  final Widget Function(HostState state) builder;

  @override
  State<Host> createState() => HostState();
}

final class HostState extends State<Host> {
  var on = true;

  void turn({required bool on}) => setState(() => this.on = on);

  @override
  Widget build(BuildContext context) => widget.builder(this);
}

final host = GlobalKey<HostState>();

/// [child] at 2, 1 of a 20 × 5 screen, 6 × 2 cells, over a [Listener]
/// `under` that fills the screen's left half, inside [inputs].
Widget over(List<String> log, Widget child) => inputs(
  log,
  Stack(
    children: [
      Positioned(
        left: 0,
        top: 0,
        width: 10,
        height: 5,
        child: listener(log, 'under'),
      ),
      Positioned(left: 2, top: 1, width: 6, height: 2, child: child),
    ],
  ),
);

/// Each kind of event at 3, 1 (over [over]'s child at 1, 0) and at 12, 4
/// (over nothing).
Future<void> everyKind(TwkTester t) async {
  await t.mouse(MouseKind.move, 3, 1);
  await t.mouse(MouseKind.down, 3, 1);
  await t.mouse(MouseKind.drag, 4, 2);
  await t.mouse(MouseKind.up, 4, 2);
  await t.mouse(MouseKind.wheelDown, 3, 1);
}

void main() {
  testTwk('IgnorePointer: presses, motion and the wheel over it go to what '
      'is under it, and to the InputListeners where nothing is', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      over(log, IgnorePointer(child: listener(log, 'inside'))),
      size: (20, 5),
    );
    await everyKind(t);
    await t.click(12, 4);
    expect(log, [
      'under move 3,1',
      'under down 3,1',
      'under drag 4,2',
      'under up 4,2',
      'under wheelDown 3,1',
      'input down 12,4',
      'input up 12,4',
    ]);

    log.clear();
    await t.pumpWidget(
      inputs(log, IgnorePointer(child: listener(log, 'inside'))),
      size: (20, 5),
    );
    await t.click(3, 1);
    expect(log, ['input down 3,1', 'input up 3,1']);
  });

  testTwk('IgnorePointer turned on and off: the mouse reaches the subtree '
      'only while it is off; a press made before goes on to it', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Host(
        key: host,
        (s) => over(
          log,
          IgnorePointer(ignoring: s.on, child: listener(log, 'inside')),
        ),
      ),
      size: (20, 5),
    );
    await t.click(3, 1);
    host.currentState!.turn(on: false);
    await t.pump();
    await t.click(3, 1);
    await t.mouse(MouseKind.wheelUp, 3, 1);
    await t.mouse(MouseKind.down, 3, 1);
    host.currentState!.turn(on: true);
    await t.pump();
    await t.mouse(MouseKind.drag, 4, 1);
    await t.mouse(MouseKind.up, 4, 1);
    await t.click(3, 1);
    expect(log, [
      'under down 3,1',
      'under up 3,1',
      'inside down 1,0',
      'inside up 1,0',
      'inside wheelUp 1,0',
      'inside down 1,0',
      'inside drag 2,0',
      'inside up 2,0',
      'under down 3,1',
      'under up 3,1',
    ]);
  });

  testTwk('IgnorePointer: the MouseRegions inside are passed by, and the '
      'hover inside ends when it turns on under a mouse that stays put', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(
      Host(
        key: host,
        (s) => Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 10,
              height: 5,
              child: region(log, 'under'),
            ),
            Positioned(
              left: 2,
              top: 1,
              width: 6,
              height: 2,
              child: IgnorePointer(
                ignoring: s.on,
                child: region(log, 'inside'),
              ),
            ),
          ],
        ),
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.move, 3, 1);
    host.currentState!.turn(on: false);
    await t.pump();
    await t.mouse(MouseKind.move, 4, 1);
    host.currentState!.turn(on: true);
    await t.pump();
    await t.mouse(MouseKind.move, 4, 2);
    expect(log, [
      'under enter 3,1',
      'under hover 3,1',
      'under exit 3,1',
      'inside enter 1,0',
      'inside hover 2,0',
      'inside exit 2,0',
      'under enter 4,1',
      'under hover 4,2',
    ]);
  });

  testTwk('AbsorbPointer: presses, motion and the wheel over it reach '
      'neither its subtree nor what is under it, nor the InputListeners; '
      'what follows a press there neither', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      over(log, AbsorbPointer(child: listener(log, 'inside'))),
      size: (20, 5),
    );
    await everyKind(t);
    // pressed there, dragged and released over what is under it
    await t.mouse(MouseKind.down, 3, 1);
    await t.mouse(MouseKind.drag, 0, 0);
    await t.mouse(MouseKind.up, 0, 0);
    // with no child, its bounds
    await t.pumpWidget(
      over(log, const AbsorbPointer()),
      size: (20, 5),
    );
    await t.click(5, 2);
    // around it, as next to it
    await t.click(0, 0);
    expect(log, ['under down 0,0', 'under up 0,0']);
  });

  testTwk('AbsorbPointer: the Listeners around it get what is over it, '
      'a scrolling view the wheel', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      inputs(
        log,
        listener(
          log,
          'around',
          child: AbsorbPointer(child: listener(log, 'inside')),
        ),
      ),
      size: (20, 5),
    );
    await t.click(3, 1);
    await t.mouse(MouseKind.wheelDown, 3, 1);
    expect(log, ['around down 3,1', 'around up 3,1', 'around wheelDown 3,1']);
  });

  testTwk('AbsorbPointer turned on and off: the subtree gets the mouse only '
      'while it is off, the MouseRegion inside left when it turns on under '
      'a mouse that stays put', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Host(
        key: host,
        (s) => over(
          log,
          AbsorbPointer(
            absorbing: s.on,
            child: region(log, 'region', child: listener(log, 'inside')),
          ),
        ),
      ),
      size: (20, 5),
    );
    await t.click(3, 1);
    host.currentState!.turn(on: false);
    await t.pump();
    await t.mouse(MouseKind.move, 3, 1);
    await t.click(3, 1);
    host.currentState!.turn(on: true);
    await t.pump();
    await t.mouse(MouseKind.move, 4, 1);
    await t.click(4, 1);
    expect(log, [
      'region enter 1,0',
      'region hover 1,0',
      'inside move 1,0',
      'inside down 1,0',
      'inside up 1,0',
      'region exit 1,0',
    ]);
  });

  test('each says whether it keeps the mouse from its child', () {
    final tree = Tree()
      ..pump(
        const IgnorePointer(child: AbsorbPointer(absorbing: false)),
      );
    expect(
      '${tree.elementOf<IgnorePointer>().describe()}',
      'IgnorePointer ‹ignoring: true›',
    );
    expect(
      '${tree.elementOf<AbsorbPointer>().describe()}',
      'AbsorbPointer ‹absorbing: false›',
    );
  });
}
