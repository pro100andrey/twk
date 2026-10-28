/// A record of the log shown whole in the console: its message and error
/// line by line, then its stack, frame by frame, as [recordLines] lays
/// them out; a stack alone so ([stackLines]), for a console program's
/// traceback.
library;

import 'package:stack_trace/stack_trace.dart';
import 'package:twk_core/twk_core.dart' show LogRecord, stringWidth;

import '../binding/source_excerpt.dart' show inPubCache, sdkOrTwk, shownPath;
import '../platform/platform.dart' show sourcePath;

/// What a line of a record shown whole is.
enum RecordLineKind {
  /// A line of the record's message.
  message,

  /// A line of its error.
  error,

  /// A frame of its stack.
  frame,

  /// Frames of its stack folded into one line: of the SDK, of twk, of a
  /// package in the pub cache, between those of the app's own code.
  folded,
}

/// Where a frame of a stack is: the [uri] of its library, the [path] of
/// its file where the program can say (a `file:` URI, a `package:` one it
/// resolves), its [line] and [column] where the stack tells them, and the
/// [member] that ran.
final class RecordFrame {
  /// A frame of [uri] at [line] and [column], in [path], running [member].
  const RecordFrame(this.uri, this.path, this.line, this.column, this.member);

  /// The URI of the frame's library.
  final Uri uri;

  /// The file the library is in; null where the program can't say.
  final String? path;

  /// The line, from 1; null where the stack doesn't tell it.
  final int? line;

  /// The column, from 1; null where the stack doesn't tell it.
  final int? column;

  /// The function, method or closure that ran.
  final String member;

  /// Whether the frame is of the app's own code: of neither the SDK, nor
  /// twk or a package of its (`package:twk_…`), nor a package in the pub
  /// cache (from pub.dev or git). The frames [stackLines] keeps where it
  /// folds the others.
  bool get isAppCode =>
      !(sdkOrTwk(uri) ||
          uri.isScheme('package') &&
              uri.pathSegments.first.startsWith('twk_') ||
          (path != null && inPubCache(path!)));

  /// `path:line:column` (the path from the working directory where it is
  /// in it), or the library's URI where there is no path.
  String get location {
    final p = path;
    final where = p != null ? shownPath(p) : '$uri';
    return [
      where,
      if (line case final l?) '$l',
      if (column case final c?) '$c',
    ].join(':');
  }
}

/// A line of a record shown whole: its [text], what it is, and for a frame
/// where it is.
final class RecordLine {
  /// A line of [text] of [kind]; [frame] for a frame of the stack.
  const RecordLine(this.text, this.kind, {this.frame});

  /// What the line reads.
  final String text;

  /// What it is a line of.
  final RecordLineKind kind;

  /// Where the frame it shows is; null but for a frame.
  final RecordFrame? frame;
}

/// [record] as lines at most [width] columns wide: its message, then its
/// error, a line of either too long broken where it reaches [width]; then
/// its stack, a frame a line (`location  member`), parsed by
/// package:stack_trace, an asynchronous stack's frames in a row. Where
/// some frames are the app's own code, the runs of the others between them
/// — the SDK's, twk's, those of packages in the pub cache — fold into a
/// line saying how many and whose; where none is, every frame shows.
List<RecordLine> recordLines(LogRecord record, int width) {
  final w = width < 8 ? 8 : width;
  final out = <RecordLine>[
    for (final line in record.message.split('\n'))
      for (final part in _broken(line, w)) RecordLine(part, .message),
  ];
  final error = record.error;
  if (error != null) {
    for (final line in '$error'.split('\n')) {
      for (final part in _broken(line, w)) {
        out.add(RecordLine(part, .error));
      }
    }
  }
  final stack = record.stack;
  if (stack != null) {
    out.addAll(stackLines(stack));
  }
  return out;
}

/// The lines of [stack], a frame a line (`location  member`), parsed by
/// package:stack_trace, an asynchronous stack's frames in a row; a line
/// it can't parse is shown as it is, without a [RecordLine.frame].
///
/// With [fold], where some frames are the app's own code
/// ([RecordFrame.isAppCode]), the runs of the others between them fold
/// into a line saying how many and whose (`… 3 frames of dart:async`);
/// where none is, or without [fold], every frame shows.
///
/// ```dart
/// for (final line in stackLines(StackTrace.current)) {
///   print(line.text);
/// }
/// ```
List<RecordLine> stackLines(StackTrace stack, {bool fold = true}) {
  final List<Frame> frames;
  try {
    frames = Chain.forTrace(stack).toTrace().frames;
  } on Object {
    return [
      for (final line in '$stack'.split('\n'))
        if (line.trim().isNotEmpty) RecordLine(line.trimRight(), .frame),
    ];
  }
  // a line package:stack_trace can't parse is shown as it is, as the
  // app's: nothing says whose it is
  final shown = [
    for (final f in frames)
      if (f is UnparsedFrame) null else _frameOf(f),
  ];
  final library = [for (final f in shown) !(f?.isAppCode ?? true)];
  final folds = fold && library.contains(false);
  final out = <RecordLine>[];
  for (var i = 0; i < shown.length;) {
    if (!folds || !library[i]) {
      final f = shown[i];
      out.add(
        f == null
            ? RecordLine(frames[i].member!.trimRight(), .frame)
            : RecordLine('${f.location}  ${f.member}', .frame, frame: f),
      );
      i++;
      continue;
    }
    final from = i;
    while (i < shown.length && library[i]) {
      i++;
    }
    final whose = <String>{for (var k = from; k < i; k++) _whose(shown[k]!)};
    final n = i - from;
    out.add(
      RecordLine(
        '… $n ${n == 1 ? 'frame' : 'frames'} of ${whose.join(', ')}',
        .folded,
      ),
    );
  }
  return out;
}

RecordFrame _frameOf(Frame f) => RecordFrame(
  f.uri,
  f.uri.isScheme('file') || f.uri.isScheme('package')
      ? sourcePath(f.uri)
      : null,
  f.line,
  f.column,
  f.member ?? '?',
);

/// Whose code a folded frame is: `dart:async`, `twk`, a package's name.
String _whose(RecordFrame f) => switch (f.uri.scheme) {
  'dart' => 'dart:${f.uri.pathSegments.first}',
  'org-dartlang-sdk' => 'the SDK',
  'package' => f.uri.pathSegments.first,
  _ => 'packages',
};

/// [line] in parts at most [width] columns wide, broken between
/// characters; a line of none is one part.
List<String> _broken(String line, int width) {
  final text = line.replaceAll('\t', '  ').trimRight();
  if (stringWidth(text) <= width) {
    return [text];
  }
  final out = <String>[];
  var start = 0;
  var columns = 0;
  for (var i = 0; i < text.length;) {
    final unit = text.codeUnitAt(i);
    final size = unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length
        ? 2
        : 1;
    final w = stringWidth(text.substring(i, i + size));
    if (columns + w > width && i > start) {
      out.add(text.substring(start, i));
      start = i;
      columns = 0;
    }
    columns += w;
    i += size;
  }
  out.add(text.substring(start));
  return out;
}
