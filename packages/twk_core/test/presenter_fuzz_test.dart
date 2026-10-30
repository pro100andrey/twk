// Property tests: after every frame, an independent terminal emulator fed
// with the presenter's bytes must show exactly what the surface asks for —
// on *every* cell, not just the damaged ones (so a missed damage span is a
// failure too).
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/src/canvas.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/surface.dart';
import 'package:twk_core/src/unicode/unicode.dart';

import 'support/harness.dart';

void runFuzz(
  String name, {
  required int seeds,
  int frames = 25,
  TerminalCaps caps = const TerminalCaps(),
  bool vtBce = true,
  bool vtKonsoleLines = false,
  TextSegmenter? Function()? vtSegmenter,
  bool ignoreUncertain = false,
  void Function(Presenter p)? tune,
  bool sweep = false,
}) {
  test(name, () {
    var totalFrames = 0;
    var shifted = 0;
    var multiScroll = 0;
    var rectScroll = 0;
    var widened = 0;
    for (var seed = 0; seed < seeds; seed++) {
      final rnd = Random(seed);
      var w = 1 + rnd.nextInt(30);
      var h = 1 + rnd.nextInt(10);
      final hs = Harness(
        w,
        h,
        caps: caps,
        vtBce: vtBce,
        vtKonsoleLines: vtKonsoleLines,
        vtSegmenter: vtSegmenter?.call(),
        strict: !ignoreUncertain,
      );
      tune?.call(hs.presenter);
      for (var f = 0; f < frames; f++) {
        if (rnd.nextInt(20) == 0) {
          w = 1 + rnd.nextInt(30);
          h = 1 + rnd.nextInt(10);
          hs.resize(w, h);
        }
        final ops = rnd.nextInt(8);
        for (var k = 0; k < ops; k++) {
          randomOp(hs, rnd);
        }
        if (sweep) {
          // cells in styles and of clusters never seen before, as a video
          // in a terminal view paints them: their ids are those the sweeps
          // freed
          for (var k = rnd.nextInt(6); k > 0; k--) {
            final style = hs.styles.style(
              fg: Color.rgb(rnd.nextInt(256), rnd.nextInt(256), 0),
              bg: Color.rgb(0, rnd.nextInt(256), rnd.nextInt(256)),
              attrs: rnd.nextBool() ? Attr.bold : 0,
            );
            hs.canvas.runStyled(
              rnd.nextInt(w),
              rnd.nextInt(h),
              hs.canvas.shape(
                [for (var n = 1 + rnd.nextInt(4); n > 0; n--) freshCluster(rnd)]
                    .join(),
              ),
              style,
            );
          }
        }
        if (rnd.nextInt(4) == 0) {
          // text-field cursor: visibility, position and shape
          hs.presenter
            ..cursorVisible = rnd.nextBool()
            ..cursorX = rnd.nextInt(w + 2) - 1
            ..cursorY = rnd.nextInt(h + 2) - 1
            ..cursorShape =
                CursorShape.values[rnd.nextInt(CursorShape.values.length)];
        }
        hs.frame();
        if (sweep) {
          sweepHarness(hs);
        }
        shifted += hs.presenter.stats.shiftedRows;
        if (hs.presenter.stats.scrollOps >= 2) {
          multiScroll++;
        }
        rectScroll += hs.presenter.stats.rectScrollOps;
        widened += hs.presenter.stats.widenedScrollOps;
        final p = hs.presenter;
        expect(
          hs.vt.cursorVisible,
          p.cursorVisible,
          reason: 'cursor visibility (seed $seed f $f)',
        );
        if (p.cursorVisible) {
          final sw = hs.surface.width;
          final sh = hs.surface.height;
          expect(
            (hs.vt.cx, hs.vt.cy),
            (p.cursorX.clamp(0, sw - 1), p.cursorY.clamp(0, sh - 1)),
            reason: 'cursor position (seed $seed f $f)',
          );
          expect(
            hs.vt.cursorShape,
            p.cursorShape.code,
            reason: 'cursor shape (seed $seed f $f)',
          );
        }
        final bad = hs.mismatches(ignoreUncertain: ignoreUncertain);
        if (bad.isNotEmpty) {
          fail(
            'seed $seed frame $f (${hs.surface.width}x${hs.surface.height}): '
            '${bad.join('; ')}\n--- terminal ---\n${hs.vt.dump()}',
          );
        }
        expect(hs.vt.syncDepth, 0, reason: 'unbalanced synchronized update');
        expect(hs.vt.printWraps, 0, reason: 'printing caused a wrap/scroll');
        // nothing changed -> not a single byte
        expect(
          hs.frame(),
          0,
          reason: 'idle frame wrote bytes (seed $seed f $f)',
        );
        totalFrames++;
      }
    }
    expect(totalFrames, seeds * frames);
    if (caps.insertDelete) {
      expect(shifted, greaterThan(0), reason: 'ICH/DCH path never exercised');
    }
    if (caps.hardwareScroll && caps.synchronizedOutput) {
      expect(
        multiScroll,
        greaterThan(0),
        reason: 'multi-block scroll path never exercised',
      );
    }
    if (caps.leftRightMargins) {
      expect(
        rectScroll,
        greaterThan(0),
        reason: 'DECSLRM path never exercised',
      );
    } else {
      expect(rectScroll, 0);
    }
    if (caps.hardwareScroll && !caps.leftRightMargins) {
      // a rectangle the terminal has no margins for: whole rows
      expect(
        widened,
        greaterThan(0),
        reason: 'rectangle scroll as whole rows never exercised',
      );
    }
    // Coverage counters: show that each fast path actually ran.
    // ignore: avoid_print
    print(
      '$name: $shifted rows shifted with ICH/DCH, '
      '$multiScroll frames with 2+ hardware scrolls, '
      '$rectScroll rectangle scrolls, '
      '$widened rectangle scrolls as whole rows',
    );
  });
}

