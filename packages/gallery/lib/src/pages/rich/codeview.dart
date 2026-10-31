// The CodeView page.
part of 'rich.dart';

// ------------------------------------------------------------ CodeView

const Map<String, String> _sources = {
  'dart': _dartSource,
  'python': _pythonSource,
  'rust': _rustSource,
  'go': _goSource,
  'javascript': _javascriptSource,
  'typescript': _typescriptSource,
  'json': _jsonSource,
  'yaml': _yamlSource,
  'bash': _bashSource,
  'diff': _diffSource,
  'plain': _plainSource,
};

/// Each language twk_rich highlights, and plain text, which it does not.
const Map<String, Language> _languages = {
  'dart': dartLanguage,
  'python': pythonLanguage,
  'rust': rustLanguage,
  'go': goLanguage,
  'javascript': javascriptLanguage,
  'typescript': typescriptLanguage,
  'json': jsonLanguage,
  'yaml': yamlLanguage,
  'bash': bashLanguage,
  'diff': diffLanguage,
  'plain': Language.plain,
};

// The lines changed since the last commit, as an editor marks them in its
// gutter: a CodeSign by line number, + added and ~ changed; the number of
// the line in the source, from 1.
const _changed = {
  'dart': {14: '~', 18: '+'},
  'python': {8: '~', 13: '+', 14: '+'},
  'rust': {10: '~'},
  'go': {13: '~', 14: '~'},
  'javascript': {13: '~', 16: '+'},
  'typescript': {14: '~', 22: '+'},
  'json': {3: '~', 17: '+', 18: '+'},
  'yaml': {14: '+', 21: '~'},
  'bash': {6: '~', 18: '+', 19: '+'},
  'diff': {9: '~'},
  'plain': {7: '~', 16: '+'},
};

/// The CodeView page's first line number less 1: what the gutter's
/// numbers are past the source's own.
int _past(Options o) => o.choice<int>('first') - 1;

/// The rows CodeView takes of the source of [o] in a Scrollbar [w] wide:
/// each line broken as twk's Text breaks it in what the gutter leaves.
int _codeRowsIn(Options o, int w) {
  final lines = _sources[o.choice<String>('lang')]!.split('\n');
  final digits = '${_past(o) + lines.length}'.length;
  final gutter =
      (o.flag('signs') ? 2 : 0) + (o.flag('numbers') ? digits + 1 : 0);
  final width = math.max(1, w - 1 - gutter);
  final wrap = TextWrap.values.byName(o.choice('wrap'));
  var rows = 0;
  for (final line in lines) {
    // tabs to the next multiple of 4, as CodeView expands them
    final text = StringBuffer();
    for (final c in line.split('')) {
      text.write(c == '\t' ? ' ' * (4 - text.length % 4) : c);
    }
    rows += RenderParagraph([
      ('$text', const Pen()),
    ], wrap: wrap).getMaxIntrinsicHeight(width);
  }
  return rows;
}

