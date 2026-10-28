// Diff.between: the hunks of the changes between two texts, their context
// and line numbers; Diff.parse: the files, headers, paths and hunks of a
// unified diff as git and diff -u write it; and its lines as values.
//
// test/diff/fixtures/git_diff.ansi is `git diff --cached --color=always` in
// a scratch repository, git_diff.diff the same with --no-color: tabs, white
// space at the ends of lines that git marks, CRLF line breaks, carriage
// returns within a line, wide characters, a hunk with a section, a file
// added, one deleted and one renamed.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

/// [file]'s hunks as a unified diff writes them, without the headers.
List<String> hunks(FileDiff file) => [
  for (final hunk in file.hunks) ...[
    [
      '@@ -${hunk.oldStart},${hunk.oldCount}',
      '+${hunk.newStart},${hunk.newCount} @@',
      if (hunk.section.isNotEmpty) hunk.section,
    ].join(' '),
    for (final line in hunk.lines) '${signs[line.kind]}${line.text}',
  ],
];

const Map<DiffLineKind, String> signs = {
  DiffLineKind.context: ' ',
  DiffLineKind.removed: '-',
  DiffLineKind.added: '+',
};

/// The numbers of [file]'s lines, old and new: `3 4`, `3 -`, `- 4`.
List<String> numbers(FileDiff file) => [
  for (final hunk in file.hunks)
    for (final line in hunk.lines)
      '${line.oldNumber ?? '-'} ${line.newNumber ?? '-'}',
];

/// What [diff] holds, to compare diffs by: each file's paths, headers and
/// hunks.
List<Object?> contents(Diff diff) => [
  for (final file in diff.files) ...[
    file.oldPath,
    file.newPath,
    ...file.headers,
    for (final hunk in file.hunks) ...[
      (hunk.oldStart, hunk.oldCount, hunk.newStart, hunk.newCount),
      hunk.section,
      ...hunk.lines,
    ],
  ],
];

/// The text of fixture [name].
String fixture(String name) =>
    File('test/diff/fixtures/$name').readAsStringSync();

/// Lines `1` to [count], a line break after each.
String lines(int count, [Map<int, String> replaced = const {}]) => [
  for (var i = 1; i <= count; i++) '${replaced[i] ?? '$i'}\n',
].join();

