// The search of example/hooks/search.dart: the packages loaded while a
// spinner turns, filtered once the typing pauses (each key typed putting
// it off again), the match highlighted; Escape clears, q is typed, Ctrl+Q
// quits.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../../example/hooks/search.dart';

/// The search as its `main` runs it, on a terminal of 50 × 12.
Future<void> start(TwkTester t) => t.pumpWidget(
  const Search(),
  size: (50, 12),
  backgroundRgb: 0x16181d,
);

/// The packages listed, by name.
List<String> listed(TwkTester t) => [
  for (final line in t.lines.sublist(3, 11))
    if (line.substring(2, line.length - 1).trim() case final row
        when row.isNotEmpty)
      row.split(' ').first,
];

void main() {
  testTwk('a spinner turns while the packages load, then they are all '
      'listed', (t) async {
    await start(t);
    expect(t, hasTextAt(2, 2, '⠋ loading the packages'));
    await t.pump(const Duration(milliseconds: 100));
    expect(t, isNot(hasTextAt(2, 2, '⠋')));
    expect(listed(t), isEmpty);

    await t.pump(loadingTime);
    expect(
      t,
      matchesScreen('''
╭ Packages ──────────────────────────────────────╮
│ ⌕ search                                       │
│ 15 of 15                                       │
│ args            parses command-line arguments  │
│ async           utilities for streams and fut… │
│ collection      collections and what to do wi… │
│ crypto          hashes: SHA-1, SHA-256, MD5    │
│ http            makes HTTP requests            │
│ intl            messages, dates and numbers b… │
│ json_annotation annotations for JSON code      │
│ logging         hierarchical loggers           │
╰──────────────────────── esc clear  ctrl+q quit ╯
'''),
    );
  });

  testTwk('what is typed filters the list once the typing has paused; a '
      'key typed before puts it off again', (t) async {
    await start(t);
    await t.pump(loadingTime);
    await t.type('s');
    await t.pump(pause - const Duration(milliseconds: 100));
    await t.type('t');
    await t.pump(pause - const Duration(milliseconds: 100));
    // 400 ms since s, 200 since t: still the whole list
    expect(t, hasTextAt(2, 2, 'searching…'));
    expect(listed(t), hasLength(8));

    await t.pump(const Duration(milliseconds: 100));
    expect(t, hasTextAt(2, 2, '5 of 15   '));
    expect(listed(t), ['async', 'http', 'meta', 'stream_channel', 'test']);
    // te·st: the part of the name that matches in the primary color
    expect(t, styleAt(4, 7, hasFg(ThemeData.dark.primary.fg!)));
    expect(t, styleAt(2, 7, hasFg(ThemeData.dark.text.fg!)));
  });

  testTwk('Escape clears the field: the whole list once the pause is over', (
    t,
  ) async {
    await start(t);
    await t.pump(loadingTime);
    await t.type('yaml');
    await t.pump(pause);
    expect(listed(t), ['yaml']);

    await t.press('escape');
    await t.pump(pause);
    expect(t, hasTextAt(2, 1, '⌕ search'));
    expect(t, hasTextAt(2, 2, '15 of 15'));
  });

  testTwk('the case of what is typed does not matter: sha finds SHA-1 in a '
      'description', (t) async {
    await start(t);
    await t.pump(loadingTime);
    await t.type('sha');
    await t.pump(pause);
    expect(listed(t), ['crypto']);
  });

  testTwk('q is typed into the field; Ctrl+Q quits', (t) async {
    await start(t);
    await t.type('q');
    await t.pump();
    expect(t, hasTextAt(2, 1, '⌕ q '));
    expect(t.isRunning, isTrue);
    await t.press('ctrl+q');
    expect(t.isRunning, isFalse);
  });
}
