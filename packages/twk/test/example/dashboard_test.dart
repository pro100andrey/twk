// The dashboard of example/dashboard.dart: panels in a grid that share
// their borders, in the theme of the terminal's brightness, switched live;
// the figures moving each second and the log following; the heatmap's
// keys; the debug keys showing the frame overlay, the repaint rainbow and
// the log console, pressed as a user pressed them in Konsole.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/dashboard.dart' show Dashboard, deploys;

/// The dashboard on a terminal of 80 × 24, as it starts.
const dashboard = '''
 ◆ acme ops · production                                 1 of 5 down   14:30:00
╭ Requests ─────────┬ Errors ───────────┬ Latency p95 ──────┬ Users ───────────╮
│ 1 246/min  ▲ 14.… │ 0.51%  ▲ 17.3%    │ 181 ms  ▲ 10.8%   │ 3 326  ▲ 2.2%    │
│         ▁▂▂▄▄▄▄▅█ │        ▃▃▃▄▆▆▆▅█▆ │ ▁   ▁▂▃▂▅▄▁ ▁▅▄█▆ │ ▅▅▅▅▅▅▆▅▆▇▇▇▇███ │
│ ▄▇▆▇▆▅▆██████████ │ ▄▆▅▅█▆▇██████████ │ █▇▄▅█████████████ │ ████████████████ │
├ Latency, last minute ─────────────────┴───────────────────┼ Services ────────┤
│ 250 ms┤⢄⡠⡀⡠⠢⠤⠤⠤⡀⡤⠤⠤⡀    ⡀                                 │ ● api         up │
│       │  ⠈     ⠈   ⠈⠉⠉⠑⠊⠱⠤⠚⡤⠢⣀ ⣠                 ⢀⣀   ⣀⡠⠤ │ ● auth        up │
│       │                       ⠉ ⠓⠢⠤⠊⠉⠢⣀⡠⣀⠎⠊⠑⠢⠤⠒⠉⠉⠁ ⠉⠒⠊    │ ● search    slow │
│       │                                                   │ ● billing     up │
│       │⠉⠉⠉⠉⠉⠉⠉⠉⠉⠒⠒⠒⠤⠒⠤⠤⢄⡠⠤⠤⠔⠢⠔⠒⠒⠉⠉⠉⠉⠉⠉⠉⠉⠉⠒⠒⠒⠒⠒⠒⠤⠤⢄⡠⠤⠤⠤⠤⠔⠒ │ ● mail      down │
│      0┤                                                   │                  │
│       └┬────────────────────────────────────────────────┬ │                  │
│      -60 s                                            now │                  │
├ Deploys ──────────────────────────────┬ Log ──────────────┴──────────────────┤
│     Jul   Aug       Sep     Oct       │ 14:29:36.000 ERROR mail: connection  │
│ Mon ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■   │ 14:29:39.000 DEBUG cache hit items/3 │
│     ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■     │ 14:29:42.000 INFO  GET /api/orders 2 │
│ Wed ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■     │ 14:29:45.000 INFO  POST /api/session │
│     ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■     │ 14:29:48.000 WARN  search: slow quer │
│ Fri ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■     │ 14:29:51.000 INFO  GET /api/items/38 │
│     ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■     │ 14:29:54.000 ERROR mail: connection  │
│ Sun ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■     │ 14:29:57.000 DEBUG cache hit items/3 │
╰─ ←↑↓→ day  enter deploys  tab log  q quit  ctrl+g debug ─────────────────────╯
''';

/// Ctrl+G as Konsole 26.08 sends it.
const ctrlG = '\x1b[103;5u';

/// The line of the debug keys over the bottom row while Ctrl+G waits, on
/// a terminal 80 columns wide.
const keysLine =
    ' ctrl+g  o overlay  r rainbow  c console  l relayout  f level  y copy'
    '  s save';

/// What a toast and the log say Enter on [day] shows.
String deployed(DateTime day) =>
    '${day.toIso8601String().substring(0, 10)}: '
    '${deploys[day]?.join(', ') ?? 'nothing'} deployed';

/// What a user typed into the dashboard in Konsole 26.08.2 on a terminal
/// of 180 × 55, read for read, each with when it was read, in
/// microseconds since the dashboard started: the terminal's focus going
/// and coming back, the keys, Ctrl+G and Ctrl+F as CSI u.
const konsoleReads = <(int, String)>[
  (2635207, '\x1b[O'),
  (4112841, '\x1b[I'),
  (12165234, '\x1b[O'),
  (19057370, '\x1b[I'),
  (21390644, ctrlG),
  (26084856, '\x1b[A'),
  (26516580, '\x1b[C'),
  (26823684, '\x1b[C'),
  (27014665, '\x1b[C'),
  (27421736, '\x1b[A'),
  (27802685, ctrlG),
  (31389200, ctrlG),
  (37948203, 'c'),
  (39945376, 'c'),
  (40527306, 'r'),
  (41543359, 'r'),
  (44775564, '\x1b[C'),
  (45201318, '\x1b[D'),
  (46160284, '\r'),
  (46218226, '\r'),
  (48344306, '\x1b[102;5u'),
  (49931404, ctrlG),
  (50904450, 'r'),
  (53430524, 'r'),
  (54904548, 'c'),
  (59032772, ctrlG),
  (59579793, 'w'),
  (60398833, 'q'),
];

