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

  /// The marks of the statuses but [TaskStatus.running], one column wide.
  List<String> get _marks => [
    glyphs.taskPending,
    '',
    glyphs.check,
    glyphs.cross,
    glyphs.taskSkipped,
  ];

  /// The mark of a task at [status]: for a running task, the frame at
  /// [step].
  String mark(TaskStatus status, int step) {
    if (status != TaskStatus.running) {
      return _marks[status.index];
    }
    final f = frames.frames;
    return f[step % f.length];
  }

  /// The columns a task's mark takes: those of the widest mark and frame,
  /// one at least.
  int width(TextSegmenter segmenter) {
    var most = 1;
    for (final mark in [..._marks, ...frames.frames]) {
      final w = segmenter.width(mark);
      most = w > most ? w : most;
    }
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
Style taskMarkStyle(ThemeData theme, TaskStatus status) => switch (status) {
  TaskStatus.pending || TaskStatus.skipped => theme.muted,
  TaskStatus.running => theme.primary,
  TaskStatus.done => theme.success,
  TaskStatus.failed => theme.error,
};
