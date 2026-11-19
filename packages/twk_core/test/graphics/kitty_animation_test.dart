// kitty's animation (TerminalCaps.kittyAnimation): an animated image is sent
// once with its frames, the terminal plays it, and `playing` stops it and
// runs it again; without the capability the first frame alone is shown.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/byte_sink.dart';
import 'package:twk_core/src/graphics.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/terminal/sequences.dart';

import '../support/harness.dart';

/// Bytes standing for a frame's PNG file, [n] of them from [seed].
Uint8List frame(int n, int seed) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 7 + seed) & 0xFF]);

/// A kitty image of three frames in 4 x 2 cells of 10 x 20 pixels: 100 ms,
/// 200 ms and 300 ms, played [loops] times.
TerminalImage animated({int loops = 0, int bytes = 60}) => TerminalImage(
  GraphicsProtocol.kitty,
  frame(bytes, 0),
  pixelWidth: 40,
  pixelHeight: 40,
  animation: ImageAnimation(
    [frame(bytes, 1), frame(bytes, 2)],
    const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 200),
      Duration(milliseconds: 300),
    ],
    loops: loops,
  ),
);

Harness harness({bool kittyAnimation = true}) => Harness(
  20,
  8,
  caps: TerminalCaps(
    graphics: GraphicsProtocol.kitty,
    kittyAnimation: kittyAnimation,
  ),
);

String out(Harness hs) => latin1.decode(hs.presenter.out.view);

int count(String s, String p) => p.allMatches(s).length;

void main() {
  test('sent once: the first frame placed, the others added with their '
      'times, the first its time, then run for ever', () {
    final hs = harness();
    final img = animated();
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    final o = out(hs);
    expect(count(o, 'a=T,'), 1);
    expect(o, contains('a=f,i=1,f=100,t=d,z=200,q=2;'));
    expect(o, contains('a=f,i=1,f=100,t=d,z=300,q=2;'));
    expect(o, contains('\x1b_Ga=a,i=1,r=1,z=100,q=2\x1b\\'));
    expect(o, endsWith('\x1b_Ga=a,i=1,s=3,v=1,q=2\x1b\\\x1b[?2026l'));
    expect(o.indexOf('a=T,'), lessThan(o.indexOf('a=f,')));
    expect(o.indexOf('r=1,'), lessThan(o.indexOf('s=3')));
    expect(hs.vt.kittyFrames, {1: 2});
    expect(hs.vt.kittyAnimations, {1: (playing: true, loops: 0)});
    expect(hs.mismatches(), isEmpty);

    // painted again, or moved: the frames are not sent again
    hs.canvas.image(2, 1, 4, 2, img);
    expect(hs.frame(), 0);
    hs.canvas.image(9, 4, 4, 2, img);
    hs.frame();
    expect(out(hs), contains('a=p,i=1,'));
    expect(out(hs), isNot(contains('a=f')));
    expect(out(hs), isNot(contains('a=a')));
    expect(hs.vt.kittyFrames, {1: 2});
  });

  test('played a number of times: v is one more', () {
    final hs = harness();
    hs.canvas.image(0, 0, 4, 2, animated(loops: 2));
    hs.frame();
    expect(out(hs), contains('a=a,i=1,s=3,v=3,q=2'));
    expect(hs.vt.kittyAnimations[1], (playing: true, loops: 2));
  });

  test('playing false stops it where it is, true runs it again, each '
      'written once', () {
    final hs = harness();
    final img = animated();
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    img.playing = false;
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    expect(out(hs), contains('\x1b_Ga=a,i=1,s=1,q=2\x1b\\'));
    expect(out(hs), isNot(contains('a=f')));
    expect(hs.vt.kittyAnimations[1]!.playing, isFalse);
    hs.canvas.image(2, 1, 4, 2, img);
    expect(hs.frame(), 0, reason: 'nothing changed');
    img.playing = true;
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    expect(out(hs), contains('\x1b_Ga=a,i=1,s=3,v=1,q=2\x1b\\'));
    expect(hs.vt.kittyAnimations[1]!.playing, isTrue);
    expect(hs.mismatches(), isEmpty);
  });

  test('sent stopped, it shows its first frame and is not run', () {
    final hs = harness();
    final img = animated()..playing = false;
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    expect(out(hs), contains('a=a,i=1,r=1,'));
    expect(out(hs), isNot(contains('s=3')));
    expect(hs.vt.kittyAnimations[1]!.playing, isFalse);
  });

  test('gone, it is deleted with its frames; a forgotten screen gets it '
      'again, frames and all', () {
    final hs = harness();
    final img = animated();
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    hs.presenter.invalidate();
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    expect(count(out(hs), 'a=T,'), 1);
    expect(count(out(hs), 'a=f,'), 2);
    expect(out(hs), contains('s=3'));
    hs.canvas.fill(0, 0, 20, 8, hs.pens[1]);
    hs.frame();
    expect(out(hs), contains('a=d,d=I,i=1,q=2'));
    expect(hs.vt.kittyImages, isEmpty);
    expect(hs.vt.kittyFrames, isEmpty);
    expect(hs.vt.kittyAnimations, isEmpty);
    expect(hs.mismatches(), isEmpty);
  });

  test('a terminal that plays none gets the first frame alone', () {
    final hs = harness(kittyAnimation: false);
    final img = animated();
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    expect(count(out(hs), 'a=T,'), 1);
    expect(out(hs), isNot(contains('a=f')));
    expect(out(hs), isNot(contains('a=a')));
    img.playing = false;
    hs.canvas.image(2, 1, 4, 2, img);
    expect(hs.frame(), 0);
    expect(hs.mismatches(), isEmpty);
  });

  test('big frames go in chunks, the keys on the first', () {
    final hs = harness();
    hs.canvas.image(0, 0, 4, 2, animated(bytes: 10000));
    hs.frame();
    final o = out(hs);
    expect(o, contains('a=f,i=1,f=100,t=d,z=200,q=2,m=1;'));
    expect(hs.vt.kittyFrames, {1: 2});
    expect(hs.mismatches(), isEmpty);
  });

  test('through tmux, wrapped', () {
    final b = ByteSink();
    kittyAnimate(
      b,
      animated().animation!,
      id: 3,
      playing: true,
      multiplexer: Multiplexer.tmux,
    );
    final o = latin1.decode(b.view);
    expect(count(o, '\x1bPtmux;\x1b\x1b_G'), 4);
    expect(
      o,
      contains('\x1bPtmux;\x1b\x1b_Ga=a,i=3,s=3,v=1,q=2\x1b\x1b\\\x1b\\'),
    );
  });

  test('a delay under a millisecond is a gap of 1', () {
    final b = ByteSink();
    kittyAnimate(
      b,
      ImageAnimation(
        [frame(4, 1)],
        const [Duration.zero, Duration(microseconds: 10)],
      ),
      id: 1,
      playing: false,
    );
    final o = latin1.decode(b.view);
    expect(o, contains('a=f,i=1,f=100,t=d,z=1,q=2;'));
    expect(o, contains('a=a,i=1,r=1,z=1,q=2'));
  });
}
