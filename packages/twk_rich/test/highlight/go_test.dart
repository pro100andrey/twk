// Go: names by what they are, numbers, strings and runes with escapes, raw
// strings and comments across lines, and relexing after an edit.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String go(String source) => lexed(goLanguage, source);

void main() {
  group('names', () {
    test('are keywords, types, constants, functions or plain', () {
      expect(
        go('func (p *Point) Dist(q Point) float64 {'),
        'keyword"func" " " punctuation"(" "p " operator"*" "Point" '
        'punctuation")" " " function"Dist" punctuation"(" "q Point" '
        'punctuation")" " " type"float64" " " punctuation"{"',
      );
      expect(
        go('x := fmt.Sprintf("%d", len(xs))'),
        '"x " operator":=" " fmt" punctuation"." function"Sprintf" '
        r'punctuation"(" string"\"%d\"" punctuation"," " " function"len" '
        'punctuation"(" "xs" punctuation"))"',
      );
      expect(
        go('var err error = nil; ch <- iota'),
        'keyword"var" " err " type"error" " " operator"=" " " constant"nil" '
        'punctuation";" " ch " operator"<-" " " constant"iota"',
      );
    });

    test('declared by type and func are types and functions', () {
      expect(
        go('type Shape interface { Area() float64 }'),
        'keyword"type" " " type"Shape" " " keyword"interface" " " '
        'punctuation"{" " " function"Area" punctuation"()" " " '
        'type"float64" " " punctuation"}"',
      );
      expect(
        go('func Map[T any](xs []T) {}'),
        'keyword"func" " " function"Map" punctuation"[" "T " type"any" '
        'punctuation"](" "xs " punctuation"[]" "T" punctuation")" " " '
        'punctuation"{}"',
      );
    });
  });

  test('numbers', () {
    expect(
      go('0x1F + 0o17 + 1_000 + 1.5e3 + 2i'),
      'number"0x1F" " " operator"+" " " number"0o17" " " operator"+" " " '
      'number"1_000" " " operator"+" " " number"1.5e3" " " operator"+" " " '
      'number"2i"',
    );
  });

  group('strings', () {
    test('and runes hold escapes', () {
      expect(
        go(r'''"a\tb\x41\u00e9\U0001F600\101" 'a' '\n' '\'' '''),
        r'''string"\"a" escape"\\t" string"b" '''
        r'''escape"\\x41\\u00e9\\U0001F600\\101" string"\"" " " '''
        r'''string"'a'" " " string"'" escape"\\n" string"'" " " '''
        r'''string"'" escape"\\'" string"'" " "''',
      );
    });

    test('end with the line', () {
      expect(go('"abc\nx'), 'string"\\"abc"\n"x"');
    });

    test('in backquotes are raw and go on across lines', () {
      expect(
        go('s := `a \\n "b"\nc` + "d"'),
        r'''
"s " operator":=" " " string"`a \\n \"b\""
string"c`" " " operator"+" " " string"\"d\""''',
      );
    });
  });

  test('comments, in a block across lines', () {
    expect(
      go('/* a\nb */ x // c'),
      'comment"/* a"\ncomment"b */" " x " comment"// c"',
    );
  });

  test('an edit lexes the lines down to where a raw string it opens ends', () {
    final lines = [for (var i = 0; i < 20; i++) 'x$i := $i'];
    lines[12] = 'f() // `';
    final code = Highlighter(goLanguage, lines.join('\n'));
    expect(code.replaceLines(5, 6, ['x5 := `5']), 8);
    expect(describe(code.tokens(12)), 'string"f() // `"');
    expect(code.replaceLines(5, 6, ['x5 := `5`']), 8);
    expect(
      describe(code.tokens(12)),
      'function"f" punctuation"()" " " comment"// `"',
    );
    expect(code.replaceLines(9, 10, ['y := "`"']), 1);
  });
}
