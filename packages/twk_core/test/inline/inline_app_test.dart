// The inline mode end to end in the emulator: an app in a region of the
// normal screen below the history, which the emulator guards (a write to
// it, or an absolute row, fails the frame).
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;
import 'package:twk_test/vt_terminal.dart';

/// Lines of text, one per row, asking for as many rows as there are;
/// with [tag], that text right-aligned on each, which only a frame laid out
/// at the width puts whole (of a row too wide, a terminal without autowrap
/// shows the last character, written over the last column).
final class Lines extends RenderObject {
  Lines(this.pen, this._lines);
  final int pen;
  List<String> _lines;
  String? tag;

  /// What asking for the max intrinsic height throws, if anything.
  Error? sizeError;

  void show(List<String> lines) {
    _lines = lines;
    markNeedsLayout();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  int computeMaxIntrinsicHeight(int width) {
    final e = sizeError;
    if (e != null) {
      throw e;
    }
    return _lines.length;
  }

  @override
  void paint(PaintContext ctx) {
    ctx.canvas.fill(0, 0, width, height, pen);
    for (var i = 0; i < _lines.length; i++) {
      ctx.canvas.text(0, i, _lines[i], pen);
      if (tag case final tag?) {
        ctx.canvas.text(width - tag.length, i, tag, pen);
      }
    }
  }
}

/// A row saying `fine` to commit, or what throws when asked for its
/// height, laid out or painted.
final class Fails extends RenderObject {
  Fails(this.pen, {this.sizeError, this.layoutError, this.paintError});
  final int pen;
  final Error? sizeError;
  final Error? layoutError;
  final Error? paintError;

  @override
  int computeMaxIntrinsicHeight(int width) {
    if (sizeError case final e?) {
      throw e;
    }
    return 1;
  }

