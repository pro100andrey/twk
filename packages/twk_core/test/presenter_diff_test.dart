// Differential test: the bytes the presenter writes for a fixed set of
// random scenes, as a digest per terminal configuration, recorded from the
// presenter as it was before its diff loop was specialised (the run of
// changed plain cells and the run of blanks that look the same). A change
// meant only to make the presenter faster must not change one byte; one
// meant to change its output re-records the digests:
//
//   PRESENTER_DIFF_RECORD=1 dart test test/presenter_diff_test.dart
//
// prints the digests in place of checking them. Unlike
// test/presenter_fuzz_test.dart, whose screens are at most 30 columns, the
// scenes here are as wide as real ones, full of long lines in pens over a
// background (the cells the diff writes in runs) and often invalidated (the
// full frame, cleared to its dominant background first).
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/src/presenter.dart';

import 'support/harness.dart';

/// The digest and the byte count of every configuration's scenes.
const _recorded = <String, (int, int)>{
  'agreeing terminal, BCE': (0xb47b2cb5, 4740977),
  'REP': (0xab18cc, 4181715),
  'DECSLRM': (0xbcc75c7, 4736223),
  'no BCE': (0x989dac39, 6204251),
  'Konsole lines': (0xc1077f61, 4748146),
  'no sync, no hardware scroll': (0x403ab38e, 5244661),
  'one scroll block, short moves': (0xab7af5d2, 4787448),
  'no scroll detection': (0x861782ed, 4937427),
  'inline, BCE': (0x16613681, 2143799),
  'inline, no BCE, REP': (0x481a2901, 1967837),
};

final _record = Platform.environment['PRESENTER_DIFF_RECORD'] == '1';

/// FNV-1a over 32 bits.
int _fnv(int h, List<int> bytes) {
  var d = h;
  for (final b in bytes) {
    d = ((d ^ b) * 0x01000193) & 0xFFFFFFFF;
  }
  return d;
}

const _fnvStart = 0x811C9DC5;

const _lines = <String>[
  'tool: ran 412 tests ✓ all passed',
  'assistant: the presenter diffs only damaged spans',
  'user: проверь прокрутку и ширину эмодзи 🧪',
  'tool: compiled 87 files · 你好 · 0 warnings',
  'a  b   c    d     e      f             g',
  'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx yyyyyyyyyyyy',
  '                    indented after spaces',
  'e\u{301} combining · 👨\u{200D}👩\u{200D}👧 · ❤\u{FE0F} · 🇺🇦',
];

/// A screen like an app's: a background, then lines of text in pens drawn
/// over it from a column, some of them edited in place.
void _screenOp(Harness hs, Random rnd) {
  final s = hs.surface;
  final cv = hs.canvas;
  final w = s.width;
  final h = s.height;
  final pens = hs.pens;
  if (rnd.nextInt(3) == 0) {
    cv.fill(0, 0, w, h, pens[rnd.nextBool() ? 1 : 3]);
  }
  final from = rnd.nextInt(h);
  final to = from + 1 + rnd.nextInt(h - from);
  for (var y = from; y < to; y++) {
    var line = _lines[rnd.nextInt(_lines.length)];
    if (rnd.nextInt(4) == 0) {
      line = '$line ${samples[rnd.nextInt(samples.length)]} #$y';
    }
    cv.text(rnd.nextInt(3), y, line, pens[rnd.nextInt(pens.length)]);
    if (rnd.nextInt(3) == 0) {
      cv.text(
        rnd.nextInt(w),
        y,
        _lines[rnd.nextInt(_lines.length)],
        pens[rnd.nextInt(pens.length)],
      );
    }
  }
}

/// Runs [seeds] random scenes on a terminal with [caps] and returns the
/// digest of every byte written, and their number.
(int, int) _scenes({
  required int seeds,
  bool inline = false,
  TerminalCaps caps = const TerminalCaps(),
  void Function(Presenter p)? tune,
}) {
  var digest = _fnvStart;
  var bytes = 0;
  for (var seed = 0; seed < seeds; seed++) {
    final rnd = Random(seed);
    var w = 1 + rnd.nextInt(160);
    var h = 1 + rnd.nextInt(30);
    final hs = inline
        ? Harness.inline(
            w,
            1 + rnd.nextInt(h),
            screenHeight: h,
            caps: caps,
            strict: false,
          )
        : Harness(w, h, caps: caps, strict: false);
    tune?.call(hs.presenter);
    for (var f = 0; f < 20; f++) {
      if (rnd.nextInt(15) == 0) {
        w = 1 + rnd.nextInt(160);
        h = 1 + rnd.nextInt(30);
        if (inline) {
          hs.resizeTerminal(w, h, pull: rnd.nextBool());
        } else {
          hs.resize(w, h);
        }
      }
      if (inline && rnd.nextInt(6) == 0) {
        hs.resizeRegion(1 + rnd.nextInt(h));
      }
      if (rnd.nextInt(2) == 0) {
        _screenOp(hs, rnd);
      }
      for (var k = rnd.nextInt(6); k > 0; k--) {
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
      if (!inline && rnd.nextInt(5) == 0) {
        hs.presenter.invalidate();
      }
      bytes += hs.frame();
      digest = _fnv(digest, hs.presenter.out.view);
    }
  }
  return (digest, bytes);
}

void _check(
  String name, {
  int seeds = 300,
  bool inline = false,
  TerminalCaps caps = const TerminalCaps(),
  void Function(Presenter p)? tune,
}) {
  test(name, () {
    final (digest, bytes) = _scenes(
      seeds: seeds,
      inline: inline,
      caps: caps,
      tune: tune,
    );
    if (_record) {
      // the digests to paste into _recorded
      // ignore: avoid_print
      print("  '$name': (0x${digest.toRadixString(16)}, $bytes),");
      return;
    }
    final want = _recorded[name];
    expect(want, isNotNull, reason: 'no digest recorded for "$name"');
    expect(bytes, want!.$2, reason: 'bytes written');
    expect(digest, want.$1, reason: 'digest of the bytes written');
  });
}

void main() {
  // the terminal configurations of test/presenter_fuzz_test.dart (its
  // legacy one differs in the emulator only), two of them inline
  group('presenter output unchanged', () {
    _check('agreeing terminal, BCE');
    _check('REP', caps: const TerminalCaps(repeatChar: true));
    _check('DECSLRM', caps: const TerminalCaps(leftRightMargins: true));
    _check(
      'no BCE',
      caps: const TerminalCaps(backgroundColorErase: false),
    );
    _check('Konsole lines', caps: const TerminalCaps(konsoleLines: true));
    _check(
      'no sync, no hardware scroll',
      caps: const TerminalCaps(
        synchronizedOutput: false,
        hardwareScroll: false,
      ),
    );
    _check(
      'one scroll block, short moves',
      tune: (p) => p
        ..maxScrollBlocks = 1
        ..maxAutoScroll = 2,
    );
    _check('no scroll detection', tune: (p) => p.autoScroll = false);
    _check('inline, BCE', inline: true);
    _check(
      'inline, no BCE, REP',
      inline: true,
      caps: const TerminalCaps(backgroundColorErase: false, repeatChar: true),
    );
  });
}
