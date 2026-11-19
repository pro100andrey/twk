// An animated Image in an app run by the tester: it steps on the app's fake
// clock, frame by frame in blocks and with each protocol, and stops.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/image.dart';
import 'package:twk_test/twk_test.dart';

import 'gif_builder.dart';

const red = 0xFFFF0000;
const blue = 0xFF0000FF;

/// A GIF of two solid frames of 10 × 20 pixels, red for 100 ms, blue for
/// 300 ms, playing [loop] more times (null: once).
Uint8List twoFrames({int? loop}) => gifBytes(
  10,
  20,
  const [255, 0, 0, 0, 0, 255],
  [
    GifImage(10, 20, List.filled(200, 0), delayCs: 10),
    GifImage(10, 20, List.filled(200, 1), delayCs: 30),
  ],
  loop: loop,
);

Widget topLeft(Image image) =>
    Align(alignment: Alignment.topLeft, child: image);

int cellColor(int argb) =>
    Color.rgb(argb >> 16 & 0xFF, argb >> 8 & 0xFF, argb & 0xFF).value;

/// The colour the first cell shows, red or blue, as its upper half.
int shownColor(TwkTester t) => t.cell(0, 0).fg;

const ms100 = Duration(milliseconds: 100);

/// What was written to the terminal so far, as text.
String written(TwkTester t) =>
    latin1.decode([for (final f in t.terminal.frames) ...f]);

int count(String s, Pattern p) => p.allMatches(s).length;

