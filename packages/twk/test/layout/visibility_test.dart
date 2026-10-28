// Offstage and Visibility: a child kept laid out with its state while it
// paints nothing, takes no room, is not hit, takes no focus and is not
// read by a screen reader; a repaint boundary in it repainting on its own
// showing nothing; Visibility's replacement, the state it keeps and the
// size.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderEffect;
import 'package:twk_test/twk_test.dart';

/// The render objects a hit test of the last frame finds at [x], [y], the
/// deepest first.
List<RenderObject> hitsAt(TwkTester t, int x, int y) {
  final result = HitTestResult();
  t.binding.twkApp.owner.hitTest(result, x, y);
  return [for (var i = 0; i < result.length; i++) result[i]];
}

/// Shows `n` [label]s, `n` counted up by [CounterState.bump]: its state
/// is the one it kept, or a new one.
final class Counter extends StatefulWidget {
  const Counter(this.label, {super.key, this.node});

  final String label;
  final FocusNode? node;

  @override
  State<Counter> createState() => CounterState();
}

final class CounterState extends State<Counter> {
  var n = 0;
  static var made = 0;

  @override
  void initState() {
    super.initState();
    made++;
  }

  void bump() => setState(() => n++);

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.node,
    child: Text('$n ${widget.label}'),
  );
}

/// Shows what [builder] builds of a flag that [HostState.flip] flips.
final class Host extends StatefulWidget {
  const Host(this.builder, {super.key});

  final Widget Function(bool on) builder;

  @override
  State<Host> createState() => HostState();
}

final class HostState extends State<Host> {
  var on = true;

  void flip() => setState(() => on = !on);

  @override
  Widget build(BuildContext context) => widget.builder(on);
}

/// A row of [notifier]'s value in the cells it covers, which it repaints.
final class Digits extends CellPainter {
  Digits(this.notifier) : super(repaint: notifier);

  final ValueNotifier<int> notifier;

  @override
  void paint(Canvas canvas, int width, int height) {
    final pen = canvas.styles.pen(const Pen());
    canvas.text(0, 0, '${notifier.value}' * width, pen);
  }

  @override
  bool shouldRepaint(Digits oldDelegate) => false;
}

