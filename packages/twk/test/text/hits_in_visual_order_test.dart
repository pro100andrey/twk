// In visual order, where a row of right-to-left text is drawn as it reads,
// a click finds the target drawn under it and the hidden cursor rests on
// the active one where it is drawn: the crumbs of a path, a chip's ×, a key
// of the hints bar, a HitRow's active target. Each row is drawn reordered
// here, so a table of columns summed in stored order finds other targets.
import 'package:test/test.dart';
import 'package:twk/src/text/hit_row.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineTextOrder, TextOrder;
import 'package:twk_test/twk_test.dart';

/// Draws the app's text in visual order from the next frame on.
Future<void> visual(TwkTester t) async {
  t.binding.twkApp.owner.textOrder = TextOrder.visual;
  await t.pump();
}

/// The column of [text] in the first row.
int at(TwkTester t, String text) {
  final x = t.lines.first.indexOf(text);
  expect(x, isNonNegative, reason: '$text in ${t.lines.first}');
  return x;
}

void main() {
  testTwk('a click on a crumb selects the crumb drawn there', (t) async {
    final selected = <int>[];
    await t.pumpWidget(
      Overlay(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 30,
            child: Breadcrumbs(
              items: const ['אבג', 'דהו', 'זחט', 'end'],
              onSelected: selected.add,
            ),
          ),
        ),
      ),
      size: (30, 2),
    );
    await visual(t);
    expect(t.lines.first, 'end ‹ טחז ‹ והד ‹ גבא');
    for (final text in ['גבא', 'והד', 'טחז']) {
      await t.click(at(t, text) + 1, 0);
      await t.pump();
    }
    // the current crumb, drawn first, is no link
    await t.click(at(t, 'end'), 0);
    await t.pump();
    expect(selected, [0, 1, 2]);
  });

  testTwk("a click on a chip's × takes away that chip, on its label not", (
    t,
  ) async {
    final deleted = <int>[];
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: ChipList<int>(
          chips: const [Choice(0, 'אבגד'), Choice(1, 'abc')],
          onDeleted: deleted.add,
        ),
      ),
      size: (30, 2),
    );
    await visual(t);
    expect(t.lines.first, ' × דגבא   abc ×');
    await t.click(at(t, 'א'), 0);
    await t.pump();
    expect(deleted, isEmpty, reason: 'the label');
    await t.click(at(t, '×'), 0);
    await t.pump();
    expect(deleted, [0]);
  });

  testTwk('a click on a hint of the keys bar presses the key it is drawn '
      'for', (t) async {
    final seen = <String>[];
    await t.pumpWidget(
      KeyBindings(
        {'1': () => seen.add('one'), '2': () => seen.add('two')},
        hints: const {'1': 'אחד', '2': 'שתיים'},
        child: const Focus(
          autofocus: true,
          child: KeyHintsBar(pressable: true),
        ),
      ),
      size: (30, 1),
    );
    await visual(t);
    // a right-to-left row: the second entry drawn first
    expect(t.lines.first, 'םייתש 2   דחא 1');
    await t.click(at(t, 'םייתש'), 0);
    await t.click(at(t, 'דחא'), 0);
    await t.click(at(t, '2'), 0);
    expect(seen, ['two', 'one', 'two']);
  });

  testTwk('the hidden cursor rests on the first cell of the active target '
      'where it is drawn', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final active = ValueNotifier(0);
    addTearDown(active.dispose);
    final hits = HitRow();
    await t.pumpWidget(
      Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Focus(
          focusNode: node,
          child: ValueListenableBuilder(
            valueListenable: active,
            builder: (_, a, _) => hits.row([
              for (final (i, label) in ['אבג', 'דהו', 'זחט'].indexed) ...[
                if (i > 0) (span: const Span(' │ '), target: -1),
                (span: Span(label), target: i),
              ],
            ], active: a),
          ),
        ),
      ),
      size: (30, 1),
    );
    node.requestFocus();
    await visual(t);
    expect(t.lines.first, '  טחז │ והד │ גבא');
    expect(t.cursor, (2 + 12, 0));
    expect(hits.startOf(0), 12);
    expect(hits.at(12), 0);
    active.value = 2;
    await t.pump();
    expect(t.cursor, (2, 0));
    expect(hits.startOf(2), 0);
  });
}
