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
