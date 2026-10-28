// JavaScript and TypeScript: names by what they are, comments, strings,
// template literals that nest and go on across lines, regular expressions
// told from division, what TypeScript adds, and relexing after an edit.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String js(String source) => lexed(javascriptLanguage, source);

String ts(String source) => lexed(typescriptLanguage, source);

void main() {
  group('names', () {
    test('are keywords, types, constants, functions or plain', () {
      expect(
        js('const x = foo(null);'),
        'keyword"const" " x " operator"=" " " function"foo" '
        'punctuation"(" constant"null" punctuation");"',
      );
      expect(
        js('class Foo extends Bar {}'),
        'keyword"class" " " type"Foo" " " keyword"extends" " " type"Bar" " " '
        'punctuation"{}"',
      );
      expect(
        js('async function* gen() { yield await x; }'),
        'keyword"async" " " keyword"function" operator"*" " " function"gen" '
        'punctuation"()" " " punctuation"{" " " keyword"yield" " " '
        'keyword"await" " x" punctuation";" " " punctuation"}"',
      );
      expect(
        js('this.#count++; undefined ?? NaN'),
        'keyword"this" punctuation"." "#count" operator"++" punctuation";" '
        '" " constant"undefined" " " operator"??" " " constant"NaN"',
      );
    });

    test('after a dot are members, never keywords', () {
      expect(
        js('obj.get(x).set.length; a?.b'),
        '"obj" punctuation"." function"get" punctuation"(" "x" '
        'punctuation")." "set" punctuation"." "length" punctuation";" " a" '
        'operator"?" punctuation"." "b"',
      );
      expect(
        js('f(...args, ...this.rest)'),
        'function"f" punctuation"(..." "args" punctuation"," " " '
        'punctuation"..." keyword"this" punctuation"." "rest" punctuation")"',
      );
    });

    test('that are keywords only where they stand as one', () {
      expect(
        js('for (const x of xs) get(x);'),
        'keyword"for" " " punctuation"(" keyword"const" " x " keyword"of" '
        '" xs" punctuation")" " " function"get" punctuation"(" "x" '
        'punctuation");"',
      );
    });

    test('after an @ are decorators', () {
      expect(
        js('@decorator @a.b() class A {}'),
        'annotation"@decorator" " " annotation"@a.b" punctuation"()" " " '
        'keyword"class" " " type"A" " " punctuation"{}"',
      );
    });
  });

  test('numbers and operators', () {
    expect(
      js('0xFF + 1_000n * 1.5e3 >>> .5'),
      'number"0xFF" " " operator"+" " " number"1_000n" " " operator"*" " " '
      'number"1.5e3" " " operator">>>" " " number".5"',
    );
  });

  group('comments', () {
    test('run to the end of the line', () {
      expect(js('x; // note /*'), '"x" punctuation";" " " comment"// note /*"');
      expect(js('#!/usr/bin/env node'), 'comment"#!/usr/bin/env node"');
    });

    test('in blocks go on across lines and do not nest', () {
      expect(
        js('a /* one\n/* two */ b'),
        '"a " comment"/* one"\ncomment"/* two */" " b"',
      );
    });
  });

  group('strings', () {
    test('hold escapes', () {
      expect(
        js(r'''"a\tb\u00e9\u{1F600}\x41" + 'it\'s' '''),
        r'''string"\"a" escape"\\t" string"b" '''
        r'''escape"\\u00e9\\u{1F600}\\x41" string"\"" " " operator"+" " " '''
        r'''string"'it" escape"\\'" string"s'" " "''',
      );
    });

    test('end with the line unless a backslash goes on', () {
      expect(js("'abc\nx"), 'string"\'abc"\n"x"');
      expect(
        js("'abc\\\ndef' + 1"),
        'string"\'abc" escape"\\\\"\n'
        'string"def\'" " " operator"+" " " number"1"',
      );
    });
  });

  group('template literals', () {
    test('interpolate code that holds templates', () {
      expect(
        js(r'`a ${b + `c ${d}`} e`'),
        r'string"`a " punctuation"${" "b " operator"+" " " string"`c " '
        r'punctuation"${" "d" punctuation"}" string"`" punctuation"}" '
        'string" e`"',
      );
    });

    test('go on across lines, and so does code in them', () {
      expect(
        js('const s = `line \${\n  {a: 1}.a\n} \\n`;'),
        r'''
keyword"const" " s " operator"=" " " string"`line " punctuation"${"
"  " punctuation"{" "a" punctuation":" " " number"1" punctuation"}." "a"
punctuation"}" string" " escape"\\n" string"`" punctuation";"''',
      );
    });
  });

  group('a slash', () {
    test('after a value divides', () {
      expect(
        js('x = a / b / c; f(a) / 2'),
        '"x " operator"=" " a " operator"/" " b " operator"/" " c" '
        'punctuation";" " " function"f" punctuation"(" "a" punctuation")" '
        '" " operator"/" " " number"2"',
      );
      expect(
        js('a++ / b; // c /'),
        '"a" operator"++" " " operator"/" " b" punctuation";" " " '
        'comment"// c /"',
      );
    });

    test('where a value goes starts a regular expression', () {
      expect(
        js('x = /ab+c/gi.test(s) ? 1 : 2'),
        '"x " operator"=" " " string"/ab+c/gi" punctuation"." '
        'function"test" punctuation"(" "s" punctuation")" " " operator"?" '
        '" " number"1" " " punctuation":" " " number"2"',
      );
      expect(
        js(r'if (/[/]\//.test(s)) return /x/;'),
        r'keyword"if" " " punctuation"(" string"/[/]\\//" punctuation"." '
        'function"test" punctuation"(" "s" punctuation"))" " " '
        'keyword"return" " " string"/x/" punctuation";"',
      );
    });

    test('that no slash closes on its line divides', () {
      expect(
        js('let r = 2 * /x'),
        'keyword"let" " r " operator"=" " " number"2" " " operator"*" " " '
        'operator"/" "x"',
      );
    });
  });

  group('TypeScript', () {
    test('adds keywords and built-in types', () {
      expect(
        ts('interface Point<T> { readonly x: number; y?: T }'),
        'keyword"interface" " " type"Point" operator"<" type"T" '
        'operator">" " " punctuation"{" " " keyword"readonly" " x" '
        'punctuation":" " " type"number" punctuation";" " y" operator"?" '
        'punctuation":" " " type"T" " " punctuation"}"',
      );
      expect(
        ts('type A = keyof B as const'),
        'keyword"type" " " type"A" " " operator"=" " " keyword"keyof" " " '
        'type"B" " " keyword"as" " " keyword"const"',
      );
      expect(
        ts('function f(): void {}'),
        'keyword"function" " " function"f" punctuation"():" " " type"void" '
        '" " punctuation"{}"',
      );
    });

    test('that JavaScript does not have', () {
      expect(js('void 0'), 'keyword"void" " " number"0"');
      expect(
        js('type A = keyof B as const'),
        '"type " type"A" " " operator"=" " keyof " type"B" " " '
        'keyword"as" " " keyword"const"',
      );
    });
  });

  test('an edit lexes the lines down to where a template it opens ends', () {
    final lines = [for (var i = 0; i < 20; i++) 'let x$i = $i;'];
    lines[12] = 'f(); // `';
    final code = Highlighter(javascriptLanguage, lines.join('\n'));
    expect(code.replaceLines(5, 6, ['let x5 = `5;']), 8);
    expect(describe(code.tokens(12)), 'string"f(); // `"');
    expect(code.replaceLines(5, 6, ['let x5 = `5`;']), 8);
    expect(
      describe(code.tokens(12)),
      'function"f" punctuation"();" " " comment"// `"',
    );
    expect(code.replaceLines(9, 10, ['let y = "`";']), 1);
  });
}
