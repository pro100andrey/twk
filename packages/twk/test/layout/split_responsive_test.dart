// The documented recipe for a split view that lies down under a width: a
// LayoutBuilder picks the direction, the controller and the panes' state
// stay across the switch.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'view.dart' show Fill;

/// [char] filling its room, calling [created] as its state is made.
final class Counted extends StatefulWidget {
  const Counted(this.char, this.created, {super.key});

  final String char;
  final void Function() created;

  @override
  State<Counted> createState() => _CountedState();
}

final class _CountedState extends State<Counted> {
  @override
  void initState() {
    super.initState();
    widget.created();
  }

  @override
  Widget build(BuildContext context) => Fill(widget.char);
}

void main() {
  group('SplitView in a LayoutBuilder', () {
    testTwk('lies down under a width, keeping its shares and the state of '
        'its panes', (t) async {
      final c = SplitController(fractions: [1, 3]);
      var created = 0;
      void count() => created++;
      await t.pumpWidget(
        Theme.terminal(
          child: LayoutBuilder(
            builder: (context, constraints) => SplitView(
              controller: c,
              direction: constraints.maxW < 20
                  ? Axis.vertical
                  : Axis.horizontal,
              panes: [
                SplitPane(child: Counted('a', count)),
                SplitPane(child: Counted('b', count)),
              ],
            ),
          ),
        ),
        size: (21, 5),
      );
      expect(t.lines, [
        'aaaaa│bbbbbbbbbbbbbbb',
        'aaaaa│bbbbbbbbbbbbbbb',
        'aaaaa│bbbbbbbbbbbbbbb',
        'aaaaa│bbbbbbbbbbbbbbb',
        'aaaaa│bbbbbbbbbbbbbbb',
      ]);
      await t.resize(11, 5);
      await t.pump();
      expect(t.lines, [
        'aaaaaaaaaaa',
        '───────────',
        'bbbbbbbbbbb',
        'bbbbbbbbbbb',
        'bbbbbbbbbbb',
      ]);
      expect(c.fractions, [0.25, 0.75]);
      await t.resize(21, 5);
      await t.pump();
      expect(t.lines.first, 'aaaaa│bbbbbbbbbbbbbbb');
      expect(created, 2);
    });
  });
}
