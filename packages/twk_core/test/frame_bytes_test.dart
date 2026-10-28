// Bytes per frame of typical updates on a chat screen. Output size is the
// deterministic part of performance: each update is bounded by what it
// costs today plus a small margin, so a change that drops an encoding
// technique (ICH/DCH, DECSTBM + SU, REP, ED 2, SGR reuse, the shortest
// cursor move, default parameters left out) fails with a message naming
// it. After every frame the emulator must still show what the surface asks
// for.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/style.dart';

import 'support/harness.dart';

const _phrases = <String>[
  'tool: ran 412 tests, all passed',
  'assistant: the presenter diffs only damaged spans',
  'user: check the scrolling and the width of emoji',
  'tool: compiled 87 files, 0 warnings',
  'assistant: hardware scroll moved the log by one row',
];

const _spinner = <String>['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧'];

/// A chat screen drawn straight onto the canvas: a header with a spinner,
/// the log, a box line, the input line with a bar cursor and a status line
/// with the message count. The first frame is presented by the constructor.
final class _Chat {
  _Chat(int w, int h, TerminalCaps caps) : hs = Harness(w, h, caps: caps) {
    final t = hs.styles;
    bg = t.pen(
      const Pen(fg: Color.rgb(200, 200, 200), bg: Color.rgb(16, 18, 24)),
    );
    header = t.pen(
      const Pen(
        fg: Color.rgb(255, 255, 255),
        bg: Color.rgb(0, 90, 180),
        attrs: Attr.bold,
      ),
    );
    headerDim = t.pen(
      const Pen(fg: Color.rgb(200, 220, 255), bg: Color.rgb(0, 90, 180)),
    );
    line = t.pen(const Pen(fg: Color.rgb(80, 80, 100)));
    input = t.pen(
      const Pen(
        fg: Color.rgb(255, 140, 0),
        bg: Color.rgb(24, 26, 34),
        attrs: Attr.bold,
      ),
    );
    status = t.pen(
      const Pen(
        fg: Color.rgb(150, 150, 160),
        bg: Color.rgb(30, 30, 40),
        attrs: Attr.italic,
      ),
    );
    speakers = [
      t.pen(const Pen(fg: Color.rgb(90, 200, 120))),
      t.pen(const Pen(fg: Color.rgb(220, 220, 220))),
      t.pen(const Pen(fg: Color.rgb(80, 160, 255))),
    ];
    for (var i = 0; i < logBottom - 1; i++) {
      log.add('${_phrases[i % _phrases.length]} #$i');
    }
    paintAll();
    hs.presenter
      ..cursorVisible = true
      ..cursorShape = CursorShape.bar
      ..cursorX = 2 + caret
      ..cursorY = h - 2;
    frame();
  }

  final Harness hs;
  late final int bg;
  late final int header;
  late final int headerDim;
  late final int line;
  late final int input;
  late final int status;
  late final List<int> speakers;
  final log = <String>[];
  var text =
      'explain the diff in the presenter, please, and name the techniques '
      'it uses';
  var caret = 12;
  var spin = 0;

  int get w => hs.surface.width;
  int get h => hs.surface.height;

  /// The log takes rows [1, logBottom).
  int get logBottom => h - 3;

  void paintAll() {
    paintHeader();
    for (var y = 1; y < logBottom; y++) {
      paintLogRow(y);
    }
    hs.canvas
      ..fill(0, h - 3, w, 1, bg)
      ..fill(0, h - 3, w, 1, line, 0x2500); // ─
    paintInput();
    paintStatus();
  }

  void paintHeader() => hs.canvas
    ..fill(0, 0, w, 1, header)
    ..text(1, 0, 'twk_core · frame bytes', header)
    ..text(w - 12, 0, '${_spinner[spin & 7]} working', headerDim);

  void paintLogRow(int y) {
    final i = log.length - (logBottom - y);
    hs.canvas.fill(0, y, w, 1, bg);
    if (i >= 0) {
      hs.canvas.text(1, y, log[i], speakers[i % speakers.length]);
    }
  }

  void paintInput() => hs.canvas
    ..fill(0, h - 2, w, 1, input)
    ..text(0, h - 2, '> $text', input);

  void paintStatus() => hs.canvas
    ..fill(0, h - 1, w, 1, status)
    ..text(1, h - 1, '${log.length} messages', status);

  /// Types [ch] at the caret: the text field repaints its row.
  void type(String ch) {
    text = text.substring(0, caret) + ch + text.substring(caret);
    moveCaret(1);
    paintInput();
  }

  /// Deletes the character before the caret.
  void backspace() {
    text = text.substring(0, caret - 1) + text.substring(caret);
    moveCaret(-1);
    paintInput();
  }

