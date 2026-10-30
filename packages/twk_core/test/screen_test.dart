import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

void main() {
  test('resizing away and back between frames rewrites the screen', () {
    final screen = Screen(20, 2);
    final vt = Vt(20, 2);
    final pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    void paint(String text) {
      screen.canvas
        ..fill(0, 0, screen.width, screen.height, pen)
        ..text(0, 0, text, pen);
      final bytes = screen.render();
      if (bytes != null) {
        vt.feed(bytes);
      }
    }

    String row(int y) => [
      for (var x = 0; x < vt.width; x++) vt.cell(x, y).text,
    ].join().trimRight();

    paint('abcdefghijklmnop');
    // the terminal is resized twice before the next frame; meanwhile it
    // cut or reflowed what it showed
    screen.resize(9, 2);
    vt.resize(9, 2);
    screen.resize(20, 2);
    vt.resize(20, 2);
    paint('abcdefghijklmnopXY');
    expect([row(0), row(1)], ['abcdefghijklmnopXY', '']);
  });

  test('an inline screen writes committed rows above its region with the '
      'next render', () {
    final screen = Screen(12, 1, inline: true)..presenter.screenHeight = 4;
    final vt = Vt(
      12,
      4,
      scrollback: true,
      allowLineFeed: true,
      relativeOnly: true,
    );
    final pen = screen.styles.pen(const Pen());
    screen.canvas.text(0, 0, 'live', pen);
    vt.feed(screen.render()!);
    final rows = Surface(12, 3);
    Canvas(rows, screen.styles, screen.glyphs)
      ..text(0, 0, 'zero', pen)
      ..text(0, 1, 'one', pen)
      ..text(0, 2, 'two', pen);
    screen.commit(rows, 1);
    vt.feed(screen.render()!);
    expect(vt.lines, ['one', 'two', 'live', '']);
    expect(screen.render(), isNull);
  });

  test('with asserts, the bytes of a frame kept past the next read as '
      'garbage, not as that frame', () {
    final screen = Screen(10, 1);
    final pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    screen.canvas.text(0, 0, 'first', pen);
    final first = screen.render()!;
    expect(String.fromCharCodes(first), contains('first'));
    screen.canvas.text(0, 0, 'second', pen);
    final second = screen.render()!;
    expect(String.fromCharCodes(second), contains('second'));
    var asserts = false;
    assert(asserts = true, 'asserts on');
    if (asserts) {
      expect(first.every((b) => b == 0x3F), isTrue);
    }
  });

  test('an empty screen renders with a visible cursor', () {
    for (final (w, h) in [(0, 0), (0, 5), (5, 0)]) {
      final screen = Screen(w, h);
      screen.presenter
        ..cursorVisible = true
        ..cursorX = 2
        ..cursorY = 2;
      expect(screen.render, returnsNormally, reason: '${w}x$h');
    }
  });

  test('sweeps its styles once twice as many are in use as after the last '
      'sweep, past the floor, its screen as it was', () {
    final floor = Screen.sweepFloor;
    addTearDown(() => Screen.sweepFloor = floor);
    Screen.sweepFloor = 8;
    final screen = Screen(4, 1);
    final vt = Vt(4, 1);
    var colors = 0;
    // a frame of four cells in colors never seen before
    void frame() {
      for (var x = 0; x < 4; x++) {
        final style = screen.styles.style(bg: Color.rgb(0, 0, ++colors));
        screen.canvas.runStyled(x, 0, screen.canvas.shape(' '), style);
      }
      vt.feed(screen.render() ?? const []);
    }

    frame();
    expect(screen.styles.sweeps, 0, reason: '5 in use, the floor 8: not yet');
    frame();
    expect(screen.styles.sweeps, 1, reason: '9 in use');
    // what the screen and the terminal show, the same 4, and style 0
    expect(screen.styles.live, 5);
    for (var f = 0; f < 50; f++) {
      frame();
    }
    expect(screen.styles.length, lessThan(32));
    for (var x = 0; x < 4; x++) {
      expect(vt.cell(x, 0).bg, 0x1000000 | colors - 3 + x);
    }
  });
}