void main() {
  group('blocks', () {
    testTwk('the frames show in turn, each for its delay, on the app clock', (
      t,
    ) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 0))),
        duration: Duration.zero,
      );
      expect(shownColor(t), cellColor(red));
      await t.pump(const Duration(milliseconds: 99));
      expect(shownColor(t), cellColor(red), reason: 'at 99 ms');
      await t.pump(const Duration(milliseconds: 1));
      expect(shownColor(t), cellColor(blue), reason: 'at 100 ms');
      await t.pump(const Duration(milliseconds: 299));
      expect(shownColor(t), cellColor(blue), reason: 'at 399 ms');
      await t.pump(const Duration(milliseconds: 1));
      expect(shownColor(t), cellColor(red), reason: 'the second play');
      await t.pump(const Duration(milliseconds: 100));
      expect(shownColor(t), cellColor(blue));
    });

    testTwk('a file that plays once stops on its last frame, and asks for '
        'no more frames', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames())),
        duration: Duration.zero,
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(shownColor(t), cellColor(blue));
      await t.pump(const Duration(seconds: 5));
      expect(shownColor(t), cellColor(blue));
      expect(
        t.clock.pendingTimers,
        0,
        reason: 'nothing left to wait for',
      );
    });

    testTwk('one repeat after the first play is two plays', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 1))),
        duration: Duration.zero,
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(shownColor(t), cellColor(red), reason: 'the second play');
      await t.pump(const Duration(milliseconds: 400));
      expect(shownColor(t), cellColor(blue), reason: 'last frame stays');
      await t.pump(const Duration(seconds: 3));
      expect(shownColor(t), cellColor(blue));
    });

    testTwk('a still image asks for no frames', (t) async {
      await t.pumpWidget(
        topLeft(Image.bitmap(Bitmap(10, 20))),
      );
      expect(t.clock.pendingTimers, 0);
    });

    testTwk('removed from the tree it stops stepping', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 0))),
        duration: Duration.zero,
      );
      expect(t.clock.pendingTimers, 1, reason: 'the next frame');
      await t.pumpWidget(const SizedBox());
      expect(t.clock.pendingTimers, 0, reason: 'cancelled with it');
      await t.pump(const Duration(seconds: 2));
      expect(t.clock.pendingTimers, 0);
    });

    testTwk('the animation starts again from its first frame in a new '
        'image', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 0))),
        duration: Duration.zero,
      );
      await t.pump(ms100);
      expect(shownColor(t), cellColor(blue));
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 0))),
        duration: Duration.zero,
      );
      await t.pump(const Duration(milliseconds: 20));
      expect(shownColor(t), cellColor(red));
      await t.pump(ms100);
      expect(shownColor(t), cellColor(blue));
    });
  });

  testTwk('muted by a TickerMode it stands on the frame it shows, asking '
      'for no frames, and goes on from that frame when unmuted', (t) async {
    final bytes = twoFrames(loop: 0);
    Widget app({required bool enabled}) =>
        TickerMode(enabled: enabled, child: topLeft(Image.memory(bytes)));
    await t.pumpWidget(app(enabled: true), duration: Duration.zero);
    await t.pump(const Duration(milliseconds: 150));
    expect(shownColor(t), cellColor(blue), reason: 'at 150 ms');
    await t.pumpWidget(app(enabled: false), duration: Duration.zero);
    expect(t.clock.pendingTimers, 0, reason: 'no frame callback');
    await t.pump(const Duration(seconds: 3));
    expect(shownColor(t), cellColor(blue), reason: 'it stands');
    await t.pumpWidget(app(enabled: true), duration: Duration.zero);
    // 150 ms of the play were shown: blue for 249 ms more, then red
    await t.pump(const Duration(milliseconds: 249));
    expect(shownColor(t), cellColor(blue));
    await t.pump(const Duration(milliseconds: 1));
    expect(shownColor(t), cellColor(red), reason: 'the next play');
  });

  group('protocols', () {
    testTwk('kitty: the frame sent again on each change, one image shown', (
      t,
    ) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 0))),
        graphics: GraphicsProtocol.kitty,
        duration: Duration.zero,
      );
      int sent() => count(written(t), 'a=T');
      expect(sent(), 1);
      await t.pump(ms100);
      expect(sent(), 2);
      await t.pump(const Duration(milliseconds: 300));
      expect(sent(), 3);
      expect([for (final i in t.vt.images) '$i'], hasLength(1));
    });

    testTwk("kitty that plays kitty's animations: the first frame at once, "
        'the others made in the next frame and sent once, the terminal '
        'plays them, the app then asks for no frames', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 0))),
        graphics: GraphicsProtocol.kitty,
        kittyAnimation: true,
        duration: Duration.zero,
      );
      expect(count(written(t), 'a=T'), 1);
      expect(written(t), contains('a=a,i=1,r=1,z=100,q=2'));
      expect(written(t), contains('a=a,i=1,s=2,q=2'), reason: 'loading');
      expect(written(t), isNot(contains('a=f')));
      await t.pump(const Duration(milliseconds: 17));
      final o = written(t);
      expect(count(o, 'a=T'), 1);
      expect(count(o, 'a=f,'), 1);
      expect(o, contains('a=f,i=1,f=100,t=d,z=300,q=2'));
      expect(o, contains('a=a,i=1,s=3,v=1,q=2'));
      expect(t.vt.kittyFrames, {1: 1});
      expect(t.vt.kittyAnimations, {1: (playing: true, loops: 0)});
      expect(t.clock.pendingTimers, 0, reason: 'no frame callback');
      final before = t.terminal.frames.length;
      await t.pump(const Duration(seconds: 2));
      expect(t.terminal.frames, hasLength(before));
    });

    testTwk('kitty: a GIF that plays once, played as many times by the '
        'terminal', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames())),
        graphics: GraphicsProtocol.kitty,
        kittyAnimation: true,
        duration: Duration.zero,
      );
      await t.pump(const Duration(milliseconds: 17));
      expect(t.vt.kittyAnimations[1], (playing: true, loops: 1));
    });

    testTwk('kitty: muted by a TickerMode, the terminal stops it; unmuted, '
        'runs it again, nothing sent anew', (t) async {
      final bytes = twoFrames(loop: 0);
      Widget app({required bool enabled}) => TickerMode(
        enabled: enabled,
        child: topLeft(Image.memory(bytes)),
      );
      await t.pumpWidget(
        app(enabled: true),
        graphics: GraphicsProtocol.kitty,
        kittyAnimation: true,
        duration: Duration.zero,
      );
      // a frame a 60th of a second after the last, the frames made
      const next = Duration(milliseconds: 17);
      await t.pump(next);
      await t.pumpWidget(app(enabled: false), duration: next);
      expect(written(t), contains('a=a,i=1,s=1,q=2'));
      expect(t.vt.kittyAnimations[1]!.playing, isFalse);
      await t.pumpWidget(app(enabled: true), duration: next);
      expect(t.vt.kittyAnimations[1]!.playing, isTrue);
      expect(count(written(t), 'a=T'), 1);
      expect(count(written(t), 'a=f,'), 1);
    });

    /// A GIF of [n] frames of 2 x 2 pixels, red and blue in turn, 100 ms
    /// each, for ever.
    Uint8List manyFrames(int n) => gifBytes(
      2,
      2,
      const [255, 0, 0, 0, 0, 255],
      [
        for (var i = 0; i < n; i++)
          GifImage(2, 2, List.filled(4, i % 2), delayCs: 10),
      ],
      loop: 0,
    );

    testTwk('kitty: a long animation made a frame or more at a time, each '
        'sent once, while the terminal plays what it has', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(manyFrames(30), width: 4, height: 2)),
        graphics: GraphicsProtocol.kitty,
        kittyAnimation: true,
        duration: Duration.zero,
      );
      expect(t.vt.kittyAnimations[1], (playing: true, loops: 0));
      var frames = 0;
      for (var i = 0; i < 30 && frames < 29; i++) {
        await t.pump(const Duration(milliseconds: 17));
        final now = t.vt.kittyFrames[1] ?? 0;
        expect(now, greaterThan(frames), reason: 'a frame at least each time');
        frames = now;
      }
      expect(frames, 29);
      expect(count(written(t), 'a=f,'), 29);
      expect(count(written(t), 'a=T'), 1);
      expect(written(t), contains('a=a,i=1,s=3,v=1,q=2'));
      expect(t.clock.pendingTimers, 0, reason: 'no frame asked for after');
    });

    testTwk('kitty: muted while it is made, it asks for no frames; unmuted, '
        'the rest are made', (t) async {
      final bytes = manyFrames(30);
      Widget app({required bool enabled}) => TickerMode(
        enabled: enabled,
        child: topLeft(Image.memory(bytes, width: 4, height: 2)),
      );
      await t.pumpWidget(
        app(enabled: true),
        graphics: GraphicsProtocol.kitty,
        kittyAnimation: true,
        duration: Duration.zero,
      );
      const next = Duration(milliseconds: 17);
      await t.pumpWidget(app(enabled: false), duration: next);
      expect(t.clock.pendingTimers, 0);
      final made = t.vt.kittyFrames[1] ?? 0;
      await t.pump(const Duration(seconds: 1));
      expect(t.vt.kittyFrames[1] ?? 0, made);
      await t.pumpWidget(app(enabled: true), duration: next);
      for (var i = 0; i < 30 && (t.vt.kittyFrames[1] ?? 0) < 29; i++) {
        await t.pump(next);
      }
      expect(t.vt.kittyFrames[1], 29);
      expect(t.vt.kittyAnimations[1], (playing: true, loops: 0));
    });

    testTwk('kitty: an animation larger than the terminal keeps is drawn '
        'frame by frame', (t) async {
      // 50 frames of 80 x 24 cells of 10 x 20 pixels: 77 MB decoded
      await t.pumpWidget(
        Image.memory(manyFrames(50), width: 80, height: 24),
        graphics: GraphicsProtocol.kitty,
        kittyAnimation: true,
        duration: Duration.zero,
      );
      await t.pump(ms100);
      expect(written(t), isNot(contains('a=f')));
      expect(count(written(t), 'a=T'), 2);
    });

    testTwk('sixel: the frame sent again on each change', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 0))),
        duration: Duration.zero,
        graphics: GraphicsProtocol.sixel,
      );
      int sent() => count(written(t), '\x1bP');
      expect(sent(), 1);
      await t.pump(ms100);
      expect(sent(), 2);
      await t.pump(const Duration(milliseconds: 300));
      expect(sent(), 3);
    });

    testTwk('iTerm2: the frame sent again on each change', (t) async {
      await t.pumpWidget(
        topLeft(Image.memory(twoFrames(loop: 0))),
        duration: Duration.zero,
        graphics: GraphicsProtocol.iterm2,
      );
      int sent() => count(written(t), '\x1b]1337;File=');
      expect(sent(), 1);
      await t.pump(ms100);
      expect(sent(), 2);
      await t.pump(const Duration(milliseconds: 300));
      expect(sent(), 3);
    });
  });

  testTwk('a GIF that does not decode is an error shown in its place', (
    t,
  ) async {
    final bad = Uint8List.fromList('GIF89a'.codeUnits);
    await t.pumpWidget(topLeft(Image.memory(bad)));
    expect(t.lines.first, contains('GIF header cut short'));
    expect(t.takeErrors(), hasLength(1));
  });
}
