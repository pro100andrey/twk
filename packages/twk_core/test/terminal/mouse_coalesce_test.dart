// Mouse motion coalesced within one read of a Terminal over an in-memory
// link: of a run of motions with no button held and the same modifiers
// only the last is delivered; presses, releases, wheel steps, every point
// of a drag, the other events and their order are kept, and motions of
// separate reads are each delivered.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

/// What the terminal answers to the probe: synchronized output, then DA1.
const _answers = '\x1b[?2026;2\$y\x1b[?62;22c';

/// An SGR report of [cb] at column [x], row [y] (from 0); a release with
/// [up].
String _sgr(int cb, int x, int y, {bool up = false}) =>
    '\x1b[<$cb;${x + 1};${y + 1}${up ? 'm' : 'M'}';

String _move(int x, int y, {int cb = 35}) => _sgr(cb, x, y);

/// What the reads deliver, up to the key `z` each ends with, the `z`s
/// left out; on a clock of the test's, what the link is given comes in
/// as it flushes.
Future<List<InputEvent>> _read(List<String> reads) async {
  final clock = FakeClock();
  final link = FakeLink(columns: 40, lines: 10)..type(_answers);
  final term = await clock.open(
    link,
    const TerminalOptions(probeTimeout: Duration(seconds: 5)),
  );
  final events = <InputEvent>[];
  final sub = term.events.listen(events.add);
  const z = KeyEvent(KeyCode.char, char: 'z');
  for (final read in reads) {
    link.type('${read}z');
  }
  await clock.flushMicrotasks();
  expect(events.where((e) => e == z), hasLength(reads.length));
  await sub.cancel();
  await clock.runUntil(term.close);
  return [
    for (final e in events)
      if (e != z) e,
  ];
}

MouseEvent _m(MouseKind kind, int x, int y, {int button = 0, int mods = 0}) =>
    MouseEvent(kind, x, y, button: button, modifiers: mods);

void main() {
  test('a sweep of motions in one read comes as its last', () async {
    final sweep = [for (var x = 0; x < 30; x++) _move(x, x % 7)].join();
    expect(await _read([sweep]), [_m(MouseKind.move, 29, 1)]);
  });

  test('motions of separate reads each come', () async {
    expect(await _read([_move(1, 1), _move(2, 1), _move(3, 1)]), [
      _m(MouseKind.move, 1, 1),
      _m(MouseKind.move, 2, 1),
      _m(MouseKind.move, 3, 1),
    ]);
  });

  test('motions with other modifiers are not merged: the last of each run '
      'comes, in order', () async {
    // 35 + 4: Shift; 35 + 16: Ctrl
    final read = [
      _move(1, 0),
      _move(2, 0),
      _move(3, 0, cb: 39),
      _move(4, 0, cb: 39),
      _move(5, 0, cb: 51),
      _move(6, 0),
      _move(7, 0),
    ].join();
    expect(await _read([read]), [
      _m(MouseKind.move, 2, 0),
      _m(MouseKind.move, 4, 0, mods: Mod.shift),
      _m(MouseKind.move, 5, 0, mods: Mod.ctrl),
      _m(MouseKind.move, 7, 0),
    ]);
  });

  test('presses, releases, wheel steps and every point of a drag are kept, '
      'and the motions on either side of them', () async {
    final read = [
      _move(1, 2),
      _move(2, 2),
      _sgr(0, 2, 2), // left down
      _sgr(32, 3, 2), // drags
      _sgr(32, 4, 2),
      _sgr(32, 5, 3),
      _sgr(0, 5, 3, up: true),
      _move(6, 3),
      _sgr(64, 6, 3), // wheel up, twice
      _sgr(64, 6, 3),
      _move(7, 3),
      _sgr(65, 7, 3), // wheel down
      _move(8, 3),
      _move(9, 4),
      _sgr(2, 9, 4), // right down, dragged, released
      _sgr(34, 9, 5),
      _sgr(2, 9, 5, up: true),
    ].join();
    expect(await _read([read]), [
      _m(MouseKind.move, 2, 2),
      _m(MouseKind.down, 2, 2),
      _m(MouseKind.drag, 3, 2),
      _m(MouseKind.drag, 4, 2),
      _m(MouseKind.drag, 5, 3),
      _m(MouseKind.up, 5, 3),
      _m(MouseKind.move, 6, 3),
      _m(MouseKind.wheelUp, 6, 3),
      _m(MouseKind.wheelUp, 6, 3),
      _m(MouseKind.move, 7, 3),
      _m(MouseKind.wheelDown, 7, 3),
      _m(MouseKind.move, 9, 4),
      _m(MouseKind.down, 9, 4, button: 2),
      _m(MouseKind.drag, 9, 5, button: 2),
      _m(MouseKind.up, 9, 5, button: 2),
    ]);
  });

  test('a key, a paste or a focus change between motions keeps the motion '
      'before it', () async {
    final read = [
      _move(1, 0),
      _move(2, 0),
      'a',
      _move(3, 0),
      _move(4, 0),
      '\x1b[200~hi\x1b[201~',
      _move(5, 0),
      '\x1b[O',
      _move(6, 0),
      _move(7, 0),
    ].join();
    expect(await _read([read]), [
      _m(MouseKind.move, 2, 0),
      const KeyEvent(KeyCode.char, char: 'a'),
      _m(MouseKind.move, 4, 0),
      const PasteEvent('hi'),
      _m(MouseKind.move, 5, 0),
      const FocusEvent(false),
      _m(MouseKind.move, 7, 0),
    ]);
  });
}
