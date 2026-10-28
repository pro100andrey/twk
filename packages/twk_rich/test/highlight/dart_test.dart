// Dart: names by what they are, comments that nest, strings of every kind
// with escapes and interpolation, the states that go on across lines, and
// relexing after an edit.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String dart(String source) => lexed(dartLanguage, source);

void main() {
  group('names', () {
    test('are keywords, types, constants, functions or plain', () {
      expect(
        dart('final x = foo(null);'),
        'keyword"final" " x " operator"=" " " function"foo" '
        'punctuation"(" constant"null" punctuation");"',
      );
      expect(
        dart('class Foo extends Bar<int> {}'),
        'keyword"class" " " type"Foo" " " keyword"extends" " " type"Bar" '
        'operator"<" type"int" operator">" " " punctuation"{}"',
      );
      expect(
        dart('void main() async {}'),
        'type"void" " " function"main" punctuation"()" " " keyword"async" '
        '" " punctuation"{}"',
      );
    });

    test('after a dot are members, never keywords', () {
      expect(
        dart('list.add(x).set.length'),
        '"list" punctuation"." function"add" punctuation"(" "x" '
        'punctuation")." "set" punctuation"." "length"',
      );
      expect(
        dart('a..sort()..get(1)'),
        '"a" punctuation".." function"sort" punctuation"().." function"get" '
        'punctuation"(" number"1" punctuation")"',
      );
    });

    test('that are keywords only where they stand as one', () {
      expect(
        dart('int get length => show(x);'),
        'type"int" " " keyword"get" " length " operator"=>" " " '
        'function"show" punctuation"(" "x" punctuation");"',
      );
      expect(
        dart('final type = of;'),
        'keyword"final" " type " operator"=" " of" punctuation";"',
      );
    });

    test('starting with a capital are types', () {
      expect(
        dart('Foo.bar(_Baz, MAX)'),
        'type"Foo" punctuation"." function"bar" punctuation"(" type"_Baz" '
        'punctuation"," " " type"MAX" punctuation")"',
      );
    });

    test('after an @ are annotations', () {
      expect(
        dart("@override @pragma('x') @a.B()"),
        'annotation"@override" " " annotation"@pragma" punctuation"(" '
        'string"\'x\'" punctuation")" " " annotation"@a.B" punctuation"()"',
      );
    });
  });

  test('numbers, symbols and operators', () {
    expect(
      dart('0xFF + 1_000 * 1.5e3 - .5'),
      'number"0xFF" " " operator"+" " " number"1_000" " " operator"*" " " '
      'number"1.5e3" " " operator"-" " " number".5"',
    );
    expect(
      dart('a ?? b?.c ~/ 2 >>>= #sym'),
      '"a " operator"??" " b" operator"?" punctuation"." "c " operator"~/" '
      '" " number"2" " " operator">>>=" " " constant"#sym"',
    );
  });

  group('comments', () {
    test('run to the end of the line', () {
      expect(
        dart('x; // note /*'),
        '"x" punctuation";" " " comment"// note /*"',
      );
      expect(dart('/// Docs [x].'), 'comment"/// Docs [x]."');
      expect(dart('#!/usr/bin/env dart'), 'comment"#!/usr/bin/env dart"');
    });

    test('in blocks nest and go on across lines', () {
      expect(
        dart('a /* one\n/* two */ still\nend */ b /**/'),
        '''
"a " comment"/* one"
comment"/* two */ still"
comment"end */" " b " comment"/**/"''',
      );
    });
  });

  group('strings', () {
    test('hold escapes and interpolation', () {
      expect(
        dart(r"'it\'s $name ${a + 1}$'"),
        r'''string"'it" escape"\\'" string"s " variable"$name" string" " '''
        r'''punctuation"${" "a " operator"+" " " number"1" punctuation"}" '''
        r'''string"$'"''',
      );
      expect(
        dart(
          r'"\x41\u{1F600}\u'
          '0041'
          r'\n\\"',
        ),
        r'string"\"" escape"\\x41\\u{1F600}\\u0041\\n\\\\" string"\""',
      );
    });

    test('raw ones hold neither', () {
      expect(dart(r"r'\n$x'"), r'''string"r'\\n$x'"''');
      expect(dart(r"r'''$y'''"), "string\"r'''\$y'''\"");
    });

    test('one quote long end with the line', () {
      expect(dart("'abc\nx"), 'string"\'abc"\n"x"');
      expect(dart("'\${a\nx"), 'string"\'" punctuation"\${" "a"\n"x"');
    });

    test('three quotes long go on across lines', () {
      expect(
        dart('var s = """\nline \$x\n\\t"q" ""\nend""";'),
        r'''
keyword"var" " s " operator"=" " " string"\"\"\""
string"line " variable"$x"
escape"\\t" string"\"q\" \"\""
string"end\"\"\"" punctuation";"''',
      );
    });

    test('interpolate code that goes on across lines', () {
      expect(
        dart(r'''
"""a ${{
  'k': 1}['k']} b
c""";'''),
        r'''
string"\"\"\"a " punctuation"${{"
"  " string"'k'" punctuation":" " " number"1" punctuation"}[" string"'k'" punctuation"]}" string" b"
string"c\"\"\"" punctuation";"''',
      );
    });
  });

  test('an edit lexes the lines down to where a comment it opens ends', () {
    final lines = [for (var i = 0; i < 20; i++) 'var x$i = $i;'];
    lines[12] = 'f(); // */';
    final code = Highlighter(dartLanguage, lines.join('\n'));
    expect(code.replaceLines(5, 6, ['/* var x5 = 5;']), 8);
    expect(describe(code.tokens(12)), 'comment"f(); // */"');
    expect(code.replaceLines(5, 6, ['/* x */ var x5 = 5;']), 8);
    expect(
      describe(code.tokens(12)),
      'function"f" punctuation"();" " " comment"// */"',
    );
    expect(code.replaceLines(9, 10, ['var y = "/*";']), 1);
  });
}