/// The inline mode: the surface is a region of a normal screen below lines
/// printed before it. Besides every check of [runFuzz]: the history never
/// changes (the emulator guards it and rejects absolute rows), the screen
/// below the region stays blank, the region grows and shrinks, the
/// terminal is resized keeping what it shows (rows cut or padded, the
/// cursor on its line, the screen scrolling or taking lines back from the
/// scrollback), and rows committed to the history (sometimes more than the
/// screen holds, sometimes with the screen height unknown) stay as they
/// were written, above the region, in order.
void runInlineFuzz(
  String name, {
  required int seeds,
  int frames = 25,
  TerminalCaps caps = const TerminalCaps(),
  bool vtBce = true,
  bool sweep = false,
}) {
  test(name, () {
    var scrolls = 0;
    var widened = 0;
    var grown = 0;
    var committed = 0;
    for (var seed = 0; seed < seeds; seed++) {
      final rnd = Random(seed);
      var w = 1 + rnd.nextInt(30);
      var screenH = 1 + rnd.nextInt(10);
      final history = [
        for (var i = 0, n = rnd.nextInt(14); i < n; i++)
          'h$i ${samples[rnd.nextInt(2)]}', // narrow text
      ].map((l) => l.substring(0, min(l.length, w))).toList();
      final hs = Harness.inline(
        w,
        1 + rnd.nextInt(screenH),
        screenHeight: screenH,
        history: history,
        atLineStart: rnd.nextInt(4) != 0,
        caps: caps,
        vtBce: vtBce,
      );
      for (var f = 0; f < frames; f++) {
        if (rnd.nextInt(20) == 0) {
          w = 1 + rnd.nextInt(30);
          screenH = 1 + rnd.nextInt(10);
          hs.resizeTerminal(w, screenH, pull: rnd.nextBool());
        }
        if (rnd.nextInt(6) == 0) {
          final before = hs.surface.height;
          hs.resizeRegion(1 + rnd.nextInt(screenH));
          if (hs.surface.height > before) {
            grown++;
          }
        }
        final h = hs.surface.height;
        final ops = rnd.nextInt(8);
        for (var k = 0; k < ops; k++) {
          randomOp(hs, rnd);
        }
        if (rnd.nextInt(4) == 0) {
          hs.presenter
            ..cursorVisible = rnd.nextBool()
            ..cursorX = rnd.nextInt(w + 2) - 1
            ..cursorY = rnd.nextInt(h + 2) - 1
            ..cursorShape =
                CursorShape.values[rnd.nextInt(CursorShape.values.length)];
        }
        if (rnd.nextInt(5) == 0) {
          commitRandomRows(
            hs,
            rnd,
            rnd.nextBool() ? 3 : 2 * screenH + 2,
            fresh: sweep,
          );
        }
        if (sweep) {
          // between the commit and the frame that writes it: the rows
          // committed are the presenter's to keep
          sweepHarness(hs);
        }
        hs.presenter.screenHeight = rnd.nextInt(4) == 0 ? 0 : screenH;
        hs.frame();
        scrolls += hs.presenter.stats.scrollOps;
        widened += hs.presenter.stats.widenedScrollOps;
        committed += hs.presenter.stats.committedRows;
        final p = hs.presenter;
        final where = 'seed $seed f $f (${w}x$h on ${w}x$screenH)';
        expect(hs.top, greaterThanOrEqualTo(0), reason: where);
        expect(hs.vt.cursorVisible, p.cursorVisible, reason: where);
        if (p.cursorVisible) {
          expect(
            (hs.vt.cx, hs.vt.cy),
            (p.cursorX.clamp(0, w - 1), hs.top + p.cursorY.clamp(0, h - 1)),
            reason: 'cursor position ($where)',
          );
        }
        final bad = [
          ...hs.mismatches(),
          ...hs.historyChanges(),
          ...hs.committedMismatches(),
          ...hs.notBlankBelow().take(3),
        ];
        if (bad.isNotEmpty) {
          fail(
            '$where: ${bad.join('; ')}\n--- terminal ---\n'
            '${hs.vt.lines.join('\n')}',
          );
        }
        expect(hs.vt.syncDepth, 0, reason: 'unbalanced synchronized update');
        expect(hs.vt.printWraps, 0, reason: 'printing caused a wrap/scroll');
        expect(hs.frame(), 0, reason: 'idle frame wrote bytes ($where)');
      }
    }
    expect(grown, greaterThan(0), reason: 'the region never grew');
    expect(committed, greaterThan(0), reason: 'no row was committed');
    if (caps.hardwareScroll) {
      expect(scrolls, greaterThan(0), reason: 'IL/DL scrolls never ran');
      expect(
        widened,
        greaterThan(0),
        reason: 'rectangle scroll as whole rows never ran',
      );
    }
    // Coverage counters: show that each path actually ran.
    // ignore: avoid_print
    print(
      '$name: $scrolls IL/DL scrolls ($widened of rectangles), '
      '$grown growths, $committed rows committed',
    );
  });
}

