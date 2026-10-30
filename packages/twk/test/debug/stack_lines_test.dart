// A stack alone as the console shows it, for a console program's
// traceback: a frame a line, the frames not of the app's own code folded
// between the app's, or every frame shown; which frames are the app's.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// The platform's separator, in the paths a stack's file: URIs give.
final String sep = Platform.pathSeparator;

void main() {
  final app = Uri.file('${Directory.current.path}/bin/tool.dart');
  final cached = Uri.file(
    '${Directory.systemTemp.path}/.pub-cache/hosted/args-2.0.0/lib/args.dart',
  );
  final stack = StackTrace.fromString('''
#0      Config.load ($app:42:7)
#1      _rootRun (dart:async/zone.dart:1399:13)
#2      MarkdownView.build (package:twk_rich/src/markdown/view.dart:120:9)
#3      ArgParser.parse ($cached:10:3)
<asynchronous suspension>
#4      main ($app:12:3)
#5      Element.rebuild (package:twk/src/framework/framework.dart:100:7)
''');

  test('folds the runs of frames not of the app between its own, saying '
      'how many and whose, an asynchronous stack in a row', () {
    expect(
      [for (final l in stackLines(stack)) (l.kind, l.text)],
      [
        (RecordLineKind.frame, 'bin${sep}tool.dart:42:7  Config.load'),
        (RecordLineKind.folded, '… 3 frames of dart:async, twk_rich, packages'),
        (RecordLineKind.frame, 'bin${sep}tool.dart:12:3  main'),
        (RecordLineKind.folded, '… 1 frame of twk'),
      ],
    );
  });

  test('shows every frame without fold, or where none is the app', () {
    final all = stackLines(stack, fold: false);
    expect([for (final l in all) l.kind], everyElement(RecordLineKind.frame));
    expect(
      [for (final l in all) l.frame!.member],
      [
        'Config.load',
        '_rootRun',
        'MarkdownView.build',
        'ArgParser.parse',
        'main',
        'Element.rebuild',
      ],
    );
    final library = StackTrace.fromString('''
#0      _rootRun (dart:async/zone.dart:1399:13)
#1      Element.rebuild (package:twk/src/framework/framework.dart:100:7)
''');
    expect(stackLines(library), hasLength(2));
  });

  test("a frame is the app's own outside the SDK, twk and its packages, "
      'and the pub cache', () {
    expect(
      [for (final l in stackLines(stack, fold: false)) l.frame!.isAppCode],
      [true, false, false, false, true, false],
    );
    // a package of the app's, by the file it resolves to or by its name
    expect(
      RecordFrame(
        Uri.parse('package:my_app/a.dart'),
        null,
        1,
        1,
        'a',
      ).isAppCode,
      isTrue,
    );
    expect(
      RecordFrame(
        Uri.parse('package:twk_rich/a.dart'),
        null,
        1,
        1,
        'a',
      ).isAppCode,
      isFalse,
    );
  });

  test('a line it cannot parse is shown as it is', () {
    final lines = stackLines(StackTrace.fromString('not a stack\n\n  at x'));
    expect(
      [for (final l in lines) (l.kind, l.text, l.frame)],
      [
        (RecordLineKind.frame, 'not a stack', null),
        (RecordLineKind.frame, '  at x', null),
      ],
    );
  });
}