/// Expects [t]'s dashboard, 80 × 24, in the styles of [theme]: its
/// background and text, its borders, titles and keys, the figures and how
/// they moved, and the colors of how the services are.
void expectTheme(TwkTester t, ThemeData theme) {
  Matcher fg(Style style) => hasFg(style.fg!);
  expect(
    t,
    styleAt(0, 1, allOf(fg(theme.border), hasBg(theme.background.bg!))),
  );
  expect(t, styleAt(1, 0, fg(theme.primary)));
  expect(t, styleAt(3, 0, hasAttr(Attr.bold)));
  expect(t, styleAt(2, 1, fg(theme.primary)));
  expect(t, styleAt(2, 2, allOf(fg(theme.text), hasAttr(Attr.bold))));
  // requests that rose are good news, errors that rose are not
  expect(t, styleAt(13, 2, fg(theme.success)));
  expect(t, styleAt(29, 2, fg(theme.error)));
  expect(t, styleAt(62, 6, fg(theme.success)));
  expect(t, styleAt(74, 8, fg(theme.warning)));
  expect(t, styleAt(74, 10, fg(theme.error)));
  expect(t, styleAt(3, 23, allOf(fg(theme.primary), hasAttr(Attr.bold))));
  expect(t, styleAt(8, 23, fg(theme.muted)));
}

