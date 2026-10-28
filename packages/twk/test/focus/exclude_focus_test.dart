// ExcludeFocus: the nodes inside passed by Tab, autofocus and
// requestFocus; the focus moved out when it turns on, and the nodes
// focusable again when it turns off.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] labelled [label] with [node], shown as the label.
Widget field(String label, {FocusNode? node, bool autofocus = false}) => Focus(
  focusNode: node,
  autofocus: autofocus,
  debugLabel: label,
  child: Text(label),
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

/// The label of the node with the primary focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses each key of [keys] and pumps a frame after it; the labels
/// focused after each.
Future<List<String?>> tab(TwkTester t, String keys) async => [
  for (final key in keys.split(' '))
    await t.press(key).then((_) => t.pump()).then((_) => focused(t)),
];

/// `a`, then `b` and `c` (with [b]'s node and autofocus) inside an
/// [ExcludeFocus] that excludes while the host is on, then `d`.
Widget fields(FocusNode b) => Host(
  key: host,
  (s) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      field('a'),
      ExcludeFocus(
        excluding: s.on,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field('b', node: b, autofocus: true),
            field('c'),
          ],
        ),
      ),
      field('d'),
    ],
  ),
);

void main() {
  testTwk('the nodes inside are passed by Tab and Shift+Tab, autofocus and '
      'requestFocus while it excludes', (t) async {
    final b = FocusNode();
    addTearDown(b.dispose);
    await t.pumpWidget(fields(b), size: (10, 4));
    expect(focused(t), isNull);
    expect(await tab(t, 'tab tab tab'), ['a', 'd', 'a']);
    expect(await tab(t, 'shift+tab shift+tab'), ['d', 'a']);
    b.requestFocus();
    await t.pump();
    expect(focused(t), 'a');
    expect(b.canRequestFocus, isFalse);
  });

  testTwk('turned on, the focus inside leaves to the stop after it, else '
      'the one before it; turned off, the nodes can have it again', (
    t,
  ) async {
    final b = FocusNode();
    addTearDown(b.dispose);
    await t.pumpWidget(fields(b), size: (10, 4));
    host.currentState!.turn(on: false);
    await t.pump();
    expect(await tab(t, 'tab tab tab tab'), ['a', 'b', 'c', 'd']);
    b.requestFocus();
    await t.pump();
    expect(focused(t), 'b');

    host.currentState!.turn(on: true);
    await t.pump();
    expect(focused(t), 'd');
    expect(b.hasFocus, isFalse);

    host.currentState!.turn(on: false);
    await t.pump();
    expect(focused(t), 'd');
    expect(await tab(t, 'shift+tab shift+tab'), ['c', 'b']);
  });

  testTwk('turned on with no stop after it, the focus inside leaves to '
      'the one before it', (t) async {
    final b = FocusNode();
    addTearDown(b.dispose);
    await t.pumpWidget(
      Host(
        key: host,
        (s) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field('a'),
            ExcludeFocus(
              excluding: s.on,
              child: field('b', node: b),
            ),
          ],
        ),
      ),
      size: (10, 4),
    );
    host.currentState!.turn(on: false);
    await t.pump();
    b.requestFocus();
    await t.pump();
    expect(focused(t), 'b');
    host.currentState!.turn(on: true);
    await t.pump();
    expect(focused(t), 'a');
  });

  testTwk('it takes no focus itself, excluding or not', (t) async {
    late FocusNode node;
    await t.pumpWidget(
      Host(
        key: host,
        (s) => ExcludeFocus(
          excluding: s.on,
          child: Builder(
            builder: (context) {
              node = Focus.of(context);
              return const Text('x');
            },
          ),
        ),
      ),
      size: (10, 4),
    );
    for (final on in [true, false]) {
      host.currentState!.turn(on: on);
      await t.pump();
      node.requestFocus();
      await t.pump();
      expect(focused(t), isNull);
      expect(await tab(t, 'tab'), [null]);
    }
  });
}
