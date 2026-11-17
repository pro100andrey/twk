// Slider where the terminal reports the pointer in pixels: a press and a
// drag move the thumb by the part of a cell the pointer moved, snapped to
// the divisions; with whole cells reported they move it as before.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget slider(ValueNotifier<double> value, List<double> changes, int? steps) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 11,
          child: Slider(
            value: value.value,
            divisions: steps,
            onChanged: (v) {
              changes.add(v);
              value.value = v;
            },
          ),
        ),
      ],
    );

void main() {
  const cell = (10, 20);

  testTwk('the thumb follows the pointer within a cell', (t) async {
    final value = ValueNotifier<double>(0);
    addTearDown(value.dispose);
    final changes = <double>[];
    await t.pumpWidget(
      slider(value, changes, null),
      size: (20, 3),
      cellPixels: cell,
      pixelMouse: true,
    );
    // 11 cells: the thumb's room is 80 eighths. Pressed 5.55 cells along:
    // the 44th eighth
    await t.mouse(MouseKind.down, 5, 0, offsetX: 5);
    await t.pump();
    expect(changes, [44 / 80]);
    // 7.25 cells: 14 eighths on
    await t.mouse(MouseKind.drag, 7, 0, offsetX: 2);
    await t.pump();
    expect(changes.last, closeTo(58 / 80, 1e-9));
    // the cell's left edge: 7 cells of the press's 5 and a half
    await t.mouse(MouseKind.drag, 7, 0, offsetX: 0);
    await t.pump();
    expect(changes.last, closeTo(56 / 80, 1e-9));
    await t.mouse(MouseKind.up, 7, 0, offsetX: 0);
  });

  testTwk('with divisions the value snaps to the nearest', (t) async {
    final value = ValueNotifier<double>(0);
    addTearDown(value.dispose);
    final changes = <double>[];
    await t.pumpWidget(
      slider(value, changes, 10),
      size: (20, 3),
      cellPixels: cell,
      pixelMouse: true,
    );
    await t.mouse(MouseKind.down, 5, 0, offsetX: 5);
    await t.pump();
    // 44 of 80 eighths is 0.55: the nearer tenth, 0.6
    expect(changes, [0.6]);
    await t.mouse(MouseKind.drag, 5, 0, offsetX: 1);
    await t.pump();
    // 40 eighths: 0.5
    expect(changes, [0.6, 0.5]);
  });

  testTwk('with whole cells reported a drag moves it by whole cells', (
    t,
  ) async {
    final value = ValueNotifier<double>(0);
    addTearDown(value.dispose);
    final changes = <double>[];
    await t.pumpWidget(
      slider(value, changes, null),
      size: (20, 3),
      cellPixels: cell,
    );
    await t.mouse(MouseKind.down, 5, 0);
    await t.mouse(MouseKind.drag, 7, 0);
    await t.pump();
    expect(changes, [0.5, 0.7]);
  });
}