void main() {
  testTwk('on a dark terminal, the panels share their borders, in the dark '
      'theme; the heatmap has the focus, its cursor on the first day', (
    t,
  ) async {
    await t.pumpWidget(
      const Dashboard(),
      size: (80, 24),
      backgroundRgb: 0x16181d,
    );
    expect(t, matchesScreen(dashboard));
    expectTheme(t, ThemeData.dark);
    expect(t, styleAt(6, 16, hasBg(ThemeData.dark.selection.bg!)));
  });

  testTwk('on a light terminal, the light theme, and the dark one once the '
      'terminal reports a dark color scheme', (t) async {
    await t.pumpWidget(
      const Dashboard(),
      size: (80, 24),
      backgroundRgb: 0xfafafb,
    );
    expect(t, matchesScreen(dashboard));
    expectTheme(t, ThemeData.light);

    await t.type('\x1b[?997;1n');
    await t.pump();
    expect(t, matchesScreen(dashboard));
    expectTheme(t, ThemeData.dark);
  });

  testTwk('each second the clock and the figures move on, and every three '
      'the log has a line more, at its bottom', (t) async {
    await t.pumpWidget(
      const Dashboard(),
      size: (80, 24),
      backgroundRgb: 0x16181d,
    );
    final figures = t.lines.sublist(2, 5);
    await t.pump(const Duration(seconds: 1));
    expect(t.lines.first, endsWith(' 14:30:01'));
    expect(t.lines.sublist(2, 5), isNot(figures));
    await t.pump(const Duration(seconds: 2));
    expect(t.lines.first, endsWith(' 14:30:03'));
    expect(t.lines[22], contains('14:30:03.000 INFO  POST /api/session'));
  });

  testTwk('Enter shows what was deployed on the day of the cursor in a '
      'toast for three seconds, and logs it, in the log panel too', (
    t,
  ) async {
    await t.pumpWidget(
      const Dashboard(),
      size: (80, 24),
      backgroundRgb: 0x16181d,
    );
    final first = DateTime(2026, 7, 6);
    await t.press('enter');
    // the toast slides in
    await t.pump(const Duration(milliseconds: 300));
    expect(t, containsLine(contains('▌ ${deployed(first)}')));
    expect(t.lines[22], contains(deployed(first).substring(0, 20)));
    await t.pump(const Duration(seconds: 3));
    expect(t, isNot(containsLine(contains('▌ '))));

    // down a day, right a week
    await t.press('down right enter');
    await t.pump(const Duration(milliseconds: 300));
    final next = DateTime(2026, 7, 14);
    expect(t, containsLine(contains('▌ ${deployed(next)}')));
    expect(t.logs.records.map((r) => r.message), [
      deployed(first),
      deployed(next),
    ]);
  });

  group('the debug keys:', () {
    testTwk('Ctrl+G shows them over the bottom row until the next key; then '
        'o shows the frame overlay at the top right, and hides it again', (
      t,
    ) async {
      await t.pumpWidget(
        const Dashboard(),
        size: (80, 24),
        backgroundRgb: 0x16181d,
      );
      await t.type(ctrlG);
      await t.pump();
      expect(t.lines.take(23), dashboard.split('\n').take(23));
      expect(t.lines.last, keysLine);
      await t.press('o');
      await t.pump();
      expect(t.binding.debug.overlay, isTrue);
      expect(t, containsLine(contains(' frames')));
      expect(t, containsLine(endsWith(' fps')));
      expect(t, containsLine(contains(' build µs ')));

      await t.type(ctrlG);
      await t.press('o');
      await t.pump();
      expect(t.binding.debug.overlay, isFalse);
      expect(t, isNot(containsLine(contains(' build µs '))));
    });

    testTwk('Ctrl+G, r tints all of the dashboard at once, then each repaint '
        'in the next color: moving the cursor repaints the heatmap', (
      t,
    ) async {
      await t.pumpWidget(
        const Dashboard(),
        size: (80, 24),
        backgroundRgb: 0x16181d,
      );
      await t.type(ctrlG);
      await t.pump();
      await t.press('r');
      await t.pump();
      expect(t.binding.debug.rainbow, isTrue);
      int bg(int x, int y) => t.cell(x, y).bg;
      final (heatmap, tiles, services) = (bg(2, 16), bg(2, 2), bg(62, 7));
      expect(heatmap, isNot(ThemeData.dark.background.bg!.value));
      expect((tiles, services), (heatmap, heatmap));

      await t.press('right');
      await t.pump();
      expect(bg(8, 16), isNot(heatmap));
    });

    testTwk('Ctrl+G, c opens the log console over the bottom rows, with what '
        'Enter logged, and closes it', (t) async {
      await t.pumpWidget(
        const Dashboard(),
        size: (80, 24),
        backgroundRgb: 0x16181d,
      );
      await t.press('enter');
      await t.type(ctrlG);
      await t.press('c');
      await t.pump();
      expect(t.binding.debug.console.isOpen, isTrue);
      expect(t, containsLine(startsWith(' console  debug+  1 of 1')));
      expect(
        t,
        containsLine(endsWith(' INFO  ${deployed(DateTime(2026, 7, 6))}')),
      );

      await t.type(ctrlG);
      await t.press('c');
      await t.pump();
      expect(t.binding.debug.console.isOpen, isFalse);
      expect(t, isNot(containsLine(startsWith(' console '))));
    });

    testTwk('the keys a user typed in Konsole, read for read: Ctrl+G shows '
        'the debug keys until the next key, a second Ctrl+G goes to the '
        'app, c and r without Ctrl+G do nothing, and Ctrl+G r tints all of '
        'the screen at once', (t) async {
      await t.pumpWidget(
        const Dashboard(),
        size: (180, 55),
        backgroundRgb: 0x16181d,
      );
      final debug = t.binding.debug;
      final background = ThemeData.dark.background.bg!.value;
      // what shows after each read
      String seen() {
        final lines = t.lines;
        var tinted = true;
        for (var y = 0; y < 55 && tinted; y++) {
          for (var x = 0; x < 180 && tinted; x++) {
            tinted = t.cell(x, y).bg != background;
          }
        }
        return [
          if (lines.last.startsWith(' ctrl+g  o overlay')) 'keys',
          if (debug.overlay) 'overlay',
          if (debug.console.isOpen) 'console',
          if (debug.rainbow) 'rainbow',
          if (tinted) 'tinted',
          // the toasts shown, also while they slide in from off the screen
          for (final _
              in find
                  .byWidgetPredicate(
                    (w) =>
                        w is Text &&
                        (w.data ?? w.spans!.map((s) => s.text).join()).contains(
                          ' deployed',
                        ) &&
                        // not the log panel's lines
                        w.data == null,
                  )
                  .evaluate())
            'toast',
        ].join(' ');
      }

      final seenAfter = <String>[];
      for (final (micros, read) in konsoleReads) {
        final wait = Duration(microseconds: micros) - t.clock.elapsed;
        if (wait > Duration.zero) {
          await t.pump(wait);
        }
        await t.type(read);
        if (!t.isRunning) {
          seenAfter.add('quit');
          break;
        }
        await t.pump();
        seenAfter.add(seen());
      }
      expect(seenAfter, [
        // the terminal's focus going and coming back
        '', '', '', '',
        // Ctrl+G; Up after it dropped
        'keys', '',
        // Right × 3, Up
        '', '', '', '',
        // Ctrl+G twice: the second to the app; then c c r r for the app
        'keys', '', '', '', '', '',
        // Right, Left, Enter twice: the day's deploys in a toast each;
        // Ctrl+F
        '', '', 'toast', 'toast toast', 'toast toast',
        // Ctrl+G r: the rainbow on, all of the screen tinted; r c for the
        // app
        'keys', 'rainbow tinted', 'rainbow tinted', 'rainbow tinted',
        // Ctrl+G w: w dropped; q quits
        'keys rainbow tinted', 'rainbow tinted', 'quit',
      ]);
      // Right × 3 from the first day: three weeks on
      final day = deployed(DateTime(2026, 7, 27));
      expect(t.logs.records.map((r) => r.message), [day, day]);
    });
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(
      const Dashboard(),
      backgroundRgb: 0x16181d,
    );
    await t.press('q');
    expect(t.isRunning, isFalse);
  });
}
