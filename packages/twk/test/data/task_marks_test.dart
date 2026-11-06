// What a TaskMarks hands out: the marks of the statuses and their width,
// without a list built per call (the frame path's rows ask for both).
import 'package:test/test.dart';
import 'package:twk/src/data/task_marks.dart';
import 'package:twk/twk.dart';

void main() {
  test('mark gives each status its glyph, a running task the frame', () {
    const marks = TaskMarks.unicode;
    const g = Glyphs.unicode;
    expect(marks.mark(TaskItemStatus.pending, 0), g.taskPending);
    expect(marks.mark(TaskItemStatus.done, 0), g.check);
    expect(marks.mark(TaskItemStatus.failed, 0), g.cross);
    expect(marks.mark(TaskItemStatus.skipped, 0), g.taskSkipped);
    final f = SpinnerFrames.dots.frames;
    expect(marks.mark(TaskItemStatus.running, 1), f[1]);
    expect(marks.mark(TaskItemStatus.running, f.length + 2), f[2]);
  });

  test('width is that of the widest mark or frame, one at least', () {
    final s = TextSegmenter();
    expect(TaskMarks.unicode.width(s), 1);
    expect(
      TaskMarks(
        SpinnerFrames.dots,
        Glyphs.unicode.copyWith(cross: '❌'),
      ).width(s),
      2,
    );
    expect(
      TaskMarks(
        SpinnerFrames.dots,
        Glyphs.unicode.copyWith(
          taskPending: '',
          check: '',
          cross: '',
          taskSkipped: '',
        ),
      ).width(s),
      1,
    );
  });
}
