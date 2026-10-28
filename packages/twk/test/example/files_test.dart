// The file manager of example/files.dart over a temporary directory: the
// tree and the table side by side, a directory opened from either and
// left; files copied and moved into the other pane's directory once a
// dialog confirms it, a progress bar filling meanwhile, frame after frame,
// and Escape cancelling; a copy that fails; the rename and new directory
// forms; the settings pushed on a screen of their own and popped, saved or
// not; files dragged from one pane onto the other; the command palette and
// the menus.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart' hide Link;
import 'package:twk_test/twk_test.dart';

import '../../example/files.dart' show FileManager;

/// The terminal the tests run the app on.
const size = (80, 16);

/// The directory the app shows: `work` in a temporary directory.
late String root;

/// Starts the app over [root], copying [bytesPerFrame] bytes a frame.
Future<void> start(TwkTester t, {int bytesPerFrame = 2000}) => t.pumpWidget(
  FileManager(directory: root, bytesPerFrame: bytesPerFrame),
  size: size,
  backgroundRgb: 0x16181d,
);

/// Presses each of [keys], a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pump();
}

Future<void> click(TwkTester t, int x, int y) async {
  await t.click(x, y);
  await t.pump();
}

/// Drags with the left button from [from] to [to], a frame after each
/// move, and releases it there.
Future<void> drag(TwkTester t, (int, int) from, (int, int) to) async {
  final (x, y) = from;
  await t.mouse(MouseKind.down, x, y);
  await t.mouse(MouseKind.drag, x + (to.$1 > x ? 1 : -1), y);
  await t.pump();
  await t.mouse(MouseKind.drag, to.$1, to.$2);
  await t.pump();
  await t.mouse(MouseKind.up, to.$1, to.$2);
  await t.pump();
}

/// Pumps frames until [done], a hundred at most.
Future<void> until(TwkTester t, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await t.pump();
  }
  expect(done(), isTrue, reason: t.lines.join('\n'));
}

/// Whether a line of the screen contains [text].
bool shows(TwkTester t, String text) => t.lines.any((l) => l.contains(text));

/// Whether a line of the screen contains [text].
Matcher hasLine(String text) => containsLine(contains(text));

/// Pumps frames until a line of the screen contains [text]: past the fade
/// of a dialog or a menu, the slide of a toast.
Future<void> see(TwkTester t, String text) => until(t, () => shows(t, text));

/// The rows of the tree pane, without its borders.
List<String> tree(TwkTester t) => [
  for (final line in t.lines.sublist(2, 13))
    if (line.substring(1, 26).trimRight() case final row when row.isNotEmpty)
      row,
];

/// The row [y] of the table: its name and its size, the date left out.
String _row(TwkTester t, int y) =>
    t.lines[y].substring(27, 62).trim().replaceAll(RegExp(' +'), ' ');

/// The rows of the table.
List<String> files(TwkTester t) => [
  for (var y = 3; y < 13; y++)
    if (_row(t, y) case final row when row.isNotEmpty) row,
];

/// Whether the cell [x], [y] is on a selection's color, of a list that
/// has the focus or of one that has not.
bool _selectedAt(TwkTester t, int x, int y) => [
  theme.selection.bg!.value,
  theme.selectionIdle.bg!.value,
].contains(t.cell(x, y).bg);

/// The theme the app takes on the tests' terminal, a dark one: twk's own.
const ThemeData theme = ThemeData.dark;

/// The row of the table selected: its name on the selection's color.
String? selected(TwkTester t) {
  for (var y = 3; y < 13; y++) {
    if (_selectedAt(t, 27, y)) {
      return _row(t, y);
    }
  }
  return null;
}

/// The row of the tree selected: its name on the selection's color.
String? selectedInTree(TwkTester t) {
  for (var y = 2; y < 13; y++) {
    final row = t.lines[y].substring(1, 26).trim();
    final x = t.lines[y].indexOf(RegExp(r'[\w.]'));
    if (x > 0 && x < 26 && _selectedAt(t, x, y)) {
      return row.replaceFirst(RegExp(r'^[^\w.]+'), '');
    }
  }
  return null;
}

/// The table's title: the path of its directory.
String title(TwkTester t) =>
    RegExp(r'┬ (\S+) ─').firstMatch(t.lines[1])?.group(1) ?? '';

String status(TwkTester t) => t.lines[14];

String hints(TwkTester t) => t.lines[15];

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// The names in the directory [path] below [root], sorted.
List<String> ls(String path) => [
  for (final e in Directory('$root/$path').listSync()) _name(e.path),
]..sort();

