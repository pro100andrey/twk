/// What packages/twk asks of the process it runs in: its environment, which
/// `TWK_SCREEN_READER` and `TWK_DEBUG` are read from, and its files and
/// directories, which a `FilePicker` lists, a `DirectoryTree` lists, reads
/// the `.gitignore` files of and watches, the log console is saved to
/// and a `WidgetError` reads the source it shows from, and the programs
/// the console opens code in. The package
/// reaches dart:io through here only, as the core does through its own:
/// `io.dart` on the VM; on the web, which has none of these, `web.dart`
/// stands in, so that nothing a web app compiles in imports dart:io.
library;

export 'io.dart' if (dart.library.js_interop) 'web.dart';
