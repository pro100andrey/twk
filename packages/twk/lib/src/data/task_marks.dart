/// What a [TaskList] and a `ProgressList` both show of a task's status:
/// its mark, the mark's style and the columns it takes. Not exported:
/// imported by the two of them alone.
library;

import 'package:twk_core/twk_core.dart' show TextSegmenter;

import '../animation/spinner.dart';
import '../style/style.dart';
import 'task_list.dart';

/// What a task's mark is drawn from: the [frames] of a running task and
/// the [glyphs] of the other statuses.
final class TaskMarks {
  /// The marks of [glyphs], a running task's [frames].
  const TaskMarks(this.frames, this.glyphs);

  /// The default marks: [Glyphs.unicode] and its spinner.
  static const unicode = TaskMarks(SpinnerFrames.dots, Glyphs.unicode);

  /// What a running task's mark shows in turn.
  final SpinnerFrames frames;

  /// The marks of the other statuses.
  final Glyphs glyphs;

  /// The mark of a task at [status]: for a running task, the frame at
  /// [step].
  String mark(TaskItemStatus status, int step) {
    switch (status) {
      case TaskItemStatus.pending:
        return glyphs.taskPending;
      case TaskItemStatus.running:
        final f = frames.frames;
        return f[step % f.length];
      case TaskItemStatus.done:
        return glyphs.check;
      case TaskItemStatus.failed:
        return glyphs.cross;
      case TaskItemStatus.skipped:
        return glyphs.taskSkipped;
    }
  }

  /// The columns a task's mark takes: those of the widest mark and frame,
  /// one at least.
  int width(TextSegmenter segmenter) {
    var most = 1;
    void measure(String mark) {
      final w = segmenter.width(mark);
      most = w > most ? w : most;
    }

    measure(glyphs.taskPending);
    measure(glyphs.check);
    measure(glyphs.cross);
    measure(glyphs.taskSkipped);
    frames.frames.forEach(measure);
    return most;
  }

  @override
  bool operator ==(Object other) =>
      other is TaskMarks && other.frames == frames && other.glyphs == glyphs;

  @override
  int get hashCode => Object.hash(frames, glyphs);
}

/// The style of the mark of a task at [status] in [theme], as a
/// [TaskList] and a `ProgressList` paint it.
Style taskMarkStyle(ThemeData theme, TaskItemStatus status) => switch (status) {
  TaskItemStatus.pending || TaskItemStatus.skipped => theme.muted,
  TaskItemStatus.running => theme.primary,
  TaskItemStatus.done => theme.success,
  TaskItemStatus.failed => theme.error,
};
