// Mouse reports switched while a terminal is open: the modes that switch
// them, and a HeadlessTerminal writing them. A Terminal is in
// socket_test.dart, over a shell spoken by hand.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  test('switching turns the mode of the old reports off and that of the new '
      'on; SGR coordinates come with the first and go with the last', () {
    const off = MouseTracking.off;
    const buttons = MouseTracking.buttons;
    const drags = MouseTracking.drags;
    const motion = MouseTracking.motion;
    expect(
      [
        for (final (from, to) in [
          (off, buttons),
          (off, drags),
          (off, motion),
          (buttons, drags),
          (motion, buttons),
          (drags, off),
          (motion, off),
          (drags, drags),
          (off, off),
        ])
          mouseTrackingSequence(from, to),
      ],
      [
        '\x1b[?1000h\x1b[?1006h',
        '\x1b[?1002h\x1b[?1006h',
        '\x1b[?1003h\x1b[?1006h',
        '\x1b[?1000l\x1b[?1002h',
        '\x1b[?1003l\x1b[?1000h',
        '\x1b[?1002l\x1b[?1006l',
        '\x1b[?1003l\x1b[?1006l',
        '',
        '',
      ],
    );
  });

  test('a HeadlessTerminal starts with no reports, whatever its options say, '
      'and writes each switch to its frames; none in the inline mode or once '
      'closed', () async {
    final term = HeadlessTerminal(
      options: const TerminalOptions(mouseMotion: true),
    );
    expect(term.mouseTracking, MouseTracking.off);
    expect(term.frames, isEmpty);
    term
      ..mouseTracking = MouseTracking.drags
      ..mouseTracking = MouseTracking.drags
      ..mouseTracking = MouseTracking.motion
      ..mouseTracking = MouseTracking.off;
    expect(
      [for (final f in term.frames) latin1.decode(f)],
      [
        '\x1b[?1002h\x1b[?1006h',
        '\x1b[?1002l\x1b[?1003h',
        '\x1b[?1003l\x1b[?1006l',
      ],
    );
    term.mouseTracking = MouseTracking.buttons;
    await term.close();
    term.mouseTracking = MouseTracking.off;
    expect(term.mouseTracking, MouseTracking.buttons);
    expect(term.frames, hasLength(4));

    final inline = HeadlessTerminal(
      options: const TerminalOptions(alternateScreen: false),
    )..mouseTracking = MouseTracking.motion;
    expect(inline.mouseTracking, MouseTracking.off);
    expect(inline.frames, isEmpty);
    await inline.close();
  });
}
