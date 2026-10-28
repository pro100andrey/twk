/// The twk gallery: every widget on a page of its own, in the gallery's
/// shell (doc/design.md). [galleryApp] is the whole app, for `runApp` or
/// a headless test; [GalleryRoute] says where it opens, as a URL hash
/// would.
library;

import 'package:twk/twk.dart';

import 'src/motion.dart';
import 'src/pages/pages.dart';
import 'src/route.dart';
import 'src/shell/shell.dart';

export 'src/catalog.dart' show CatalogGroup, CatalogPage, catalog;
export 'src/motion.dart' show Clock;
export 'src/page.dart';
export 'src/pages/pages.dart' show galleryPages;
export 'src/route.dart' show GalleryRoute, slug;
export 'src/shell/shell.dart' show GalleryShell, GalleryShellState, Zone;

/// The gallery, opened at [route] (the first page, dark, when null), on
/// [clock]: by default the app's, or stopped at the route's `t=`. The
/// terminal's title is `twk gallery`, which a page's own `WindowTitle`
/// gives way to while it shows (App › Window title).
Widget galleryApp({GalleryRoute? route, Clock? clock}) {
  final t = route?.t;
  return WindowTitle(
    title: 'twk gallery',
    child: GalleryShell(
      key: ValueKey(route?.toString()),
      pages: galleryPages,
      route: route,
      clock: clock ?? (t == null ? const Clock.app() : Clock.frozen(t)),
    ),
  );
}
