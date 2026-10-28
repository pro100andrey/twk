// The lines of source around a frame of a stack, as data: found as a
// WidgetError finds them, or read around any line, with as many lines of
// context as asked; its text the WidgetError's.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    // under the working directory, so that it is shown from it
    dir = Directory('.dart_tool').createTempSync('source_excerpt_');
    addTearDown(() => dir.deleteSync(recursive: true));
    // the path a stack's file: URI gives, with the platform's separator
    file = File('${dir.absolute.path}${Platform.pathSeparator}app.dart')
      ..writeAsStringSync(
        [for (var i = 1; i <= 12; i++) 'line $i'].join('\n'),
      );
  });

  test('of a stack: the first frame of the app, two lines around it, the '
      'path from the working directory', () {
    final excerpt = SourceExcerpt.of(
      StackTrace.fromString('''
#0      _rootRun (dart:async/zone.dart:1399:13)
#1      Element.rebuild (package:twk/src/framework/framework.dart:100:7)
#2      main (${file.uri}:5:3)
'''),
    )!;
    expect(excerpt.path, file.path);
    expect((excerpt.line, excerpt.column), (5, 3));
    expect((excerpt.firstLine, excerpt.lastLine), (3, 7));
    expect(excerpt.lines, ['line 3', 'line 4', 'line 5', 'line 6', 'line 7']);
    expect(excerpt.fileLines, hasLength(12));
    final shown = '${dir.path}${Platform.pathSeparator}app.dart';
    expect(excerpt.shownPath, shown);
    expect(excerpt.location, '$shown:5:3');
    expect('$excerpt', '''
at $shown:5:3
  3 | line 3
  4 | line 4
> 5 | line 5
  6 | line 6
  7 | line 7''');
  });

  test('as many lines of context as asked, within the file', () {
    final stack = StackTrace.fromString('#0      main (${file.uri}:11)\n');
    final none = SourceExcerpt.of(stack, context: 0)!;
    expect(none.lines, ['line 11']);
    expect(none.column, isNull);
    expect(none.location, endsWith('app.dart:11'));
    final more = SourceExcerpt.of(stack, context: 4)!;
    expect((more.firstLine, more.lastLine), (7, 12));
    expect('$more'.split('\n')[5], '> 11 | line 11');
  });

  test('read: around any line of a file; null where it cannot be', () {
    final at = SourceExcerpt.read(file.path, 1, column: 2, context: 1)!;
    expect(at.lines, ['line 1', 'line 2']);
    expect(at.location, endsWith('app.dart:1:2'));
    expect(SourceExcerpt.read(file.path, 13), isNull);
    expect(SourceExcerpt.read(file.path, 0), isNull);
    expect(SourceExcerpt.read('${dir.path}/gone.dart', 1), isNull);
    expect(
      SourceExcerpt.of(
        StackTrace.fromString('#0      main (package:no_such/a.dart:2:1)\n'),
      ),
      isNull,
    );
    expect(SourceExcerpt.of(null), isNull);
  });
}
