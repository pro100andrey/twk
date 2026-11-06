// What a widget around a GestureDetector sees of a press the detector
// takes: a Listener, which is not in the competition, sees all of it; a
// GestureDetector does not. And where a Box's cells are hit.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  Widget card(List<String> log) {
    final inner = GestureDetector(
      onTap: () => log.add('inner tap'),
      child: const Box(
        border: Border.all(),
        child: Text('in'),
      ),
    );
    return Listener(
      onPointerDown: (e) => log.add('outer down ${e.x},${e.y}'),
      onPointerUp: (e) => log.add('outer up ${e.x},${e.y}'),
      child: GestureDetector(
        onTap: () => log.add('outer tap'),
        child: Box(
          border: const Border.all(type: BorderType.rounded),
          padding: const EdgeInsets.all(1),
          child: inner,
        ),
      ),
    );
  }

  testTwk('a Listener around a detector sees the press and release of a tap '
      'the detector inside takes; the detector around gets no tap', (t) async {
    final log = <String>[];
    await t.pumpWidget(card(log), size: (12, 7));
    await t.mouse(MouseKind.down, 3, 3);
    await t.mouse(MouseKind.up, 3, 3);
    expect(log, ['outer down 3,3', 'inner tap', 'outer up 3,3']);
  });

  testTwk('the padding of a Box without a background is not hit, so a tap '
      'there does not reach the detector around it; an opaque one is', (
    t,
  ) async {
    final log = <String>[];
    Widget padded(HitTestBehavior behavior) => GestureDetector(
      behavior: behavior,
      onTap: () => log.add('tap'),
      child: const Box(
        border: Border.all(type: BorderType.rounded),
        padding: EdgeInsets.all(1),
        child: Text('x'),
      ),
    );
    await t.pumpWidget(padded(HitTestBehavior.deferToChild), size: (9, 5));
    // the border, the padding, the text
    for (final (x, y) in [(0, 2), (1, 2), (2, 2)]) {
      await t.mouse(MouseKind.down, x, y);
      await t.mouse(MouseKind.up, x, y);
    }
    expect(log, ['tap', 'tap']);
    log.clear();
    await t.pumpWidget(padded(HitTestBehavior.opaque), size: (9, 5));
    await t.mouse(MouseKind.down, 1, 2);
    await t.mouse(MouseKind.up, 1, 2);
    expect(log, ['tap']);
  });
}
