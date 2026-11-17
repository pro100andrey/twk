// The cursor's color (OSC 12 / OSC 112): written with the cursor, once while
// it is unchanged, and given back to the terminal on every way out.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'support/harness.dart';

String _out(Harness hs) => latin1.decode(hs.presenter.out.view);

const _orange = Color.rgb(0xff, 0x5f, 0x00);
const _set = '\x1b]12;#ff5f00\x1b\\';
const _reset = '\x1b]112\x1b\\';

final class _Fill extends RenderObject {
  _Fill(this.pen);
  final int pen;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxWidth;
    height = c.maxHeight;
  }

  @override
  void paint(PaintContext ctx) => ctx.canvas.fill(0, 0, width, height, pen);
}

void main() {
  Harness shown() {
    final hs = Harness(10, 2);
    hs.presenter
      ..cursorVisible = true
      ..cursorX = 1
      ..cursorY = 0;
    hs.frame();
    return hs;
  }

  test('a color is written once while it stays, again when it changes, '
      'and OSC 112 gives the terminal its own back', () {
    final hs = shown();
    expect(_out(hs), isNot(contains(']12')));
    hs.presenter.cursorColor = _orange;
    hs.frame();
    expect(_out(hs), _set);
    expect(hs.presenter.cursorColorWritten, isTrue);
    // nothing changed: not a byte
    expect(hs.frame(), 0);
    hs.presenter.cursorX = 4;
    hs.frame();
    expect(_out(hs), isNot(contains(']12')));
    hs.presenter.cursorColor = const Color.rgb(1, 2, 3);
    hs.frame();
    expect(_out(hs), '\x1b]12;#010203\x1b\\');
    hs.presenter.cursorColor = null;
    hs.frame();
    expect(_out(hs), _reset);
    expect(hs.frame(), 0);
    expect(hs.vt.errors, isEmpty);
  });

  test('an app that sets no color writes none, and no OSC 112', () {
    final hs = Harness(10, 2);
    hs.presenter
      ..cursorVisible = true
      ..cursorShape = CursorShape.bar;
    hs.canvas.text(0, 0, 'ab', hs.pens[1]);
    hs.frame();
    hs.presenter.cursorVisible = false;
    hs.frame();
    hs.presenter
      ..invalidate()
      ..cursorVisible = true;
    hs.frame();
    expect(_out(hs), isNot(contains(']12')));
    expect(_out(hs), isNot(contains(']112')));
    expect(hs.presenter.cursorColorWritten, isFalse);
  });

  test('the color waits for the cursor to show', () {
    final hs = Harness(10, 2);
    hs.presenter
      ..cursorVisible = false
      ..cursorColor = _orange;
    hs.frame();
    expect(_out(hs), isNot(contains(']12')));
    hs.presenter.cursorVisible = true;
    hs.frame();
    expect(_out(hs), contains(_set));
  });

  test('a palette entry is written as the RGB the core knows for it: '
      "the terminal's own where it told it", () {
    final hs = shown();
    hs.presenter.cursorColor = Color.red;
    hs.frame();
    // xterm's red where the terminal told nothing
    expect(_out(hs), '\x1b]12;#cd0000\x1b\\');
    hs.styles.setPaletteRgb(1, 0x123456);
    hs.presenter.cursorColor = Color.red;
    hs.frame();
    expect(_out(hs), '\x1b]12;#123456\x1b\\');
  });

  test("the terminal's default color is its own cursor color", () {
    final hs = shown();
    hs.presenter.cursorColor = _orange;
    hs.frame();
    hs.presenter.cursorColor = Color.defaultColor;
    hs.frame();
    expect(_out(hs), _reset);
  });

  test('nothing is written where the styles show no colors', () {
    final hs = Harness(10, 2);
    hs.styles.colorMode = ColorMode.none;
    hs.presenter
      ..cursorVisible = true
      ..cursorColor = _orange;
    hs.frame();
    expect(_out(hs), isNot(contains(']12')));
    expect(hs.presenter.cursorColorWritten, isFalse);
  });

  test('after invalidate the color is written again, or given back when '
      'none is wanted any more', () {
    final hs = shown();
    hs.presenter.cursorColor = _orange;
    hs.frame();
    hs.presenter.invalidate();
    hs.frame();
    expect(_out(hs), contains(_set));
    hs.presenter
      ..cursorColor = null
      ..invalidate();
    hs.frame();
    expect(_out(hs), contains(_reset));
  });

  group('the terminal', () {
    late FakeClock clock;
    setUp(() => clock = FakeClock());

    Future<List<String>> run(Color? color, {bool suspend = false}) async {
      final term = HeadlessTerminal(width: 10, height: 2);
      final app = TwkApp(term, clock: clock.clock, environment: const {});
      app.screen.presenter
        ..cursorVisible = true
        ..cursorColor = color;
      final root = _Fill(app.screen.styles.pen(const Pen()));
      final done = clock.run(() => app.run(root, (_) {}));
      await clock.elapse(const Duration(milliseconds: 30));
      if (suspend) {
        final back = Completer<void>();
        final handed = app.suspend(() => back.future);
        await clock.elapse(const Duration(milliseconds: 30));
        final seen = [for (final f in term.frames) latin1.decode(f)];
        back.complete();
        await clock.elapse(const Duration(milliseconds: 30));
        await handed;
        app.quit();
        await clock.elapseUntil(done);
        return seen;
      }
      app.quit();
      await clock.elapseUntil(done);
      return [for (final f in term.frames) latin1.decode(f)];
    }

    test('gives the color back on the way out, after it was written', () async {
      final frames = await run(_orange);
      final all = frames.join();
      expect(all, contains(_set));
      expect(all.lastIndexOf(_reset), greaterThan(all.indexOf(_set)));
    });

    test('writes no OSC 112 when no color was written', () async {
      expect((await run(null)).join(), isNot(contains(']112')));
    });

    test('gives it back when the terminal is handed over', () async {
      final seen = (await run(_orange, suspend: true)).join();
      expect(seen, contains(_reset));
    });
  });
}
