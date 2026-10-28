// A DirectoryTree over an InMemoryFileSystem: the root expanded as it
// starts, each directory listed only as it is expanded, the directories
// first, by name in any case; hidden entries, those the nested .gitignore
// files ignore and .git left out, files a filter refuses; sizes and icons;
// an unreadable directory's note; the watch listing a directory again a
// tenth of a second after it changes, the selection and what is expanded
// kept, a collapsed one no longer listed; the controller revealing a
// path, expanding, collapsing and listing again; Enter and a double click
// opening a file and toggling a directory.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [files], counting the listings of each directory.
final class Counting extends PickerFileSystem {
  Counting(this.files);

  final PickerFileSystem files;
  final listed = <String, int>{};

  @override
  String get currentDirectory => files.currentDirectory;

  @override
  String? get homeDirectory => files.homeDirectory;

  @override
  Stream<DirectoryEntry> list(String directory) {
    listed.update(directory, (n) => n + 1, ifAbsent: () => 1);
    return files.list(directory);
  }

  @override
  FileKind kindOf(String path) => files.kindOf(path);

  @override
  Future<String> read(String file) => files.read(file);

  @override
  Future<int?> sizeOf(String file) => files.sizeOf(file);

  @override
  Stream<void> watch(String directory) => files.watch(directory);
}

/// A project: sources, tests, what its .gitignore ignores, hidden files.
InMemoryFileSystem project() => InMemoryFileSystem(
  [
    '/app/lib/src/table.dart',
    '/app/lib/Button.dart',
    '/app/lib/about.md',
    '/app/test/table_test.dart',
    '/app/build/out.o',
    '/app/.git/HEAD',
    '/app/.env',
    '/app/run.log',
    '/app/README.md',
    '/app/analysis.yaml',
  ],
  contents: {'/app/.gitignore': 'build/\n*.log\n'},
);

/// The tree's rows, a frame of a spinner in them as `@`.
List<String> rows(TwkTester t) => [
  for (final line in t.lines)
    SpinnerFrames.dots.frames.fold(line, (l, f) => l.replaceAll(f, '@')),
];