  @override
  void performLayout(BoxConstraints c) {
    if (layoutError case final e?) {
      throw e;
    }
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    if (paintError case final e?) {
      throw e;
    }
    ctx.canvas.text(0, 0, 'fine', pen);
  }
}

void main() {
  const history = [r'$ ls', 'a  b  c', r'$ app'];

  // The apps run on a clock of the test's: their frames are spaced by it
  // and run as it moves on ([pass]). A frame a resize asks for is asked
  // for once the terminal's ResizeEvent arrives, after a wait on the wall
  // clock had begun: on a loaded machine that wait could end first.
  late FakeClock clock;
  late VtTerminal term;
  late TwkApp app;
  late Lines root;
  late Future<void> done;

  setUp(() => clock = FakeClock());

  /// Moves the clock on by [ms]: the frames due by then run.
  Future<void> pass([int ms = 30]) => clock.elapse(Duration(milliseconds: ms));

  Future<void> start(
    List<String> lines, {
    int width = 20,
    int height = 8,
    List<String> history = history,
    bool atLineStart = true,
    int? maxRows,
    bool clear = false,
    void Function(InputEvent e)? onEvent,
    Error? sizeError,
    void Function(RenderObject, RenderPhase, Object, StackTrace)? onError,
  }) async {
    term = VtTerminal(
      width: width,
      height: height,
      history: history,
      atLineStart: atLineStart,
    );
    app = TwkApp(
      term,
      maxFps: 1000,
      maxInlineRows: maxRows,
      clearInlineOnExit: clear,
      clock: clock.stopwatch,
      environment: const {},
    );
    app.owner.onError = onError;
    root = Lines(app.screen.styles.pen(const Pen()), lines)
      ..sizeError = sizeError;
    done = clock.run(() => app.run(root, onEvent ?? (_) {}));
    await pass();
  }

  Future<void> stop() async {
    app.quit();
    await clock.elapseUntil(done);
  }

  test('the region starts on the line below the history', () async {
    await start(['one', 'two']);
    expect(term.lines, [...history, 'one', 'two', '', '', '']);
    expect(app.screen.height, 2);
    await stop();
  });

  test('on exit the region stays and the cursor is on the line below '
      'it', () async {
    await start(['one', 'two']);
    await stop();
    expect(term.lines, [...history, 'one', 'two', '', '', '']);
    expect((term.vt.cx, term.vt.cy), (0, 5));
    expect(term.vt.cursorVisible, isFalse, reason: 'the backend shows it');
    expect(term.closed, isTrue);
  });

  test('with clearInlineOnExit the region is erased and the cursor is '
      'where it began', () async {
    await start(['one', 'two'], clear: true);
    await stop();
    expect(term.lines, [...history, '', '', '', '', '']);
    expect((term.vt.cx, term.vt.cy), (0, 3));
  });

  test('the region grows with its content and pushes the history into '
      'the scrollback', () async {
    await start(['1'], height: 6);
    for (var n = 2; n <= 5; n++) {
      root.show([for (var i = 1; i <= n; i++) '$i']);
      await pass();
      expect(app.screen.height, n);
    }
    expect(term.lines, [...history, '1', '2', '3', '4', '5']);
    expect(term.vt.history, hasLength(2));
    await stop();
    expect(term.lines, [...history, '1', '2', '3', '4', '5', '']);
  });

  test("the cursor's row in the region finds the region on the screen, "
      'as it grows into the scrollback and after text on the cursor '
      'line', () async {
    /// The row of the screen the region begins on, by the cursor's.
    int top() => term.vt.cy - app.screen.presenter.cursorRow;
    await start(['1'], height: 6);
    expect(top(), 3);
    for (var n = 2; n <= 5; n++) {
      root.show([for (var i = 1; i <= n; i++) '$i']);
      await pass();
      // the lines of the scrollback first
      final row = term.lines.indexOf('1') - term.vt.history.length;
      expect(top(), row, reason: '$n rows');
    }
    expect(top(), 1, reason: 'the history scrolled up');
    await stop();

    await start(['one'], history: [r'$ printf abc', 'abc'], atLineStart: false);
    expect(top(), 2);
    await stop();
  });

  test('the region grows to maxInlineRows at most', () async {
    await start(['1', '2', '3', '4', '5'], maxRows: 3);
    expect(app.screen.height, 3);
    expect(term.lines, [...history, '1', '2', '3', '', '']);
    await stop();
  });

  test('the region shrinks only when asked, erasing the rows it '
      'leaves', () async {
    await start(['1', '2', '3', '4']);
    root.show(['1', '2']);
    await pass();
    expect(app.screen.height, 4);
    expect(term.lines, [...history, '1', '2', '', '', '']);
    app.shrinkRegion();
    await pass();
    expect(app.screen.height, 2);
    await stop();
    expect((term.vt.cx, term.vt.cy), (0, 5));
  });

  test('after text on the cursor line the region starts on the next '
      'line', () async {
    await start(['one'], history: [r'$ printf abc', 'abc'], atLineStart: false);
    expect(term.lines.take(3), [r'$ printf abc', 'abc', 'one']);
    await stop();
  });

  test('a resize repaints the region at the new width; the history '
      'stays', () async {
    // The terminal cuts its rows itself (no reflow): only a frame laid
    // out at the new width ends each row in the tag.
    String tagged(String line, int width) =>
        '${line.padRight(width - 3).substring(0, width - 3)}[x]';
    await start(['first line here', 'second']);
    root
      ..tag = '[x]'
      ..show(['first line here', 'second']);
    await pass();
    expect(term.lines, [
      ...history,
      tagged('first line here', 20),
      tagged('second', 20),
      '',
      '',
      '',
    ]);
    term.resize(10, 8);
    await pass();
    expect(term.lines, [...history, 'first l[x]', 'second [x]', '', '', '']);
    // the cursor's row is cut off: the screen scrolls the history up
    term.resize(30, 4, pull: true);
    await pass();
    expect(term.lines, [
      ...history,
      tagged('first line here', 30),
      tagged('second', 30),
    ]);
    expect(term.vt.history, hasLength(1));
    term.resize(30, 2);
    await pass();
    expect(app.screen.height, 2);
    expect(term.lines.skip(3), [
      tagged('first line here', 30),
      tagged('second', 30),
    ]);
    await stop();
  });

  group('an error while sizing the region', () {
    final errors = <(RenderObject, RenderPhase, Object)>[];
    void onError(RenderObject o, RenderPhase phase, Object e, StackTrace _) =>
        errors.add((o, phase, e));
    setUp(errors.clear);

    test('goes to onError as an error of the root in layout, once while '
        'it is the same; the region keeps its height and the frame goes '
        'on', () async {
      await start(['one', 'two'], onError: onError);
      final error = StateError('no height');
      root
        ..sizeError = error
        ..show(['1', '2', '3']);
      await pass();
      expect(errors, [(root, RenderPhase.layout, error)]);
      expect(app.screen.height, 2);
      expect(term.lines, [...history, '1', '2', '', '', '']);
      root.show(['a', 'b', 'c']);
      await pass();
      expect(errors, hasLength(1));
      expect(term.lines, [...history, 'a', 'b', '', '', '']);
      root
        ..sizeError = null
        ..show(['1', '2', '3']);
      await pass();
      expect(app.screen.height, 3);
      root
        ..sizeError = StateError('no height')
        ..show(['x']);
      await pass();
      expect(errors, hasLength(2), reason: 'sized without an error since');
      await stop();
    });

    test('on the first frame leaves the region at 1 row', () async {
      final error = StateError('no height');
      await start(['one', 'two'], sizeError: error, onError: onError);
      expect(errors, [(root, RenderPhase.layout, error)]);
      expect(app.screen.height, 1);
      expect(term.lines, [...history, 'one', '', '', '', '']);
      await stop();
    });

    test('keeps a shrink asked for until the region is sized', () async {
      await start(['1', '2', '3'], onError: onError);
      root
        ..sizeError = StateError('no height')
        ..show(['1']);
      app.shrinkRegion();
      await pass();
      expect(app.screen.height, 3);
      root
        ..sizeError = null
        ..show(['1']);
      await pass();
      expect(app.screen.height, 1);
      await stop();
    });

    test("leaves the region within the terminal's height", () async {
      await start(['1', '2', '3'], onError: onError);
      root
        ..sizeError = StateError('no height')
        ..show(['1', '2', '3']);
      term.resize(20, 2);
      await pass();
      expect(errors, hasLength(1));
      expect(app.screen.height, 2);
      await stop();
    });

    test('without onError ends run()', () async {
      await start(['one']);
      root
        ..sizeError = StateError('no height')
        ..show(['1', '2']);
      await expectLater(clock.elapseUntil(done), throwsStateError);
    });
  });

  group('commit', () {
    /// Text spans as a paragraph to commit.
    RenderParagraph text(List<(String, Pen)> spans) => RenderParagraph(spans);
    const plain = Pen();

    test('puts content above the region as lines of the history, wrapped '
        'at the width, styles and wide glyphs intact', () async {
      await start(['live 1', 'live 2'], height: 10);
      const bold = Pen(fg: Color.rgb(90, 200, 255), attrs: Attr.bold);
      app
        ..commit(text([('done ', plain), ('你好', bold)]))
        ..commit(text([('a line long enough to wrap at twenty', plain)]));
      await pass();
      expect(term.lines, [
        ...history,
        'done 你好',
        'a line long enough',
        'to wrap at twenty',
        'live 1',
        'live 2',
        '',
        '',
      ]);
      final wide = term.vt.cell(5, 3);
      expect((wide.text, wide.role, wide.attrs & Attr.bold), ('你', 2, 1));
      expect(term.vt.cell(4, 3).attrs, 0);
      root.show(['live 3']);
      await pass();
      expect(term.lines.skip(3).take(4), [
        'done 你好',
        'a line long enough',
        'to wrap at twenty',
        'live 3',
      ]);
      await stop();
    });

    test('of a burst of 10,000 lines leaves input handled meanwhile and '
        'writes every line in order', () async {
      const n = 10000;
      var writtenAtKey = -1;
      int written() => term.lines.where((l) => l.startsWith('line ')).length;
      await start(
        ['live'],
        onEvent: (e) {
          if (e is KeyEvent && writtenAtKey < 0) {
            writtenAtKey = written();
          }
        },
      );
      for (var i = 0; i < n; i++) {
        app.commit(text([('line $i', plain)]));
      }
      // a key typed once the first of them are on the screen
      for (var t = 0; t < 1000 && written() == 0; t++) {
        await pass(1);
      }
      term.type('x');
      for (var t = 0; t < 500 && written() < n; t++) {
        await pass(10);
      }
      expect(writtenAtKey, inInclusiveRange(1, n - 1));
      expect(term.lines, [
        ...history,
        for (var i = 0; i < n; i++) 'line $i',
        'live',
      ]);
      expect(term.frames.length, greaterThan(n ~/ 1000));
      await stop();
    });

    test('before run is written by the first frame', () async {
      term = VtTerminal(width: 20, height: 8, history: history);
      app = TwkApp(
        term,
        maxFps: 1000,
        clock: clock.stopwatch,
        environment: const {},
      );
      root = Lines(app.screen.styles.pen(const Pen()), ['live']);
      app.commit(text([('early', plain)]));
      await pass();
      expect(term.frames, isEmpty);
      done = clock.run(() => app.run(root, (_) {}));
      await pass();
      expect(term.lines.take(5), [...history, 'early', 'live']);
      await stop();
    });

    test('waiting when the app quits is written before the region is '
        'left', () async {
      await start(['live']);
      for (var i = 0; i < 1000; i++) {
        app.commit(text([('line $i', plain)]));
      }
      await stop();
      expect(term.lines, [
        ...history,
        for (var i = 0; i < 1000; i++) 'line $i',
        'live',
        '',
      ]);
      expect((term.vt.cx, term.vt.cy), (0, 7));
    });

    test('needs the inline mode', () {
      final app = TwkApp(HeadlessTerminal(), environment: const {});
      expect(() => app.commit(text([('x', plain)])), throwsStateError);
    });

    group('that throws', () {
      final errors = <(RenderObject, RenderPhase, Object)>[];
      void onError(RenderObject o, RenderPhase phase, Object e, StackTrace _) =>
          errors.add((o, phase, e));
      setUp(errors.clear);

      test('goes to onError as an error of the commit, in the phase it threw '
          'in, and an error block at the width goes in its place; the region '
          'and later commits go on', () async {
        await start(['live'], height: 12, onError: onError);
        final pen = app.screen.styles.pen(const Pen());
        final sized = Fails(pen, sizeError: StateError('no height'));
        final inner = Fails(pen, layoutError: StateError('no layout'));
        final laidOut = RenderBox(pen: pen, child: inner);
        final painted = Fails(
          pen,
          paintError: StateError('nothing to paint here'),
        );
        app
          ..commit(sized)
          ..commit(laidOut)
          ..commit(painted)
          ..commit(Fails(pen));
        root.show(['live 2']);
        await pass();
        expect(errors, [
          (sized, RenderPhase.layout, sized.sizeError),
          (laidOut, RenderPhase.layout, inner.layoutError),
          (painted, RenderPhase.paint, painted.paintError),
        ]);
        expect(term.lines, [
          ...history,
          'Bad state: no height',
          'Bad state: no layout',
          'Bad state: nothing',
          'to paint here',
          'fine',
          'live 2',
          '',
          '',
          '',
        ]);
        for (final y in [3, 4, 5, 6]) {
          for (var x = 0; x < 20; x++) {
            expect(term.vt.cell(x, y).bg, Color.red.value, reason: '($x, $y)');
          }
        }
        expect(term.vt.cell(10, 7).bg, 0);
        expect(term.vt.errors, isEmpty);
        expect([sized.owner, laidOut.owner, painted.owner], [null, null, null]);
        await stop();
      });

      test('without onError ends run()', () async {
        for (final fails in <Fails Function(int pen)>[
          (pen) => Fails(pen, sizeError: StateError('no height')),
          (pen) => Fails(pen, layoutError: StateError('no layout')),
          (pen) => Fails(pen, paintError: StateError('no paint')),
        ]) {
          await start(['live']);
          app.commit(fails(app.screen.styles.pen(const Pen())));
          await expectLater(clock.elapseUntil(done), throwsStateError);
          expect(term.closed, isTrue);
        }
      });
    });
  });
}