/// What the file [path] below [root] holds.
String read(String path) => File('$root/$path').readAsStringSync();

String _name(String path) => path.substring(path.lastIndexOf('/') + 1);

void main() {
  setUp(() {
    // under /tmp: macOS's own temporary directory (/var/folders/…/T) is a
    // path too long for the table's title to show whole
    final temp = (Platform.isWindows ? Directory.systemTemp : Directory('/tmp'))
        .createTempSync('files_');
    addTearDown(() => temp.deleteSync(recursive: true));
    root = '${temp.resolveSymbolicLinksSync()}/work';
    for (final d in ['', '/docs', '/src', '/src/lib', '/.git']) {
      Directory('$root$d').createSync();
    }
    for (final (path, length) in [
      ('notes.txt', 3000),
      ('README.md', 100),
      ('.env', 10),
      ('docs/guide.md', 5000),
      ('src/main.dart', 2000),
      ('src/lib/util.dart', 1500),
    ]) {
      // its name over and over
      final name = _name(path);
      File('$root/$path')
        ..writeAsStringSync(
          (name * (length ~/ name.length + 1)).substring(0, length),
        )
        ..setLastModifiedSync(DateTime(2026, 1, 2, 3, 4));
    }
  });

  testTwk('the directories in a tree on the left, the entries of one in a '
      'table on the right, directories first, dotfiles hidden; the status '
      'bar counts them and says where F5 copies to', (t) async {
    await start(t);
    expect(t.lines.first, ' File  View  Options');
    expect(tree(t), ['▾ work/', '├── docs/', '└─▸ src/']);
    expect(title(t), root);
    expect(t.lines[2].substring(27), startsWith('Name '));
    expect(files(t), [
      '../ up',
      'docs/ dir',
      'src/ dir',
      'notes.txt 2.9K',
      'README.md 100',
    ]);
    expect(t.lines[6], endsWith(' 2.9K 2026-01-02 03:04│'));
    expect(focused(t), 'files');
    expect(selected(t), 'docs/ dir', reason: 'the first below ../');
    for (final x in [27, 50, 60, 70]) {
      expect(t, styleAt(x, 4, hasBg(theme.selection.bg!)), reason: 'the row');
    }
    expect(selectedInTree(t), 'work/');
    expect(status(t), endsWith(' 4 entries'));
    expect(status(t), startsWith(' to $root '));
    expect(
      hints(t),
      startsWith('space mark   backspace up   f10 menu   f2 rename   f5 copy'),
    );
  });

  testTwk('Enter opens a directory, Backspace and ../ go up with the one '
      'left selected; from the tree, Right shows the directories in one '
      'and Enter opens it in the table', (t) async {
    await start(t);
    await press(t, 'enter');
    expect(title(t), '$root/docs');
    expect(files(t), ['../ up', 'guide.md 4.9K']);
    expect(selected(t), 'guide.md 4.9K');
    await press(t, 'backspace');
    expect(title(t), root);
    expect(selected(t), 'docs/ dir');

    await press(t, 'down enter up enter');
    expect(title(t), root, reason: '../ of src');
    expect(selected(t), 'src/ dir');

    await press(t, 'tab');
    expect(focused(t), 'tree');
    expect(status(t), startsWith(' to $root '), reason: "the table's");
    await press(t, 'down down right');
    expect(tree(t), ['▾ work/', '├── docs/', '└─▾ src/', '  └── lib/']);
    await press(t, 'down enter');
    expect(selectedInTree(t), 'lib/');
    expect(title(t), '$root/src/lib');
    expect(files(t), ['../ up', 'util.dart 1.5K']);
    expect(focused(t), 'tree', reason: 'the focus left in the tree');
  });

  testTwk('F5 asks where to copy the files marked, the directory selected '
      'in the tree in the field; then a progress bar fills a slice a '
      'frame until they are copied, and a toast says so', (t) async {
    await start(t);
    await click(t, 6, 3);
    expect(selectedInTree(t), 'docs/');
    expect(focused(t), 'tree');
    await click(t, 40, 6);
    expect(focused(t), 'files');
    await press(t, 'space space');
    expect(
      t.cell(27, 6).fg,
      theme.warning.fg!.value,
      reason: 'notes.txt marked',
    );
    expect(status(t), startsWith(' to $root/docs '));
    expect(status(t), endsWith(' 4 entries, 2 marked, 3.0K'));

    await press(t, 'f5');
    await see(t, '  Copy 2 entries to ');
    await see(t, '  $root/docs ');
    await see(t, '   Copy    Cancel ');

    await press(t, 'enter');
    final seen = <String>[];
    // read from the dialog's texts, frame by frame: the dialog fades in
    // over the frames the copy takes
    final copying = find.byWidgetPredicate(
      (w) => w is Dialog && w.title == 'Copying',
    );
    await until(t, () {
      if (copying.evaluate().isEmpty) {
        return true;
      }
      // its title, the name, the share done, what is done
      final texts = [
        for (final e
            in find
                .descendant(of: copying, matching: find.byType(Text))
                .evaluate())
          (e.widget as Text).data ?? '',
      ];
      seen.add('${texts[1]} | ${texts[2]} | ${texts[3]}');
      return false;
    });
    expect(seen, [
      // built as the copy starts, before the first slice
      ' | 0% | 0 of 2 done, 0 of 3.0K',
      'notes.txt | 17% | 0 of 2 done, 2.0K of 3.0K',
      'README.md | 62% | 1 of 2 done, 2.9K of 3.0K',
    ]);
    await until(t, () => shows(t, '▌ Copied 2 entries to docs.'));
    expect(ls('docs'), ['README.md', 'guide.md', 'notes.txt']);
    expect(read('docs/notes.txt'), read('notes.txt'));
    expect(read('docs/README.md'), read('README.md'));
    expect(ls(''), contains('notes.txt'), reason: 'copied, not moved');
    expect(focused(t), 'files');
    await t.pump(const Duration(seconds: 3));
    expect(
      status(t),
      endsWith(' 4 entries'),
      reason: 'unmarked, the toast gone',
    );

    await click(t, 40, 6);
    await press(t, 'space space f5');
    await see(t, '  2 of them are there already: they are replaced. ');
    await press(t, 'ctrl+a ctrl+k');
    await type(t, 'src');
    expect(t, isNot(hasLine('there already')));
    await press(t, 'escape space up space f5');
    await see(t, '  README.md is there already: it is replaced. ');
  });

  testTwk('Escape cancels a copy: the file half copied is deleted, those '
      'copied before it stay', (t) async {
    File('$root/video.mp4').writeAsBytesSync(List.filled(20000, 7));
    await start(t);
    await click(t, 6, 3);
    await click(t, 40, 6);
    await press(t, 'space down down space');
    expect(status(t), endsWith(' 2 marked, 22K'));
    await press(t, 'f5 enter');
    await until(t, () => shows(t, '  video.mp4 '));
    await t.pump();
    expect(File('$root/docs/video.mp4').existsSync(), isTrue);
    expect(hints(t), contains('esc cancel'));
    await press(t, 'escape');
    await see(t, '▌ Cancelled: 1 of 2 copied.');
    expect(ls('docs'), ['guide.md', 'notes.txt']);
    await t.pump(const Duration(seconds: 1));
    expect(ls('docs'), ['guide.md', 'notes.txt'], reason: 'it stopped');
  });

  testTwk('the field of the dialog takes another directory, relative to '
      "the table's; one that is not there or where the files are "
      'already is refused; F6 moves', (t) async {
    await start(t);
    await press(t, 'down down down');
    expect(selected(t), 'README.md 100');
    await press(t, 'f6');
    await see(t, '  Move README.md to ');
    await see(t, '   Move    Cancel ');
    await press(t, 'enter');
    await see(t, '  README.md is there already. ');
    await press(t, 'ctrl+a ctrl+k');
    await type(t, 'nowhere');
    await press(t, 'enter');
    await see(t, '  No such directory. ');
    await press(t, 'ctrl+a ctrl+k');
    await type(t, 'src/lib');
    await press(t, 'enter');
    await until(t, () => shows(t, 'Moved'));
    await see(t, '▌ Moved README.md to lib.');
    expect(ls(''), isNot(contains('README.md')));
    expect(ls('src/lib'), ['README.md', 'util.dart']);
    expect(read('src/lib/README.md'), startsWith('README.md'));
    await t.pump(const Duration(seconds: 3));
    expect(files(t), ['../ up', 'docs/ dir', 'src/ dir', 'notes.txt 2.9K']);
    expect(selected(t), 'notes.txt 2.9K');
  });

  testTwk('from the tree, F6 moves the directory selected into the '
      "table's, and the tree follows; a directory does not go into "
      'itself', (t) async {
    await start(t);
    await press(t, 'down enter');
    expect(title(t), '$root/src');
    await press(t, 'tab down down right down');
    expect(selectedInTree(t), 'lib/');
    await press(t, 'up f5');
    await see(t, '  Copy src to ');
    await press(t, 'enter');
    await see(t, '  src cannot go into itself. ');
    await press(t, 'ctrl+a ctrl+k');
    await type(t, '..');
    await press(t, 'enter');
    await see(t, '  src is there already. ');
    await press(t, 'escape');

    await click(t, 6, 3);
    expect(selectedInTree(t), 'docs/');
    await press(t, 'f6 enter');
    await until(t, () => shows(t, 'Moved'));
    await see(t, '▌ Moved docs to src.');
    expect(ls(''), ['.env', '.git', 'README.md', 'notes.txt', 'src']);
    expect(read('src/docs/guide.md'), startsWith('guide.md'));
    expect(tree(t), ['▾ work/', '└─▾ src/', '  ├── docs/', '  └── lib/']);
    expect(selectedInTree(t), 'work/', reason: 'docs is gone from there');
    await t.pump(const Duration(seconds: 3));
    expect(files(t), ['../ up', 'docs/ dir', 'lib/ dir', 'main.dart 2.0K']);
  });

  testTwk('a copy that fails stops there and says why', (t) async {
    File('$root/docs/src').writeAsStringSync('a file');
    await start(t);
    await click(t, 6, 3);
    await click(t, 40, 5);
    expect(selected(t), 'src/ dir');
    await press(t, 'f5 enter');
    await until(t, () => shows(t, 'failed'));
    await see(t, '▌ Copy failed: ');
    expect(read('docs/src'), 'a file');
  });

  testTwk('F2 renames in a form, which refuses no name, a name with a / '
      'and the name of another entry; F7 makes a directory', (t) async {
    await start(t);
    await press(t, 'down down f2');
    await see(t, '  Rename');
    await see(t, '  notes.txt ');
    await press(t, 'ctrl+a ctrl+k enter');
    await see(t, '  A name, please. ');
    await type(t, 'a/b');
    await press(t, 'enter');
    await see(t, '  A name has no /. ');
    await press(t, 'ctrl+a ctrl+k');
    await type(t, 'README.md');
    await press(t, 'enter');
    await see(t, '  README.md is there already. ');
    await press(t, 'ctrl+a ctrl+k');
    await type(t, 'todo.txt');
    await press(t, 'enter');
    expect(t, isNot(hasLine('Rename')));
    expect(ls(''), ['.env', '.git', 'README.md', 'docs', 'src', 'todo.txt']);
    expect(selected(t), 'todo.txt 2.9K');

    await press(t, 'f7');
    await see(t, '  New directory');
    await see(t, '   Create    Cancel ');
    await type(t, 'build');
    await press(t, 'enter');
    expect(Directory('$root/build').existsSync(), isTrue);
    expect(selected(t), 'build/ dir');
    expect(tree(t), ['▾ work/', '├── build/', '├── docs/', '└─▸ src/']);

    await press(t, 'f2 escape');
    expect(ls(''), contains('build'), reason: 'Escape renamed nothing');

    await t.pump(const Duration(seconds: 3));
    await press(t, 'tab f2');
    await see(t, '▌ The root of the tree stays where it is.');
  });

  testTwk('F9 pushes the settings on a screen of their own; Ctrl+S saves '
      'them and goes back, Escape goes back without; the browser is as it '
      'was under it', (t) async {
    await start(t);
    await press(t, 'enter');
    expect(title(t), '$root/docs');
    await press(t, 'f9');
    expect(
      t,
      matchesScreen('''
╭ Settings ────────────────────────────────────────────────────────────────────╮
│ [ ] show hidden files                                                        │
│ [x] show the lines of the tree                                               │
│ ▐  ●▌ ask before copying and moving                                          │
│                                                                              │
│ Sort the files by                                                            │
│ (●) name  ( ) size  ( ) modified                                             │
│                                                                              │
│  Save    Cancel                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
space toggle   ctrl+s save   esc back
'''),
    );
    await press(t, 'space tab space tab tab right');
    await press(t, 'escape');
    expect(title(t), '$root/docs', reason: 'back, the table as it was');
    expect(selected(t), 'guide.md 4.9K');
    expect(focused(t), 'files');
    expect(tree(t), ['▾ work/', '├── docs/', '└─▸ src/'], reason: 'unsaved');

    await press(t, 'backspace f9');
    expect(t, hasLine('│ [ ] show hidden files '));
    expect(t, hasLine('│ (●) name  ( ) size '));
    await press(t, 'space tab space tab tab right ctrl+s');
    expect(focused(t), 'files');
    expect(tree(t), ['▾ work/', '    .git/', '    docs/', '  ▸ src/']);
    expect(files(t), [
      '../ up',
      '.git/ dir',
      'docs/ dir',
      'src/ dir',
      'notes.txt 2.9K',
      'README.md 100',
      '.env 10',
    ]);
    expect(selected(t), 'docs/ dir');
    await press(t, 'f9');
    expect(t, hasLine('│ [x] show hidden files '));
    expect(t, hasLine('│ [ ] show the lines of the tree '));
    expect(t, hasLine('│ ( ) name  (●) size '));
  });

  testTwk('not asked to, F5 copies at once', (t) async {
    await start(t);
    await press(t, 'f9 tab tab space ctrl+s');
    await click(t, 6, 4);
    await click(t, 40, 6);
    // the progress dialog closes before its fade ends
    await press(t, 'f5');
    await until(t, () => shows(t, 'Copied'));
    expect(ls('src'), ['lib', 'main.dart', 'notes.txt']);
  });

  testTwk('a file dragged from the table onto a directory of the tree is '
      'copied or moved there, as the dialog asks; a directory dragged from '
      'the tree onto the table goes into its directory; a drop where the '
      'files are already is refused', (t) async {
    await start(t);
    await drag(t, (30, 6), (8, 4));
    await see(t, '  Copy or move');
    await see(t, '  Copy or move notes.txt to ');
    await see(t, '  $root/src ');
    await see(t, '   Copy    Move    Cancel ');
    await press(t, 'tab tab enter');
    await until(t, () => shows(t, 'Moved'));
    expect(ls('src'), ['lib', 'main.dart', 'notes.txt']);
    expect(ls(''), isNot(contains('notes.txt')));

    await click(t, 30, 5);
    await press(t, 'enter');
    expect(title(t), '$root/src');
    await drag(t, (6, 3), (40, 9));
    await see(t, '  Copy or move docs to ');
    await see(t, '  $root/src ');
    await press(t, 'enter');
    await until(t, () => shows(t, 'Copied'));
    expect(ls('src/docs'), ['guide.md']);
    expect(ls(''), contains('docs'));

    await drag(t, (30, 6), (40, 9));
    expect(t, isNot(hasLine('Copy or move')), reason: 'where it is');
    await drag(t, (30, 6), (8, 4));
    expect(t, isNot(hasLine('Copy or move')), reason: 'in src/ already');
    await drag(t, (30, 6), (30, 3));
    await see(t, '  Copy or move main.dart to ');
    await see(t, '  $root ');
  });

  testTwk('Ctrl+P lists the commands with their keys; one picked by typing '
      'runs', (t) async {
    await start(t);
    await press(t, 'ctrl+p');
    await see(t, '  Copy… ');
    await until(
      t,
      () => t.lines.any(RegExp('  Settings… +f9  ').hasMatch),
    );
    await type(t, 'new dir');
    await press(t, 'enter');
    await see(t, '  New directory');
    await type(t, 'out');
    await press(t, 'enter');
    expect(ls(''), contains('out'));

    await press(t, 'ctrl+p');
    await type(t, 'show hidden');
    await press(t, 'enter');
    expect(files(t), contains('.env 10'));
  });

  testTwk('the menus: View sorts by size or by the time of the last change, '
      'shows the hidden files; File ▸ Quit quits', (t) async {
    File('$root/README.md').setLastModifiedSync(DateTime(2026, 3));
    await start(t);
    await press(t, 'alt+v');
    await t.pump(const Duration(milliseconds: 300));
    expect(t, hasLine('▎ ✓ Sort by name '));
    await press(t, 'm');
    expect(files(t).sublist(3), ['README.md 100', 'notes.txt 2.9K']);
    await press(t, 'alt+v s');
    expect(files(t).sublist(3), ['notes.txt 2.9K', 'README.md 100']);
    await press(t, 'alt+v h');
    expect(files(t), contains('.env 10'));
    await press(t, 'alt+f');
    await t.pump(const Duration(milliseconds: 300));
    expect(t, containsLine(matches(RegExp('▎ Copy… +f5  '))));
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  testTwk('Ctrl+Q quits', (t) async {
    await start(t);
    await t.press('ctrl+q');
    expect(t.isRunning, isFalse);
  });
}
