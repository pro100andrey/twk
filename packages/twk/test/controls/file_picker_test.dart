// FilePicker over a temporary directory: the list of its entries under the
// field naming it, those starting with a dot and the files a filter leaves
// out hidden; the cursor moved and an entry taken by the keys and the
// mouse, from the list and from the field; the path typed completed and
// taken in the open, save and directory modes; files marked and picked
// together; a directory that cannot be listed; showFilePicker's dialog
// picking and cancelled.
//
// The paths are written with `/`, as Linux and macOS show them; Windows
// shows them with `\` (its forms are paths_test.dart's).
@TestOn('!windows')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

late String root;

/// Columns enough for the field to show [root] whole, and the paths the
/// tests put under it, however long the temporary directory's path is
/// (`TMPDIR`): 100 at the least.
int get columns => max(100, root.length + 40);

/// Pumps, the file system answering in real time meanwhile, until [done];
/// a failure showing the screen if it has not after 10 s.
Future<void> until(TwkTester t, bool Function() done) =>
    waitUntil(
      done,
      'what the file system answers',
      between: t.pump,
    ).onError<TestFailure>(
      (e, _) => fail('${e.message}: nothing came:\n${t.lines.join('\n')}'),
    );

/// The machine's file system, counting the listings it has going: begun
/// and neither ended nor cancelled.
final class _Counted extends PickerFileSystem {
  /// How many listings are going.
  var going = 0;

  @override
  String get currentDirectory => PickerFileSystem.local.currentDirectory;

  @override
  String? get homeDirectory => PickerFileSystem.local.homeDirectory;

  @override
  FileKind kindOf(String path) => PickerFileSystem.local.kindOf(path);

  @override
  Future<String> read(String file) => PickerFileSystem.local.read(file);

  @override
  Future<int?> sizeOf(String file) => PickerFileSystem.local.sizeOf(file);

  @override
  Stream<void> watch(String directory) =>
      PickerFileSystem.local.watch(directory);

  @override
  Stream<DirectoryEntry> list(String directory) {
    going++;
    var ended = false;
    void end() {
      if (!ended) {
        ended = true;
        going--;
      }
    }

    late final StreamController<DirectoryEntry> out;
    out = StreamController(
      onListen: () {
        final entries = PickerFileSystem.local
            .list(directory)
            .listen(
              out.add,
              onError: out.addError,
              onDone: () {
                end();
                unawaited(out.close());
              },
            );
        out.onCancel = () {
          end();
          return entries.cancel();
        };
      },
    );
    return out.stream;
  }
}

/// Pumps through the fade of a dialog opened (160 ms), then until the
/// list shows no `listing` row: while the dialog is still transparent,
/// the row is not on the screen.
Future<void> opened(TwkTester t) async {
  await t.pump(const Duration(milliseconds: 200));
  await listed(t);
}

/// Pumps until the list shows no `listing` row.
Future<void> listed(TwkTester t) =>
    until(t, () => !t.lines.any((line) => line.contains('listing')));

/// The suggestions shown, top to bottom: the rows of the panel of the
/// dark theme's surface under the field, the highlighted one on its
/// selection, each without its bar; not the cursor's row of the list,
/// which is as wide as the screen.
List<String> suggestions(TwkTester t) {
  const dark = ThemeData.dark;
  final panel = {dark.surface.bg, dark.selection.bg};
  final last = t.terminal.width - 1;
  return [
    for (var y = 1; y < t.terminal.height - 1; y++)
      if (panel.contains(t.cell(2, y).bg) &&
          !panel.contains(t.cell(last, y).bg))
        [
          for (var x = 0; x < t.terminal.width; x++)
            if (panel.contains(t.cell(x, y).bg)) t.cell(x, y).text else '\n',
        ].join().split('\n').first.replaceFirst('▎', '').trim(),
  ];
}

/// Pumps until [name] is among the suggestions.
Future<void> suggested(TwkTester t, String name) =>
    until(t, () => suggestions(t).contains(name));

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

/// Types [text], pumping until the app is idle: suggestions that fade in
/// have done so.
Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pumpUntilIdle();
}

