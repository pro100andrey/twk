/// The `twk` command: developer tools for apps built on twk. As a library,
/// what its commands are made of: `runTwk`, which runs it on a command
/// line; `Cast`, `CastHeader`, `CastEvent` and `CastWriter`, the asciicast
/// v2 recordings `twk record` writes and `twk play` plays; `formatLine` and
/// `formatRecord`, a record of an app's log as `twk logs` shows it.
///
/// `package:twk_dev/cast_frames.dart` plays a recording through the test
/// emulator, a screen a frame.
library;

export 'src/cast.dart' show Cast, CastEvent, CastHeader, CastWriter;
export 'src/cli.dart' show runTwk, usageExitCode;
export 'src/logs.dart' show formatLine, formatRecord;
