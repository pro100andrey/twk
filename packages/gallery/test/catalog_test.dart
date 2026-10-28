import 'package:gallery/gallery.dart';
import 'package:test/test.dart';

void main() {
  test("the catalog has the design's 20 groups and 143 pages", () {
    expect(catalog, hasLength(20));
    expect(catalog.fold(0, (n, g) => n + g.pages.length), 143);
    expect(catalog.first.title, 'Text');
    expect(catalog.last.title, 'Terminal');
  });

  test('every page that draws has its place in the catalog, once', () {
    final places = {
      for (final g in catalog)
        for (final p in g.pages) '${g.title} › ${p.title}',
    };
    final drawn = [for (final p in galleryPages) '${p.group} › ${p.title}'];
    expect(drawn.toSet(), hasLength(drawn.length));
    for (final d in drawn) {
      expect(places, contains(d));
    }
  });

  test('the example pages draw, one of each kind', () {
    final drawn = {for (final p in galleryPages) '${p.group} › ${p.title}'};
    expect(
      drawn,
      containsAll([
        'Text › Text',
        'Controls › Button',
        'Data › Sparkline',
        'Overlays › Dialog',
      ]),
    );
  });

  test('routes name every page apart', () {
    final keys = {
      for (final g in catalog)
        for (final p in g.pages) '${slug(g.title)}/${slug(p.title)}',
    };
    expect(keys, hasLength(143));
  });

  test("every page's options start where they say and write their Code", () {
    for (final page in galleryPages) {
      final o = Options.initial(page);
      for (final opt in page.options) {
        expect(o.raw(opt.key), opt.initialRaw, reason: opt.key);
        expect(o.label(opt.key), isNotEmpty);
      }
      expect(o.route, isEmpty, reason: page.title);
      // in no room yet and in a small one, as a narrow stage gives it
      for (final room in const [StageRoom.unbounded, StageRoom(40, 6)]) {
        expect(
          page.codeOf(o, room),
          page.hasCode ? isNotEmpty : isNull,
          reason: page.title,
        );
      }
    }
  });
}
