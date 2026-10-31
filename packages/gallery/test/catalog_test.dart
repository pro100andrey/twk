import 'package:gallery/testing.dart';
import 'package:test/test.dart';

void main() {
  test('the catalog runs from Text to Terminal, no group empty', () {
    expect(catalog.where((g) => g.pages.isEmpty), isEmpty);
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
    final paths = [for (final p in pagePlaces) p.path];
    expect(paths.toSet(), hasLength(paths.length));
  });

  test('every page of the catalog draws: none shows a placeholder', () {
    final drawn = {for (final p in galleryPages) '${p.group} › ${p.title}'};
    expect([
      for (final p in pagePlaces)
        if (!drawn.contains('${p.group.title} › ${p.page.title}')) p.path,
    ], isEmpty);
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
