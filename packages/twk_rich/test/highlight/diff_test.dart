// Diffs: headers of files and hunks, added, removed and context lines,
// hunks counted by their headers, and relexing after an edit.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String diff(String source) => lexed(diffLanguage, source);

void main() {
  test('headers, and added, removed and context lines', () {
    expect(
      diff(
        'diff --git a/f.txt b/f.txt\n'
        'index 83db48f..bf269f4 100644\n'
        '--- a/f.txt\n'
        '+++ b/f.txt\n'
        '@@ -1,3 +1,3 @@ fn main() {\n'
        ' one\n'
        '-two\n'
        '+deux\n'
        ' three',
      ),
      '''
heading"diff --git a/f.txt b/f.txt"
heading"index 83db48f..bf269f4 100644"
heading"--- a/f.txt"
heading"+++ b/f.txt"
heading"@@ -1,3 +1,3 @@" " fn main() {"
" one"
deleted"-two"
inserted"+deux"
" three"''',
    );
  });

  test('in a hunk its header counts, --- and +++ are lines', () {
    expect(
      diff('--- a/x\n+++ b/x\n@@ -1 +1 @@\n--- a/y\n+++ b/y\n--- a/z'),
      '''
heading"--- a/x"
heading"+++ b/x"
heading"@@ -1 +1 @@"
deleted"--- a/y"
inserted"+++ b/y"
heading"--- a/z"''',
    );
  });

  test('a hunk header with numbers past 9 digits counts no lines', () {
    expect(
      diff('@@ -1,${'9' * 30} +1 @@\n-a\n+b'),
      '''
heading"@@ -1,${'9' * 30} +1 @@"
deleted"-a"
inserted"+b"''',
    );
  });

  test('a missing newline is a comment, counted in no file', () {
    expect(
      diff('@@ -5 +5,2 @@\n-a\n+b\n\\ No newline at end of file\n+c\n+d'),
      r'''
heading"@@ -5 +5,2 @@"
deleted"-a"
inserted"+b"
comment"\\ No newline at end of file"
inserted"+c"
inserted"+d"''',
    );
  });

  test('without counts, lines are what they start with', () {
    expect(
      diff('@@ ... @@\n- old\n+ new\n same\n--- x\nplain'),
      '''
heading"@@ ... @@"
deleted"- old"
inserted"+ new"
" same"
heading"--- x"
"plain"''',
    );
  });

  test('an edit lexes the lines down to where its hunk ends', () {
    final code = Highlighter(
      diffLanguage,
      '--- a/f\n+++ b/f\n@@ -1,4 +1,4 @@\n a\n b\n c\n d\n--- a/g\n+++ b/g',
    );
    expect(describe(code.tokens(7)), 'heading"--- a/g"');
    expect(code.replaceLines(3, 4, ['-a']), 5);
    expect(describe(code.tokens(7)), 'heading"--- a/g"');
    expect(code.replaceLines(3, 4, ['+a']), 5);
    expect(describe(code.tokens(7)), 'deleted"--- a/g"');
    expect(code.replaceLines(4, 5, [' B']), 1);
  });
}
