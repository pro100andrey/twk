// The guides of doc/guides/ held to the code: each ```dart block is the
// file its `<!-- file: … -->` line names, as it is (its opening comment
// left out); the apps of example/guides/ run, showing the screens the
// guides show; and every relative link of a guide leads to a file.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/guides/focus.dart' show SignIn;
import '../../example/guides/inline.dart' show Prompt;
import '../../example/guides/layout.dart' show Layout;
import '../../example/guides/theming.dart' show Status;

/// The theming guide's app, as its `main` runs it.
const app = Theme.adaptive(
  dark: ThemeData.catppuccinMocha,
  light: ThemeData.catppuccinLatte,
  child: Status(),
);

/// The repository's root, from this package's directory.
const root = '../..';

final List<File> guides = [
  for (final f in Directory('$root/doc/guides').listSync())
    if (f is File && f.path.endsWith('.md')) f,
]..sort((a, b) => a.path.compareTo(b.path));

String guide(String name) => File('$root/doc/guides/$name').readAsStringSync();

/// [path], from the root, without the comment lines it opens with.
String body(String path) {
  final lines = File('$root/$path').readAsLinesSync();
  return '${lines.skipWhile((l) => l.startsWith('//')).join('\n').trimRight()}'
      '\n';
}

final _dart = RegExp(
  r'(?:<!-- file: (\S+) -->\n)?```dart\n(.*?)```',
  dotAll: true,
);

/// Expects the guide [name] to show [screen] in a ```text block.
void shows(String name, String screen) =>
    expect(guide(name), contains('```text\n$screen```'));

void main() {
  test('there are guides', () => expect(guides, hasLength(7)));

  for (final file in guides) {
    final name = file.path.split('/').last;
    test('$name: each Dart block is the file it names', () {
      final blocks = _dart.allMatches(file.readAsStringSync()).toList();
      for (final block in blocks) {
        expect(block[1], isNotNull, reason: 'a Dart block names no file');
        expect(block[2], body(block[1]!), reason: block[1]);
      }
    });

    test('$name: its relative links lead to files', () {
      final links = RegExp(r'\]\(([^)#:]+)(?:#[^)]*)?\)');
      for (final link in links.allMatches(file.readAsStringSync())) {
        final target = File('${file.parent.path}/${link[1]}');
        expect(target.existsSync(), isTrue, reason: link[1]);
      }
    });
  }

  testTwk('layout: a fixed column and one that takes the rest', (t) async {
    await t.pumpWidget(
      const Layout(),
      size: (50, 8),
      backgroundRgb: 0x16181d,
    );
    const screen = '''
 twk · layout
╭ Files ───────────╮╭ Preview ───────────────────╮
│ lib/             ││ Everything is measured in  │
│ test/            ││ cells. A Row gives its     │
│ pubspec.yaml     ││ fixed children their width │
│                  ││ first, then shares what is │
╰──────────────────╯╰────────────────────────────╯
 q quits
''';
    expect(t, matchesScreen(screen));
    shows('layout.md', screen);
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  testTwk('focus: Tab goes on to the password, Ctrl+S saves from it', (
    t,
  ) async {
    await t.pumpWidget(
      const SignIn(),
      size: (40, 10),
      backgroundRgb: 0x16181d,
    );
    await t.type('ann');
    await t.press('tab');
    await t.type('secret');
    await t.press('ctrl+s');
    await t.pump();
    const screen = '''
╭ Sign in ─────────────────────────────╮
│                                      │
│ Name     ann                         │
│                                      │
│ Password ••••••                      │
│                                      │
│           Sign in   hi, ann          │
│                                      │
╰──────────────────────────────────────╯
ctrl+z undo   ctrl+s save   ctrl+q quit
''';
    expect(t, matchesScreen(screen));
    shows('input-and-focus.md', screen);
    await t.press('ctrl+q');
    expect(t.isRunning, isFalse);
  });

  testTwk('theming: Mocha on a dark terminal', (t) async {
    await t.pumpWidget(
      app,
      size: (30, 8),
      backgroundRgb: 0x16181d,
    );
    expect(t, containsLine('│ ● api      up              │'));
    expect(t, styleAt(2, 2, hasFg(ThemeData.catppuccinMocha.success.fg!)));
  });

  testTwk('theming: Latte on a light terminal', (t) async {
    await t.pumpWidget(app, size: (30, 8), backgroundRgb: 0xFFFFFF);
    expect(t, styleAt(2, 2, hasFg(ThemeData.catppuccinLatte.success.fg!)));
  });

  testTwk('theming: without a Theme, the dark theme on a dark terminal', (
    t,
  ) async {
    await t.pumpWidget(
      const Status(),
      size: (30, 8),
      backgroundRgb: 0x16181d,
    );
    expect(t, styleAt(2, 2, hasFg(ThemeData.dark.success.fg!)));
  });

  testTwk('inline: the lines sent go to the scrollback, the field stays', (
    t,
  ) async {
    await t.pumpWidget(
      const Prompt(),
      size: (30, 3),
      mode: ScreenMode.inline,
      history: [r'$ my_app'],
      backgroundRgb: 0x16181d,
    );
    for (final line in ['one', 'two']) {
      await t.type(line);
      await t.press('enter');
      await t.pump();
    }
    expect(t.scrollback, [r'$ my_app']);
    expect(t.lines, ['> one', '> two', 'say something, Enter sends']);
  });
}
