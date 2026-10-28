// The emulator takes what an app passes through tmux or GNU screen: a DCS
// ends at ST alone, and ESC ESC in it is one ESC, as tmux's passthrough
// doubles every ESC; one it does not double there is an error.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart'
    show Multiplexer, NotificationProtocol, clipboardSequence, notifySequence;
import 'package:twk_test/vt.dart';

/// The top row of a fresh emulator fed [s], at once or byte by byte.
String shown(String s, {bool byByte = false}) {
  final vt = Vt(10, 2);
  final bytes = utf8.encode(s);
  if (byByte) {
    for (final b in bytes) {
      vt.feed([b]);
    }
  } else {
    vt.feed(bytes);
  }
  expect(vt.errors, isEmpty, reason: 'what the emulator rejected');
  return vt.dump().split('\n').first.trimRight();
}

void main() {
  test('OSC 52 and notifications wrapped for each multiplexer: nothing '
      'shown, nothing rejected', () {
    for (final m in Multiplexer.values) {
      final copy = clipboardSequence('x' * 400, multiplexer: m);
      expect(shown('a${copy}b'), 'ab', reason: m.name);
      expect(shown('a${copy}b', byByte: true), 'ab', reason: m.name);
      final note = notifySequence(
        'Build',
        'done',
        protocol: NotificationProtocol.osc99,
        multiplexer: m,
      );
      expect(shown('a${note}b'), 'ab', reason: m.name);
    }
  });

  test('a DCS goes on past BEL and ESC ESC, up to ST', () {
    expect(shown('a\x1bP\x1b]52;c;eA==\x07\x1b\\b'), 'ab');
    expect(shown('a\x1bPtmux;\x1b\x1b]2;t\x1b\x1b\\\x1b\\b'), 'ab');
    expect(shown('a\x1b_G\x07x\x1b\\b'), 'ab', reason: 'APC as DCS');
  });

  test('an ESC tmux passthrough does not double: an error', () {
    final vt = Vt(10, 2, strict: false)
      ..feed(utf8.encode('\x1bPtmux;\x1b]52;c;eA==\x07\x1b\\'));
    expect(vt.errors, ['an ESC not doubled in tmux passthrough']);
  });
}
