// Python: names by what they are, decorators, soft keywords, comments,
// strings with their prefixes, triple-quoted ones and f-strings across
// lines, and relexing after an edit.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String python(String source) => lexed(pythonLanguage, source);

void main() {
  group('names', () {
    test('are keywords, types, constants, functions or plain', () {
      expect(
        python('def area(self, r: float) -> float:'),
        'keyword"def" " " function"area" punctuation"(" "self" '
        'punctuation"," " r" punctuation":" " " type"float" punctuation")" '
        '" " operator"->" " " type"float" punctuation":"',
      );
      expect(
        python('def first[T](xs: list[T]) -> T:'),
        'keyword"def" " " function"first" punctuation"[" type"T" '
        'punctuation"](" "xs" punctuation":" " " type"list" punctuation"[" '
        'type"T" punctuation"])" " " operator"->" " " type"T" punctuation":"',
      );
      expect(
        python('class Shape(ABC):'),
        'keyword"class" " " type"Shape" punctuation"(" type"ABC" '
        'punctuation"):"',
      );
      expect(
        python('x = len(xs) if xs is not None else True'),
        '"x " operator"=" " " function"len" punctuation"(" "xs" '
        'punctuation")" " " keyword"if" " xs " keyword"is" " " '
        'keyword"not" " " constant"None" " " keyword"else" " " '
        'constant"True"',
      );
      expect(
        python('obj.method(a).attr'),
        '"obj" punctuation"." function"method" punctuation"(" "a" '
        'punctuation")." "attr"',
      );
    });

    test('after an @ starting a line are decorators', () {
      expect(
        python("@dataclass(frozen=True)\n  @app.route('/')\nc = a @ b"),
        '''
annotation"@dataclass" punctuation"(" "frozen" operator"=" constant"True" punctuation")"
"  " annotation"@app.route" punctuation"(" string"'/'" punctuation")"
"c " operator"=" " a " operator"@" " b"''',
      );
    });

    test('match, case and type are keywords starting a statement', () {
      expect(
        python(
          'match command.split():\n'
          '    case [action, obj]:\n'
          '        pass\n'
          'match = re.match(p, s)\n'
          'match in seen\n'
          'type Point = tuple[float, float]',
        ),
        '''
keyword"match" " command" punctuation"." function"split" punctuation"():"
"    " keyword"case" " " punctuation"[" "action" punctuation"," " obj" punctuation"]:"
"        " keyword"pass"
"match " operator"=" " re" punctuation"." function"match" punctuation"(" "p" punctuation"," " s" punctuation")"
"match " keyword"in" " seen"
keyword"type" " " type"Point" " " operator"=" " " type"tuple" punctuation"[" type"float" punctuation"," " " type"float" punctuation"]"''',
      );
    });
  });

  test('numbers and operators', () {
    expect(
      python('0xFF + 1_000 * 1.5e-3j // 2 ** 3 != (y := 4)'),
      'number"0xFF" " " operator"+" " " number"1_000" " " operator"*" " " '
      'number"1.5e-3j" " " operator"//" " " number"2" " " operator"**" " " '
      'number"3" " " operator"!=" " " punctuation"(" "y " operator":=" " " '
      'number"4" punctuation")"',
    );
  });

  test('comments', () {
    expect(
      python('x = 1  # note "q"'),
      r'"x " operator"=" " " number"1" "  " comment"# note \"q\""',
    );
  });

  group('strings', () {
    test('hold escapes unless raw', () {
      expect(
        python(r"b'\x00\n' + r'\d+\'' + rb'\''"),
        r'''string"b'" escape"\\x00\\n" string"'" " " operator"+" " " '''
        r'''string"r'\\d+\\''" " " operator"+" " " string"rb'\\''"''',
      );
      expect(
        python(r'"\N{EM DASH}\u00e9\U0001F600\101\q"'),
        r'string"\"" escape"\\N{EM DASH}\\u00e9\\U0001F600\\101\\q" '
        r'string"\""',
      );
    });

    test('in one quote end with the line unless a backslash goes on', () {
      expect(python("'abc\nx"), 'string"\'abc"\n"x"');
      expect(
        python("'abc\\\ndef'"),
        'string"\'abc" escape"\\\\"\nstring"def\'"',
      );
    });

    test('in three quotes go on across lines', () {
      expect(
        python('doc = """First\n  "quoted" \\t\nend"""'),
        r'''
"doc " operator"=" " " string"\"\"\"First"
string"  \"quoted\" " escape"\\t"
string"end\"\"\""''',
      );
    });
  });

  group('f-strings', () {
    test('interpolate fields with conversions and format specs', () {
      expect(
        python('''f'{name!r:>{width}} {{x}} {d["k"]:#x}' '''),
        '''string"f'" punctuation"{" "name" operator"!" "r" '''
        '''punctuation":" string">" punctuation"{" "width" '''
        '''punctuation"}}" string" " escape"{{" string"x" escape"}}" '''
        r'''string" " punctuation"{" "d" punctuation"[" string"\"k\"" '''
        '''punctuation"]:" string"#x" punctuation"}" string"'" " "''',
      );
    });

    test('in three quotes interpolate code across lines', () {
      expect(
        python('msg = f"""\n{ {\'a\': 1}[\n  \'a\'] } done"""'),
        r'''
"msg " operator"=" " " string"f\"\"\""
punctuation"{" " " punctuation"{" string"'a'" punctuation":" " " number"1" punctuation"}["
"  " string"'a'" punctuation"]" " " punctuation"}" string" done\"\"\""''',
      );
    });
  });

  test('an edit lexes the lines down to where a string it opens ends', () {
    final lines = [for (var i = 0; i < 20; i++) 'x$i = $i'];
    lines[12] = 'f()  # """';
    final code = Highlighter(pythonLanguage, lines.join('\n'));
    expect(code.replaceLines(5, 6, ['x5 = """5']), 8);
    expect(describe(code.tokens(12)), r'string"f()  # \"\"\""');
    expect(code.replaceLines(5, 6, ['x5 = """5"""']), 8);
    expect(
      describe(code.tokens(12)),
      r'function"f" punctuation"()" "  " comment"# \"\"\""',
    );
    expect(code.replaceLines(9, 10, ["y = \"'''\""]), 1);
  });
}
