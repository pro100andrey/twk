import 'dart:math' as math;

import 'package:gallery/gallery.dart';
import 'package:gallery/src/pages/rich.dart' show qrEncodes;
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart' show MarkdownView;
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] (the clock stopped at 2 s unless the route
/// says) in a terminal of [size].
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
}) async {
  final at = route.contains('t=')
      ? route
      : route.contains('?')
      ? '$route&t=2000'
      : '$route?t=2000';
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(at)), size: size);
  await t.pump();
}

/// Presses [keys] (apart by commas), a frame after each.
Future<void> keys(TwkTester t, String keys) async {
  for (final k in keys.split(',')) {
    await t.press(k);
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 100));
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// Each cell of the screen as it shows ([_shown]).
List<(String, int, int, int, int)> cells(TwkTester t) => [
  for (var y = 0; y < t.vt.height; y++)
    for (var x = 0; x < t.vt.width; x++) _shown(t.vt.cell(x, y)),
];

/// [cell] as it shows: its text, colors, underline and attributes; of a
/// blank, its text color and the attributes that do not show on it
/// ([Attr.visibleOnBlank]) left out, as the terminal gets whichever is at
/// hand.
(String, int, int, int, int) _shown(VtCell cell) => cell.text == ' '
    ? (' ', 0, cell.bg, cell.ul, cell.attrs & Attr.visibleOnBlank)
    : (cell.text, cell.fg, cell.bg, cell.ul, cell.attrs);

/// Each page of the groups, and what its stage shows as it opens.
const _pages = {
  'rich/markdownview': 'Release notes',
  'rich/codeview': "import 'package:twk/twk.dart';",
  'rich/diffview': 'bin/greet.dart',
  'rich/bigtext': 'Hello',
  'rich/ansi': 'read: 613 characters at once, 7 lines',
  'images/image': '▀▀▀▀▀▀',
  'terminal/terminalview': r'user@twk:~/twk$ ls',
};

/// The modules the screen's half blocks draw, a row of cells two rows of
/// them: `▀` the upper dark, `▄` the lower, `█` both; anything else light.
List<List<bool>> _modules(List<String> lines) => [
  for (final line in lines) ...[
    for (final half in const ['▀', '▄'])
      [for (final c in line.runes) c == half.runes.single || c == 0x2588],
  ],
];

/// Whether a QR finder pattern's 7 × 7 modules are at [x], [y] of [m]: a
/// dark ring, a light ring, a dark 3 × 3 core.
bool _finderAt(List<List<bool>> m, int x, int y) {
  if (y + 7 > m.length) {
    return false;
  }
  for (var dy = 0; dy < 7; dy++) {
    if (x + 7 > m[y + dy].length) {
      return false;
    }
    for (var dx = 0; dx < 7; dx++) {
      final ring = math.max((dx - 3).abs(), (dy - 3).abs());
      if (m[y + dy][x + dx] != (ring != 2)) {
        return false;
      }
    }
  }
  return true;
}

/// The finder patterns on the screen, by their top left module.
List<(int, int)> _finders(TwkTester t) {
  final m = _modules(t.lines);
  return [
    for (var y = 0; y < m.length; y++)
      for (var x = 0; x < m[y].length; x++)
        if (_finderAt(m, x, y)) (x, y),
  ];
}

