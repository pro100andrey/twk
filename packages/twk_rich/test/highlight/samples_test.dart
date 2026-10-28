// Each language's sample in test/highlight/samples, `<name>.txt`, lexed to
// the tokens in `<name>.tokens`, a line of them per line of the sample as
// tokens.dart writes them; the tokens give back the text, and an edit of
// any line, and undoing it, leave every line lexed as the whole text
// lexes. Random text lexes too, its tokens giving it back.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

const Map<String, Language> samples = {
  'bash': bashLanguage,
  'dart': dartLanguage,
  'diff': diffLanguage,
  'go': goLanguage,
  'javascript': javascriptLanguage,
  'json': jsonLanguage,
  'python': pythonLanguage,
  'rust': rustLanguage,
  'typescript': typescriptLanguage,
  'yaml': yamlLanguage,
};

/// The tokens of every line of [code], described.
List<String> all(Highlighter code) => [
  for (var i = 0; i < code.lineCount; i++) describe(code.tokens(i)),
];

void main() {
  for (final MapEntry(key: name, value: language) in samples.entries) {
    group(name, () {
      final text = File('test/highlight/samples/$name.txt').readAsStringSync();

      test('lexes to the tokens expected', () {
        final expected = File(
          'test/highlight/samples/$name.tokens',
        ).readAsLinesSync();
        expect(all(Highlighter(language, text)), expected);
      });

      test('gives back the text', () {
        final code = Highlighter(language, text);
        for (var i = 0; i < code.lineCount; i++) {
          expect(code.tokens(i).map((t) => t.text).join(), code.line(i));
        }
      });

      test('lexes an edit and its undoing as it lexes the whole text', () {
        final lines = Highlighter.splitLines(text);
        final code = Highlighter(language, text);
        final whole = all(code);
        for (var at = 0; at < lines.length; at++) {
          for (final edit in ['', '${lines[at]}"', "'${lines[at]}"]) {
            final edited = ([...lines]..[at] = edit).join('\n');
            code.update(edited);
            expect(
              all(code),
              all(Highlighter(language, edited)),
              reason: 'line ${at + 1} made $edit',
            );
            code.update(text);
            expect(all(code), whole, reason: 'line ${at + 1} undone');
          }
        }
      });
    });
  }

  test('every language lexes random text, its tokens giving it back', () {
    const units = '\'"`\$(){}[]<>|&;#/*\\ \tabEOF019=:-.!?@%^~,+\n';
    final random = Random(7);
    for (final language in [...languages, Language.plain]) {
      for (var n = 0; n < 200; n++) {
        final text = String.fromCharCodes([
          for (var k = random.nextInt(120); k > 0; k--)
            units.codeUnitAt(random.nextInt(units.length)),
        ]);
        final code = Highlighter(language, text);
        for (var i = 0; i < code.lineCount; i++) {
          expect(
            code.tokens(i).map((t) => t.text).join(),
            code.line(i),
            reason: '$language: ${jsonEncode(text)}',
          );
        }
      }
    }
  });
}
