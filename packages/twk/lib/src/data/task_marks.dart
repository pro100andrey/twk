/// What a [TaskList] and a `ProgressList` both show of a task's status:
/// its mark, the mark's style and the columns it takes. Not exported:
/// imported by the two of them alone.
library;

import 'package:twk_core/twk_core.dart' show TextSegmenter;

import '../animation/spinner.dart';
import '../style/style.dart';
import 'task_list.dart';

/// The marks of the statuses but [TaskStatus.running], one column wide.
const _marks = ['◦', '', '✓', '✗', '↓'];

/// The mark of a task at [status], as a [TaskList] and a `ProgressList`
/// show it: for a running task, the frame of [frames] at [step].
String taskMark(TaskStatus status, SpinnerFrames frames, int step) {
  if (status != TaskStatus.running) {
    return _marks[status.index];
  }
  final f = frames.frames;
  return f[step % f.length];
}

/// The style of the mark of a task at [status] in [theme], as a
/// [TaskList] and a `ProgressList` paint it.
Style taskMarkStyle(ThemeData theme, TaskStatus status) => switch (status) {
  TaskStatus.pending || TaskStatus.skipped => theme.muted,
  TaskStatus.running => theme.primary,
  TaskStatus.done => theme.success,
  TaskStatus.failed => theme.error,
};

/// The columns a task's mark takes: those of the widest mark and frame of
/// [frames], one at least.
int taskMarkWidth(TextSegmenter segmenter, SpinnerFrames frames) {
  var most = 1;
  for (final mark in [..._marks, ...frames.frames]) {
    final w = segmenter.width(mark);
    most = w > most ? w : most;
  }
  return most;
}
