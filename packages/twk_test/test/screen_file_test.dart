// matchesScreenFile: the file it writes, what it matches, and the message
// it fails with.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/src/screen_file.dart';
import 'package:twk_test/twk_test.dart';

/// The lines of the message [matcher] fails with on [actual].
List<String> failure(Object? actual, Matcher matcher) {
  try {
    expect(actual, matcher);
  } on TestFailure catch (e) {
    return e.message!.split('\n');
  }
  fail('it matched');
}

/// A bold word and plain text over a line in red on an RGB background
/// with a `[` and a wide glyph.
Widget form({Color fg = Color.red}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text.rich(['sent:'.bold, const Span(' привет')]),
    Text(
      '[x] 界',
      style: Style(fg: fg, bg: const Color.rgb(1, 2, 3)),
    ),
  ],
);

/// [form]'s screen on 14 × 3, as the file holds it.
const formFile = '''
screen 14×3, cursor hidden
text
│sent: привет  │
│[x] 界        │
│              │
styles
│aaaaa         │
│bbbcbb        │
│              │
legend
a bold
b red on #010203
c on #010203
''';

/// How a failure says the file is written.
const _update = 'TWK_UPDATE_GOLDENS=1 writes';

/// What the lines of a failed match are.
const _legend = '(- the file, + the screen; $_update the screen to it):';