  void moveCaret(int by) {
    caret += by;
    hs.presenter.cursorX = 2 + caret;
  }

  void nextSpinner() {
    spin++;
    paintHeader();
  }

  /// Appends a log line and updates the count. With [record] the log rows
  /// move on the surface (`Surface.scrollRows`, replayed by the presenter);
  /// otherwise every log row is drawn again one line further on, and the
  /// presenter has to detect the move.
  void append({required bool record}) {
    log.add('${_phrases[log.length % _phrases.length]} #${log.length}');
    if (record) {
      hs.surface.scrollRows(1, logBottom, 1, hs.styles.opaqueStyleOf(bg));
      paintLogRow(logBottom - 1);
    } else {
      for (var y = 1; y < logBottom; y++) {
        paintLogRow(y);
      }
    }
    paintStatus();
  }

  /// Presents a frame, checks what the emulator shows and returns the
  /// bytes written, one character per byte.
  String frame() {
    hs.frame();
    final bad = hs.mismatches();
    if (bad.isNotEmpty) {
      fail('${bad.join('; ')}\n--- terminal ---\n${hs.vt.dump()}');
    }
    expect(hs.vt.printWraps, 0, reason: 'printing caused a wrap/scroll');
    expect(hs.vt.syncDepth, 0, reason: 'unbalanced synchronized update');
    final p = hs.presenter;
    expect(hs.vt.cursorVisible, isTrue, reason: 'cursor visibility');
    expect((hs.vt.cx, hs.vt.cy), (p.cursorX, p.cursorY), reason: 'cursor');
    return latin1.decode(p.out.view);
  }
}

/// Expects [out] to take at most [today] bytes plus a small margin;
/// [encoding] says what it should be, so a failure names what regressed.
void _expectBytes(String out, int today, String encoding) {
  final limit = today + today ~/ 100 + 2;
  expect(
    out.length,
    lessThanOrEqualTo(limit),
    reason:
        'expected $encoding: at most $limit bytes ($today today), got '
        '${out.length}: ${_show(out)}',
  );
}

/// [out] as text with ESC visible, cut to a readable length.
String _show(String out) {
  final s = utf8
      .decode(latin1.encode(out), allowMalformed: true)
      .replaceAll('\x1b', r'\e');
  return s.length > 300 ? '${s.substring(0, 300)}…' : s;
}

int _sgrCount(String out) => RegExp(r'\x1b\[[0-9;:]*m').allMatches(out).length;

