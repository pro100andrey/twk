// JSON: keys apart from other strings, escapes, numbers, the constants,
// and comments, which go on across lines in a block.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String json(String source) => lexed(jsonLanguage, source);

void main() {
  test('keys, strings, numbers and constants', () {
    expect(
      json('{"a": 1, "b" : [true, false, null], "c": "x"}'),
      r'punctuation"{" key"\"a\"" punctuation":" " " number"1" '
      r'punctuation"," " " key"\"b\"" " " punctuation":" " " '
      'punctuation"[" constant"true" punctuation"," " " constant"false" '
      'punctuation"," " " constant"null" punctuation"]," " " '
      r'key"\"c\"" punctuation":" " " string"\"x\"" punctuation"}"',
    );
  });

  test('numbers with a sign, a fraction and an exponent', () {
    expect(
      json('[-1.5e+10, 0, 2E3, -]'),
      'punctuation"[" number"-1.5e+10" punctuation"," " " number"0" '
      'punctuation"," " " number"2E3" punctuation"," " -" '
      'punctuation"]"',
    );
  });

  test('escapes in strings and keys', () {
    expect(
      json(
        r'{"a\"b": "x\ny\u00e9\/"}',
      ),
      r'punctuation"{" key"\"a" escape"\\\"" key"b\"" punctuation":" " " '
      r'string"\"x" escape"\\n" string"y" escape"\\u00e9\\/" string"\"" '
      'punctuation"}"',
    );
  });

  test('a string not closed ends with the line', () {
    expect(
      json('["abc\n1]'),
      'punctuation"[" string"\\"abc"\nnumber"1" punctuation"]"',
    );
  });

  test('comments, in a block across lines', () {
    expect(
      json('{ // one\n/* two\nthree */ "k": 1 /**/}'),
      r'''
punctuation"{" " " comment"// one"
comment"/* two"
comment"three */" " " key"\"k\"" punctuation":" " " number"1" " " comment"/**/" punctuation"}"''',
    );
  });

  test('what JSON does not have is plain', () {
    expect(
      json('{a: undefined}'),
      'punctuation"{" "a" punctuation":" " undefined" punctuation"}"',
    );
  });
}
