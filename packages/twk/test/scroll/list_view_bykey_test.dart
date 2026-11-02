// The keyed items a ListView takes to their new indexes when the list is
// rearranged: each keeps its State (and so its identity) and the list shows
// them in the new order, whatever the walk over the live items that finds
// them by key.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'list_view_test.dart' show Tally;

void main() {
  testTwk('a rearranged keyed list keeps every item that stays, in the new '
      'order, and builds only those that are new', (t) async {
    final log = <String>[];
    final keys = [for (var i = 0; i < 6; i++) 'k$i'];
    Widget view() => ListView.builder(
      itemCount: keys.length,
      itemBuilder: (_, i) => Tally(keys[i], log, key: ValueKey(keys[i])),
    );
    await t.pumpWidget(view(), size: (20, 6));
    expect(t.lines, keys);
    expect(log, [for (final k in keys) '+$k']);
    log.clear();

    // reversed: every item moves
    keys.setAll(0, keys.reversed.toList());
    await t.pumpWidget(view());
    expect(t.lines, ['k5', 'k4', 'k3', 'k2', 'k1', 'k0']);
    expect(log, isEmpty);

    // rotated, one scrolled out (kept) and one new among them
    keys
      ..removeAt(2)
      ..add(keys.removeAt(0))
      ..insert(1, 'new');
    await t.pumpWidget(view());
    expect(t.lines, ['k4', 'new', 'k2', 'k1', 'k0', 'k5']);
    expect(log, ['+new']);
    log.clear();

    // swapped ends: the keys of the first and the last trade places
    final first = keys.first;
    keys
      ..[0] = keys.last
      ..[keys.length - 1] = first;
    await t.pumpWidget(view());
    expect(t.lines, ['k5', 'new', 'k2', 'k1', 'k0', 'k4']);
    expect(log, isEmpty);
  });

  testTwk('an item of no key does not take the place of a keyed one that '
      'moved', (t) async {
    final log = <String>[];
    final keys = <String?>['a', null, 'b', null, 'c'];
    Widget view() => ListView.builder(
      itemCount: keys.length,
      itemBuilder: (_, i) => Tally(
        keys[i] ?? 'n$i',
        log,
        key: keys[i] == null ? null : ValueKey(keys[i]),
      ),
    );
    await t.pumpWidget(view(), size: (20, 5));
    expect(log, ['+a', '+n1', '+b', '+n3', '+c']);
    log.clear();
    keys.setAll(0, ['c', null, 'a', null, 'b']);
    await t.pumpWidget(view());
    expect(t.lines, ['c', 'n1', 'a', 'n3', 'b']);
    expect(log, isEmpty);
  });
}