void main() {
  group('every page of Rich, Images and Terminal', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final MapEntry(key: page, value: shows) in _pages.entries) {
        testTwk('$page at ${size.$1}x${size.$2}', (t) async {
          await open(t, '#/$page', size: size);
          final s = screen(t);
          expect(s, isNot(contains('drawn in the next part')));
          expect(s, contains(shows));
          expect(problems(t), isEmpty);
        });
      }
    }
  });

  group('the options apply', () {
    testTwk('MarkdownView: the answer streamed in', (t) async {
      await open(t, '#/rich/markdownview?o=content:chat answer&t=300');
      expect(screen(t), contains('thinking…'));
      await open(t, '#/rich/markdownview?o=content:chat answer&t=1200');
      expect(screen(t), contains('answering…'));
      expect(screen(t), contains('To read a file'));
      await open(t, '#/rich/markdownview?o=content:chat answer&t=6000');
      expect(screen(t), contains('answered in'));
    });

    testTwk('MarkdownView: the answer streams in a piece a frame, each '
        'passed as appended, the screen as at that time', (t) async {
      const route = '#/rich/markdownview?o=content:chat answer';
      await t.pumpWidget(galleryApp(route: GalleryRoute.parse(route)));
      await t.pump();
      MarkdownView view() => t.widget<MarkdownView>(find.byType(MarkdownView));
      var last = view().data!;
      // the screen at times of the stream, to see again with the clock
      // stopped there, the answer parsed whole
      final seen = <int, List<(String, int, int, int, int)>>{};
      var pieces = 0;
      for (var i = 0; i < 120; i++) {
        await t.pump(const Duration(milliseconds: 40));
        final data = view().data!;
        if (data.length > last.length) {
          pieces++;
          expect(data, startsWith(last));
          expect(view().appended, data.substring(last.length));
          if (pieces % 15 == 1) {
            seen[t.binding.frameTime.inMilliseconds] = cells(t);
          }
        }
        last = data;
      }
      expect(pieces, greaterThan(100));
      for (final MapEntry(key: ms, value: shown) in seen.entries) {
        await t.pumpWidget(
          galleryApp(route: GalleryRoute.parse('$route&t=$ms')),
        );
        await t.pump();
        expect(cells(t), shown, reason: 'at $ms ms');
      }
    });

    testTwk('MarkdownView: the width', (t) async {
      await open(t, '#/rich/markdownview?o=width:40');
      expect(screen(t), contains('40 × 24'));
    });

    testTwk('CodeView: the language, no line numbers', (t) async {
      await open(t, '#/rich/codeview?o=lang:Go;numbers:false');
      expect(screen(t), contains('package main'));
      expect(screen(t), isNot(contains(' 1 package main')));
    });

    testTwk('CodeView: the changes in the gutter', (t) async {
      await open(t, '#/rich/codeview?o=signs:true');
      expect(screen(t), contains('~ 14'));
    });

    testTwk('DiffView: side by side, no context', (t) async {
      await open(t, '#/rich/diffview?o=layout:sideBySide;context:0');
      expect(screen(t), contains('│'));
      expect(screen(t), isNot(contains("import 'dart:io';")));
    });

    testTwk('DiffView: the live edit, a step a second', (t) async {
      await open(t, '#/rich/diffview?o=live:true&t=500');
      expect(screen(t), isNot(contains('in [language]')));
      await open(t, '#/rich/diffview?o=live:true&t=1500');
      expect(screen(t), contains('in [language]'));
    });

    testTwk('BigText: the clock from 9:41', (t) async {
      await open(t, '#/rich/bigtext?o=text:clock;font:thin&t=2000');
      final s = screen(t);
      expect(s, isNot(contains('type here')));
      expect(s, isNot(contains('Hello')));
    });

    testTwk('ANSI: streamed a piece at a time', (t) async {
      await open(t, '#/rich/ansi?o=read:AnsiStream;piece:16&t=200');
      expect(screen(t), contains('read: 80 of 613 characters, 16 at a time'));
      expect(screen(t), contains('piece: '));
    });

    testTwk('ANSI: ls', (t) async {
      await open(t, '#/rich/ansi?o=output:ls');
      expect(screen(t), contains('CHANGELOG.md'));
      expect(screen(t), contains('ls --color'));
    });
  });

  group('the Image page', () {
    testTwk('the box: as wide and as tall as the options say', (t) async {
      await open(t, '#/images/image');
      expect(screen(t), contains('44 × 12'));
      await open(t, '#/images/image?o=width:20;height:6');
      expect(screen(t), contains('20 × 6'));
    });

    testTwk('the logo: its corners transparent, quadrants', (t) async {
      await open(t, '#/images/image?o=picture:logo.png;mode:quadrant');
      final s = screen(t);
      expect(s, contains('▗'));
      expect(s, contains('▖'));
    });

    testTwk('the files are found wherever the gallery runs from', (t) async {
      await open(t, '#/images/image?o=picture:logo.png');
      expect(screen(t), isNot(contains('PathNotFoundException')));
      expect(problems(t), isEmpty);
    });

    testTwk('the Code names the file and the options', (t) async {
      await open(t, '#/images/image?o=fit:cover;mode:quadrant&tab=code');
      final s = screen(t);
      expect(s, contains("'assets/lake.jpg', // 240 × 160 pixels"));
      expect(s, contains('fit: .cover,'));
      expect(s, contains('blockMode: .quadrant,'));
    });
  });

  group('the TerminalView page: the scripted shell', () {
    testTwk('the script on the clock: ls, dart test, htop', (t) async {
      await open(t, '#/terminal/terminalview?t=2000');
      expect(screen(t), contains('analysis_options.yaml'));
      expect(screen(t), contains(' user@twk: ~/twk '));
      await open(t, '#/terminal/terminalview?t=9000');
      expect(screen(t), contains('dart test -r expanded'));
      expect(screen(t), contains(': test/'));
      await open(t, '#/terminal/terminalview?t=12500');
      expect(screen(t), contains(' htop '));
      expect(screen(t), contains('F10Quit'));
    });

    testTwk('a key takes it over: help', (t) async {
      await open(t, '#/terminal/terminalview?t=300');
      await keys(t, 'tab');
      await t.type('help');
      await keys(t, 'enter');
      final s = screen(t);
      expect(s, contains('processes, full screen (q quits)'));
      expect(s, isNot(contains('analysis_options.yaml')));
    });

    testTwk('the typist stops for good once taken over', (t) async {
      await open(t, '#/terminal/terminalview?t=300');
      await keys(t, 'tab');
      await t.type('whoami');
      await keys(t, 'enter');
      await t.pump(const Duration(seconds: 3));
      final s = screen(t);
      expect(s, contains(r'$ whoami'));
      expect(s, isNot(contains('analysis_options.yaml')));
    });

    testTwk('htop: Down moves its selection, q quits it', (t) async {
      await open(t, '#/terminal/terminalview?t=12500');
      await keys(t, 'tab,q');
      expect(screen(t), isNot(contains('F10Quit')));
      expect(screen(t), contains(r'$ htop'));
    });

    testTwk('exit: ended, then another shell', (t) async {
      // the app's clock, which goes on
      await t.pumpWidget(
        galleryApp(route: GalleryRoute.parse('#/terminal/terminalview')),
        size: (120, 36),
      );
      await t.pump();
      await keys(t, 'tab');
      await t.type('exit');
      await keys(t, 'enter');
      expect(screen(t), contains(' ended '));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(screen(t), isNot(contains(' ended ')));
      expect(screen(t), contains(r'user@twk:~/twk$'));
    });

    testTwk('the Code builds a ScriptedShell in a view the room allows', (
      t,
    ) async {
      await open(t, '#/terminal/terminalview');
      final page = galleryPages.firstWhere((p) => p.title == 'TerminalView');
      final code = page.codeOf(Options.initial(page))!;
      expect(code, contains('ScriptedShell(autoplay: true)'));
      expect(code, contains('width: 82,'));
    });
  });

  group('the hints and the room', () {
    testTwk('a view that scrolls says its keys, those that would move it; '
        'one that does not, none', (t) async {
      await open(t, '#/rich/codeview?o=width:40');
      await keys(t, 'tab');
      expect(t.lines.last, contains('↓ scroll'));
      expect(t.lines.last, isNot(contains('↑')));
      await keys(t, 'down');
      expect(t.lines.last, contains('↑↓ scroll'));
      await open(t, '#/rich/codeview?o=wrap:none;width:80');
      await keys(t, 'tab');
      expect(t.lines.last, isNot(contains('scroll')));
    });

    testTwk('BigText: the field says what typing does', (t) async {
      await open(t, '#/rich/bigtext');
      await keys(t, 'tab');
      expect(t.lines.last, contains('type big text'));
    });

    testTwk('TerminalView: take over, then the commands', (t) async {
      await open(t, '#/terminal/terminalview');
      await keys(t, 'tab');
      expect(t.lines.last, contains('type take over'));
      await t.type('x');
      await t.pump();
      expect(t.lines.last, contains('help commands'));
    });

    testTwk('a narrow screen: the options whole under a capped widget', (
      t,
    ) async {
      // the last option of each
      for (final (page, last) in const [
        ('rich/codeview', 'width'),
        ('rich/bigtext', 'style'),
        ('images/image', 'height'),
      ]) {
        await open(t, '#/$page', size: (80, 24));
        expect(screen(t), contains(last), reason: page);
      }
    });
  });

  group('the keys', () {
    testTwk('CodeView: Tab to it, Down scrolls', (t) async {
      await open(t, '#/rich/codeview?o=width:40');
      expect(screen(t), contains("import 'package:twk/twk.dart';"));
      await keys(t, 'tab,down,down');
      expect(screen(t), isNot(contains("import 'package:twk/twk.dart';")));
    });

    testTwk('DiffView: End goes to the last lines', (t) async {
      await open(t, '#/rich/diffview');
      await keys(t, 'tab,end');
      expect(screen(t), isNot(contains('+++ ')));
    });

    testTwk('BigText: what is typed is big', (t) async {
      await open(t, '#/rich/bigtext');
      await keys(t, 'tab,backspace,backspace,backspace,backspace,backspace');
      expect(screen(t), contains('type here'));
      await t.type('Hi');
      await t.pump();
      expect(screen(t), contains('│Hi'));
    });
  });

  group('the QrCode page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      testTwk('the whole symbol at ${size.$1}x${size.$2}: its finder '
          'patterns at three corners', (t) async {
        await open(t, '#/rich/qrcode', size: size);
        final f = _finders(t);
        expect(f, hasLength(3), reason: screen(t));
        final [(x, y), (rx, ry), (bx, by)] = f
          ..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
        // the top right one, the bottom left one, as far from the first
        expect(ry, y);
        expect(bx, x);
        expect(rx - x, greaterThan(7));
        expect(by - y, rx - x);
        expect(problems(t), isEmpty);
      });
    }

    testTwk('a symbol is encoded once for each text and level', (t) async {
      final before = qrEncodes;
      await open(t, '#/rich/qrcode?o=text:wifi;level:low');
      await t.pump(const Duration(milliseconds: 500));
      expect(qrEncodes - before, 1);
      // the level option, then a level on
      await keys(t, 'tab,down,right');
      expect(screen(t), contains('mask'));
      expect(qrEncodes - before, 2);
      // back to one encoded already
      await keys(t, 'left');
      expect(qrEncodes - before, 2);
    });

    // after the test that counts encodings: these encode symbols of
    // their own, which the page keeps
    for (final text in const ['link', 'wifi']) {
      testTwk('the $text symbol, cut off at 80x24 even without a quiet '
          'zone, says the rows it needs', (t) async {
        await open(t, '#/rich/qrcode?o=text:$text', size: (80, 24));
        expect(screen(t), contains('version 3'));
        expect(screen(t), contains('needs 15 rows'));
        expect(problems(t), isEmpty);
      });
    }

    testTwk('a symbol the stage shows whole says nothing of rows', (t) async {
      await open(t, '#/rich/qrcode?o=text:link');
      expect(screen(t), contains('version 3'));
      expect(screen(t), isNot(contains('needs')));
    });
  });
}
