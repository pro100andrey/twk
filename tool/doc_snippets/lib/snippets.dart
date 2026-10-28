/// The ```dart examples of `///` doc comments: found in a file, made into
/// a Dart file of their own that compiles in the package they document,
/// and the generated file's lines traced back to the doc comment's.
///
/// The conventions (doc/internals/quality/README.md):
///
/// - Every fenced block tagged `dart` in a `///` comment is analyzed;
///   blocks tagged otherwise (`text`, `sh`, ...) are not.
/// - A block tagged `dart-nocheck`, or whose first line is
///   `// not analyzed`, is shown as Dart and not analyzed.
/// - The block sees every public library of its package (the files directly
///   in `lib/`).
/// - A file may name what its examples can assume, in a plain `//` comment
///   at the top level whose first line is `// Examples can assume:`: each
///   line after it, up to the first that is not a `//` comment, is Dart —
///   an `import` goes with the imports, anything else is declared at the
///   top level beside every example of the file.
/// - A block that parses as a compilation unit (declarations, a `main`) is
///   taken as it is; one that parses as statements goes into the body of
///   an async function; anything else is taken as one expression.
library;

import 'package:analyzer/dart/analysis/utilities.dart';

/// A ```dart block of a doc comment.
final class Snippet {
  /// The block whose fence opens on [fenceLine], its code starting on the
  /// line after it.
  const Snippet({
    required this.fenceLine,
    required this.lines,
    required this.columns,
    required this.skipped,
  });

  /// The line of the opening fence, from 1.
  final int fenceLine;

  /// The code, a line of the file each, without the `///`.
  final List<String> lines;

  /// For each of [lines], how many characters of the file's line come
  /// before it (the indentation and the `/// `).
  final List<int> columns;

  /// Whether the block is marked not to be analyzed.
  final bool skipped;

  /// The line of the file [index] of [lines] is on, from 1.
  int lineOf(int index) => fenceLine + 1 + index;
}

/// What a file's examples can assume: its `// Examples can assume:` block.
final class Preamble {
  /// The block's imports and declarations, each with its line in the file.
  const Preamble(this.imports, this.declarations);

  /// None.
  static const none = Preamble([], []);

  /// The `import` lines, each with its line in the file (from 1).
  final List<(int, String)> imports;

  /// The other lines, each with its line in the file (from 1).
  final List<(int, String)> declarations;
}

final _docLine = RegExp(r'^(\s*/// ?)(.*)$');
final _fence = RegExp(r'^\s*```(.*)$');

/// The ```dart blocks of the `///` comments of [source].
List<Snippet> snippetsOf(String source) {
  final lines = source.split('\n');
  final found = <Snippet>[];
  int? open;
  var tag = '';
  var code = <String>[];
  var columns = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final m = _docLine.firstMatch(lines[i]);
    if (m == null) {
      open = null;
      continue;
    }
    final text = m[2]!;
    final fence = _fence.firstMatch(text);
    if (open == null) {
      if (fence != null) {
        open = i + 1;
        tag = fence[1]!.trim();
        code = [];
        columns = [];
      }
      continue;
    }
    if (fence != null && fence[1]!.trim().isEmpty) {
      if (tag == 'dart' || tag == 'dart-nocheck') {
        final first = code.firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        );
        found.add(
          Snippet(
            fenceLine: open,
            lines: code,
            columns: columns,
            skipped: tag == 'dart-nocheck' || first.trim() == '// not analyzed',
          ),
        );
      }
      open = null;
      continue;
    }
    code.add(text);
    columns.add(m[1]!.length);
  }
  return found;
}

/// The `// Examples can assume:` block of [source], or [Preamble.none].
Preamble preambleOf(String source) {
  final lines = source.split('\n');
  final start = lines.indexWhere((l) => l.trim() == '// Examples can assume:');
  if (start < 0) {
    return Preamble.none;
  }
  final imports = <(int, String)>[];
  final declarations = <(int, String)>[];
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith('//') || line.startsWith('///')) {
      break;
    }
    final text = line.substring(line.startsWith('// ') ? 3 : 2);
    if (text.trim().isEmpty) {
      continue;
    }
    (text.trimLeft().startsWith('import ') ? imports : declarations).add((
      i + 1,
      text,
    ));
  }
  return Preamble(imports, declarations);
}

/// How a snippet's code is put into its file.
enum Shape {
  /// Top-level declarations, as they are.
  unit,

  /// Statements, the body of a function.
  statements,

  /// One expression, the value of a function.
  expression,
}

/// The name of the function a snippet's statements or expression go in.
const snippetFunction = 'docSnippet';

/// How [code] parses: as a compilation unit, statements, or one
/// expression; statements when it parses as none of them, so that the
/// analyzer reports the syntax errors where they are.
Shape shapeOf(String code) {
  bool parses(String text) =>
      parseString(content: text, throwIfDiagnostics: false).errors.isEmpty;
  if (parses(code)) {
    return Shape.unit;
  }
  if (parses('Future<void> f() async {\n$code\n}')) {
    return Shape.statements;
  }
  if (parses('Object? f() =>\n$code\n;')) {
    return Shape.expression;
  }
  return Shape.statements;
}

/// A generated file: its text, and where each of its lines came from.
final class Generated {
  /// The file [text], whose line `i + 1` came from [origins]`[i]`.
  const Generated(this.text, this.origins, this.shape);

  /// The Dart file.
  final String text;

  /// For each line of [text], the line of the source file it came from
  /// (from 1) and the columns that come before it there; null for a line
  /// the generator wrote.
  final List<(int, int)?> origins;

  /// How the snippet was put in.
  final Shape shape;
}

/// The Dart file for [snippet] of a file whose [preamble] is given, seeing
/// the libraries [imports] (`package:` URIs).
Generated generate(
  Snippet snippet,
  Preamble preamble,
  List<String> imports,
) {
  final shape = shapeOf(snippet.lines.join('\n'));
  final text = <String>[];
  final origins = <(int, int)?>[];
  void wrote(String line) {
    text.add(line);
    origins.add(null);
  }

  void copied(List<(int, String)> lines) {
    for (final (line, code) in lines) {
      text.add(code);
      origins.add((line, 3));
    }
  }

  void body() {
    for (var i = 0; i < snippet.lines.length; i++) {
      text.add(snippet.lines[i]);
      origins.add((snippet.lineOf(i), snippet.columns[i]));
    }
  }

  wrote(
    '// Generated by tool/doc_snippets: the example at line '
    '${snippet.fenceLine}.',
  );
  for (final uri in imports) {
    wrote("import '$uri';");
  }
  copied(preamble.imports);
  switch (shape) {
    case Shape.unit:
      body();
      copied(preamble.declarations);
    case Shape.statements:
      copied(preamble.declarations);
      wrote('Future<void> $snippetFunction() async {');
      body();
      wrote('}');
    case Shape.expression:
      copied(preamble.declarations);
      wrote('Object? $snippetFunction() =>');
      body();
      wrote(';');
  }
  return Generated('${text.join('\n')}\n', origins, shape);
}
