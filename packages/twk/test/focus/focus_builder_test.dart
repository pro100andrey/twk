// FocusBuilder: built again as the focus enters and leaves its subtree,
// the child handed to it not, and no stop of Tab itself.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not; counts its builds in [builds].
final class Field extends StatelessWidget {
  const Field(this.label, {this.builds, super.key});

  final String label;
  final List<String>? builds;

  @override
  Widget build(BuildContext context) =>
      Focus(debugLabel: label, child: _Mark(label, builds));
}

final class _Mark extends StatelessWidget {
  const _Mark(this.label, this.builds);

  final String label;
  final List<String>? builds;

  @override
  Widget build(BuildContext context) {
    builds?.add(label);
    return Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
  }
}

/// [children] one below another at their left edge.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

/// The label of the node with the primary focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

void main() {
  testTwk('a FocusBuilder is built again as the focus enters and leaves its '
      'subtree, not as it moves within it, nor is the child handed to it; '
      'Tab does not stop at it', (t) async {
    final built = <bool>[];
    final childBuilds = <String>[];
    await t.pumpWidget(
      column([
        const Field('a'),
        FocusBuilder(
          debugLabel: 'pane',
          builder: (context, hasFocus, child) {
            built.add(hasFocus);
            return Row(children: [Text(hasFocus ? '*' : '-'), child!]);
          },
          child: column([
            Field('b', builds: childBuilds),
            Field('c', builds: childBuilds),
          ]),
        ),
        const Field('d'),
      ]),
      size: (6, 4),
    );
    expect(built, [false]);
    expect(t.lines.take(4), [' a', '- b', '  c', ' d']);
    final order = <String?>[];
    final shown = <List<bool>>[];
    for (var i = 0; i < 5; i++) {
      await t.press('tab');
      await t.pump();
      order.add(focused(t));
      shown.add(List.of(built));
    }
    expect(order, ['a', 'b', 'c', 'd', 'a']);
    expect(shown, [
      [false],
      [false, true],
      [false, true],
      [false, true, false],
      [false, true, false],
    ]);
    // b and c are built again only for their own focus
    expect(childBuilds, ['b', 'c', 'b', 'b', 'c', 'c']);
    expect(t.lines.take(4), ['>a', '- b', '  c', ' d']);
  });

  testTwk('a FocusBuilder sees the focus of a node anywhere below it, and '
      'shows it in the frame that moves it', (t) async {
    final inner = FocusNode(debugLabel: 'inner');
    final outer = FocusNode(debugLabel: 'outer');
    addTearDown(inner.dispose);
    addTearDown(outer.dispose);
    await t.pumpWidget(
      column([
        FocusBuilder(
          builder: (context, hasFocus, _) => column([
            Text(hasFocus ? 'in' : 'out'),
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: FocusScope(
                child: Focus(focusNode: inner, child: const Text('x')),
              ),
            ),
          ]),
        ),
        Focus(focusNode: outer, child: const Text('o')),
      ]),
      size: (6, 3),
    );
    expect(t.lines.first, 'out');
    final frames = t.terminal.frames.length;
    inner.requestFocus();
    await t.pump();
    expect(t.lines.first, 'in');
    expect(t.terminal.frames, hasLength(frames + 1));
    inner.unfocus();
    await t.pump();
    expect(t.lines.first, 'in', reason: 'its scope, below it, has it');
    outer.requestFocus();
    await t.pump();
    expect(t.lines.first, 'out');
  });
}