void main() {
  callerFileTests();
  fromPackageRootTests();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('screen_file_'));
  tearDown(() {
    updateScreenFilesOverride = null;
    dir.deleteSync(recursive: true);
  });

  testTwk('writes the screen to the file while updating, making its '
      'directories, and matches', (t) async {
    await t.pumpWidget(form(), size: (14, 3));
    final path = '${dir.path}/a/b/form.txt';
    updateScreenFilesOverride = true;
    expect(t, matchesScreenFile(path));
    expect(File(path).readAsStringSync(), formFile);
    updateScreenFilesOverride = false;
    expect(t, matchesScreenFile(path));
  });

  testTwk('matches the screen the file holds, whatever characters its '
      'legend gives the styles', (t) async {
    await t.pumpWidget(form(), size: (14, 3));
    final path = '${dir.path}/form.txt';
    File(path).writeAsStringSync(
      formFile.replaceAll('aaaaa ', 'zzzzz ').replaceAll('a bold', 'z bold'),
    );
    expect(t, matchesScreenFile(path));
  });

  testTwk('a cursor shown is in the header', (t) async {
    await t.pumpWidget(
      const SizedBox(width: 10, child: TextField(autofocus: true)),
      size: (10, 1),
    );
    await t.type('ab');
    await t.pump();
    final path = '${dir.path}/field.txt';
    updateScreenFilesOverride = true;
    expect(t, matchesScreenFile(path));
    expect(
      File(path).readAsLinesSync().first,
      'screen 10×1, cursor at 2,0',
    );
  });

  testTwk('a hyperlink is in the style', (t) async {
    await t.pumpWidget(
      const Text('docs', style: Style(link: 'https://dart.dev')),
      size: (4, 1),
    );
    final path = '${dir.path}/link.txt';
    updateScreenFilesOverride = true;
    expect(t, matchesScreenFile(path));
    expect(File(path).readAsLinesSync().last, 'a link=https://dart.dev');
  });

  testTwk('written again, the styles keep their characters and a new one '
      'takes one the file had not given', (t) async {
    final path = '${dir.path}/form.txt';
    File(path).writeAsStringSync(
      formFile
          .replaceFirst('aaaaa ', 'bbbbb ')
          .replaceFirst('bbbcbb', 'aaaxaa')
          .replaceFirst(
            'a bold\nb red on #010203\nc on',
            'b bold\na red on #010203\nx on',
          ),
    );
    await t.pumpWidget(form(fg: Color.green), size: (14, 3));
    updateScreenFilesOverride = true;
    expect(t, matchesScreenFile(path));
    final lines = File(path).readAsLinesSync();
    expect(lines.sublist(6, 8), ['│bbbbb         │', '│cccxcc        │']);
    expect(lines.sublist(10), ['b bold', 'c green on #010203', 'x on #010203']);
  });

  testTwk('fails on a missing file, saying how to write it', (t) async {
    await t.pumpWidget(form(), size: (14, 3));
    final path = '${dir.path}/none.txt';
    expect(failure(t, matchesScreenFile(path)).take(3), [
      'Expected: the screen of $path',
      '  Actual: TwkTester:<fullscreen, 14×3>',
      '   Which: $path does not exist; $_update the screen to it',
    ]);
  });

  testTwk('fails on a file that is not one, naming what is wrong', (t) async {
    await t.pumpWidget(form(), size: (14, 3));
    final path = '${dir.path}/bad.txt';
    File(path).writeAsStringSync(formFile.replaceFirst('│[x] 界', '[x] 界'));
    expect(
      failure(t, matchesScreenFile(path))[2],
      '   Which: $path is not a screen file: line 4 is not a row in │…│',
    );
  });

  testTwk('fails with the rows whose text differs, and the cells whose '
      'style does, the file first', (t) async {
    await t.pumpWidget(form(fg: Color.green), size: (14, 3));
    final path = '${dir.path}/form.txt';
    File(path).writeAsStringSync(formFile.replaceFirst('привет', 'привед'));
    expect(failure(t, matchesScreenFile(path)).sublist(2, 15), [
      '   Which: differs from $path $_legend',
      '          text:',
      '          - 0│sent: привед  │',
      '          + 0│sent: привет  │',
      '          styles:',
      '          - 1│bbbcbb        │',
      '          + 1│???c??        │',
      '          the first cells whose style differs:',
      '            (0, 1): - red on #010203, + green on #010203',
      '            (1, 1): - red on #010203, + green on #010203',
      '            (2, 1): - red on #010203, + green on #010203',
      '            (4, 1): - red on #010203, + green on #010203',
      '            (5, 1): - red on #010203, + green on #010203',
    ]);
  });

  testTwk('styles: false compares the text alone, and fails on a text '
      'that differs', (t) async {
    await t.pumpWidget(form(fg: Color.green), size: (14, 3));
    final path = '${dir.path}/form.txt';
    File(path).writeAsStringSync(formFile);
    expect(t, matchesScreenFile(path, styles: false));
    expect(failure(t, matchesScreenFile(path)).length, greaterThan(3));
    File(path).writeAsStringSync(formFile.replaceFirst('привет', 'привед'));
    expect(failure(t, matchesScreenFile(path, styles: false)).sublist(0, 6), [
      'Expected: the text of the screen of $path',
      '  Actual: TwkTester:<fullscreen, 14×3>',
      '   Which: differs from $path $_legend',
      '          text:',
      '          - 0│sent: привед  │',
      '          + 0│sent: привет  │',
    ]);
  });

  testTwk('a screen that does not match is left beside the file as '
      '.actual, as the file would hold it; a match removes it', (t) async {
    await t.pumpWidget(form(fg: Color.green), size: (14, 3));
    final path = '${dir.path}/form.txt';
    final actual = File(actualScreenFilePath(path));
    expect(actual.path, '$path.actual');
    File(path).writeAsStringSync(formFile);
    expect(failure(t, matchesScreenFile(path)), isNotEmpty);
    // what updating would write, the legend's characters kept
    // the style that is new takes a character the file does not use
    expect(
      actual.readAsStringSync(),
      formFile
          .replaceFirst('│bbbcbb', '│dddcdd')
          .replaceFirst('b red on', 'd green on'),
    );
    expect(File(path).readAsStringSync(), formFile);

    await t.pumpWidget(form(), size: (14, 3));
    expect(t, matchesScreenFile(path));
    expect(actual.existsSync(), isFalse);
  });

  testTwk('a mismatch that is expected, or polled, leaves no .actual', (
    t,
  ) async {
    await t.pumpWidget(form(fg: Color.green), size: (14, 3));
    final path = '${dir.path}/form.txt';
    final actual = File(actualScreenFilePath(path));
    File(path).writeAsStringSync(formFile);
    expect(t, isNot(matchesScreenFile(path)));
    expect(actual.existsSync(), isFalse);
    expect(t, isNot(matchesScreenFile('${dir.path}/none.txt')));
    expect(File('${dir.path}/none.txt.actual').existsSync(), isFalse);
  });

  testTwk('a directory that cannot be written to does not hide the '
      'difference', (t) async {
    await t.pumpWidget(form(fg: Color.green), size: (14, 3));
    final path = '${dir.path}/form.txt';
    File(path).writeAsStringSync(formFile);
    // the .actual's place is taken by a directory: the write fails
    Directory('$path.actual').createSync();
    final lines = failure(t, matchesScreenFile(path));
    expect(lines[2], '   Which: differs from $path $_legend');
    expect(lines.join('\n'), contains('$path.actual not written'));
    Directory('$path.actual').deleteSync();
  });

  testTwk('a missing file gets an .actual to accept, and updating removes '
      'it', (t) async {
    await t.pumpWidget(form(), size: (14, 3));
    final path = '${dir.path}/a/new.txt';
    final actual = File(actualScreenFilePath(path));
    failure(t, matchesScreenFile(path));
    expect(actual.readAsStringSync(), formFile);
    updateScreenFilesOverride = true;
    expect(t, matchesScreenFile(path));
    expect(actual.existsSync(), isFalse);
    expect(File(path).readAsStringSync(), formFile);
  });

  testTwk('the shared golden: the extension reads this very file', (t) async {
    await t.pumpWidget(form(), size: (14, 3));
    expect(t, matchesScreenFile('test/screen_file.golden.txt'));
    expect(File('test/screen_file.golden.txt').readAsStringSync(), formFile);
  });

  // that it is not the working directory is fromPackageRoot's test of a
  // package elsewhere: Directory.current is the whole process's, which the
  // runner's other suites run in and start programs from
  testTwk('a relative path is from the package of the test', (t) async {
    await t.pumpWidget(form(), size: (14, 3));
    final path = 'test/_tmp_screen_file_${pid}_relative.txt';
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:twk_test/twk_test.dart'),
    );
    final file = File('${File.fromUri(lib!).parent.parent.path}/$path');
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    updateScreenFilesOverride = true;
    expect(t, matchesScreenFile(path));
    expect(file.readAsStringSync(), formFile);
  });

  testTwk('fails on another size or cursor', (t) async {
    await t.pumpWidget(form(), size: (14, 3));
    final path = '${dir.path}/form.txt';
    File(path).writeAsStringSync(
      formFile.replaceFirst('cursor hidden', 'cursor at 1,2'),
    );
    expect(
      failure(t, matchesScreenFile(path))[3],
      '          the cursor: - at 1,2, + hidden',
    );
    await t.pumpWidget(form(), size: (15, 3));
    expect(
      failure(t, matchesScreenFile(path))[3],
      '          the size: - 14×3, + 15×3',
    );
  });

  testTwk('fails on a screen of more styles than it has characters for', (
    t,
  ) async {
    await t.pumpWidget(
      Column(
        children: [
          for (var y = 0; y < 40; y++)
            Text.rich([
              for (var x = 0; x < 60; x++)
                Span(
                  '▀',
                  Style(fg: Color.rgb(x, y, 0), bg: Color.rgb(0, x, y)),
                ),
            ]),
        ],
      ),
      size: (60, 40),
    );
    final path = '${dir.path}/blocks.txt';
    updateScreenFilesOverride = true;
    expect(
      failure(t, matchesScreenFile(path))[2],
      startsWith(
        '   Which: $path cannot hold the screen: the screen has more '
        'than ',
      ),
    );
    expect(File(path).existsSync(), isFalse);
  });
}