void main() {
  group('listing', () {
    testTwk('the root shows expanded, its directories first, then its files, '
        'each by name in any case', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(root: '/app', fileSystem: project()),
        ),
        size: (24, 7),
      );
      await t.pump();
      expect(rows(t), [
        '▾ app/',
        '  ▸ lib/',
        '  ▸ test/',
        '    analysis.yaml',
        '    README.md',
        '',
        '',
      ]);
    });

    testTwk('a directory is listed as it is first expanded, a spinner below '
        'it meanwhile, and not again while it stays expanded', (t) async {
      final files = Counting(project());
      final controller = DirectoryTreeController();
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: files,
            controller: controller,
          ),
        ),
        size: (24, 8),
      );
      await t.pump();
      expect(files.listed, {'/app': 1});
      controller.expand('lib');
      await t.pump(Duration.zero);
      expect(rows(t).sublist(0, 3), ['▾ app/', '  ▾ lib/', '    @']);
      await t.pump();
      expect(rows(t).sublist(0, 6), [
        '▾ app/',
        '  ▾ lib/',
        '    ▸ src/',
        '      about.md',
        '      Button.dart',
        '  ▸ test/',
      ]);
      await t.press('down');
      await t.pump();
      expect(files.listed, {'/app': 1, '/app/lib': 1});
    });

    testTwk('a relative root is under the current directory, ~ the home '
        'directory', (t) async {
      final files = InMemoryFileSystem(
        ['/home/me/notes/todo.md'],
        currentDirectory: '/home',
        homeDirectory: '/home/me',
      );
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            children: [
              Expanded(
                child: DirectoryTree(root: 'me', fileSystem: files),
              ),
              Expanded(
                child: DirectoryTree(root: '~/notes', fileSystem: files),
              ),
            ],
          ),
        ),
        size: (20, 6),
      );
      await t.pump();
      expect(rows(t), [
        '▾ me/',
        '  ▸ notes/',
        '',
        '▾ notes/',
        '    todo.md',
        '',
      ]);
    });
  });

  group('what shows', () {
    testTwk('hidden entries, what .gitignore ignores and .git show neither '
        'by default; showHidden shows the hidden but .git', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: project(),
            showHidden: true,
          ),
        ),
        size: (24, 8),
      );
      await t.pump();
      expect(rows(t), [
        '▾ app/',
        '  ▸ lib/',
        '  ▸ test/',
        '    .env',
        '    .gitignore',
        '    analysis.yaml',
        '    README.md',
        '',
      ]);
    });

    testTwk('without gitignore, the ignored entries and .git show', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: project(),
            showHidden: true,
            gitignore: false,
          ),
        ),
        size: (24, 11),
      );
      await t.pump();
      expect(rows(t), [
        '▾ app/',
        '  ▸ .git/',
        '  ▸ build/',
        '  ▸ lib/',
        '  ▸ test/',
        '    .env',
        '    .gitignore',
        '    analysis.yaml',
        '    README.md',
        '    run.log',
        '',
      ]);
    });

    testTwk('a .gitignore deeper down decides before one above it, of the '
        'paths below its own directory', (t) async {
      final files = InMemoryFileSystem(
        ['/app/lib/debug.log', '/app/lib/gen/a.g.dart', '/app/lib/a.dart'],
        contents: {
          '/app/.gitignore': '*.log\ngen/\n',
          '/app/lib/.gitignore': '!debug.log\n*.dart\n',
          '/app/lib/gen/.gitignore': '!*.dart\n',
        },
      );
      final controller = DirectoryTreeController()..expand('/app/lib');
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: files,
            controller: controller,
          ),
        ),
        size: (20, 4),
      );
      await t.pump();
      await t.pump();
      expect(rows(t), ['▾ app/', '  ▾ lib/', '      debug.log', '']);
    });

    testTwk('a filter shows the files it accepts, and every directory', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app/lib',
            fileSystem: project(),
            filter: const FileFilter('Dart', ['dart']),
          ),
        ),
        size: (20, 4),
      );
      await t.pump();
      expect(rows(t), ['▾ lib/', '  ▸ src/', '    Button.dart', '']);
    });

    testTwk("showSizes puts each file's size at the end of its row, in "
        'decimal units as a ProgressList writes bytes; icon what goes before '
        'a name', (t) async {
      final files = InMemoryFileSystem(
        ['/p/src/'],
        contents: {'/p/a.txt': 'x' * 4096, '/p/b.txt': 'hi'},
      );
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/p',
            fileSystem: files,
            showSizes: true,
            icon: (entry) => entry.isDirectory ? 'D' : null,
          ),
        ),
        size: (22, 5),
      );
      await t.pump();
      expect(rows(t), [
        '▾ D p/',
        '  ▸ D src/',
        '    a.txt       4.1 kB',
        '    b.txt          2 B',
        '',
      ]);
    });

    testTwk('a directory that does not list shows why below it, muted', (
      t,
    ) async {
      final files = InMemoryFileSystem(
        ['/app/a.txt'],
        unreadable: ['/app/secret'],
      );
      final controller = DirectoryTreeController()..expand('/app/secret');
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: files,
            controller: controller,
          ),
        ),
        size: (26, 4),
      );
      await t.pump();
      await t.pump();
      expect(rows(t), [
        '▾ app/',
        '  ▾ secret/',
        '      (permission denied)',
        '    a.txt',
      ]);
      expect(t.cell(6, 2), hasFg(const Color.indexed(245)));
    });
  });

  group('watch', () {
    testTwk('a directory expanded is listed again a tenth of a second after '
        'it changes, the changes in between with it', (t) async {
      final files = Counting(project());
      final memory = files.files as InMemoryFileSystem;
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(root: '/app', fileSystem: files),
        ),
        size: (24, 6),
      );
      await t.pump();
      memory
        ..write('/app/CHANGELOG.md', '')
        ..remove('/app/analysis.yaml');
      await t.pump(const Duration(milliseconds: 50));
      expect(rows(t)[3], '    analysis.yaml');
      await t.pump(const Duration(milliseconds: 60));
      await t.pump();
      expect(rows(t), [
        '▾ app/',
        '  ▸ lib/',
        '  ▸ test/',
        '    CHANGELOG.md',
        '    README.md',
        '',
      ]);
      expect(files.listed['/app'], 2);
    });

    testTwk('listed again, the selection and what is expanded stay, and no '
        'spinner shows', (t) async {
      final files = project();
      final controller = DirectoryTreeController()..expand('/app/lib');
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: files,
            controller: controller,
            autofocus: true,
          ),
        ),
        size: (24, 9),
      );
      await t.pump();
      await t.pump();
      await controller.reveal('/app/lib/Button.dart');
      files.write('/app/lib/Aardvark.dart', '');
      await t.pump(const Duration(milliseconds: 90));
      expect(rows(t).sublist(0, 6), [
        '▾ app/',
        '  ▾ lib/',
        '    ▸ src/',
        '      about.md',
        '      Button.dart',
        '  ▸ test/',
      ]);
      await t.pump(const Duration(milliseconds: 10));
      expect(rows(t).sublist(0, 7), [
        '▾ app/',
        '  ▾ lib/',
        '    ▸ src/',
        '      Aardvark.dart',
        '      about.md',
        '      Button.dart',
        '  ▸ test/',
      ]);
      expect(controller.selected, '/app/lib/Button.dart');
      expect(controller.isExpanded('/app/lib'), isTrue);
    });

    testTwk('a change to a .gitignore shows what it ignores no longer, '
        'below it too', (t) async {
      final files = project();
      final controller = DirectoryTreeController()..expand('/app/lib');
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: files,
            controller: controller,
          ),
        ),
        size: (24, 6),
      );
      await t.pump();
      await t.pump();
      expect(rows(t)[4], '      Button.dart');
      files.write('/app/.gitignore', 'build/\n*.log\n*.dart\ntest/\n');
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      expect(rows(t), [
        '▾ app/',
        '  ▾ lib/',
        '    ▸ src/',
        '      about.md',
        '    analysis.yaml',
        '    README.md',
      ]);
    });

    testTwk('a directory collapsed is no longer watched; expanded again, it '
        'is listed again', (t) async {
      final files = Counting(project());
      final memory = files.files as InMemoryFileSystem;
      final controller = DirectoryTreeController()..expand('/app/lib');
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: files,
            controller: controller,
          ),
        ),
        size: (24, 8),
      );
      await t.pump();
      await t.pump();
      controller.collapse('/app/lib');
      memory.write('/app/lib/new.dart', '');
      await t.pump(const Duration(milliseconds: 200));
      expect(files.listed['/app/lib'], 1);
      controller.expand('/app/lib');
      await t.pump();
      await t.pump();
      expect(files.listed['/app/lib'], 2);
      expect(rows(t)[5], '      new.dart');
    });

    testTwk('without watch, a change shows once the controller refreshes', (
      t,
    ) async {
      final files = project();
      final controller = DirectoryTreeController();
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: files,
            controller: controller,
            watch: false,
          ),
        ),
        size: (24, 6),
      );
      await t.pump();
      files.remove('/app/README.md');
      await t.pump(const Duration(milliseconds: 200));
      expect(rows(t)[4], '    README.md');
      await controller.refresh('/app');
      await t.pump();
      expect(rows(t)[4], '');
    });
  });

  group('controller', () {
    testTwk('reveal expands the directories down to a path, each listed in '
        'turn, and selects it; onSelected is called', (t) async {
      final selected = <String>[];
      final controller = DirectoryTreeController();
      final told = <String?>[];
      controller.addListener(() => told.add(controller.selected));
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: project(),
            controller: controller,
            onSelected: selected.add,
          ),
        ),
        size: (24, 8),
      );
      await t.pump();
      await controller.reveal('lib/src/table.dart');
      await t.pump();
      expect(rows(t).sublist(0, 5), [
        '▾ app/',
        '  ▾ lib/',
        '    ▾ src/',
        '        table.dart',
        '      about.md',
      ]);
      expect(controller.selected, '/app/lib/src/table.dart');
      expect(selected, ['/app/lib/src/table.dart']);
      expect(told.last, '/app/lib/src/table.dart');
      expect(controller.isExpanded('/app/lib/src'), isTrue);
    });

    testTwk('a path revealed before a tree has the controller is revealed '
        'as the tree starts; expand works before it too', (t) async {
      final controller = DirectoryTreeController()..expand('/app/test');
      unawaited(controller.reveal('/app/lib/about.md'));
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: project(),
            controller: controller,
          ),
        ),
        size: (24, 8),
      );
      await t.pump();
      await t.pump();
      expect(rows(t).sublist(0, 7), [
        '▾ app/',
        '  ▾ lib/',
        '    ▸ src/',
        '      about.md',
        '      Button.dart',
        '  ▾ test/',
        '      table_test.dart',
      ]);
      expect(controller.selected, '/app/lib/about.md');
    });

    testTwk('a path outside the root reveals nothing', (t) async {
      final controller = DirectoryTreeController();
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app/lib',
            fileSystem: project(),
            controller: controller,
          ),
        ),
        size: (24, 4),
      );
      await t.pump();
      await controller.reveal('/app/test/table_test.dart');
      expect(controller.selected, isNull);
      expect(controller.isExpanded('/app/test'), isFalse);
    });

    testTwk('collapse hides the entries of a directory', (t) async {
      final controller = DirectoryTreeController();
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: project(),
            controller: controller,
          ),
        ),
        size: (24, 3),
      );
      await t.pump();
      controller.collapse('/app');
      await t.pump();
      expect(rows(t), ['▸ app/', '', '']);
    });
  });

  group('opening', () {
    testTwk('Enter opens the file selected, and expands or collapses the '
        'directory selected', (t) async {
      final opened = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: project(),
            onOpened: opened.add,
            autofocus: true,
          ),
        ),
        size: (24, 8),
      );
      await t.pump();
      await t.press('down');
      await t.press('down');
      await t.press('enter');
      await t.pump();
      await t.pump();
      expect(rows(t)[1], '  ▾ lib/');
      await t.press('enter');
      await t.pump();
      expect(rows(t)[1], '  ▸ lib/');
      await t.press('end');
      await t.press('enter');
      await t.pump();
      expect(opened, ['/app/README.md']);
    });

    testTwk('a double click opens a file and toggles a directory', (t) async {
      final opened = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: DirectoryTree(
            root: '/app',
            fileSystem: project(),
            onOpened: opened.add,
          ),
        ),
        size: (24, 8),
      );
      await t.pump();
      await t.click(6, 4);
      await t.click(6, 4);
      await t.pump();
      expect(opened, ['/app/README.md']);
      await t.click(6, 1);
      await t.click(6, 1);
      await t.pump();
      await t.pump();
      expect(rows(t)[1], '  ▾ lib/');
    });
  });
}
