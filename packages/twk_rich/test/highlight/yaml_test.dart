// YAML: keys, scalars by what they hold, comments, sequences, flow
// collections, quoted scalars with escapes, anchors, aliases and tags,
// directives and document markers, and the states that go on across
// lines: block scalars, quoted scalars and flow collections.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String yaml(String source) => lexed(yamlLanguage, source);

void main() {
  test('keys and plain scalars by what they hold', () {
    expect(
      yaml(
        'name: twk rich\nversion: 0.1.0\npublish: false\ncount: 42\n'
        'ratio: -1.5e3\nempty: ~\nurl: http://x.y/z\nkey with blanks:  1',
      ),
      '''
key"name" punctuation":" " " string"twk rich"
key"version" punctuation":" " " string"0.1.0"
key"publish" punctuation":" " " constant"false"
key"count" punctuation":" " " number"42"
key"ratio" punctuation":" " " number"-1.5e3"
key"empty" punctuation":" " " constant"~"
key"url" punctuation":" " " string"http://x.y/z"
key"key with blanks" punctuation":" "  " number"1"''',
    );
  });

  test('comments start a line or follow a blank', () {
    expect(
      yaml('# top\nkey: a#b # note\n  # indented\nk:'),
      '''
comment"# top"
key"key" punctuation":" " " string"a#b" " " comment"# note"
"  " comment"# indented"
key"k" punctuation":"''',
    );
  });

  test('sequences and flow collections', () {
    expect(
      yaml("- a\n- b: 1\n  c: [x, 'y', 2]\n- {d: e, f}"),
      '''
punctuation"-" " " string"a"
punctuation"-" " " key"b" punctuation":" " " number"1"
"  " key"c" punctuation":" " " punctuation"[" string"x" punctuation"," " " string"'y'" punctuation"," " " number"2" punctuation"]"
punctuation"-" " " punctuation"{" key"d" punctuation":" " " string"e" punctuation"," " " string"f" punctuation"}"''',
    );
  });

  test('quoted scalars and keys with their escapes', () {
    expect(
      yaml('"a b": "x\\ty"\n\'k\': \'it\'\'s\'\n{"j":1}'),
      r'''
key"\"a b\"" punctuation":" " " string"\"x" escape"\\t" string"y\""
key"'k'" punctuation":" " " string"'it" escape"''" string"s'"
punctuation"{" key"\"j\"" punctuation":" number"1" punctuation"}"''',
    );
  });

  test('anchors, aliases and tags', () {
    expect(
      yaml('base: &b !!map\nother: *b\nstr: !!str 12'),
      '''
key"base" punctuation":" " " variable"&b" " " type"!!map"
key"other" punctuation":" " " variable"*b"
key"str" punctuation":" " " type"!!str" " " number"12"''',
    );
  });

  test('directives and document markers', () {
    expect(
      yaml('%YAML 1.2 # v\n---\nk: v\n...\n--- |\n  text'),
      '''
annotation"%YAML 1.2" " " comment"# v"
punctuation"---"
key"k" punctuation":" " " string"v"
punctuation"..."
punctuation"---" " " punctuation"|"
"  " string"text"''',
    );
  });

  group('across lines', () {
    test('a block scalar holds the lines indented more than its key', () {
      expect(
        yaml('script: |\n  echo "hi" # no comment\n\n  done\nafter: 1'),
        r'''
key"script" punctuation":" " " punctuation"|"
"  " string"echo \"hi\" # no comment"

"  " string"done"
key"after" punctuation":" " " number"1"''',
      );
      expect(
        yaml('jobs:\n  - run: >- # c\n      folded\n      text\n    name: x'),
        '''
key"jobs" punctuation":"
"  " punctuation"-" " " key"run" punctuation":" " " punctuation">-" " " comment"# c"
"      " string"folded"
"      " string"text"
"    " key"name" punctuation":" " " string"x"''',
      );
      expect(
        yaml('- |2+\n   a\nb: c'),
        '''
punctuation"-" " " punctuation"|2+"
"   " string"a"
key"b" punctuation":" " " string"c"''',
      );
    });

    test('a quoted scalar goes on to its closing quote', () {
      expect(
        yaml('k: "one\n  two" # c\nj: \'a\nb\'\'\''),
        r'''
key"k" punctuation":" " " string"\"one"
string"  two\"" " " comment"# c"
key"j" punctuation":" " " string"'a"
string"b" escape"''" string"'"''',
      );
    });

    test('a flow collection goes on to where it closes', () {
      expect(
        yaml('k: {a: 1,\n  b: [2, "3\n4"]}\nc: d'),
        r'''
key"k" punctuation":" " " punctuation"{" key"a" punctuation":" " " number"1" punctuation","
"  " key"b" punctuation":" " " punctuation"[" number"2" punctuation"," " " string"\"3"
string"4\"" punctuation"]}"
key"c" punctuation":" " " string"d"''',
      );
    });
  });

  test('an edit that makes a key a block scalar lexes its lines', () {
    final code = Highlighter(
      yamlLanguage,
      'a: 1\nb: x\n  c: 1\n  d\ne: 2\nf: 3',
    );
    expect(
      describe(code.tokens(2)),
      '"  " key"c" punctuation":" " " number"1"',
    );
    expect(code.replaceLines(1, 2, ['b: |']), 4);
    expect(describe(code.tokens(2)), '"  " string"c: 1"');
    expect(code.replaceLines(5, 6, ['f: 4']), 1);
  });
}
