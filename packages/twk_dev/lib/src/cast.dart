/// asciicast v2, which `twk record` writes and `twk play` plays: the
/// implementation is twk_driver's (the driver's trace is a recording too),
/// re-exported here.
///
/// `test/cast.golden.json` holds the format as this package's tests and the
/// VS Code extension's port of it (`editors/vscode/src/core/cast.ts`) read
/// it: a change to it is made there and in the golden too.
library;

export 'package:twk_driver/twk_driver.dart'
    show Cast, CastEvent, CastHeader, CastWriter;
