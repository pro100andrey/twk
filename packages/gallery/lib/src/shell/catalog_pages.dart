// The catalog's groups and pages joined with the pages that draw them.
import '../catalog.dart';
import '../page.dart';
import '../route.dart';

/// A group of the gallery's list.
final class ShellGroup {
  ShellGroup(this.title, this.source);

  final String title;
  final String source;
  final pages = <ShellPage>[];

  String get slug => slugOf(title);
}

/// A page of the gallery's list: what the catalog says of it, and the
/// [def] that draws it (none yet: a placeholder).
final class ShellPage {
  ShellPage(this.group, this.index, this.title, this.about, this.def);

  final ShellGroup group;

  /// Where it is in its group, from 0.
  final int index;

  final String title;
  final String about;
  final GalleryPage? def;

  String get slug => slugOf(title);

  /// `group/page`, as a route names it.
  String get key => '${group.slug}/$slug';

  @override
  String toString() => key;
}

/// [title] as a route names it.
String slugOf(String title) => slug(title);

/// The catalog's groups, each page joined with the one of [defs] of its
/// group and title. A def the catalog has no place for is an error, as is
/// a second def of a page.
List<ShellGroup> joinCatalog(List<GalleryPage> defs) {
  final byName = <String, GalleryPage>{};
  for (final d in defs) {
    final name = '${d.group}\u0000${d.title}';
    if (byName.containsKey(name)) {
      throw StateError('two pages for ${d.group} › ${d.title}');
    }
    byName[name] = d;
  }
  final groups = <ShellGroup>[];
  for (final g in catalog) {
    final group = ShellGroup(g.title, g.source);
    for (final (i, p) in g.pages.indexed) {
      final def = byName.remove('${g.title}\u0000${p.title}');
      group.pages.add(ShellPage(group, i, p.title, def?.about ?? p.about, def));
    }
    groups.add(group);
  }
  if (byName.isNotEmpty) {
    final names = [for (final d in byName.values) '${d.group} › ${d.title}'];
    throw StateError('pages not in the catalog: ${names.join(', ')}');
  }
  return groups;
}
