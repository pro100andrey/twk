// matchesScreenFile: the file it writes, what it matches, and the message
// it fails with.
import 'dart:io';

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