final _codeView = GalleryPage(
  group: 'Rich',
  title: 'CodeView',
  options: [
    const ChoiceOption(
      'lang',
      'language',
      values: [
        'dart',
        'python',
        'rust',
        'go',
        'javascript',
        'typescript',
        'json',
        'yaml',
        'bash',
        'diff',
        'plain',
      ],
      labels: [
        'Dart',
        'Python',
        'Rust',
        'Go',
        'JavaScript',
        'TypeScript',
        'JSON',
        'YAML',
        'Bash',
        'diff',
        'plain',
      ],
    ),
    const SwitchOption('numbers', 'line numbers', initial: true),
    const SwitchOption('signs', 'changes'),
    const ChoiceOption(
      'wrap',
      'wrap',
      values: ['none', 'word', 'grapheme'],
      initial: 'word',
    ),
    SliderOption(
      'width',
      'width',
      min: 24,
      max: 80,
      initial: 56,
      format: (v) => '$v cells',
    ),
    const ChoiceOption(
      'rows',
      'rows',
      values: [null, 10],
      labels: ['all', '10'],
    ),
    // an excerpt of a file: its lines numbered from where it starts, the
    // signs and the controller's lines by those numbers
    const ChoiceOption('first', 'first line', values: [1, 120]),
    // the controller's: scrollToLine, highlightLines, query
    const ChoiceOption(
      'goto',
      'to line $_goto',
      values: ['none', 'least', 'middle'],
      labels: ['none', 'least', '½'],
    ),
    const ChoiceOption(
      'lit',
      'highlight',
      values: ['none', '14', '13–16'],
    ),
    const SwitchOption('find', 'find'),
  ],
  build: (context, o) => inRoom((rw, rh) {
    final theme = Theme.of(context);
    final w = math.min(o.number('width').toInt(), rw);
    final lang = o.choice<String>('lang');
    final view = _controlled(o)
        // a new State, and with it a controller asked anew, for each set
        // of options
        ? _CodeWithController(o, key: ValueKey(_codeKey(o)))
        : SingleChildScrollView(child: _codeViewOf(theme, o, lang, null));
    return SizedBox(
      width: w,
      height: _codeHeight(o, w, rh),
      child: Scrollbar(style: theme.border, child: view),
    );
  }),
  heightIn: (o, room) => _codeHeight(
    o,
    math.min(o.number('width').toInt(), room.width),
    room.height,
  ),
  codeIn: (o, room) {
    final (rw, rh) = codeRoomOf(room);
    final w = math.min(o.number('width').toInt(), rw);
    final lang = o.choice<String>('lang');
    final source = _sources[lang]!.split('\n');
    final h = _codeHeight(o, w, rh);
    final ctl = _controlled(o);
    // Go is indented with tabs: a string with \t in it, which CodeView
    // expands to the next multiple of tabWidth (4)
    final tabs = source.any((l) => l.contains('\t'));
    final src = tabs
        ? [
            "const _source = '''",
            for (final l in source)
              l
                  .replaceAll(r'\', r'\\')
                  .replaceAll(r'$', r'\$')
                  .replaceAll('\t', r'\t'),
            "''';",
          ]
        : ["const _source = r'''", ...source, "''';"];
    final past = _past(o);
    final args = [
      if (ctl) 'controller: _code',
      // plain text, the default: no language
      if (lang != 'plain') 'language: ${lang}Language',
      if (o.flag('numbers')) 'lineNumbers: true',
      if (past > 0) 'firstLineNumber: ${past + 1}',
      if (o.flag('signs')) 'signs: changes',
      if (o.label('wrap') != 'none') 'wrap: .${o.label('wrap')}',
    ];
    // the controller, asked before the view is laid out: what it asks is
    // made as the view is first laid out
    final asks = [
      if (o['goto'] == 'least') '  ..scrollToLine(${past + _goto})',
      if (o['goto'] == 'middle')
        '  ..scrollToLine(${past + _goto}, alignment: 0.5)',
      if (o['lit'] == '14') '  ..highlightLines([${past + 14}])',
      if (o['lit'] == '13–16') '  ..highlightRange(${past + 13}, ${past + 16})',
    ];
    final make =
        'CodeViewController('
        "${o.flag('find') ? "query: '${_queries[lang]}'" : ''})";
    final view = [
      '        child: CodeView(',
      '          _source,',
      for (final a in args) '          $a,',
      '        ),',
    ];
    return [
      ...src,
      '',
      if (ctl) ...[
        if (o.flag('find'))
          '// n and N go round what it finds while the view has the focus',
        if (asks.isEmpty)
          'final _code = $make;'
        else ...[
          'final _code = $make',
          ...asks.sublist(0, asks.length - 1),
          '${asks.last};',
        ],
        '',
        '@override',
        'void dispose() {',
        '  _code.dispose();',
        '  super.dispose();',
        '}',
        '',
      ],
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      if (o.flag('signs')) ...[
        '  // the lines changed since the last commit, by their numbers',
        '  final changes = {',
        for (final MapEntry(:key, :value) in _changed[lang]!.entries)
          codeLine([
            "    ${past + key}: CodeSign('$value', style: ",
            "${value == '+' ? 'theme.success' : 'theme.warning'}),",
          ]),
        '  };',
      ],
      '  return SizedBox(',
      '    width: $w,',
      '    height: $h,',
      '    child: Scrollbar(',
      '      style: theme.border,',
      if (ctl) ...[
        '      // with a controller it scrolls its lines itself',
        for (final l in view) l.substring(2),
      ] else ...[
        '      child: SingleChildScrollView(',
        ...view,
        '      ),',
      ],
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The line the CodeView page's controller scrolls to.
const _goto = 18;

/// What the CodeView page's controller finds in each language, in lower
/// case: smartcase ignores the case.
const _queries = {
  'dart': 'count',
  'python': 'task',
  'rust': 'word',
  'go': 'greet',
  'javascript': 'repos',
  'typescript': 'shape',
  'json': 'commits',
  'yaml': 'sdk',
  'bash': 'target',
  'diff': 'greet',
  'plain': 'release',
};

/// Whether the CodeView page's options give the view a controller.
bool _controlled(Options o) =>
    o['goto'] != 'none' || o['lit'] != 'none' || o.flag('find');

/// The options that make the CodeView page's controller, as a key.
String _codeKey(Options o) => [
  for (final k in const [
    'lang',
    'numbers',
    'first',
    'signs',
    'wrap',
    'width',
    'rows',
    'goto',
    'lit',
    'find',
  ])
    o.label(k),
].join('/');

/// The CodeView page's height: its rows, as far as the room and the rows
/// option let it be.
int _codeHeight(Options o, int w, int rh) {
  final rows = o.choice<int?>('rows');
  final h = math.min(_codeRowsIn(o, w), rh);
  return rows == null ? h : math.min(h, rows);
}

/// The CodeView page's view of [lang], given [controller].
CodeView _codeViewOf(
  ThemeData theme,
  Options o,
  String lang,
  CodeViewController? controller,
) => CodeView(
  _sources[lang]!,
  controller: controller,
  language: _languages[lang]!,
  lineNumbers: o.flag('numbers'),
  firstLineNumber: _past(o) + 1,
  signs: o.flag('signs')
      ? {
          for (final MapEntry(:key, :value) in _changed[lang]!.entries)
            _past(o) + key: CodeSign(
              value,
              style: value == '+' ? theme.success : theme.warning,
            ),
        }
      : null,
  wrap: TextWrap.values.byName(o.choice('wrap')),
);

/// The CodeView page's view with a controller, made and asked as the
/// options say.
final class _CodeWithController extends StatefulWidget {
  const _CodeWithController(this.o, {super.key});

  final Options o;

  @override
  State<_CodeWithController> createState() => _CodeWithControllerState();
}

final class _CodeWithControllerState extends State<_CodeWithController> {
  late final CodeViewController _code = () {
    final o = widget.o;
    final past = _past(o);
    final code = CodeViewController(
      query: o.flag('find') ? _queries[o.choice<String>('lang')]! : '',
    );
    switch (o['goto']) {
      case 'least':
        code.scrollToLine(past + _goto);
      case 'middle':
        code.scrollToLine(past + _goto, alignment: 0.5);
    }
    switch (o['lit']) {
      case '14':
        code.highlightLines([past + 14]);
      case '13–16':
        code.highlightRange(past + 13, past + 16);
    }
    return code;
  }();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _codeViewOf(
    Theme.of(context),
    widget.o,
    widget.o.choice<String>('lang'),
    _code,
  );
}

const _dartSource = r'''
import 'package:twk/twk.dart';

/// Counts the presses of the space bar.
final class Counter extends StatefulWidget {
  const Counter({super.key, this.start = 0});

  final int start;

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  late var _count = widget.start;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'space': () => setState(() => _count++)},
    child: Text('Pressed $_count times, ${_count.isEven ? 'even' : 'odd'}'),
  );
}''';

const _pythonSource = '''
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Task:
    """A task on the board, and who it waits on."""
    title: str
    done: bool = False
    owners: list[str] = field(default_factory=list)


def summary(tasks: list[Task]) -> str:
    waiting = [t for t in tasks if not t.done]
    names = sorted({o for t in waiting for o in t.owners})
    return f"{len(waiting)} open of {len(tasks)}, waiting on {', '.join(names) or 'nobody'}"


if __name__ == "__main__":
    print(summary([Task("Ship it", owners=["user"]), Task("Docs", True)]))''';

const _rustSource = '''
use std::collections::HashMap;

/// The words of a text by how often they come, the most first.
fn word_counts(text: &str) -> Vec<(&str, usize)> {
    let mut counts: HashMap<&str, usize> = HashMap::new();
    for word in text.split_whitespace() {
        *counts.entry(word).or_insert(0) += 1;
    }
    let mut pairs: Vec<_> = counts.into_iter().collect();
    pairs.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    pairs
}

fn main() {
    let text = "the cat and the hat and the bat";
    for (word, n) in word_counts(text).iter().take(3) {
        println!("{word:>5} {n}");
    }
}''';

const _goSource = '''
package main

import (
\t"fmt"
\t"strings"
)

// Greeter greets places by name, in a language of its own.
type Greeter struct {
\tHello string
}

func (g Greeter) Greet(names ...string) string {
\treturn fmt.Sprintf("%s, %s!", g.Hello, strings.Join(names, " and "))
}

func main() {
\tg := Greeter{Hello: "Привіт"}
\tfmt.Println(g.Greet("Kyiv", "Lviv"))
}''';

const _javascriptSource = r'''
// The most starred repositories of a user, the forks left out.
const API = "https://api.github.com";

async function topRepos(user, count = 3) {
  const res = await fetch(`${API}/users/${user}/repos`);
  if (!res.ok) {
    throw new Error(`GitHub said ${res.status}`);
  }
  const repos = await res.json();
  return repos
    .filter((r) => !r.fork)
    .sort((a, b) => b.stargazers_count - a.stargazers_count)
    .slice(0, count)
    .map(({ name, stargazers_count: stars }) => ({ name, stars }));
}

const user = process.argv[2] ?? "dart-lang";
for (const { name, stars } of await topRepos(user)) {
  console.log(`${name.padEnd(24)} ★ ${stars}`);
}''';

const _typescriptSource = r'''
/** A shape, by its kind. */
type Shape =
  | { kind: "circle"; radius: number }
  | { kind: "rect"; width: number; height: number };

interface Labeled<T> {
  readonly label: string;
  value: T;
}

function area(shape: Shape): number {
  switch (shape.kind) {
    case "circle":
      return Math.PI * shape.radius ** 2;
    case "rect":
      return shape.width * shape.height;
  }
}

const shapes: Labeled<Shape>[] = [
  { label: "plate", value: { kind: "circle", radius: 12 } },
  { label: "door", value: { kind: "rect", width: 90, height: 200 } },
];
export const areas = shapes.map(({ label, value }) => `${label}: ${area(value).toFixed(1)}`);''';

const _jsonSource = '''
{
  "name": "twk-gallery",
  "version": "0.4.0",
  "private": true,
  "description": "Every widget of twk, live, with the Dart that builds it",
  "keywords": ["terminal", "tui", "dart"],
  "scripts": {
    "start": "dart run bin/gallery.dart",
    "test": "dart test",
    "golden": "TWK_UPDATE_GOLDENS=1 dart test test/goldens_test.dart"
  },
  "engines": { "dart": ">=3.10.0" },
  "contributors": [
    { "name": "user", "email": "user@example.com", "commits": 1412 },
    { "name": "bot", "email": null, "commits": 87 }
  ],
  "ratio": 0.9425,
  "stable": false,
  "pages": 141
}''';

const _yamlSource = r'''
# The checks, as CI runs them on each push.
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        sdk: [stable, beta]
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: ${{ matrix.sdk }}
      - run: dart pub get
      - run: dart analyze --fatal-infos
      - name: Tests
        run: dart test --reporter expanded
        timeout-minutes: 15
        continue-on-error: false''';

const _bashSource = r'''
#!/usr/bin/env bash
# Builds the gallery for each platform, and says how big each came out.
set -euo pipefail

readonly out="${OUT_DIR:-build}"
targets=(linux-x64 linux-arm64 macos-arm64)

mkdir -p "$out"
for target in "${targets[@]}"; do
  echo "building for $target…"
  if ! dart compile exe bin/gallery.dart \
      --target-os "${target%%-*}" -o "$out/gallery-$target"; then
    echo "failed: $target" >&2
    exit 1
  fi
done

# the sizes, the largest first
du -h "$out"/gallery-* | sort -rh | while read -r size file; do
  printf '%-28s %s\n' "$(basename "$file")" "$size"
done
echo "done in ${SECONDS}s"''';

const _diffSource = r'''
diff --git a/bin/greet.dart b/bin/greet.dart
index 3b18e51..a9c0d2f 100644
--- a/bin/greet.dart
+++ b/bin/greet.dart
@@ -3,4 +3,5 @@ import 'dart:io';
 /// Greets [name] on the terminal.
-String greet(String name) {
-  return 'Hello, ' + name + '!';
+String greet(String name, {String language = 'en'}) {
+  final hello = {'en': 'Hello', 'uk': 'Привіт'}[language];
+  return '$hello, $name!';
 }
@@ -17,7 +18,8 @@ List<String> readNames(String path) {
 void main(List<String> args) {
   final names = readNames(args.first);
+  final language = args.length > 1 ? args[1] : 'en';
   for (final name in names) {
-    print(greet(name));
+    print(greet(name, language: language));
   }
   print('Greeted ${names.length} names.');
 }''';

const _plainSource = '''
Release checklist

Before the tag
  1. Every package's tests pass on stable and beta.
  2. The goldens match: no file under test/goldens changed.
  3. The benchmark is no slower than the last release's.
  4. CHANGELOG.md says what changed, in the words a user reads.

The tag
  Bump the version in each pubspec.yaml, the same in all of them,
  commit "Release 0.4.0", and tag it v0.4.0.

After it
  - Publish the packages in order: twk_core first, then twk, then
    the rest, each after the one it depends on.
  - Announce it where the users are.
  - Open the milestone of the next one.

Owners: the release is cut by whoever merged last; nobody waits on
anybody else to start it.''';