// callerFile: the frame of the file that called a matcher.
void callerFileTests() {
  const own =
      '#0 _fromPackageRoot (file:///h/twk_test/lib/src/matchers.dart:250:3)';
  String? from(String frames) => callerFile('$own\n$frames')?.toString();

  test('a plain path', () {
    expect(
      from('#1 main (file:///h/app/test/a_test.dart:12:3)'),
      'file:///h/app/test/a_test.dart',
    );
  });

  test('parentheses in the path', () {
    expect(
      from(
        '#1 main (file:///h/my%20app%20(2)/test/a_test.dart:12:3)\n'
        '#2 other (file:///h/zzz/test/b_test.dart:1:1)',
      ),
      'file:///h/my%20app%20(2)/test/a_test.dart',
    );
  });

  test('spaces as %20 decode in the file path', () {
    final uri = callerFile(
      '#1 main (file:///h/my%20app/test/a_test.dart:12:3)',
    )!;
    expect(uri.pathSegments, ['h', 'my app', 'test', 'a_test.dart']);
  });

  test('a drive letter', () {
    final uri = callerFile(
      '#1 main (file:///C:/proj/test/a_test.dart:12:3)',
    )!;
    expect(uri.path, '/C:/proj/test/a_test.dart');
  });

  test("twk_test's own matchers.dart frames are skipped", () {
    expect(
      callerFile('$own\n$own\n#2 m (file:///h/app/test/a_test.dart:1:1)')?.path,
      '/h/app/test/a_test.dart',
    );
  });

  test('no frame of a file gives null', () {
    expect(callerFile(own), isNull);
    expect(callerFile('#0 f (dart:async/zone.dart:1:1)'), isNull);
  });
}

