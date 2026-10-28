import 'package:test/test.dart';
import 'package:twk_doc_snippets/snippets.dart';

void main() {
  group('snippetsOf', () {
    test('finds a dart block of a doc comment, its lines without the ///', () {
      const source = '''
/// Says hello.
///
/// ```dart
/// final greeting = hello();
///   print(greeting);
/// ```
String hello() => 'hello';
''';
      final [s] = snippetsOf(source);
      expect(s.fenceLine, 3);
      expect(s.lines, ['final greeting = hello();', '  print(greeting);']);
      expect(s.lineOf(1), 5);
      expect(s.columns, [4, 4]);
      expect(s.skipped, isFalse);
    });

    test('keeps the indentation of a member doc comment in its columns', () {
      const source = '''
class A {
  /// ```dart
  /// A().b();
  /// ```
  void b() {}
}
''';
      final [s] = snippetsOf(source);
      expect(s.lines, ['A().b();']);
      expect(s.columns, [6]);
    });

    test('takes no block tagged otherwise, nor one in a plain comment', () {
      const source = '''
/// ```text
/// not dart
/// ```
// ```dart
// not a doc comment
// ```
void f() {}
''';
      expect(snippetsOf(source), isEmpty);
    });

    test('marks dart-nocheck and a first line // not analyzed as skipped', () {
      const source = '''
/// ```dart-nocheck
/// anything at all
/// ```
///
/// ```dart
///
/// // not analyzed
/// still anything
/// ```
void f() {}
''';
      expect([for (final s in snippetsOf(source)) s.skipped], [true, true]);
    });

    test('ends an unclosed block where the doc comment ends', () {
      const source = '''
/// ```dart
/// f();
void f() {}

/// ```dart
/// g();
/// ```
void g() {}
''';
      final [s] = snippetsOf(source);
      expect(s.lines, ['g();']);
    });
  });

  group('preambleOf', () {
    test('splits the lines after // Examples can assume: into imports and '
        'declarations, up to the first line that is no // comment', () {
      const source = '''
import 'dart:io';

// Examples can assume:
// import 'package:test/test.dart';
// late int count;
//
// void tick() {}

/// Doc.
int f() => 0;
''';
      final p = preambleOf(source);
      expect(p.imports, [(4, "import 'package:test/test.dart';")]);
      expect(p.declarations, [(5, 'late int count;'), (7, 'void tick() {}')]);
    });

    test('is none without the block', () {
      final p = preambleOf('void f() {}\n');
      expect(p.imports, isEmpty);
      expect(p.declarations, isEmpty);
    });
  });

  group('shapeOf', () {
    test('takes declarations and a main as a compilation unit', () {
      expect(shapeOf('class A {}\nvoid main() => A();'), Shape.unit);
    });

    test('takes statements as the body of a function', () {
      expect(shapeOf('final a = 1;\nprint(a);'), Shape.statements);
      expect(shapeOf('await Future<void>.value();'), Shape.statements);
    });

    test('takes a call with no semicolon as an expression', () {
      expect(shapeOf("Text(\n  'hi',\n)"), Shape.expression);
    });

    test('takes what parses as nothing as statements, for the analyzer to '
        'report', () {
      expect(shapeOf('final = ;'), Shape.statements);
    });
  });

  group('generate', () {
    Snippet snippet(List<String> lines) => Snippet(
      fenceLine: 10,
      lines: lines,
      columns: [for (final _ in lines) 4],
      skipped: false,
    );

    test("imports the libraries and the preamble's imports, and traces "
        'each line of the example back to its line and columns', () {
      final g = generate(
        snippet(['final a = count;', 'print(a);']),
        const Preamble(
          [(3, "import 'package:test/test.dart';")],
          [(4, 'late int count;')],
        ),
        ['package:p/p.dart'],
      );
      expect(g.shape, Shape.statements);
      final lines = g.text.split('\n');
      expect(
        lines,
        containsAllInOrder([
          "import 'package:p/p.dart';",
          "import 'package:test/test.dart';",
          'late int count;',
          'Future<void> $snippetFunction() async {',
          'final a = count;',
          'print(a);',
          '}',
        ]),
      );
      final at = lines.indexOf('print(a);');
      expect(g.origins[at], (12, 4));
      expect(g.origins[lines.indexOf('late int count;')], (4, 3));
      expect(g.origins[lines.indexOf('}')], isNull);
    });

    test("puts the preamble's declarations after a compilation unit, so "
        "that the example's own imports stay first", () {
      final g = generate(
        snippet(["import 'dart:math';", 'void main() => print(pi + n);']),
        const Preamble([], [(4, 'late int n;')]),
        const [],
      );
      expect(g.shape, Shape.unit);
      final lines = g.text.split('\n');
      expect(
        lines.indexOf("import 'dart:math';"),
        lessThan(lines.indexOf('late int n;')),
      );
    });

    test('makes an expression the value of a function', () {
      final g = generate(snippet(['Text()']), Preamble.none, const []);
      expect(g.shape, Shape.expression);
      expect(g.text, contains('Object? $snippetFunction() =>\nText()\n;'));
    });
  });
}