/// Takes the text of the field away.
Future<void> clear(TwkTester t) => press(t, 'ctrl+a ctrl+k');

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// The text of the field, on the first row.
String field(TwkTester t) => t.lines.first.trimRight();

/// The rows of the list, between the field and the last row, without the
/// column of the cursor's bar.
List<String> rows(TwkTester t) => [
  for (final line in t.lines.sublist(1, t.lines.length - 1))
    if (line.trim().isNotEmpty) line.substring(1).trimRight(),
];

/// The row the cursor is on, in the dark theme's selection while the list
/// has the focus or its selectionIdle while it has not, without the
/// column of its bar.
String? cursor(TwkTester t) {
  const dark = ThemeData.dark;
  for (var y = 1; y < t.lines.length - 1; y++) {
    final bg = t.cell(1, y).bg;
    if (bg == dark.selection.bg || bg == dark.selectionIdle.bg) {
      expect(t.lines[y], startsWith('▎'));
      return t.lines[y].substring(1).trimRight();
    }
  }
  return null;
}

/// The last row: the check, what was refused, the buttons.
String bottom(TwkTester t) => t.lines.last.trimRight();

/// A [FilePicker] of [directory], [root] by default, with its field
/// focused, in an overlay in the dark theme; [picked] gets each list of
/// paths it picks.
Widget picker({
  PickerFileSystem fileSystem = PickerFileSystem.local,
  List<List<String>>? picked,
  FilePickerMode mode = FilePickerMode.open,
  String? directory,
  String name = '',
  List<FileFilter> filters = const [],
  bool showHidden = false,
  bool multiple = false,
}) => Theme(
  data: ThemeData.dark,
  child: Overlay(
    child: FilePicker(
      onPicked: (paths) => picked?.add(paths),
      mode: mode,
      directory: directory ?? root,
      name: name,
      filters: filters,
      showHidden: showHidden,
      multiple: multiple,
      fileSystem: fileSystem,
      autofocus: true,
    ),
  ),
);

/// Starts [widget] on a terminal of [columns] × 12, its directory listed.
Future<void> start(TwkTester t, Widget widget) async {
  await t.pumpWidget(widget, size: (columns, 12));
  await listed(t);
}

