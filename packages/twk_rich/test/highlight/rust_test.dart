// Rust: names by what they are, macros and attributes, lifetimes told from
// characters, numbers with suffixes, comments that nest, strings and raw
// strings across lines, and relexing after an edit.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String rust(String source) => lexed(rustLanguage, source);

void main() {
  group('names', () {
    test('are keywords, types, constants, functions or plain', () {
      expect(
        rust('pub fn area<T: Shape>(s: &T) -> f64 {'),
        'keyword"pub" " " keyword"fn" " " function"area" operator"<" '
        'type"T" punctuation":" " " type"Shape" operator">" punctuation"(" '
        '"s" punctuation":" " " operator"&" type"T" punctuation")" " " '
        'operator"->" " " type"f64" " " punctuation"{"',
      );
      expect(
        rust('let mut v: Vec<u8> = Vec::new(); true'),
        'keyword"let" " " keyword"mut" " v" punctuation":" " " type"Vec" '
        'operator"<" type"u8" operator">" " " operator"=" " " type"Vec" '
        'punctuation"::" function"new" punctuation"();" " " constant"true"',
      );
      expect(
        rust('self.items.iter().map(|x| x * 2)'),
        'keyword"self" punctuation"." "items" punctuation"." function"iter" '
        'punctuation"()." function"map" punctuation"(" operator"|" "x" '
        'operator"|" " x " operator"*" " " number"2" punctuation")"',
      );
      expect(
        rust('Point { x, ..self.p }'),
        'type"Point" " " punctuation"{" " x" punctuation"," " " '
        'punctuation".." keyword"self" punctuation"." "p " punctuation"}"',
      );
    });

    test('raw ones are plain', () {
      expect(
        rust('let r#type = 1;'),
        'keyword"let" " r#type " '
        'operator"=" " " number"1" punctuation";"',
      );
    });
  });

  test('macros, attributes and macro variables', () {
    expect(
      rust('#[derive(Debug, Clone)]'),
      'annotation"#[derive" punctuation"(" type"Debug" punctuation"," " " '
      'type"Clone" punctuation")]"',
    );
    expect(
      rust('#![allow(dead_code)] #[rustfmt::skip]'),
      'annotation"#![allow" punctuation"(" "dead_code" punctuation")]" " " '
      'annotation"#[rustfmt::skip" punctuation"]"',
    );
    expect(
      rust('println!("{}", x != y); vec![1]'),
      r'function"println!" punctuation"(" string"\"{}\"" punctuation"," '
      '" x " operator"!=" " y" punctuation");" " " function"vec!" '
      'punctuation"[" number"1" punctuation"]"',
    );
    expect(
      rust(r'($x:expr) => { $x }'),
      r'punctuation"(" variable"$x" punctuation":" "expr" punctuation")" '
      r'" " operator"=>" " " punctuation"{" " " variable"$x" " " '
      'punctuation"}"',
    );
  });

  group('a quote', () {
    test('before a name alone starts a lifetime or a label', () {
      expect(
        rust("fn f<'a>(x: &'a str) -> &'static str"),
        'keyword"fn" " " function"f" operator"<" type"\'a" operator">" '
        'punctuation"(" "x" punctuation":" " " operator"&" type"\'a" " " '
        'type"str" punctuation")" " " operator"->" " " operator"&" '
        'type"\'static" " " type"str"',
      );
      expect(
        rust("'outer: loop { break 'outer; }"),
        'type"\'outer" punctuation":" " " keyword"loop" " " punctuation"{" '
        '" " keyword"break" " " type"\'outer" punctuation";" " " '
        'punctuation"}"',
      );
    });

    test('around a character makes a character', () {
      expect(
        rust(r"('x', '\n', '\'', b'a', '😀', '\u{1F600}')"),
        '''punctuation"(" string"'x'" punctuation"," " " string"'" '''
        r'''escape"\\n" string"'" punctuation"," " " string"'" '''
        r'''escape"\\'" string"'" punctuation"," " " string"b'a'" '''
        '''punctuation"," " " string"'😀'" punctuation"," " " '''
        r'''string"'" escape"\\u{1F600}" string"'" punctuation")"''',
      );
    });
  });

  test('numbers with suffixes', () {
    expect(
      rust('0xFF_u8 + 1_000i64 * 1.5e3f32 + 0b1010 + x.0 + 1..10'),
      'number"0xFF_u8" " " operator"+" " " number"1_000i64" " " '
      'operator"*" " " number"1.5e3f32" " " operator"+" " " number"0b1010" '
      '" " operator"+" " x" punctuation"." number"0" " " operator"+" " " '
      'number"1" punctuation".." number"10"',
    );
  });

  group('comments', () {
    test('run to the end of the line', () {
      expect(rust('/// Docs\nx // y'), 'comment"/// Docs"\n"x " comment"// y"');
      expect(
        rust('#!/usr/bin/env rust-script'),
        'comment"#!/usr/bin/env rust-script"',
      );
    });

    test('in blocks nest and go on across lines', () {
      expect(
        rust('a /* one\n/* two */ still\nend */ b'),
        '''
"a " comment"/* one"
comment"/* two */ still"
comment"end */" " b"''',
      );
    });
  });

  group('strings', () {
    test('go on across lines, with escapes', () {
      expect(
        rust('let s = "line \\"one\\"\ntwo \\\n  three\\u{1F600}";'),
        r'''
keyword"let" " s " operator"=" " " string"\"line " escape"\\\"" string"one" escape"\\\""
string"two " escape"\\"
string"  three" escape"\\u{1F600}" string"\"" punctuation";"''',
      );
    });

    test('raw ones end at a quote and as many hashes', () {
      expect(
        rust(r'r#"a "quoted" \n"# + r"x" + c"y"'),
        r'string"r#\"a \"quoted\" \\n\"#" " " operator"+" " " '
        r'string"r\"x\"" " " operator"+" " " string"c\"y\""',
      );
      expect(
        rust('br##"one\n"# still\n"##;'),
        r'''
string"br##\"one"
string"\"# still"
string"\"##" punctuation";"''',
      );
    });
  });

  test('an edit lexes the lines down to where comments it opens end', () {
    final lines = [for (var i = 0; i < 20; i++) 'let x$i = $i;'];
    lines[12] = 'f(); // */ */';
    final code = Highlighter(rustLanguage, lines.join('\n'));
    expect(code.replaceLines(5, 6, ['/* /* x5']), 8);
    expect(describe(code.tokens(12)), 'comment"f(); // */ */"');
    expect(code.replaceLines(5, 6, ['/* x5']), 8);
    expect(
      describe(code.tokens(12)),
      'comment"f(); // */" " " operator"*/"',
    );
    expect(code.replaceLines(9, 10, ['/* x9']), 4);
    expect(describe(code.tokens(12)), 'comment"f(); // */ */"');
  });
}