void main() {
  group('Diff.between', () {
    test('finds no hunk between texts that are equal', () {
      final diff = Diff.between('a\nb\n', 'a\nb\n');
      expect(diff.files, hasLength(1));
      expect(diff.files.single.hunks, isEmpty);
    });

    test('makes a hunk of a change and the lines around it', () {
      final file = Diff.between(
        lines(9, {5: 'five'}),
        lines(9, {5: 'FIVE'}),
      ).files.single;
      expect(hunks(file), [
        '@@ -2,7 +2,7 @@',
        ' 2',
        ' 3',
        ' 4',
        '-five',
        '+FIVE',
        ' 6',
        ' 7',
        ' 8',
      ]);
      expect(numbers(file), [
        '2 2',
        '3 3',
        '4 4',
        '5 -',
        '- 5',
        '6 6',
        '7 7',
        '8 8',
      ]);
    });

    test('makes one hunk of changes up to twice the context apart', () {
      final before = lines(20);
      final apart = lines(20, {4: 'x', 10: 'y'});
      final close = lines(20, {4: 'x', 9: 'y'});
      expect(hunks(Diff.between(before, apart, context: 2).files.single), [
        '@@ -2,5 +2,5 @@',
        ' 2',
        ' 3',
        '-4',
        '+x',
        ' 5',
        ' 6',
        '@@ -8,5 +8,5 @@',
        ' 8',
        ' 9',
        '-10',
        '+y',
        ' 11',
        ' 12',
      ]);
      expect(hunks(Diff.between(before, close, context: 2).files.single), [
        '@@ -2,10 +2,10 @@',
        ' 2',
        ' 3',
        '-4',
        '+x',
        ' 5',
        ' 6',
        ' 7',
        ' 8',
        '-9',
        '+y',
        ' 10',
        ' 11',
      ]);
    });

    test('counts the lines added and removed on each side', () {
      final file = Diff.between(
        'a\nb\nc\nd\n',
        'a\nc\nx\ny\nd\n',
        context: 0,
      ).files.single;
      expect(hunks(file), [
        '@@ -2,1 +1,0 @@',
        '-b',
        '@@ -3,0 +3,2 @@',
        '+x',
        '+y',
      ]);
      expect(numbers(file), ['2 -', '- 3', '- 4']);
    });

    test('takes a final line break as the end of the last line, and '
        'carriage returns as part of line breaks', () {
      final file = Diff.between('', 'a\r\nb\r\n', path: 'x.txt').files.single;
      expect(hunks(file), ['@@ -0,0 +1,2 @@', '+a', '+b']);
      expect(file.oldLines, isEmpty);
      expect(file.newLines, ['a', 'b']);
      expect(
        (file.oldPath, file.newPath, file.path),
        (
          'x.txt',
          'x.txt',
          'x.txt',
        ),
      );
      expect(Diff.between('a', 'a\n').files.single.hunks, isEmpty);
    });
  });

  group('Diff.parse', () {
    const gitDiff = r'''
commit 0123456789abcdef
Author: A <a@example.com>

    Change things

diff --git a/lib/a.dart b/lib/a.dart
index 1111111..2222222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,4 +1,4 @@
 void main() {
-  print('hello');
+  print('hi');
   return;
 }
@@ -10,2 +10,3 @@ void other() {
 a();
+b();

diff --git a/old name.txt b/new name.txt
similarity index 100%
rename from old name.txt
rename to new name.txt
diff --git a/added.sh b/added.sh
new file mode 100755
index 0000000..3333333
--- /dev/null
+++ b/added.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+--- echo
\ No newline at end of file
diff --git a/gone.txt b/gone.txt
deleted file mode 100644
--- a/gone.txt
+++ /dev/null
@@ -1 +0,0 @@
--- gone
''';

    test('reads the files of a git diff, their paths and headers', () {
      final files = Diff.parse(gitDiff).files;
      expect(
        [for (final f in files) (f.oldPath, f.newPath)],
        [
          ('lib/a.dart', 'lib/a.dart'),
          ('old name.txt', 'new name.txt'),
          (null, 'added.sh'),
          ('gone.txt', null),
        ],
      );
      expect(files.map((f) => f.path), [
        'lib/a.dart',
        'new name.txt',
        'added.sh',
        'gone.txt',
      ]);
      expect(files[0].headers, [
        'diff --git a/lib/a.dart b/lib/a.dart',
        'index 1111111..2222222 100644',
        '--- a/lib/a.dart',
        '+++ b/lib/a.dart',
      ]);
      expect(files[1].headers, hasLength(4));
      expect(files[1].hunks, isEmpty);
      expect(files.map((f) => f.oldLines), everyElement(isNull));
    });

    test('reads the hunks of a git diff: lines that look like headers by '
        'the counts, an empty line as context, no marker of a missing '
        'newline', () {
      final files = Diff.parse(gitDiff).files;
      expect(hunks(files[0]), [
        '@@ -1,4 +1,4 @@',
        ' void main() {',
        "-  print('hello');",
        "+  print('hi');",
        '   return;',
        ' }',
        '@@ -10,2 +10,3 @@ void other() {',
        ' a();',
        '+b();',
        ' ',
      ]);
      expect(numbers(files[0]), [
        '1 1',
        '2 -',
        '- 2',
        '3 3',
        '4 4',
        '10 10',
        '- 11',
        '11 12',
      ]);
      expect(hunks(files[2]), ['@@ -0,0 +1,2 @@', '+#!/bin/sh', '+--- echo']);
      expect(hunks(files[3]), ['@@ -1,1 +0,0 @@', '--- gone']);
      expect(numbers(files[3]), ['1 -']);
    });

    test('reads a diff -u: paths without the time, line breaks with '
        'carriage returns', () {
      const text =
          '--- old/x.txt\t2026-10-19 10:00:00.000000000 +0200\r\n'
          '+++ new/x.txt\t2026-10-19 11:00:00.000000000 +0200\r\n'
          '@@ -1 +1 @@\r\n'
          '-one\r\n'
          '+two\r\n'
          '--- y.txt\n'
          '+++ y.txt\n'
          '@@ -3,0 +4 @@\n'
          '+four\n';
      final files = Diff.parse(text).files;
      expect(
        [for (final f in files) (f.oldPath, f.newPath)],
        [
          ('old/x.txt', 'new/x.txt'),
          ('y.txt', 'y.txt'),
        ],
      );
      expect(hunks(files[0]), ['@@ -1,1 +1,1 @@', '-one', '+two']);
      expect(hunks(files[1]), ['@@ -3,0 +4,1 @@', '+four']);
      expect(numbers(files[1]), ['- 4']);
    });

    test('reads nothing from text with no diff in it', () {
      expect(Diff.parse('').files, isEmpty);
      expect(Diff.parse('hello\nworld\n').files, isEmpty);
    });

    test("reads git's coloured output, its colours taken off by stripAnsi, "
        'as its plain twin, tabs and carriage returns kept', () {
      final coloured = Diff.parse(stripAnsi(fixture('git_diff.ansi')));
      final plain = Diff.parse(fixture('git_diff.diff'));
      expect(plain.files.map((f) => f.path), [
        'main.c',
        'names.txt',
        'new.txt',
        'old.txt',
        'progress.log',
        'renamed.txt',
      ]);
      expect(contents(coloured), contents(plain));
      expect(
        [
          for (final file in coloured.files)
            for (final hunk in file.hunks) ...hunk.lines.map((l) => l.text),
        ],
        containsAll([
          '\tint n = 4;\t/* four */  ',
          '\treturn x\t* 2;\t',
          'список 日本語 🙂',
          '10%\r50%\r75%\r100%',
          '\tbrand new\twith tabs',
        ]),
      );
      expect(coloured.files.first.hunks.last.section, 'int main(void)');
    });

    test('takes escape sequences as part of the lines they are in', () {
      final file = Diff.parse(
        '@@ -1 +1 @@\n-\x1B[31mred\x1B[m\n+red\n',
      ).files.single;
      expect(hunks(file), ['@@ -1,1 +1,1 @@', '-\x1B[31mred\x1B[m', '+red']);
    });
  });

  test('lines are equal by kind, text and numbers, hash alike and show '
      'them', () {
    DiffLine removed(String text, int number) =>
        DiffLine(DiffLineKind.removed, text, oldNumber: number);
    expect(removed('a', 3), removed('a', 3));
    expect(removed('a', 3).hashCode, removed('a', 3).hashCode);
    expect(removed('a', 3), isNot(removed('a', 4)));
    expect(removed('a', 3), isNot(removed('b', 3)));
    expect(
      removed('a', 3),
      isNot(const DiffLine(DiffLineKind.added, 'a', oldNumber: 3)),
    );
    expect('${removed('a', 3)}', 'DiffLine(removed, 3, null, "a")');
  });
}