void main() {
  memoryTests();

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('file_picker_');
    addTearDown(() => dir.deleteSync(recursive: true));
    root = dir.path;
    for (final d in ['.git', 'docs', 'src', 'src/util']) {
      Directory('$root/$d').createSync();
    }
    for (final f in [
      '.env',
      'docs/guide.md',
      'docs/guidelines.md',
      'src/main.dart',
      'src/Model.dart',
      'src/.secret.dart',
      'README.md',
      'notes.txt',
      'pubspec.yaml',
    ]) {
      File('$root/$f').writeAsStringSync('');
    }
  });

  group('the list', () {
    testTwk('shows ../, the directories, then the files, each by name in '
        'any case, under the field naming the directory; listing meanwhile; '
        'the cursor on the first below ../', (t) async {
      await t.pumpWidget(picker(), size: (columns, 12));
      final first = t.frames.firstWhere((f) => f.lines.first.isNotEmpty);
      expect(first.lines.sublist(0, 3), ['$root/', ' listing', '']);
      // while listing, no row is there for the cursor to be on
      expect(first.lines.sublist(1, first.lines.length - 1).toSet(), {
        ' listing',
        '',
      });
      await listed(t);
      expect(field(t), '$root/');
      expect(rows(t), [
        '../',
        'docs/',
        'src/',
        'notes.txt',
        'pubspec.yaml',
        'README.md',
      ]);
      expect(cursor(t), 'docs/');
      expect(t, styleAt(1, 2, hasAttr(Attr.bold)));
      expect(t, isNot(styleAt(1, 4, hasAttr(Attr.bold))));
      expect(focused(t), 'file picker field');
      // the field on the selection color while it has the focus; the
      // cursor idle, its bar muted, while the list has not
      const dark = ThemeData.dark;
      expect(t.cell(0, 0).bg, dark.selection.bg);
      expect(t.cell(1, 2).bg, dark.selectionIdle.bg);
      expect(t.cell(0, 2).fg, dark.muted.fg);
      expect(t, styleAt(0, 2, isNot(hasAttr(Attr.bold))));
      await press(t, 'tab');
      expect(focused(t), 'file picker list');
      expect(t.cell(0, 0).bg, dark.well.bg);
      expect(t.cell(1, 2).bg, dark.selection.bg);
      expect(t.cell(0, 2).fg, dark.primary.fg);
      expect(bottom(t), matches(RegExp(r'^\[ \] hidden +Open$')));
    });

    testTwk('shows the entries starting with a dot once Alt+H, hinted, or '
        'the check of hidden says so, and with showHidden from the '
        'first', (t) async {
      await start(t, picker());
      expect(hints(t), contains('alt+h hidden'));
      await press(t, 'alt+h');
      expect(rows(t), [
        '../',
        '.git/',
        'docs/',
        'src/',
        '.env',
        'notes.txt',
        'pubspec.yaml',
        'README.md',
      ]);
      expect(bottom(t), startsWith('[x] hidden'));
      await t.click(1, 11);
      await t.pump();
      expect(rows(t), isNot(contains('.env')));
      expect(bottom(t), startsWith('[ ] hidden'));
    });

    testTwk('shows them from the first with showHidden', (t) async {
      await start(t, picker(showHidden: true, directory: '$root/src'));
      expect(rows(t), [
        '../',
        'util/',
        '.secret.dart',
        'main.dart',
        'Model.dart',
      ]);
      expect(bottom(t), startsWith('[x] hidden'));
    });

    testTwk('a screen reader reads the field as a textbox named Path, the '
        'path in it as its value', (t) async {
      await start(t, picker());
      expect(t.binding.semantics.lines, contains('textbox Path: $root/'));
    });

    testTwk('lists the files the filter chosen accepts, by their extension '
        'in any case, the first filter at first, the directories all; a '
        'Select chooses another', (t) async {
      await start(
        t,
        picker(
          filters: const [
            FileFilter('Docs', ['md', 'TXT']),
            FileFilter('All files'),
          ],
        ),
      );
      expect(rows(t), ['../', 'docs/', 'src/', 'notes.txt', 'README.md']);
      expect(bottom(t), startsWith(' Docs'));
      await press(t, 'tab tab enter down enter');
      expect(rows(t), [
        '../',
        'docs/',
        'src/',
        'notes.txt',
        'pubspec.yaml',
        'README.md',
      ]);
      expect(bottom(t), startsWith(' All files'));
    });

    testTwk('a lone filter is not chosen from', (t) async {
      await start(
        t,
        picker(
          filters: const [
            FileFilter('YAML', ['yaml']),
          ],
        ),
      );
      expect(rows(t), ['../', 'docs/', 'src/', 'pubspec.yaml']);
      expect(bottom(t), startsWith('[ ] hidden'));
    });

    testTwk('bar, idleStyle and fieldFocusedStyle give a plain look', (
      t,
    ) async {
      const dark = ThemeData.dark;
      await start(
        t,
        Theme(
          data: dark,
          child: Overlay(
            child: FilePicker(
              onPicked: (_) {},
              directory: root,
              autofocus: true,
              bar: false,
              idleStyle: dark.selection,
              fieldFocusedStyle: const Style(),
            ),
          ),
        ),
      );
      expect(t.lines[2], startsWith('docs/'));
      expect(t.cell(0, 2).bg, dark.selection.bg);
      expect(t.cell(0, 0).bg, dark.well.bg);
    });

    testTwk('the directory mode lists no files, nor suggests them', (t) async {
      await start(t, picker(mode: FilePickerMode.directory));
      expect(rows(t), ['../', 'docs/', 'src/']);
      await type(t, 'n');
      await t.pump();
      expect(t.lines.where((line) => line.contains('notes.txt')), isEmpty);
    });

    testTwk('says why a directory cannot be listed, below ../', (t) async {
      await start(t, picker(directory: '$root/gone'));
      expect(rows(t), ['../', 'cannot list: No such file or directory']);
      expect(t.cell(1, 2).fg, ThemeData.dark.error.fg);
      await press(t, 'enter');
      await listed(t);
      expect(field(t), '$root/');
      expect(cursor(t), 'docs/');
    });

    testTwk('shows no ../ in the root', (t) async {
      await start(t, picker(directory: '/'));
      expect(field(t), '/');
      expect(rows(t), isNot(contains('../')));
      expect(cursor(t), rows(t).first);
    });
  });

  group('the keys of the list', () {
    testTwk('Up, Down, Page Up, Page Down, Home and End move the cursor; '
        'Enter, open hinted, and Right go into a directory, Left, parent '
        'hinted, and Backspace up, the cursor on the directory left', (
      t,
    ) async {
      final picked = <List<String>>[];
      await start(t, picker(picked: picked));
      await press(t, 'tab');
      expect(focused(t), 'file picker list');
      expect(hints(t), containsAll(['enter open', 'left parent']));
      await press(t, 'down');
      expect(cursor(t), 'src/');
      await press(t, 'end');
      expect(cursor(t), 'README.md');
      await press(t, 'home');
      expect(cursor(t), '../');
      await press(t, 'pagedown');
      expect(cursor(t), 'README.md');
      await press(t, 'pageup');
      expect(cursor(t), '../');
      await press(t, 'down down');
      expect(cursor(t), 'src/');
      await press(t, 'enter');
      await listed(t);
      expect(field(t), '$root/src/');
      expect(rows(t), ['../', 'util/', 'main.dart', 'Model.dart']);
      expect(cursor(t), 'util/');
      await press(t, 'right');
      await listed(t);
      expect(field(t), '$root/src/util/');
      expect(rows(t), ['../']);
      await press(t, 'left');
      await listed(t);
      expect(cursor(t), 'util/');
      await press(t, 'down right');
      expect(field(t), '$root/src/');
      expect(cursor(t), 'main.dart');
      expect(picked, isEmpty);
      await press(t, 'home enter');
      await listed(t);
      expect(field(t), '$root/');
      expect(cursor(t), 'src/');
      await press(t, 'enter');
      await listed(t);
      await press(t, 'backspace');
      await listed(t);
      expect(field(t), '$root/');
      expect(cursor(t), 'src/');
      await press(t, 'up up enter');
      await listed(t);
      expect(field(t), '${Directory(root).parent.path}/');
    });

    testTwk('Up, Down, Page Up and Page Down move the cursor from the '
        'field too; going into a directory keeps the name typed', (t) async {
      final files = _Counted();
      await start(t, picker(fileSystem: files));
      await type(t, 'gu');
      await press(t, 'down');
      expect(cursor(t), 'src/');
      expect(focused(t), 'file picker field');
      await press(t, 'up up');
      expect(cursor(t), '../');
      await press(t, 'pagedown');
      expect(cursor(t), 'README.md');
      await press(t, 'pageup down tab enter');
      await listed(t);
      expect(field(t), '$root/docs/gu');
      // what a listing for suggestions would bring has come, and would
      // have faded in (160 ms)
      await waitUntil(
        () => files.going == 0,
        'the listings to end',
        between: t.pump,
      );
      await t.pump(const Duration(milliseconds: 200));
      expect(suggestions(t), isEmpty);
    });

    testTwk('the list scrolls to show the cursor', (t) async {
      await t.pumpWidget(picker(), size: (columns, 6));
      await listed(t);
      expect(rows(t), ['../', 'docs/', 'src/', 'notes.txt']);
      await press(t, 'tab end');
      expect(rows(t), ['src/', 'notes.txt', 'pubspec.yaml', 'README.md']);
      expect(cursor(t), 'README.md');
    });

    testTwk('a press puts the cursor on an entry and gives the list the '
        'focus; a double click takes it', (t) async {
      final picked = <List<String>>[];
      await start(t, picker(picked: picked));
      await t.click(2, 5);
      await t.pump();
      expect(cursor(t), 'pubspec.yaml');
      expect(focused(t), 'file picker list');
      expect(picked, isEmpty);
      await t.click(2, 3);
      await t.click(2, 3);
      await t.pump();
      await listed(t);
      expect(field(t), '$root/src/');
      await t.click(2, 3);
      await t.click(2, 3);
      await t.pump();
      expect(picked, [
        ['$root/src/main.dart'],
      ]);
    });
  });

  group('the open mode', () {
    testTwk('Enter on a file picks it; Enter in the field with nothing '
        'named takes the entry under the cursor, as Open does', (t) async {
      final picked = <List<String>>[];
      await start(t, picker(picked: picked));
      await press(t, 'down down down enter');
      expect(picked, [
        ['$root/pubspec.yaml'],
      ]);
      await press(t, 'tab enter');
      expect(picked, hasLength(2));
      await press(t, 'up up up enter');
      await listed(t);
      expect(field(t), '$root/docs/');
      await t.click(columns - 2, 11);
      await t.pump();
      expect(picked.last, ['$root/docs/guide.md']);
    });

    testTwk('the field takes the path typed, relative to the directory '
        'shown, absolute, with . and ..: a file picked, a directory gone '
        'into; what is not there refused until the text is edited', (
      t,
    ) async {
      final picked = <List<String>>[];
      await start(t, picker(picked: picked));
      await clear(t);
      await type(t, 'src/../docs/./guide.md\r');
      expect(picked, [
        ['$root/docs/guide.md'],
      ]);
      await clear(t);
      await type(t, '$root/src\r');
      await listed(t);
      expect(field(t), '$root/src/');
      expect(rows(t), ['../', 'util/', 'main.dart', 'Model.dart']);
      await type(t, 'main.darts\r');
      expect(bottom(t), contains('not found'));
      expect(picked, hasLength(1));
      final x = bottom(t).indexOf('not found');
      expect(t.cell(x, 11).fg, ThemeData.dark.error.fg);
      await press(t, 'backspace');
      expect(bottom(t), isNot(contains('not found')));
      await press(t, 'enter');
      expect(picked.last, ['$root/src/main.dart']);
      await type(t, '/\r');
      expect(bottom(t), contains('not a directory'));
    });

    testTwk('~ is the home directory', (t) async {
      await start(t, picker());
      await clear(t);
      await type(t, '~\r');
      await listed(t);
      expect(field(t), '${Platform.environment['HOME']}/');
    });

    testTwk('with multiple, Space, hinted, marks the file under the cursor '
        'or unmarks it; the marks stay as the directory changes, counted; '
        'a file taken picks those marked, in the order they were', (
      t,
    ) async {
      final picked = <List<String>>[];
      await start(t, picker(picked: picked, multiple: true));
      expect(rows(t), [
        '    ../',
        '    docs/',
        '    src/',
        '[ ] notes.txt',
        '[ ] pubspec.yaml',
        '[ ] README.md',
      ]);
      await press(t, 'tab');
      expect(hints(t), contains('space mark'));
      await press(t, 'space');
      expect(rows(t)[1], '    docs/');
      expect(bottom(t), isNot(contains('marked')));
      await press(t, 'end space up up space');
      expect(rows(t).sublist(3), [
        '[x] notes.txt',
        '[ ] pubspec.yaml',
        '[x] README.md',
      ]);
      expect(bottom(t), contains('2 marked'));
      await press(t, 'space');
      expect(rows(t)[3], '[ ] notes.txt');
      expect(bottom(t), contains('1 marked'));
      await press(t, 'home down down enter');
      await listed(t);
      await press(t, 'down space');
      expect(bottom(t), contains('2 marked'));
      await press(t, 'up');
      expect(cursor(t), '    util/');
      await press(t, 'down down enter');
      expect(picked, [
        ['$root/README.md', '$root/src/main.dart'],
      ]);
      await press(t, 'shift+tab up up enter');
      expect(picked, hasLength(2));
      expect(picked.last, ['$root/README.md', '$root/src/main.dart']);
    });
  });

  group('the save mode', () {
    testTwk('picks a name not there yet in a directory that is, and a file '
        'that is; refuses one in a directory that is not; the name at '
        'first in the field', (t) async {
      final picked = <List<String>>[];
      await start(
        t,
        picker(picked: picked, mode: FilePickerMode.save, name: 'out.txt'),
      );
      expect(field(t), '$root/out.txt');
      expect(bottom(t), endsWith('Save'));
      await press(t, 'enter');
      expect(picked, [
        ['$root/out.txt'],
      ]);
      await clear(t);
      await type(t, 'missing/out.txt\r');
      expect(bottom(t), contains('no such directory'));
      await clear(t);
      await type(t, 'notes.txt\r');
      expect(picked.last, ['$root/notes.txt']);
      await clear(t);
      await type(t, 'new/\r');
      expect(bottom(t), contains('not found'));
      expect(picked, hasLength(2));
    });

    testTwk('what was refused is cleared once a file is picked from '
        'the list', (t) async {
      final picked = <List<String>>[];
      await start(t, picker(picked: picked, mode: FilePickerMode.save));
      await type(t, 'missing/out.txt\r');
      expect(bottom(t), contains('no such directory'));
      await press(t, 'tab end enter');
      expect(picked, [
        ['$root/README.md'],
      ]);
      expect(bottom(t), isNot(contains('no such directory')));
    });
  });

  group('the directory mode', () {
    testTwk('picks the directory shown when the field names no more, as '
        'Choose does; refuses a file', (t) async {
      final picked = <List<String>>[];
      await start(t, picker(picked: picked, mode: FilePickerMode.directory));
      expect(bottom(t), endsWith('Choose'));
      await press(t, 'tab down enter shift+tab');
      await listed(t);
      expect(field(t), '$root/src/');
      await press(t, 'enter');
      expect(picked, [
        ['$root/src'],
      ]);
      await type(t, 'main.dart\r');
      expect(bottom(t), contains('not a directory'));
      await clear(t);
      await type(t, '$root/docs/\r');
      await listed(t);
      await t.click(columns - 3, 11);
      await t.pump();
      expect(picked.last, ['$root/docs']);
    });
  });

  group('the path typed', () {
    testTwk('suggests the entries of the directory before it that start '
        'with the name after it, any case; Tab puts in their shared start; '
        'Enter on a directory goes into it', (t) async {
      await start(t, picker());
      await type(t, 's');
      expect(suggestions(t), ['src/']);
      await press(t, 'enter');
      await listed(t);
      expect(field(t), '$root/src/');
      expect(rows(t), ['../', 'util/', 'main.dart', 'Model.dart']);
      await type(t, 'M');
      expect(suggestions(t), ['main.dart', 'Model.dart']);
      await clear(t);
      await type(t, '../docs/g');
      await suggested(t, 'guide.md');
      expect(suggestions(t), ['guide.md', 'guidelines.md']);
      await press(t, 'tab');
      expect(field(t), '../docs/guide');
      await type(t, 'l');
      await suggested(t, 'guidelines.md');
      await press(t, 'tab');
      expect(field(t), '../docs/guidelines.md');
      expect(suggestions(t), isEmpty);
    });

    testTwk('suggests what is in another directory, those starting with a '
        'dot once the name does, the files the filter accepts, none while '
        'the name is empty or one in full', (t) async {
      await start(
        t,
        picker(
          filters: const [
            FileFilter('Dart', ['dart']),
          ],
        ),
      );
      await clear(t);
      await type(t, '$root/');
      expect(suggestions(t), isEmpty);
      await type(t, 'n');
      expect(suggestions(t), isEmpty);
      await clear(t);
      await type(t, 'src/.');
      await suggested(t, '.secret.dart');
      await clear(t);
      await type(t, 'src/util/../ma');
      await suggested(t, 'main.dart');
      await type(t, 'in.dart');
      await t.pump();
      expect(suggestions(t), isEmpty);
    });

    testTwk('lists a directory for suggestions again once another is gone '
        'into', (t) async {
      await start(t, picker());
      await clear(t);
      await type(t, 'src/m');
      await suggested(t, 'Model.dart');
      File('$root/src/mx.dart').writeAsStringSync('');
      await press(t, 'escape');
      await clear(t);
      await type(t, 'docs\r');
      await listed(t);
      await t.paste('../src/m');
      await suggested(t, 'mx.dart');
    });

    testTwk('the path the picker puts in is no step to undo, as it starts '
        'and as it goes into a directory: a KeyHintsBar hints Ctrl+Z once '
        'a character is typed', (t) async {
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: Overlay(
            child: Column(
              children: [
                Expanded(
                  child: FilePicker(
                    onPicked: (_) {},
                    directory: root,
                    name: 'new',
                    autofocus: true,
                  ),
                ),
                KeyHintsBar(keyLabel: (combo) => '$combo'),
              ],
            ),
          ),
        ),
        size: (columns, 12),
      );
      await listed(t);
      String bar() => t.lines.last;
      expect(field(t), '$root/new');
      expect(bar(), isNot(contains('ctrl+z')));
      await type(t, 'x');
      expect(bar(), contains('ctrl+z undo'));
      await press(t, 'ctrl+z');
      expect(field(t), '$root/new');
      expect(bar(), isNot(contains('ctrl+z')));
      await clear(t);
      await type(t, 'docs');
      await press(t, 'enter');
      await listed(t);
      expect(field(t), '$root/docs/');
      expect(bar(), isNot(contains('ctrl+z')));
    });
  });

  group('showFilePicker', () {
    testTwk('shows the picker in a dialog titled by its mode, the field '
        'focused; completes with the paths picked, or with null by Cancel '
        'and Escape', (t) async {
      final results = <List<String>?>[];
      await t.pumpWidget(
        Overlay(child: _Opener(results)),
        size: (dialogColumns + 30, 24),
      );
      await press(t, 'o');
      await opened(t);
      expect(t, containsLine(endsWith('  Open')));
      expect(focused(t), 'file picker field');
      expect(t, containsLine(endsWith('  $root/')));
      await press(t, 'down down enter');
      expect(results, [
        ['$root/notes.txt'],
      ]);
      expect(t, isNot(containsLine(contains('Open'))));
      await press(t, 'o');
      await opened(t);
      await press(t, 'escape');
      expect(results.last, isNull);
      await press(t, 's');
      await opened(t);
      expect(t, containsLine(endsWith('  Save as')));
      await press(t, 'shift+tab shift+tab enter');
      expect(results, hasLength(3));
      expect(results.last, isNull);
      expect(t, isNot(containsLine(contains('Save as'))));
      await press(t, 'd');
      await opened(t);
      expect(t, containsLine(endsWith('  Choose a directory')));
    });
  });
}