// fromPackageRoot: where a relative path starts from, or why it cannot.
void fromPackageRootTests() {
  test('an absolute path is kept', () {
    // absolute as the platform writes it: on Windows with a drive
    final path = Platform.isWindows ? r'C:\x\y.txt' : '/x/y.txt';
    expect(fromPackageRoot(path, ''), path);
  });

  test('a relative path with no file frame fails and says what to pass', () {
    for (final stack in [
      '',
      '#0 f (dart:async/zone.dart:1:1)',
      '#1 main (file:///h/app/test/a_test.dart)',
      'at Object.main (http://localhost/a_test.dart.js:1:2)',
    ]) {
      expect(
        () => fromPackageRoot('test/g.txt', stack),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('absolute path'), contains('test/g.txt')),
          ),
        ),
        reason: stack,
      );
    }
  });

  test('a relative path from a file with no package above it fails', () {
    expect(
      () => fromPackageRoot(
        'g.txt',
        '#0 main (file:///nonexistent-twk-dir/a_test.dart:1:1)',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('a relative path from a file in a package starts at its root', () {
    final root = Directory.current.path;
    // the frame's URI as the VM writes it, `file:///D:/…` on Windows
    final file = Uri.file('$root/test/a_test.dart');
    expect(fromPackageRoot('g.txt', '#0 main ($file:1:1)'), '$root/g.txt');
  });

  test("a relative path from a file in another package starts at that one's "
      'root, not the working directory', () {
    final other = Directory.systemTemp.createTempSync('twk_other_package');
    addTearDown(() => other.deleteSync(recursive: true));
    File('${other.path}/pubspec.yaml').writeAsStringSync('name: other\n');
    Directory('${other.path}/test').createSync();
    final file = Uri.file('${other.path}/test/a_test.dart');
    final found = fromPackageRoot('g.txt', '#0 main ($file:1:1)');
    expect(found, '${other.path}/g.txt');
    expect(found, isNot(startsWith(Directory.current.path)));
  });
}
