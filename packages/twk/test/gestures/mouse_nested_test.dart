// More regions and Listeners nested than the tracker keeps room for at
// first: each is told in order, in the cell of its own coordinates.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [depth] regions, each a column right of the one around it, with a
/// Listener in the deepest; [log] gets `name what x,y`.
Widget _nest(List<String> log, int depth, [int level = 0]) {
  void Function(PointerEvent) as(String name, String what) =>
      (e) => log.add('$name $what ${e.x},${e.y}');
  if (level == depth) {
    return Listener(
      onDown: as('listener', 'down'),
      onMove: as('listener', 'move'),
      onScroll: as('listener', 'scroll'),
      behavior: HitTestBehavior.opaque,
    );
  }
  final name = 'r$level';
  return Padding(
    padding: const EdgeInsets.only(left: 1),
    child: MouseRegion(
      onEnter: as(name, 'enter'),
      onExit: as(name, 'exit'),
      onHover: as(name, 'hover'),
      child: _nest(log, depth, level + 1),
    ),
  );
}

void main() {
  testTwk('twenty regions nested: entered the outermost first, hovered and '
      'left the deepest first, each in its own cell; the Listener in them '
      'too', (t) async {
    const depth = 20;
    final log = <String>[];
    await t.pumpWidget(_nest(log, depth), size: (40, 3));
    await t.mouse(MouseKind.move, 25, 1);
    expect(log, [
      for (var i = 0; i < depth; i++) 'r$i enter ${25 - 1 - i},1',
      for (var i = depth - 1; i >= 0; i--) 'r$i hover ${25 - 1 - i},1',
      'listener move 5,1',
    ]);
    log.clear();
    await t.mouse(MouseKind.down, 22, 2);
    await t.mouse(MouseKind.up, 22, 2);
    await t.mouse(MouseKind.wheelDown, 30, 0);
    expect(log, [
      'listener down 2,2',
      'listener scroll 10,0',
    ]);
    log.clear();
    await t.mouse(MouseKind.move, 10, 1);
    expect(log, [
      for (var i = depth - 1; i >= 10; i--) 'r$i exit ${10 - 1 - i},1',
      for (var i = 9; i >= 0; i--) 'r$i hover ${10 - 1 - i},1',
    ]);
  });
}