/// A tree that is on no disk: a home with a project in it, its working
/// directory the project.
final memory = PickerFileSystem.memory(
  [
    '/home/me/app/lib/main.dart',
    '/home/me/app/lib/src/',
    '/home/me/app/README.md',
    '/home/me/.profile',
    '/home/me/notes.txt',
    '/tmp/',
  ],
  currentDirectory: '/home/me/app',
  homeDirectory: '/home/me',
);

/// A [FilePicker] over [memory], its field focused, in an overlay in the
/// dark theme.
Widget memoryPicker({
  List<List<String>>? picked,
  FilePickerMode mode = FilePickerMode.open,
  String? directory,
}) => Theme(
  data: ThemeData.dark,
  child: Overlay(
    child: FilePicker(
      fileSystem: memory,
      onPicked: (paths) => picked?.add(paths),
      mode: mode,
      directory: directory,
      autofocus: true,
    ),
  ),
);

/// The tests over a file system of the app's own.
void memoryTests() {
  group('a file system of its own', () {
    test('a directory is every path above one, and one ending in a '
        'separator', () async {
      expect(memory.kindOf('/'), FileKind.directory);
      expect(memory.kindOf('/home/me/app/lib/src'), FileKind.directory);
      expect(memory.kindOf('/home/me/app/lib/src/'), FileKind.directory);
      expect(memory.kindOf('/home/me/notes.txt'), FileKind.file);
      expect(memory.kindOf('/home/me/none'), FileKind.none);
      expect(memory.kindOf('/home/me/notes.txt/x'), FileKind.none);
      expect(await memory.list('/home/me').toList(), [
        (path: '/home/me/app', isDirectory: true),
        (path: '/home/me/.profile', isDirectory: false),
        (path: '/home/me/notes.txt', isDirectory: false),
      ]);
      expect(await memory.list('/tmp').toList(), isEmpty);
      await expectLater(memory.list('/none').toList(), throwsA(anything));
      await expectLater(
        memory.list('/home/me/notes.txt').toList(),
        throwsA(anything),
      );
    });

    testTwk('lists its working directory, the picker given none', (t) async {
      await start(t, memoryPicker());
      expect(field(t), '/home/me/app/');
      expect(rows(t), ['../', 'lib/', 'README.md']);
    });

    testTwk('a directory given relative is below its working directory, '
        'and ~ is its home', (t) async {
      await start(t, memoryPicker(directory: 'lib'));
      expect(field(t), '/home/me/app/lib/');
      expect(rows(t), ['../', 'src/', 'main.dart']);
      await clear(t);
      await type(t, '~\r');
      await listed(t);
      expect(field(t), '/home/me/');
      expect(rows(t), ['../', 'app/', 'notes.txt']);
    });

    testTwk('a file typed is picked, one not there refused, and a new name '
        'saved in a directory that is', (t) async {
      final picked = <List<String>>[];
      await start(t, memoryPicker(picked: picked));
      await type(t, 'lib/main.dart\r');
      expect(picked.last, ['/home/me/app/lib/main.dart']);
      await clear(t);
      await type(t, '/home/me/app/none.dart\r');
      expect(bottom(t), contains('not found'));
      await t.pumpWidget(
        memoryPicker(picked: picked, mode: FilePickerMode.save),
      );
      await listed(t);
      await clear(t);
      await type(t, '/tmp/new.txt\r');
      expect(picked.last, ['/tmp/new.txt']);
    });

    testTwk('says why a directory cannot be listed', (t) async {
      await start(t, memoryPicker(directory: '/home/me/gone'));
      expect(rows(t), ['../', 'cannot list: no such directory']);
    });

    test('without a working directory, a tree is in the root', () {
      final tree = PickerFileSystem.memory(['/srv/www/index.html']);
      expect(tree.currentDirectory, '/');
      expect(tree.homeDirectory, isNull);
    });

    testTwk('given another file system, lists the directory shown from it', (
      t,
    ) async {
      Widget over(PickerFileSystem files) => Theme(
        data: ThemeData.dark,
        child: Overlay(
          child: FilePicker(
            fileSystem: files,
            directory: '/home/me',
            onPicked: (_) {},
          ),
        ),
      );
      await start(t, over(memory));
      expect(rows(t), ['../', 'app/', 'notes.txt']);
      await t.pumpWidget(
        over(PickerFileSystem.memory(['/home/me/todo.md'])),
      );
      await listed(t);
      expect(field(t), '/home/me/');
      expect(rows(t), ['../', 'todo.md']);
    });
  });
}

/// The width of the dialog the `o` of the opener below opens: enough for
/// its field to show [root] whole, 50 at the least.
int get dialogColumns => max(50, root.length + 20);

/// Opens a picker of [root] by `o`, a save one by `s`, one of a directory
/// by `d`; [results] gets
/// what each completes with.
final class _Opener extends StatelessWidget {
  const _Opener(this.results);

  final List<List<String>?> results;

  @override
  Widget build(BuildContext context) => KeyBindings({
    'o': () => showFilePicker(
      context,
      directory: root,
      width: dialogColumns,
      height: 10,
    ).then(results.add),
    's': () => showFilePicker(
      context,
      mode: FilePickerMode.save,
      directory: root,
    ).then(results.add),
    'd': () => showFilePicker(
      context,
      mode: FilePickerMode.directory,
      directory: root,
    ).then(results.add),
  }, child: const Focus(autofocus: true, child: Text('app')));
}