void main() {
  setUp(() => CounterState.made = 0);

  testTwk('an offstage child is laid out but not painted, the offstage as '
      'small as it may be: what comes after it takes its place', (t) async {
    await t.pumpWidget(
      const Row(
        children: [
          Offstage(child: Text('hidden')),
          Text('after'),
        ],
      ),
      size: (20, 2),
    );
    expect(t.lines.first, 'after');
    final offstage = t.renderObject(find.byType(Offstage));
    expect((offstage.width, offstage.height), (0, 0));
    final text = t.renderObject(find.text('hidden'));
    expect((text.width, text.height), (6, 1), reason: 'laid out');
    expect(offstage.getMaxIntrinsicWidth(1), 0);
  });

  testTwk('Offstage(offstage: false) shows its child as it is, as big', (
    t,
  ) async {
    await t.pumpWidget(
      const Row(
        children: [
          Offstage(offstage: false, child: Text('shown')),
          Text('|'),
        ],
      ),
      size: (20, 2),
    );
    expect(t.lines.first, 'shown|');
    final offstage = t.renderObject(find.byType(Offstage));
    expect((offstage.width, offstage.height), (5, 1));
  });

  testTwk('a child keeps its state offstage, and shows it on stage again', (
    t,
  ) async {
    final host = GlobalKey<HostState>();
    final counter = GlobalKey<CounterState>();
    await t.pumpWidget(
      Host(
        key: host,
        (on) => Offstage(
          offstage: !on,
          child: Counter('taps', key: counter),
        ),
      ),
      size: (20, 2),
    );
    final state = counter.currentState!..bump();
    await t.pump();
    expect(t.lines.first, '1 taps');
    host.currentState!.flip();
    await t.pump();
    expect(t.lines.first, '', reason: 'offstage');
    expect(identical(counter.currentState, state), isTrue);
    state.bump();
    await t.pump();
    expect(t.lines.first, '', reason: 'built offstage, not shown');
    host.currentState!.flip();
    await t.pump();
    expect(t.lines.first, '2 taps');
    expect(identical(counter.currentState, state), isTrue);
    expect(CounterState.made, 1);
  });

  testTwk('an offstage child takes no focus: Tab passes it by, a request is '
      'refused, and the focus it had leaves it as it goes offstage', (
    t,
  ) async {
    final host = GlobalKey<HostState>();
    final inside = FocusNode(debugLabel: 'inside');
    final outside = FocusNode(debugLabel: 'outside');
    addTearDown(inside.dispose);
    addTearDown(outside.dispose);
    await t.pumpWidget(
      Host(
        key: host,
        (on) => Column(
          children: [
            Offstage(
              offstage: !on,
              child: Counter('in', node: inside),
            ),
            Focus(focusNode: outside, child: const Text('out')),
          ],
        ),
      ),
      size: (20, 3),
    );
    inside.requestFocus();
    await t.pump();
    expect(inside.hasPrimaryFocus, isTrue, reason: 'on stage');
    host.currentState!.flip();
    await t.pump();
    expect(inside.hasFocus, isFalse, reason: 'gone offstage');
    expect(inside.canRequestFocus, isFalse);
    inside.requestFocus();
    await t.pump();
    expect(inside.hasFocus, isFalse, reason: 'asked offstage');
    for (var i = 0; i < 3; i++) {
      await t.press('tab');
      expect(inside.hasFocus, isFalse, reason: 'tab $i');
      expect(outside.hasPrimaryFocus, isTrue, reason: 'tab $i');
    }
    host.currentState!.flip();
    await t.pump();
    inside.requestFocus();
    await t.pump();
    expect(inside.hasPrimaryFocus, isTrue, reason: 'on stage again');
  });

  testTwk('no cell of an offstage child is hit, even where the constraints '
      'give the offstage its cells', (t) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 6,
          height: 1,
          child: Offstage(child: Text('hidden')),
        ),
      ),
      size: (10, 2),
    );
    final offstage = t.renderObject(find.byType(Offstage));
    expect((offstage.width, offstage.height), (6, 1), reason: 'tight');
    expect(t.lines.first, '');
    final text = t.renderObject(find.text('hidden'));
    for (var x = 0; x < 6; x++) {
      expect(hitsAt(t, x, 0), isNot(contains(text)), reason: 'cell $x');
      expect(hitsAt(t, x, 0), isNot(contains(offstage)), reason: 'cell $x');
    }
  });

  testTwk('a repaint boundary in an offstage child that repaints on its own '
      'shows nothing', (t) async {
    final digits = ValueNotifier(1);
    addTearDown(digits.dispose);
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 6,
            height: 1,
            child: Offstage(
              child: RepaintBoundary(
                child: CustomPaint(painter: Digits(digits), size: (6, 1)),
              ),
            ),
          ),
          const Text('below'),
        ],
      ),
      size: (10, 3),
    );
    expect(t.lines.take(2), ['', 'below']);
    final boundary = t.renderObject<RenderEffect>(
      find.byType(RepaintBoundary),
    );
    expect(boundary.isRepaintBoundary, isTrue);
    digits.value = 2;
    await t.pump();
    expect(t.lines.take(2), ['', 'below']);
  });

  testTwk('Visibility shows its replacement in place of a child it is not '
      'to show, the child out of the tree with its state', (t) async {
    final host = GlobalKey<HostState>();
    await t.pumpWidget(
      Host(
        key: host,
        (on) => Visibility(
          visible: on,
          replacement: const Text('instead'),
          child: const Counter('child'),
        ),
      ),
      size: (20, 2),
    );
    expect(t.lines.first, '0 child');
    host.currentState!.flip();
    await t.pump();
    expect(t.lines.first, 'instead');
    expect(find.byType(Counter), findsNothing);
    host.currentState!.flip();
    await t.pump();
    expect(t.lines.first, '0 child');
    expect(CounterState.made, 2, reason: 'a new state');
  });

  testTwk('Visibility(maintainState: true) keeps its child offstage, state '
      'and all; the default replacement is empty', (t) async {
    final host = GlobalKey<HostState>();
    final counter = GlobalKey<CounterState>();
    await t.pumpWidget(
      Host(
        key: host,
        (on) => Row(
          children: [
            Visibility(
              visible: on,
              maintainState: true,
              child: Counter('kept', key: counter),
            ),
            const Text('|'),
          ],
        ),
      ),
      size: (20, 2),
    );
    counter.currentState!.bump();
    await t.pump();
    expect(t.lines.first, '1 kept|');
    host.currentState!.flip();
    await t.pump();
    expect(t.lines.first, '|');
    expect(find.byType(Offstage), findsOneWidget);
    host.currentState!.flip();
    await t.pump();
    expect(t.lines.first, '1 kept|');
    expect(CounterState.made, 1);
  });

  testTwk('Visibility(maintainSize: true) keeps the room of a child it does '
      'not show, which is not painted, hit or focused', (t) async {
    final host = GlobalKey<HostState>();
    final node = FocusNode();
    addTearDown(node.dispose);
    await t.pumpWidget(
      Host(
        key: host,
        (on) => Row(
          children: [
            Visibility(
              visible: on,
              maintainState: true,
              maintainSize: true,
              child: Counter('sized', node: node),
            ),
            const Text('|'),
          ],
        ),
      ),
      size: (20, 2),
    );
    node.requestFocus();
    await t.pump();
    expect(t.lines.first, '0 sized|');
    expect(node.hasPrimaryFocus, isTrue);
    host.currentState!.flip();
    await t.pump();
    expect(t.lines.first, '       |');
    expect(node.hasFocus, isFalse);
    final text = t.renderObject(find.text('0 sized'));
    for (var x = 0; x < 7; x++) {
      expect(hitsAt(t, x, 0), isNot(contains(text)), reason: 'cell $x');
    }
    host.currentState!.flip();
    await t.pump();
    expect(t.lines.first, '0 sized|');
    expect(hitsAt(t, 0, 0), contains(text));
  });

  testTwk('a screen reader reads nothing of an offstage child, the label '
      'of the node it is in its text left out too, and reads it on stage '
      'again', (t) async {
    final host = GlobalKey<HostState>();
    await t.pumpWidget(
      Host(
        key: host,
        (on) => Column(
          children: [
            const Text('before'),
            Offstage(offstage: !on, child: const Text('hidden')),
            Semantics(
              role: SemanticsRole.button,
              child: Row(
                children: [
                  const Text('OK'),
                  Offstage(offstage: !on, child: const Text('later')),
                ],
              ),
            ),
            const Text('after'),
          ],
        ),
      ),
      size: (20, 4),
    );
    expect(t.binding.semantics.lines, [
      'before',
      'hidden',
      'button OK later',
      'after',
    ]);
    host.currentState!.flip();
    await t.pump();
    expect(t.binding.semantics.lines, ['before', 'button OK', 'after']);
    host.currentState!.flip();
    await t.pump();
    expect(t.binding.semantics.lines, [
      'before',
      'hidden',
      'button OK later',
      'after',
    ]);
  });

  testTwk('a screen reader reads nothing of a child Visibility does not '
      'show, its state or its size kept', (t) async {
    final host = GlobalKey<HostState>();
    await t.pumpWidget(
      Host(
        key: host,
        (on) => Column(
          children: [
            Visibility(
              visible: on,
              maintainState: true,
              child: const Text('state'),
            ),
            Visibility(
              visible: on,
              maintainState: true,
              maintainSize: true,
              child: const Text('size'),
            ),
            const Text('shown'),
          ],
        ),
      ),
      size: (20, 3),
    );
    expect(t.binding.semantics.lines, ['state', 'size', 'shown']);
    host.currentState!.flip();
    await t.pump();
    expect(t.binding.semantics.lines, ['shown']);
  });

  testTwk('the debug tree says whether a child is offstage, and how '
      'Visibility hides it where it is not visible', (t) async {
    await t.pumpWidget(
      const Column(
        children: [
          Offstage(child: Text('a')),
          Visibility(visible: false, maintainState: true, child: Text('b')),
          Visibility(child: Text('c')),
        ],
      ),
      size: (5, 3),
    );
    expect(
      '${t.element(find.byType(Offstage).first).describe()}',
      'Offstage ‹offstage: true›',
    );
    final shown = find.byType(Visibility);
    expect(
      '${t.element(shown.first).describe()}',
      'Visibility ‹visible: false, maintainState: true›',
    );
    expect('${t.element(shown.at(1)).describe()}', 'Visibility');
  });
}
