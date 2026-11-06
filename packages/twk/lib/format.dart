/// How the widgets write sizes and times, for an app to write them the same
/// way: [formatBytes] a size in decimal (`4.1 kB`) or binary units
/// ([ByteUnits.binary], `4.0 KiB`), and [formatTook] the time something took
/// (`3.1 s`, `01:05`).
///
/// @docImport 'src/foundation/format.dart';
library;

export 'src/foundation/format.dart' show ByteUnits, formatBytes, formatTook;
