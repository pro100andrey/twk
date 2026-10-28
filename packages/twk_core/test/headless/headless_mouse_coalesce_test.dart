// Mouse motion coalesced within one input() of a HeadlessTerminal, by the
// rule a Terminal applies to a read: of a run of motions with no button
// held and the same modifiers only the last is delivered; presses,
// releases, wheel steps, every point of a drag, keys and their order are
// kept, and motions of separate inputs are each delivered.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// An SGR report of [cb] at column [x], row [y] (from 0); a release with
/// [up].
String _sgr(int cb, int x, int y, {bool up = false}) =>
    '\x1b[<$cb;${x + 1};${y + 1}${up ? 'm' : 'M'}';

String _move(int x, int y, {int cb = 35}) => _sgr(cb, x, y);

MouseEvent _m(MouseKind kind, int x, int y, {int button = 0, int mods = 0}) =>
    MouseEvent(kind, x, y, button: button, modifiers: mods);

/// What [inputs], each one input() call, are delivered as.
Future<List<InputEvent>> _read(List<String> inputs) async {
  final term = HeadlessTerminal(width: 40, height: 10);
  final got = <InputEvent>[];
  final sub = term.events.listen(got.add);
  for (final bytes in inputs) {
    term.input(utf8.encode(bytes));
  }
  await pumpEventQueue();
  await sub.cancel();
  return got;
}

void main() {
  test('a flood of motions in one input comes as its last', () async {
    final sweep = [for (var x = 0; x < 30; x++) _move(x, x % 7)].join();
    expect(await _read([sweep]), [_m(MouseKind.move, 29, 1)]);
  });

  test('motions of separate inputs each come', () async {
    expect(await _read([_move(1, 1), _move(2, 1), _move(3, 1)]), [
      _m(MouseKind.move, 1, 1),
      _m(MouseKind.move, 2, 1),
      _m(MouseKind.move, 3, 1),
    ]);
  });

  test('motions with other modifiers are not merged', () async {
    final read = [
      _move(1, 0),
      _move(2, 0),
      _move(3, 0, cb: 39), // Shift
      _move(4, 0, cb: 39),
      _move(5, 0),
    ].join();
    expect(await _read([read]), [
      _m(MouseKind.move, 2, 0),
      _m(MouseKind.move, 4, 0, mods: Mod.shift),
      _m(MouseKind.move, 5, 0),
    ]);
  });

  test('every point of a drag, presses, releases, wheel steps and keys are '
      'kept, in order', () async {
    final read = [
      _move(1, 2),
      _move(2, 2),
      _sgr(0, 2, 2), // left down
      _sgr(32, 3, 2), // drags
      _sgr(32, 4, 2),
      _sgr(32, 5, 3),
      _sgr(0, 5, 3, up: true),
      _move(6, 3),
      _move(7, 3),
      _sgr(64, 7, 3), // wheel up, twice
      _sgr(64, 7, 3),
      _move(8, 3),
      'a',
      _move(9, 3),
      _move(9, 4),
    ].join();
    expect(await _read([read]), [
      _m(MouseKind.move, 2, 2),
      _m(MouseKind.down, 2, 2),
      _m(MouseKind.drag, 3, 2),
      _m(MouseKind.drag, 4, 2),
      _m(MouseKind.drag, 5, 3),
      _m(MouseKind.up, 5, 3),
      _m(MouseKind.move, 7, 3),
      _m(MouseKind.wheelUp, 7, 3),
      _m(MouseKind.wheelUp, 7, 3),
      _m(MouseKind.move, 8, 3),
      const KeyEvent(KeyCode.char, char: 'a'),
      _m(MouseKind.move, 9, 4),
    ]);
  });
}
