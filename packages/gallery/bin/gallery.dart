// The twk gallery: every widget on a page of its own.
//
//   dart run packages/gallery/bin/gallery.dart
//   dart run packages/gallery/bin/gallery.dart --route='#/controls/button?theme=light'
//
// --route opens it where a route says (packages/gallery/README.md,
// "Routes"): the page, theme, options, tab, focus, filter, palette, a
// toast, the clock stopped at t=, and keys= and type= pressed and typed
// once it shows.
import 'package:gallery/src/launcher.dart';

Future<void> main(List<String> args) => runGallery(args);