/// A cluster of a letter and two combining marks, of 4096 there are.
String freshCluster(Random rnd) =>
    'a${String.fromCharCode(0x300 + rnd.nextInt(64))}'
    '${String.fromCharCode(0x340 + rnd.nextInt(64))}';

/// Sweeps [hs]'s styles and glyphs as a screen does, its surface and its
/// presenter the roots, and the rows the harness keeps of the history.
void sweepHarness(Harness hs) {
  void none(int _) {}
  void roots(void Function(int) glyph, void Function(int) style) {
    hs.surface.markCells(glyph, style);
    hs.presenter.markCells(glyph, style);
    hs.markCommitted(glyph, style);
  }

  hs.styles.sweep((mark) => roots(none, mark));
  hs.glyphs.sweep((mark) => roots(mark, none));
}

/// Commits 1 to [most] random rows, some of them wider or narrower than
/// the region, sometimes only part of what was drawn; with [fresh], some
/// cells in styles never seen before.
void commitRandomRows(Harness hs, Random rnd, int most, {bool fresh = false}) {
  final w = hs.surface.width;
  final n = 1 + rnd.nextInt(most);
  final rows = Surface(rnd.nextInt(4) == 0 ? 1 + rnd.nextInt(32) : w, n + 1);
  final c = Canvas(rows, hs.styles, hs.glyphs);
  for (var y = 0; y <= n; y++) {
    if (rnd.nextInt(3) == 0) {
      c.fill(0, y, rows.width, 1, hs.pens[rnd.nextInt(hs.pens.length)]);
    }
    for (var k = rnd.nextInt(3); k >= 0; k--) {
      c.text(
        rnd.nextInt(rows.width + 2) - 1,
        y,
        samples[rnd.nextInt(samples.length)],
        hs.pens[rnd.nextInt(hs.pens.length)],
      );
    }
  }
  if (fresh) {
    for (var y = 0; y <= n; y++) {
      c.runStyled(
        rnd.nextInt(rows.width),
        y,
        c.shape('a${freshCluster(rnd)}'),
        hs.styles.style(fg: Color.rgb(rnd.nextInt(256), 7, 7)),
      );
    }
  }
  final from = rnd.nextInt(2);
  hs.commit(rows, from, from + n);
}

