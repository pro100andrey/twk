// The framework: what a scanner emits, splitting source into lines, the
// registry of languages and plain text for a name none goes by, and an
// edit lexing again only the lines it changes, counted.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

/// `/*` to `*/` as comments, which go on across lines, and the rest plain;
/// the state is whether a line ends inside a comment.
final class CommentLexer extends Lexer {
  const CommentLexer();

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    var inside = state == true;
    while (!s.atEnd) {
      if (inside) {
        final close = s.indexOf('*/');
        if (close < 0) {
          s.emitRest(TokenKind.comment);
        } else {
          s.emit(TokenKind.comment, close + 2);
          inside = false;
        }
      } else if (s.startsWith('/*')) {
        s.emitLength(TokenKind.comment, 2);
        inside = true;
      } else {
        s.emitLength(TokenKind.plain, 1);
      }
    }
    return inside ? true : null;
  }
}

const comments = Language(name: 'comments', lexer: CommentLexer());

/// Ten lines `line 0` to `line 9`.
List<String> get ten => [for (var i = 0; i < 10; i++) 'line $i'];

/// The tokens of every line of [code], described.
List<String> all(Highlighter code) => [
  for (var i = 0; i < code.lineCount; i++) describe(code.tokens(i)),
];

void main() {
  group('a scanner', () {
    test('makes tokens of one kind that follow each other one token', () {
      final s = TokenScanner('a+-b')
        ..emitLength(TokenKind.plain, 1)
        ..emitLength(TokenKind.operator, 1)
        ..emitLength(TokenKind.operator, 1)
        ..emitRest(TokenKind.plain);
      expect(describe(s.tokens()), '"a" operator"+-" "b"');
    });

    test('leaves the rest of a line it does not lex plain', () {
      final s = TokenScanner('if x')..emitLength(TokenKind.keyword, 2);
      expect(describe(s.tokens()), 'keyword"if" " x"');
      expect(TokenScanner('').tokens(), isEmpty);
    });

    test('emits nothing for an empty token', () {
      final s = TokenScanner('x')
        ..emit(TokenKind.keyword, 0)
        ..emitRest(TokenKind.plain);
      expect(describe(s.tokens()), '"x"');
    });

    test('looks around its position', () {
      final s = TokenScanner('ab/*c')..emitLength(TokenKind.plain, 2);
      expect(s.pos, 2);
      expect(s.current, 0x2F);
      expect(s.peek(-1), 0x62);
      expect(s.peek(3), -1);
      expect(s.startsWith('/*'), isTrue);
      expect(s.startsWith('c', 2), isTrue);
      expect(s.indexOf('c'), 4);
      expect(s.match(RegExp('/[*]+')), 4);
      expect(s.match(RegExp('x')), -1);
      expect(s.endWhile((unit) => unit != 0x63), 4);
    });

    test('finds where a number ends', () {
      int end(String line) => TokenScanner(line).numberEnd();
      expect(end('12;'), 2);
      expect(end('1_000 '), 5);
      expect(end('1.5e-3+'), 6);
      expect(end('.5)'), 2);
      expect(end('0xFF_u8,'), 7);
      expect(end('0b101'), 5);
      expect(end('0o17'), 4);
      expect(end('10u32'), 5);
      expect(end('1.isEven'), 1);
      expect(end('1..2'), 1);
      expect(end('1e'), 2);
      expect(end('x1'), 0);
      expect(end('.x'), 0);
    });
  });

  group('lines', () {
    test('are split at line feeds and CR LF', () {
      final code = Highlighter(Language.plain, 'a\r\nb\nc');
      expect(
        [for (var i = 0; i < code.lineCount; i++) code.line(i)],
        [
          'a',
          'b',
          'c',
        ],
      );
    });

    test('end in an empty one after a final line break', () {
      expect(Highlighter(Language.plain, 'a\n').lineCount, 2);
      expect(Highlighter(Language.plain).lineCount, 1);
      expect(Highlighter(Language.plain).tokens(0), isEmpty);
    });

    test('are one plain token each in plain text', () {
      expect(
        lexed(Language.plain, 'if (x) {\n\n  "y"'),
        r'''
"if (x) {"

"  \"y\""''',
      );
    });
  });

  group('languages', () {
    test('are found by name and alias, in any case', () {
      expect(languageNamed('dart'), dartLanguage);
      expect(languageNamed('JSON'), jsonLanguage);
      expect(languageNamed('jsonc'), jsonLanguage);
      expect(languageNamed('yml'), yamlLanguage);
      expect(languageNamed('Yaml'), yamlLanguage);
      expect(languageNamed('sh'), bashLanguage);
      expect(languageNamed('shell'), bashLanguage);
      expect(languageNamed('zsh'), bashLanguage);
      expect(languageNamed('text'), Language.plain);
      for (final (name, language) in [
        ('javascript', javascriptLanguage),
        ('js', javascriptLanguage),
        ('jsx', javascriptLanguage),
        ('TypeScript', typescriptLanguage),
        ('ts', typescriptLanguage),
        ('tsx', typescriptLanguage),
        ('python', pythonLanguage),
        ('py', pythonLanguage),
        ('rust', rustLanguage),
        ('rs', rustLanguage),
        ('go', goLanguage),
        ('golang', goLanguage),
        ('diff', diffLanguage),
        ('patch', diffLanguage),
      ]) {
        expect(languageNamed(name), language, reason: name);
      }
    });

    test('fall back to plain text for a name none goes by', () {
      expect(languageNamed('cobol'), Language.plain);
      expect(languageNamed(''), Language.plain);
      expect(
        lexed(languageNamed('cobol'), 'MOVE 1 TO X.'),
        '"MOVE 1 TO X."',
      );
    });

    test('are looked up among those given', () {
      expect(languageNamed('comments', among: [comments]), comments);
      expect(languageNamed('dart', among: [comments]), Language.plain);
    });

    test('are registered each under its own names', () {
      final names = [
        for (final language in [...languages, Language.plain]) ...[
          language.name,
          ...language.aliases,
        ],
      ];
      expect(names.toSet(), hasLength(names.length));
      for (final name in names) {
        expect(name, name.toLowerCase());
      }
    });
  });

  group('an edit', () {
    test('lexes a line changed within it alone', () {
      final code = Highlighter(comments, ten.join('\n'));
      final before = [for (var i = 0; i < 10; i++) code.tokens(i)];
      expect(code.replaceLines(4, 5, ['line four']), 1);
      expect(code.line(4), 'line four');
      for (var i = 0; i < 10; i++) {
        if (i != 4) {
          expect(code.tokens(i), same(before[i]), reason: 'line $i');
        }
      }
    });

    test('lexes on from a comment it opens to where the comment ends', () {
      final lines = ten..[6] = 'end */ line 6';
      final code = Highlighter(comments, lines.join('\n'));
      expect(code.replaceLines(2, 3, ['/* line 2']), 5);
      expect(all(code).sublist(1, 8), [
        '"line 1"',
        'comment"/* line 2"',
        'comment"line 3"',
        'comment"line 4"',
        'comment"line 5"',
        'comment"end */" " line 6"',
        '"line 7"',
      ]);
      expect(code.replaceLines(2, 3, ['line 2']), 5);
      expect(all(code)[6], '"end */ line 6"');
    });

    test('lexes to the end a comment it opens that does not end', () {
      final code = Highlighter(comments, ten.join('\n'));
      expect(code.replaceLines(7, 8, ['/*']), 3);
      expect(all(code).last, 'comment"line 9"');
    });

    test('lexes lines it inserts, and those a removed line changes', () {
      final code = Highlighter(comments, ten.join('\n'));
      expect(code.replaceLines(3, 3, ['new', 'lines']), 2);
      expect(code.lineCount, 12);
      expect(code.line(5), 'line 3');
      expect(code.replaceLines(3, 5, []), 0);
      expect(code.lineCount, 10);
      expect(code.replaceLines(3, 3, ['/*', '*/']), 2);
      expect(code.replaceLines(4, 5, []), 7);
      expect(all(code).last, 'comment"line 9"');
    });

    test('of the whole text replaces the lines between the same ones', () {
      final code = Highlighter(comments, ten.join('\n'));
      expect(code.update(ten.join('\n')), 0);
      expect(code.update([...ten, 'line 10'].join('\n')), 1);
      expect(code.update((ten..[5] = 'x /*').join('\n')), 5);
      expect(code.lineCount, 10);
      expect(all(code)[9], 'comment"line 9"');
      expect(code.update('a\n'), 2);
      expect(all(code), ['"a"', '']);
      expect(code.update(''), 0);
      expect(code.lineCount, 1);
    });

    test('that removes every line leaves one empty line, lexing none', () {
      final code = Highlighter(comments, 'a /*\nb');
      expect(code.replaceLines(0, 2, []), 0);
      expect(code.lineCount, 1);
      expect(code.line(0), '');
      expect(code.tokens(0), isEmpty);
    });

    test('keeps every line lexed as the whole text lexes it', () {
      const text = 'a /* b\nc */ d\ne\n/* f */ g\nh /*\ni';
      final code = Highlighter(comments, text);
      final lines = Highlighter.splitLines(text);
      for (var at = 0; at < lines.length; at++) {
        for (final edit in ['', '/*', '*/', 'x']) {
          final edited = [...lines]..[at] = edit;
          code
            ..update(lines.join('\n'))
            ..update(edited.join('\n'));
          expect(
            all(code),
            all(Highlighter(comments, edited.join('\n'))),
            reason: 'line $at made "$edit"',
          );
        }
      }
    });
  });

  group('values', () {
    test('tokens are equal by kind and text, and hash alike', () {
      final text = String.fromCharCodes('if'.codeUnits);
      expect(
        Token(TokenKind.keyword, text),
        const Token(TokenKind.keyword, 'if'),
      );
      expect(
        Token(TokenKind.keyword, text).hashCode,
        const Token(TokenKind.keyword, 'if').hashCode,
      );
      expect(
        const Token(TokenKind.keyword, 'if'),
        isNot(const Token(TokenKind.plain, 'if')),
      );
      expect(
        const Token(TokenKind.keyword, 'if'),
        isNot(const Token(TokenKind.keyword, 'in')),
      );
    });

    test('frames are equal by every field of their stacks, hash alike and '
        'show them', () {
      LexFrame heredoc(String word, int outerMode) => LexFrame(
        1,
        depth: 2,
        text: word,
        outer: LexFrame(outerMode),
      );
      expect(heredoc('EOF', 0), heredoc('EOF', 0));
      expect(heredoc('EOF', 0).hashCode, heredoc('EOF', 0).hashCode);
      expect(heredoc('EOF', 0), isNot(heredoc('END', 0)));
      expect(heredoc('EOF', 0), isNot(heredoc('EOF', 3)));
      expect(heredoc('EOF', 0), isNot(heredoc('EOF', 0).withDepth(1)));
      expect(
        '${heredoc('EOF', 0)}',
        'LexFrame(1, depth: 2, text: EOF, '
            'outer: LexFrame(0, depth: 0, text: , outer: null))',
      );
    });
  });
}
