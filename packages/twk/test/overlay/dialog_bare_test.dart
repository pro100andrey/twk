// A box of the app's own in showDialog (a palette): no room, no title row,
// no dimming; the recipe showDialog's docs give.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

Widget app({int? barrierAlpha = 0}) => Overlay(
  child: Builder(
    builder: (context) => KeyBindings({
      'p': () => unawaited(
        showDialog<void>(
          context,
          (_) => const SizedBox(
            width: 8,
            child: Box(
              style: Style(bg: Color.rgb(0, 0, 90)),
              child: Text('> find'),
            ),
          ),
          alignment: Alignment.topCenter,
          barrierAlpha: barrierAlpha,
        ),
      ),
    }, child: const Text('under')),
  ),
);

void main() {
  testTwk('a Box in showDialog is its child alone, at the top', (t) async {
    await t.pumpWidget(app(), size: (12, 3));
    await t.press('p');
    await t.pump(ms * 200);
    // the box is its text alone; the app's text stays beside it
    expect(t.lines[0], 'un> find');
    expect(t.lines[1], '');
  });

  testTwk('a Dialog adds a cell of room and the box does not', (t) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: Dialog(padding: EdgeInsets.zero, child: Text('ab')),
      ),
      size: (6, 3),
    );
    expect(t.lines.take(3), ['', ' ab', '']);
  });
}
