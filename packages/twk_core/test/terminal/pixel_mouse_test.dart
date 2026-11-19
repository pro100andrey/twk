// The pixel mouse (SGR-Pixels, mode 1016): the input parser dividing a
// report's pixels into the cell and the offset in it, the sequences that
// switch it, and what the probe finds: the mode answered, a cell's size
// from the terminal, the tty or the text area.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

const _on = '\x1b[?1016;1\$y';
const _off = '\x1b[?1016;0\$y';
const _cellSize = '\x1b[6;20;10t';
const _da1 = '\x1b[?62;22c';

late FakeClock clock;

Future<Terminal> open(
  FakeLink link,
  String answers, {
  TerminalOptions options = const TerminalOptions(
    probeTimeout: Duration(seconds: 5),
  ),
}) {
  link.type('$answers$_da1');
  return clock.open(link, options);
}

void main() {
  setUp(() => clock = FakeClock());

  group('the parser', () {
    InputParser pixels() => InputParser()
      ..pixelMouse = true
      ..cellPixelWidth = 10
      ..cellPixelHeight = 20;

    test('divides pixels into the cell and the offset in it', () {
      // pixel (95, 45), 1-based 96;46: column 9, row 2, 5 and 5 into it
      expect(pixels().feed('\x1b[<0;96;46M'.codeUnits), [
        const MouseEvent(MouseKind.down, 9, 2, offsetX: 5, offsetY: 5),
      ]);
      // the cell's first and last pixel
      expect(pixels().feed('\x1b[<0;1;1m\x1b[<35;10;20M'.codeUnits), [
        const MouseEvent(MouseKind.up, 0, 0, offsetX: 0, offsetY: 0),
        const MouseEvent(MouseKind.move, 0, 0, offsetX: 9, offsetY: 19),
      ]);
      // the kind, button and modifiers are decoded as in cells
      expect(pixels().feed('\x1b[<68;105;41M'.codeUnits), [
        const MouseEvent(
          MouseKind.wheelUp,
          10,
          2,
          modifiers: Mod.shift,
          offsetX: 4,
          offsetY: 0,
        ),
      ]);
    });

    test('takes the numbers for cells while no cell size is known', () {
      final p = InputParser()..pixelMouse = true;
      expect(p.feed('\x1b[<0;96;46M'.codeUnits), [
        const MouseEvent(MouseKind.down, 95, 45),
      ]);
    });

    test('a parser not told of pixels gives cells and no offsets', () {
      final p = InputParser()
        ..cellPixelWidth = 10
        ..cellPixelHeight = 20;
      final e = p.feed('\x1b[<0;96;46M'.codeUnits).single as MouseEvent;
      expect((e.x, e.y, e.offsetX, e.offsetY), (95, 45, null, null));
    });

    test('an in-band resize with the window pixels sets the cell size', () {
      final p = InputParser()..pixelMouse = true;
      expect(p.feed('\x1b[48;24;80;480;800t'.codeUnits), [
        const ResizeEvent(80, 24),
      ]);
      expect((p.cellPixelWidth, p.cellPixelHeight), (10, 20));
      expect(p.feed('\x1b[<0;11;21M'.codeUnits), [
        const MouseEvent(MouseKind.down, 1, 1, offsetX: 0, offsetY: 0),
      ]);
      // without pixels it leaves the size as it was
      p.feed('\x1b[48;24;80;0;0t'.codeUnits);
      expect((p.cellPixelWidth, p.cellPixelHeight), (10, 20));
    });

    test('events with and without offsets differ', () {
      expect(
        const MouseEvent(MouseKind.down, 1, 1),
        isNot(const MouseEvent(MouseKind.down, 1, 1, offsetX: 0, offsetY: 0)),
      );
      expect(
        const MouseEvent(
          MouseKind.down,
          1,
          1,
          offsetX: 3,
          offsetY: 4,
        ).toString(),
        'Mouse(down 1,1 b0 m0 +3,+4)',
      );
    });
  });

  test('the sequences switch 1016 with the SGR coordinates', () {
    const off = MouseTracking.off;
    expect(
      mouseTrackingSequence(off, MouseTracking.drags, pixels: true),
      '\x1b[?1002h\x1b[?1006h\x1b[?1016h',
    );
    expect(
      mouseTrackingSequence(MouseTracking.drags, off, pixels: true),
      '\x1b[?1002l\x1b[?1016l\x1b[?1006l',
    );
    // between two modes it stays on
    expect(
      mouseTrackingSequence(
        MouseTracking.drags,
        MouseTracking.motion,
        pixels: true,
      ),
      '\x1b[?1002l\x1b[?1003h',
    );
  });

  group('the probe', () {
    test('asks for the mode and the text area, and turns it on with the '
        'mouse when it is answered and a cell size is known', () async {
      final link = FakeLink();
      final term = await open(link, '$_on$_cellSize');
      expect(link.text, contains('\x1b[?1016\$p'));
      expect(link.text, contains('\x1b[14t'));
      expect(term.info.pixelMouse, isTrue);
      expect(link.text, contains('\x1b[?1002h\x1b[?1006h\x1b[?1016h'));
      // a report in pixels arrives as a cell and an offset
      final events = <InputEvent>[];
      term.events.listen(events.add);
      link.type('\x1b[<0;96;46M');
      await clock.flushMicrotasks();
      expect(events, [
        const MouseEvent(MouseKind.down, 9, 2, offsetX: 5, offsetY: 5),
      ]);
      await clock.runUntil(term.close);
      expect(link.text, contains('\x1b[?1016l\x1b[?1006l'));
    });

    test('is not on where the terminal does not answer for the mode', () async {
      final link = FakeLink();
      final term = await open(link, '$_off$_cellSize');
      expect(term.info.pixelMouse, isFalse);
      final silent = FakeLink();
      final other = await open(silent, _cellSize);
      expect(other.info.pixelMouse, isFalse);
      expect(silent.text, isNot(contains('1016h')));
      await clock.runUntil(term.close);
      await clock.runUntil(other.close);
    });

    test('is not on where the cell size is not known, or the options say '
        'no', () async {
      final unknown = FakeLink();
      final a = await open(unknown, _on);
      expect(a.info.pixelMouse, isFalse);
      expect(a.info.caps.cellPixelWidth, 0);
      final refused = FakeLink();
      final b = await open(
        refused,
        '$_on$_cellSize',
        options: const TerminalOptions(
          probeTimeout: Duration(seconds: 5),
          pixelMouse: false,
        ),
      );
      expect(b.info.pixelMouse, isFalse);
      expect(refused.text, isNot(contains('1016h')));
      await clock.runUntil(a.close);
      await clock.runUntil(b.close);
    });

    test("the tty's pixels stand in for CSI 16 t", () async {
      final link = FakeLink()..cellPixelSize = (width: 8, height: 16);
      final term = await open(link, _on);
      expect(term.info.pixelMouse, isTrue);
      expect(
        (term.info.caps.cellPixelWidth, term.info.caps.cellPixelHeight),
        (8, 16),
      );
      await clock.runUntil(term.close);
      // the terminal's own answer comes first
      final both = FakeLink()..cellPixelSize = (width: 8, height: 16);
      final b = await open(both, '$_on$_cellSize');
      expect(b.info.caps.cellPixelWidth, 10);
      await clock.runUntil(b.close);
    });

    test('the text area (CSI 14 t) over the size in cells is the last '
        'resort', () async {
      // 20 columns by 4 lines
      final link = FakeLink();
      final term = await open(link, '$_on\x1b[4;80;200t');
      expect(
        (term.info.caps.cellPixelWidth, term.info.caps.cellPixelHeight),
        (10, 20),
      );
      expect(term.info.pixelMouse, isTrue);
      await clock.runUntil(term.close);
    });

    test('a resize reads the tty again for the cell size', () async {
      final link = FakeLink()..cellPixelSize = (width: 10, height: 20);
      final term = await open(link, _on);
      final events = <InputEvent>[];
      term.events.listen(events.add);
      link
        ..cellPixelSize = (width: 20, height: 40)
        ..resize(30, 6);
      await clock.flushMicrotasks();
      link.type('\x1b[<0;41;81M');
      await clock.flushMicrotasks();
      expect(events, [
        const ResizeEvent(30, 6),
        const MouseEvent(MouseKind.down, 2, 2, offsetX: 0, offsetY: 0),
      ]);
      await clock.runUntil(term.close);
    });

    group("a link that cannot tell the tty's pixels", () {
      Future<(Terminal, FakeLink, List<InputEvent>)> start(
        String answers,
      ) async {
        final link = FakeLink();
        final term = await open(link, answers);
        final events = <InputEvent>[];
        term.events.listen(events.add);
        return (term, link, events);
      }

      test('asks again at a resize and divides by the answer', () async {
        final (term, link, events) = await start('$_on$_cellSize');
        final before = link.text.length;
        link.resize(30, 6);
        await clock.flushMicrotasks();
        expect(link.text.substring(before), contains('\x1b[16t'));
        // until the answer comes the old size stands
        link.type('\x1b[<0;41;81M');
        await clock.flushMicrotasks();
        // the font was zoomed: a cell is 20x40 now
        link.type('\x1b[6;40;20t\x1b[4;120;300t');
        await clock.flushMicrotasks();
        link.type('\x1b[<0;41;81M');
        await clock.flushMicrotasks();
        expect(events, [
          const ResizeEvent(30, 6),
          const MouseEvent(MouseKind.down, 4, 4, offsetX: 0, offsetY: 0),
          const MouseEvent(MouseKind.down, 2, 2, offsetX: 0, offsetY: 0),
        ]);
        await clock.runUntil(term.close);
      });

      test('two re-asks before an answer are both answered, none of it '
          'delivered as input', () async {
        final (term, link, events) = await start('$_on$_cellSize');
        link.resize(30, 6);
        await clock.flushMicrotasks();
        link.resize(31, 6);
        await clock.flushMicrotasks();
        link
          ..type('\x1b[6;40;20t\x1b[4;120;300t')
          ..type('\x1b[6;40;20t\x1b[4;120;300t');
        await clock.flushMicrotasks();
        link.type('\x1b[<0;41;81M');
        await clock.flushMicrotasks();
        expect(events, [
          const ResizeEvent(30, 6),
          const ResizeEvent(31, 6),
          const MouseEvent(MouseKind.down, 2, 2, offsetX: 0, offsetY: 0),
        ]);
        await clock.runUntil(term.close);
      });

      test('cellPixels is the live size, which a re-ask changes and the '
          "probe's caps do not", () async {
        final (term, link, _) = await start('$_on$_cellSize');
        expect(term.cellPixels, (10, 20));
        link.resize(30, 6);
        await clock.flushMicrotasks();
        link.type('\x1b[6;40;20t\x1b[4;120;300t');
        await clock.flushMicrotasks();
        expect(term.cellPixels, (20, 40));
        expect(term.info.caps.cellPixelWidth, 10);
        await clock.runUntil(term.close);
      });

      test('takes the text area over the cells where CSI 16 t is not '
          'answered', () async {
        final (term, link, events) = await start('$_on$_cellSize');
        link.resize(30, 6);
        await clock.flushMicrotasks();
        // 240 x 600 pixels over 30 x 6 cells: 20 x 40
        link.type('\x1b[4;240;600t');
        await clock.flushMicrotasks();
        link.type('\x1b[<0;41;81M');
        await clock.flushMicrotasks();
        expect(
          events.last,
          const MouseEvent(MouseKind.down, 2, 2, offsetX: 0, offsetY: 0),
        );
        await clock.runUntil(term.close);
      });

      test('a terminal that answers one of the two does not leave the other '
          "owing: a later round's answer is taken", () async {
        final (term, link, events) = await start('$_on$_cellSize');
        // round 1: only CSI 16 t is answered (a cell is 20 x 40)
        link.resize(30, 6);
        await clock.flushMicrotasks();
        link.type('\x1b[6;40;20t');
        await clock.flushMicrotasks();
        // round 2: only CSI 14 t (240 x 600 over 30 x 6 cells: 8 x 100)
        link.resize(30, 6);
        await clock.flushMicrotasks();
        link.type('\x1b[4;600;240t');
        await clock.flushMicrotasks();
        link.type('\x1b[<0;41;101M');
        await clock.flushMicrotasks();
        expect(
          events.last,
          const MouseEvent(
            MouseKind.down,
            5,
            1,
            offsetX: 0,
            offsetY: 0,
          ),
        );
        await clock.runUntil(term.close);
      });

      test('is not asked at a resize where the pixel mouse is off', () async {
        final link = FakeLink();
        final term = await open(
          link,
          '$_on$_cellSize',
          options: const TerminalOptions(
            probeTimeout: Duration(seconds: 5),
            pixelMouse: false,
          ),
        );
        final before = link.text.length;
        link.resize(30, 6);
        await clock.flushMicrotasks();
        expect(link.text.substring(before), isNot(contains('16t')));
        await clock.runUntil(term.close);
      });
    });
  });
}
