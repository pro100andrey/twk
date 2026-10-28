// Output of real tools, captured in test/ansi/fixtures: `<name>.ansi` with
// colours, `<name>.txt` the same command's output without them (or, for
// output a terminal draws over, what the terminal shows):
//
//   git_log    git -c color.ui=always log -3 --stat --decorate=short
//                --date=short
//                --format='%C(auto)%h%d %s%n%C(blue)%ad%C(reset)'
//   git_show   git -c color.ui=always show --format='%C(auto)%h%d %s'
//                a91fabf -- <two files>
//   dart_test  dart test --reporter expanded --color, a test that passes,
//                one skipped and one that fails
//   dart_test_compact
//              the same with --reporter compact in an 80-column
//                pseudo-terminal (`script`), the path of the SDK cut to
//                `dart`
//   gcc        gcc -Wall -fdiagnostics-color=always
//                -fdiagnostics-urls=always -c main.c
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart' show Span, Style;
import 'package:twk_core/twk_core.dart' show Attr, Color;
import 'package:twk_rich/twk_rich.dart';

/// The lines of fixture [name].ansi, read as bytes.
List<List<Span>> parsed(String name) {
  final bytes = File('test/ansi/fixtures/$name.ansi').readAsBytesSync();
  return (AnsiStream()
        ..addBytes(bytes)
        ..close())
      .lines;
}

/// The lines of fixture [name].txt.
List<String> plain(String name) {
  final text = File('test/ansi/fixtures/$name.txt').readAsStringSync();
  return text.substring(0, text.length - 1).split('\n');
}

/// The style of the first span of [lines] whose text has [text].
Style styleOf(List<List<Span>> lines, String text) => lines
    .expand((line) => line)
    .firstWhere((span) => span.text.contains(text))
    .style;

void main() {
  for (final name in [
    'git_log',
    'git_show',
    'dart_test',
    'dart_test_compact',
    'gcc',
  ]) {
    test('$name: the text is the output without colours', () {
      expect([
        for (final line in parsed(name)) line.map((span) => span.text).join(),
      ], plain(name));
    });
  }

  for (final name in ['git_log', 'git_show', 'dart_test', 'gcc']) {
    test('$name: stripAnsi gives the output without colours', () {
      expect(
        stripAnsi(File('test/ansi/fixtures/$name.ansi').readAsStringSync()),
        File('test/ansi/fixtures/$name.txt').readAsStringSync(),
      );
    });
  }

  test('git_log: hashes, decorations and the stat graph', () {
    final lines = parsed('git_log');
    expect(lines.first.first, const Span('6473e80 (', Style(fg: Color.yellow)));
    expect(
      styleOf(lines, 'HEAD'),
      const Style(fg: Color.cyan, attrs: Attr.bold),
    );
    expect(
      styleOf(lines, 'main'),
      const Style(fg: Color.green, attrs: Attr.bold),
    );
    expect(styleOf(lines, '2026-10-19'), const Style(fg: Color.blue));
    expect(styleOf(lines, '+++'), const Style(fg: Color.green));
    expect(styleOf(lines, '---'), const Style(fg: Color.red));
  });

  test('git_show: headers, hunks, additions and deletions', () {
    final lines = parsed('git_show');
    expect(styleOf(lines, 'diff --git'), const Style(attrs: Attr.bold));
    expect(styleOf(lines, '@@ -16,6'), const Style(fg: Color.cyan));
    expect(
      styleOf(lines, "+import 'child_list.dart';"),
      const Style(fg: Color.green),
    );
    expect(
      styleOf(lines, '-  MultiChildRenderObjectElement'),
      const Style(fg: Color.red),
    );
  });

  test('dart_test: counts, the loading line and the failure', () {
    final lines = parsed('dart_test');
    expect(styleOf(lines, '+0'), const Style(fg: Color.green));
    expect(
      styleOf(lines, 'loading'),
      const Style(fg: Color.brightBlack, attrs: Attr.bold),
    );
    expect(styleOf(lines, '~1'), const Style(fg: Color.yellow));
    expect(styleOf(lines, '-1'), const Style(fg: Color.red));
    expect(styleOf(lines, '[E]'), const Style(fg: Color.red, attrs: Attr.bold));
  });

  test('dart_test_compact: the progress line shows its last state', () {
    final lines = parsed('dart_test_compact');
    expect(lines.first.take(5), [
      const Span('00:00 '),
      const Span('+1', Style(fg: Color.green)),
      const Span(' ~1', Style(fg: Color.yellow)),
      const Span(' -1', Style(fg: Color.red)),
      const Span(': test/sample_test.dart: compares '),
    ]);
    expect(
      styleOf(lines, 'To run'),
      const Style(fg: Color.cyan, attrs: Attr.bold),
    );
  });

  test('gcc: severities, quoted names and a link to the docs', () {
    final lines = parsed('gcc');
    expect(
      styleOf(lines, 'error: '),
      const Style(fg: Color.red, attrs: Attr.bold),
    );
    expect(
      styleOf(lines, 'warning: '),
      const Style(fg: Color.magenta, attrs: Attr.bold),
    );
    expect(styleOf(lines, 'missing'), const Style(attrs: Attr.bold));
    expect(
      styleOf(lines, '-Wunused-variable'),
      const Style(
        fg: Color.magenta,
        attrs: Attr.bold,
        link:
            'https://gcc.gnu.org/onlinedocs/gcc-16.2.0/gcc/'
            'Warning-Options.html#index-Wno-unused-variable',
      ),
    );
  });
}