void main() {
  group('presenter vs terminal emulator', () {
    runFuzz('agreeing terminal, BCE', seeds: 400);
    runFuzz(
      'agreeing terminal, its styles swept after every frame, new ones '
      'painted in the ids freed',
      seeds: 300,
      sweep: true,
    );
    runFuzz(
      'agreeing terminal, BCE, REP',
      seeds: 300,
      caps: const TerminalCaps(repeatChar: true),
    );
    runFuzz(
      'terminal with left/right margins (DECSLRM)',
      seeds: 300,
      caps: const TerminalCaps(leftRightMargins: true),
    );
    runFuzz(
      'terminal without BCE',
      seeds: 200,
      vtBce: false,
      caps: const TerminalCaps(backgroundColorErase: false),
    );
    runFuzz(
      "Konsole's lines: ICH in the default colours, DCH at the line's end",
      seeds: 300,
      vtKonsoleLines: true,
      caps: const TerminalCaps(konsoleLines: true),
    );
    runFuzz(
      "Konsole's caps on an xterm-like terminal (BCE)",
      seeds: 300,
      caps: const TerminalCaps(konsoleLines: true),
    );
    runFuzz(
      'no synchronized output, no hardware scroll',
      seeds: 150,
      caps: const TerminalCaps(
        synchronizedOutput: false,
        hardwareScroll: false,
      ),
    );
    runFuzz(
      'scroll detection: one block, short moves',
      seeds: 200,
      tune: (p) => p
        ..maxScrollBlocks = 1
        ..maxAutoScroll = 2,
    );
    runFuzz(
      'no scroll detection',
      seeds: 100,
      tune: (p) => p.autoScroll = false,
    );
    runFuzz(
      'legacy (wcwidth) terminal: width disagreements stay contained',
      seeds: 300,
      vtSegmenter: () => TextSegmenter(mode: TextMode.legacy),
      caps: const TerminalCaps(repeatChar: true),
      ignoreUncertain: true,
    );
  });

  group('inline region vs terminal emulator', () {
    runInlineFuzz('BCE', seeds: 300);
    runInlineFuzz(
      'its styles swept between a commit and the frame that writes it',
      seeds: 300,
      sweep: true,
    );
    runInlineFuzz(
      'without BCE',
      seeds: 150,
      vtBce: false,
      caps: const TerminalCaps(backgroundColorErase: false),
    );
    runInlineFuzz(
      'no synchronized output, no hardware scroll',
      seeds: 150,
      caps: const TerminalCaps(
        synchronizedOutput: false,
        hardwareScroll: false,
      ),
    );
    runInlineFuzz(
      'left/right margins announced',
      seeds: 100,
      caps: const TerminalCaps(leftRightMargins: true, repeatChar: true),
    );
  });
}