void main() {
  // what the frames that depend on the screen cost today: the spinner (its
  // column has one digit more on 200 columns) and a full frame without and
  // with REP
  const screens = [
    (w: 200, h: 60, sync: true, spinner: 31, full: 5001, fullRep: 4410),
    (w: 200, h: 60, sync: false, spinner: 31, full: 5029, fullRep: 4438),
    (w: 100, h: 30, sync: true, spinner: 30, full: 2535, fullRep: 2243),
    (w: 100, h: 30, sync: false, spinner: 30, full: 2533, fullRep: 2241),
  ];
  for (final (:w, :h, :sync, :spinner, :full, :fullRep) in screens) {
    final caps = TerminalCaps(synchronizedOutput: sync);
    // the DEC 2026 wrapper of a frame that changes more than one row
    final wrap = sync ? 16 : 0;
    group('${w}x$h, synchronized output ${sync ? 'on' : 'off'}', () {
      test('nothing changed: no frame', () {
        final c = _Chat(w, h, caps);
        expect(c.frame(), isEmpty, reason: 'an idle frame writes nothing');
        // every row drawn again, identically: damage without a change
        c.paintAll();
        expect(
          c.frame(),
          isEmpty,
          reason: 'a repaint that changes no cell writes nothing',
        );
      });

      test('a character typed mid-line: ICH', () {
        // the first keystroke also switches SGR to the input pen
        final c = _Chat(w, h, caps)
          ..type('x')
          ..frame()
          ..type('y');
        final out = c.frame();
        expect(
          out,
          contains('\x1b[@'),
          reason:
              'the tail of the line should move right with ICH 1, its count '
              'left out (CSI @)',
        );
        // hide the cursor, ICH 1, the character (the cursor is already
        // there and ends where it is shown), show the cursor; one row, so
        // no DEC 2026 wrapper
        _expectBytes(out, 16, 'ICH 1 (CSI @) and the character');
      });

      test('a character deleted mid-line: DCH', () {
        final c = _Chat(w, h, caps)
          ..backspace()
          ..frame()
          ..backspace();
        final out = c.frame();
        expect(
          out,
          contains('\x1b[D\x1b[P'),
          reason:
              'the tail of the line should move left with CUB 1 and DCH 1, '
              'their counts left out (CSI D, CSI P)',
        );
        // hide the cursor, CUB 1 onto the deleted character, DCH 1, show
        // the cursor where the DCH left it
        _expectBytes(out, 18, 'CUB 1 and DCH 1 (CSI D, CSI P)');
      });

      test('the cursor moved: CUF', () {
        final c = _Chat(w, h, caps)..moveCaret(1);
        final out = c.frame();
        expect(
          out,
          isNot(contains('\x1b[?25')),
          reason: 'nothing is drawn, so the cursor should move while shown',
        );
        // CUF 1 alone (shorter than CUP and CHA, its count left out)
        _expectBytes(out, 3, 'CUF 1 (CSI C) alone, the cursor left shown');
      });

      test('the spinner turned: a move and the glyph', () {
        // the first turn also switches SGR to the spinner's pen
        final c = _Chat(w, h, caps)
          ..nextSpinner()
          ..frame()
          ..nextSpinner();
        final out = c.frame();
        expect(
          _sgrCount(out),
          0,
          reason:
              'the glyph should reuse the SGR state the last turn left: '
              '${_show(out)}',
        );
        // hide the cursor, CUP to the spinner, the glyph (3 bytes of UTF-8),
        // CUP back to the input, show the cursor; one row, so no DEC 2026
        // wrapper
        _expectBytes(out, spinner, 'CUP, the glyph, no SGR');
      });

      test('a log line appended, the move recorded: DECSTBM + SU', () {
        final c = _Chat(w, h, caps)..append(record: true);
        final out = c.frame();
        expect(
          out,
          contains('\x1b[m\x1b[2;${h - 3}r\x1b[S\x1b[r'),
          reason:
              'the log rows should scroll in hardware (SGR 0, DECSTBM + SU '
              '1, their default parameters left out)',
        );
        // SGR 0 before the scroll, then one SGR per style run: the new row
        // (its leading blank drawn in its text's SGR, which looks the same
        // on a space) and the count
        expect(
          _sgrCount(out),
          lessThanOrEqualTo(3),
          reason:
              'one SGR per style run, a blank in the SGR of the text after '
              'it: ${_show(out)}',
        );
        // hide the cursor, SGR 0 (the exposed row must not take a stray
        // background), DECSTBM + SU 1 + DECSTBM reset; the new row: CUP to
        // its first column (the column left out), its text and EL for the
        // rest; the count: CUP, SGR, the digit that changed; CUP back to the
        // input, show the cursor
        _expectBytes(
          out,
          wrap + 173,
          'DECSTBM + SU and only the new row (its leading blank in its '
          "text's SGR) and the count",
        );
      });

      test('a log line appended, the log repainted: scroll detection', () {
        final c = _Chat(w, h, caps)..append(record: false);
        final out = c.frame();
        expect(
          out,
          contains('\x1b[m\x1b[2;${h - 3}r\x1b[S\x1b[r'),
          reason:
              'the move should be detected and scrolled in hardware '
              '(DECSTBM + SU 1)',
        );
        // the same bytes as with the move recorded
        _expectBytes(
          out,
          wrap + 173,
          'a detected scroll (DECSTBM + SU) and only the new row (its '
          "leading blank in its text's SGR) and the count",
        );
      });

      test('a full repaint: ${sync ? 'ED 2 + rows' : 'rows with EL'}', () {
        final c = _Chat(w, h, caps);
        c.hs.presenter.invalidate();
        final out = c.frame();
        if (sync) {
          expect(
            out,
            contains('\x1b[2J'),
            reason: 'the log background should be painted with one ED 2',
          );
          // DEC 2026, ED 2 in the log background, then only the cells that
          // differ from it, one SGR per style run: the header (its gap
          // erased with ECH), the text of the log lines, the box line as
          // 3-byte glyphs, the input and the status rows (their tails
          // erased with EL); the cursor shape and position
          _expectBytes(out, full, 'ED 2 and the cells it left wrong');
        } else {
          // an unsynchronized clear would flash
          expect(out, isNot(contains('\x1b[2J')), reason: 'ED 2 without 2026');
          // every row written, its blank runs erased with ECH and EL
          _expectBytes(out, full, 'every row, blank runs with ECH and EL');
        }
      });

      test('a full repaint with REP: a box line is one glyph', () {
        final c = _Chat(
          w,
          h,
          TerminalCaps(synchronizedOutput: sync, repeatChar: true),
        );
        c.hs.presenter.invalidate();
        final out = c.frame();
        expect(
          out,
          contains(latin1.decode(utf8.encode('─\x1b[${w - 1}b'))),
          reason: 'the box line should be one ─ and REP ${w - 1} (CSI n b)',
        );
        _expectBytes(out, fullRep, 'the full repaint with REP for box lines');
      });
    });
  }
}
