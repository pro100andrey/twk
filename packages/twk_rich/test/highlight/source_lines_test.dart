// dartSourceLines: the source a traceback shows, highlighted as Dart from
// the top of its file.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';

const _source = '''
/* The configuration of the tool,
   read from JSON. */
Never fail() {
  throw StateError('no "name"');
}
''';

void main() {
  late File file;

  setUp(() {
    // under the working directory, so that it is the app's own code
    final dir = Directory('.dart_tool').createTempSync('sl').absolute;
    addTearDown(() => dir.deleteSync(recursive: true));
    file = File('${dir.path}/source.dart')..writeAsStringSync(_source);
  });

  test("in a traceback: the code in the theme's syntax colours, a line "
      'inside a comment that opens above it a comment', () {
    const theme = ThemeData.terminal(Brightness.dark);
    final syntax = SyntaxTheme.from(theme);
    List<List<Span>> at(int line) => traceback(
      StateError('no "name"'),
      StackTrace.fromString('#0      fail (${file.uri}:$line:3)\n'),
      context: 0,
      sourceLines: dartSourceLines,
    );
    final marked = at(4)[3];
    expect(
      marked.firstWhere((s) => s.text == 'throw').style,
      syntax.keyword,
    );
    expect(
      marked.firstWhere((s) => s.text.startsWith("'")).style,
      syntax.string,
    );
    final inComment = at(2)[3];
    expect(
      inComment.map((s) => s.text).join(),
      '  ▶ 2 │    read from JSON. */',
    );
    expect(inComment.last.style, syntax.comment);
  });
}
