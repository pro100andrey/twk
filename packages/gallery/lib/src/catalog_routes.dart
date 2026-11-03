// The catalog's pages as routes name them: the one walk over the catalog
// that the tests, the Code check and the tools share.
import 'catalog.dart';
import 'route.dart';

/// Where a page of the catalog is: its `group`, the `page`, and the
/// `path` of its route, `controls/button`.
typedef PagePlace = ({CatalogGroup group, CatalogPage page, String path});

/// The path of [page] of [group] in a route: `controls/button`.
String pagePath(CatalogGroup group, CatalogPage page) =>
    '${slug(group.title)}/${slug(page.title)}';

/// Every page of the catalog, in the order of its list.
Iterable<PagePlace> get pagePlaces sync* {
  for (final group in catalog) {
    for (final page in group.pages) {
      yield (group: group, page: page, path: pagePath(group, page));
    }
  }
}

/// The route of every page of the catalog as it opens: `#/controls/button`.
Iterable<String> get pageRoutes => pagePlaces.map((p) => '#/${p.path}');

/// Whether [route] names a page of the catalog, or none (the gallery then
/// opens at its first).
bool namesAPage(GalleryRoute route) =>
    route.group == null ||
    pagePlaces.any((p) => p.path == '${route.group}/${route.page}');
