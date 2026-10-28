/// Text carrying ANSI escape sequences, such as the output of a command,
/// turned into styled spans, or into the text without them.
///
/// [parseAnsi] and [AnsiStream] read it into lines of spans, the lines a
/// terminal would show it in; [stripAnsi] takes the sequences out and keeps
/// the rest of the text as it is.
library;

import 'stream.dart';
import 'strip.dart';

export 'stream.dart';
export 'strip.dart';
