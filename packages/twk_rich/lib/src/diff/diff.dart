/// Diffs shown unified or side by side, with a gutter of line numbers.
///
/// [diffLists] finds where two lists differ, by Myers' algorithm. A [Diff]
/// is read from a unified diff ([Diff.parse]) or found between two texts
/// ([Diff.between]): [FileDiff]s of [DiffHunk]s of [DiffLine]s.
/// [changedWords] finds the words a changed line changed. [DiffView]
/// shows a diff in a [DiffLayout], its code highlighted, in the styles of
/// a [DiffTheme].
library;

import 'diff_theme.dart';
import 'diff_view.dart';
import 'model.dart';
import 'myers.dart';
import 'words.dart';

export 'diff_theme.dart';
export 'diff_view.dart';
export 'model.dart';
export 'myers.dart';
export 'words.dart';
