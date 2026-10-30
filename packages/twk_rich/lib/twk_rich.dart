/// Rich text for widgets of the twk package: Markdown, syntax highlighting,
/// diffs, JSON trees, big text and QR codes.
///
/// Each topic is a library of its own, `src/<topic>/<topic>.dart`; this
/// library exports all of them. Images are apart, in
/// `package:twk_rich/image.dart`, which this library does not export.
library;

export 'src/bigtext/bigtext.dart';
export 'src/diff/diff.dart';
export 'src/highlight/highlight.dart';
export 'src/json_view/json_view.dart';
export 'src/markdown/markdown.dart';
export 'src/qr/qr.dart';
