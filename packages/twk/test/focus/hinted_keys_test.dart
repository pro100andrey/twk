// HintedKeys, which twk's scroll views and fields put above their Focus:
// what its takes says of each key, however many keys it hints, is what
// the key path lists, a change to any of them told.
import 'package:test/test.dart';
import 'package:twk/src/focus/hinted_keys.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('a change to what is taken of any key is told, past the 64th '
      'too', (t) async {
    final names = [
      for (final mod in ['', 'ctrl+', 'alt+'])
        for (var c = 0x61; c <= 0x7A; c++) '$mod${String.fromCharCode(c)}',
    ];
    expect(names.length, greaterThan(70));
    final taken = names.toSet();
    final changes = ValueNotifier(0);
    final node = FocusNode(debugLabel: 'field');
    addTearDown(node.dispose);
    await t.pumpWidget(
      HintedKeys(
        node: node,
        hints: {for (final name in names) name: 'does $name'},
        takes: taken.contains,
        changes: changes,
        child: Focus(focusNode: node, autofocus: true, child: const Text('')),
      ),
    );
    final manager = t.binding.focusManager;
    List<KeyCombo> hinted() => [
      for (final key in manager.activeKeys)
        if (key.hint != null) key.combo,
    ];
    expect(hinted(), hasLength(names.length));
    var told = 0;
    void count() => told++;
    manager.keysChanged.addListener(count);
    addTearDown(() => manager.keysChanged.removeListener(count));
    for (final i in [3, 66, names.length - 1]) {
      taken.remove(names[i]);
      changes.value++;
      await t.pump();
      expect(told, 1, reason: names[i]);
      told = 0;
      expect(hinted(), isNot(contains(KeyCombo.parse(names[i]))));
    }
  });
}
