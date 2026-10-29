// The tester runs an app in a fixed viewport: laid out at the rectangle
// and drawn in it alone, the emulator's screen the whole terminal's, the
// history around the rectangle left as it was; the mouse reported on the
// normal screen, its events relative to the rectangle. Last, a capture of
// such an app in a pseudo-terminal through tool/replay.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

/// Where the apps here draw: 12 x 3 cells from column 4 of row 1.
const _viewport = Viewport.fixed(4, 1, 12, 3);

/// Four lines as wide as the screen of 20 x 6, a letter in each cell,
/// which the viewport covers part of.
final List<String> _history = [
  for (var y = 0; y < 4; y++)
    String.fromCharCodes([for (var x = 0; x < 20; x++) 0x61 + (x + y) % 26]),
];

/// Shows the size it is laid out at.
Widget _size() => LayoutBuilder(builder: (_, c) => Text('${c.maxW}x${c.maxH}'));

void main() {
  // twk's viewport app and the replay, run in processes of their own,
  // compiled once
  late String app;
  late String replayTool;
  setUpAll(() async {
    final packages = (await Isolate.packageConfig)!.toFilePath();
    const cache = '.dart_tool/twk_test/programs';
    app = await compiledProgram(
      '../twk/test/binding/viewport_app.dart',
      packages: packages,
      cache: cache,
    );
    replayTool = await compiledProgram(
      '../../tool/replay.dart',
      packages: packages,
      cache: cache,
    );
  });

  testTwk('in a viewport of the normal screen the app is laid out at the '
      'rectangle and drawn in it alone: the history around it shows as it '
      'did, the cursor stays where the app found it', (t) async {
    await t.pumpWidget(
      _size(),
      mode: ScreenMode.inline,
      viewport: _viewport,
      size: (20, 6),
      history: _history,
    );
    expect(t.viewportLines, ['12x3', '', '']);
    String around(int y, String inside) =>
        '${_history[y].substring(0, 4)}${inside.padRight(12)}'
        '${_history[y].substring(16)}';
    expect(t.lines, [
      _history[0],
      around(1, '12x3'),
      around(2, ''),
      around(3, ''),
      '',
      '',
    ]);
    // each cell outside the rectangle as the history left it, unstyled
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 20; x++) {
        if (x < 4 || x >= 16 || y < 1 || y >= 4) {
          expect('${t.cell(x, y)}', y < 4 ? _history[y][x] : ' ');
        }
      }
    }
    expect(t.cursor, (0, 4));
    // the viewport stays as it is when the app ends
    final shown = t.lines;
    await t.quit();
    expect(t.lines, shown);
    expect(t.cursor, (0, 4));
  });

  testTwk('a press in the viewport comes in its own cells, one outside it '
      'is dropped; the terminal reports the mouse on the normal '
      'screen', (t) async {
    final presses = <String>[];
    await t.pumpWidget(
      Listener(
        behavior: HitTestBehavior.opaque,
        onDown: (e) => presses.add('${e.x}, ${e.y}'),
        child: const SizedBox(),
      ),
      mode: ScreenMode.inline,
      viewport: _viewport,
      size: (20, 6),
    );
    expect(t.terminal.mouseTracking, MouseTracking.buttons);
    await t.click(6, 2);
    await t.click(1, 1);
    await t.click(16, 3);
    expect(presses, ['2, 1']);
  });

  testTwk('in the fullscreen mode the viewport is on the alternate screen; '
      'viewportLines reads what of it the screen has, cut by a '
      'resize', (t) async {
    await t.pumpWidget(_size(), viewport: _viewport, size: (20, 6));
    expect(t.lines, ['', '    12x3', '', '', '', '']);
    expect(t.viewportLines, ['12x3', '', '']);
    await t.resize(10, 3);
    await t.pump();
    expect(t.viewportLines, ['6x2', '']);
  });

  testTwk('viewportLines is for an app in a viewport', (t) async {
    await t.pumpWidget(const Text('x'), mode: ScreenMode.inline);
    expect(() => t.viewportLines, throwsStateError);
  });

  test(
    "tool/replay.dart replays twk's viewport_app run in a pseudo-terminal "
    'with --inline and its rectangle, which plain --inline rejects for its '
    'absolute rows; the cells outside the rectangle the app wrote, blank '
    'or not, the cursor not put back and drawing on the alternate screen '
    'fail it',
    () async {
      final dir = Directory.systemTemp.createTempSync('viewport');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/out.bin';
      // a press at screen cell (12, 4) once the app has drawn its box, and
      // a q once the box shows the press
      final run = await runProcess(
        'python3',
        [
          'tool/pty_run.py',
          '--when',
          'pressed nothing',
          '--when',
          'at 2, 1',
          '--input',
          r'#1:\x1b[<0;13;5M\x1b[<0;13;5m,#2:q',
          '--out',
          out,
          '--',
          Platform.resolvedExecutable,
          app,
        ],
        workingDirectory: '../..',
        group: true,
      );
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      final written = latin1.decode(File(out).readAsBytesSync());
      final notPutBack = '${dir.path}/not_put_back.bin';
      File(notPutBack).writeAsStringSync(
        written.replaceAll('\x1b8', ''),
        encoding: latin1,
      );
      // the frames drawn on the alternate screen, past the probe's queries
      // asked there
      final alternate = '${dir.path}/alternate.bin';
      File(alternate).writeAsStringSync(
        written.replaceFirst(
          '\x1b[?2026h',
          '\x1b[?1049h\x1b[?2026h',
          written.indexOf('\x1b[?1049l'),
        ),
        encoding: latin1,
      );
      Future<String> replay(String file, List<String> flags, int status) async {
        final r = await runProcess(Platform.resolvedExecutable, [
          replayTool,
          ...flags,
          file,
          '100',
          '30',
        ], workingDirectory: '../..');
        expect(r.exitCode, status, reason: '${r.stdout}${r.stderr}');
        return '${r.stdout}';
      }

      const box = '--viewport=10,3,30,5';
      final [drawn, strict, narrower, notBack, switched] = await Future.wait([
        replay(out, ['--inline', box], 0),
        replay(out, ['--inline'], 1),
        // short of the box's last two columns
        replay(out, ['--inline', '--viewport=0,0,38,30'], 1),
        replay(notPutBack, ['--inline', box], 1),
        replay(alternate, ['--inline', box], 1),
      ]);
      expect(
        drawn,
        allOf(
          // the screen printed as the terminal shows it, without letters
          startsWith('\n\n\n          ╭'),
          contains('│pressed at 2, 1             │'),
          contains('outsideChanged=0 cursorPutBack=true'),
        ),
      );
      expect(strict, contains('CUP addresses an absolute row'));
      expect(
        narrower,
        allOf(
          contains('outsideChanged=10 '),
          contains(
            'cell (38, 4) outside the viewport written or erased: now " ", '
            'before blank',
          ),
          contains(
            'cell (39, 4) outside the viewport written or erased: now "│", '
            'before blank',
          ),
        ),
      );
      expect(notBack, contains('outsideChanged=0 cursorPutBack=false'));
      expect(
        switched,
        contains(
          'drawn on the alternate screen in a viewport of the normal screen',
        ),
      );
    },
    testOn: 'linux || mac-os',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
