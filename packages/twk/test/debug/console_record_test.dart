// A record shown whole in the console: its message and error line by
// line, its stack a frame a line through package:stack_trace, the runs of
// frames that are not the app's own folded; drawn in twice the list's
// rows, the selected line lit, a frame's place a link to its file.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show Shot;

import 'console_test.dart' show record;

/// A stack as the VM writes it: the app's code (a file in the working
/// directory, a package the program does not resolve) between the SDK's
/// and twk's.
/// The platform's separator, in the paths a stack's file: URIs give.
final String sep = Platform.pathSeparator;

StackTrace vmStack() {
  final app = Uri.file('${Directory.current.path}/lib/main.dart');
  return StackTrace.fromString('''
#0      main.<anonymous closure> ($app:12:5)
#1      _rootRun (dart:async/zone.dart:1399:13)
#2      Element.rebuild (package:twk/src/framework/framework.dart:100:7)
#3      MyWidget.build (package:my_app/widgets.dart:30:9)
#4      _CustomZone.run (dart:async/zone.dart:1301:19)
#5      _microtaskLoop (dart:async/schedule_microtask.dart:40:21)
''');
}

void main() {
  group('recordLines', () {
    test('the message and the error line by line, a line too long broken '
        'at the width', () {
      final lines = recordLines(
        record('first\nsecond', error: 'boom\n  ${'x' * 30}'),
        20,
      );
      expect(
        [for (final l in lines) (l.kind, l.text)],
        [
          (RecordLineKind.message, 'first'),
          (RecordLineKind.message, 'second'),
          (RecordLineKind.error, 'boom'),
          (RecordLineKind.error, '  ${'x' * 18}'),
          (RecordLineKind.error, 'x' * 12),
        ],
      );
    });

    test("the stack a frame a line, the runs of frames not the app's "
        'folded, saying how many and whose', () {
      final lines = recordLines(record('m', stack: vmStack()), 80);
      expect(
        [for (final l in lines.skip(1)) l.text],
        [
          'lib${sep}main.dart:12:5  main.<fn>',
          '… 2 frames of dart:async, twk',
          'package:my_app/widgets.dart:30:9  MyWidget.build',
          '… 2 frames of dart:async',
        ],
      );
      final frame = lines[1].frame!;
      expect(frame.path, '${Directory.current.path}${sep}lib${sep}main.dart');
      expect((frame.line, frame.column), (12, 5));
      // a package the program does not resolve has no path
      expect(lines[3].frame!.path, isNull);
      expect(lines[2].frame, isNull);
    });

    test("where no frame is the app's own, every frame shows", () {
      final stack = StackTrace.fromString('''
#0      Element.rebuild (package:twk/src/framework/framework.dart:100:7)
#1      _rootRun (dart:async/zone.dart:1399:13)
''');
      final lines = recordLines(record('m', stack: stack), 80);
      expect(
        [for (final l in lines.skip(1)) l.kind],
        [
          RecordLineKind.frame,
          RecordLineKind.frame,
        ],
      );
      expect(lines[2].text, startsWith('dart:async/zone.dart:1399:13'));
    });
  });

  group('shown whole', () {
    late ConsoleController controller;
    late Shot shot;
    setUp(() {
      final sink = LogSink()
        ..add(record('before'))
        ..add(
          record(
            'failed\nwhile building',
            level: LogLevel.error,
            error: 'boom',
            stack: vmStack(),
          ),
        );
      controller = ConsoleController(sink)
        ..open()
        ..selectPrevious();
      shot = Shot(
        Theme(
          data: ThemeData.dark,
          child: Console(
            controller: controller,
            rows: 4,
            child: const SizedBox(),
          ),
        ),
        60,
        12,
      );
    });

    test('Enter shows it in twice the rows, a line selected and moved; '
        'Escape goes back', () {
      expect(shot.rows.where((r) => r.isNotEmpty), hasLength(3));
      controller.showSelected();
      shot.frame();
      expect(shot.rows.skip(4), [
        ' 09:05:07.042 ERROR  line 1 of 7  esc back',
        ' failed',
        ' while building',
        ' boom',
        '   lib${sep}main.dart:12:5  main.<fn>',
        '   … 2 frames of dart:async, twk',
        '   package:my_app/widgets.dart:30:9  MyWidget.build',
        '   … 2 frames of dart:async',
      ]);
      expect(controller.selectedLine!.text, 'failed');
      controller.moveLine(3);
      shot.frame();
      expect(controller.selectedLine!.frame!.line, 12);
      expect(shot.rows[4], ' 09:05:07.042 ERROR  line 4 of 7  esc back');
      // the place a link to its file, the member not
      const y = 8;
      expect(
        shot.vt.cell(3, y).link,
        Uri.file('${Directory.current.path}/lib/main.dart').toString(),
      );
      expect(shot.vt.cell(24, y).link, isNull);
      // the frame of a package the program does not resolve: no link
      expect(shot.vt.cell(3, 10).link, isNull);
      controller.hideRecord();
      shot.frame();
      expect(controller.shownRecord, isNull);
      expect(shot.rows.where((r) => r.isNotEmpty), hasLength(3));
    });

    test('a window too short for its lines scrolls to the selected one', () {
      controller.showSelected();
      shot.frame();
      controller.moveLine(100);
      shot.frame();
      expect(controller.lineIndex, 6);
      expect(shot.rows.last, '   … 2 frames of dart:async');
      controller.moveLine(-100);
      shot.frame();
      expect(controller.firstLine, 0);
    });
  });
}
