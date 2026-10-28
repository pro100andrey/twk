// tool/catalog.dart: the widget catalog's front matter, packages, links
// and cards.
import 'package:gallery/gallery.dart';
import 'package:test/test.dart';

import '../tool/catalog.dart';

void main() {
  test('front matter: each value a JSON string, nulls left out', () {
    expect(
      frontMatter({'title': 'Rich "text"', 'pages': 3, 'gone': null}),
      '---\ntitle: "Rich \\"text\\""\npages: 3\n---\n',
    );
  });

  test('every group is said something of, and every page has its package', () {
    for (final group in catalog) {
      expect(groupAbout, contains(group.title));
      for (final page in group.pages) {
        expect(
          ['twk', 'twk_rich', 'twk_term', 'twk_cli'],
          contains(packageOf(group, page)),
        );
      }
    }
    final app = catalog.singleWhere((g) => g.title == 'App');
    expect(
      packageOf(app, app.pages.singleWhere((p) => p.title == 'Cli')),
      'twk_cli',
    );
  });

  test('the API is linked for a class package:twk/twk.dart exports, and '
      "nothing else's", () {
    expect(
      apiLink('twk', 'Button'),
      'https://pub.dev/documentation/twk/latest/twk/Button-class.html',
    );
    expect(apiLink('twk', 'Window title'), isNull);
    expect(apiLink('twk', 'NoSuchWidget'), isNull);
    expect(apiLink('twk_rich', 'MarkdownView'), isNull);
    // declared in twk, exported by package:twk/hooks.dart alone
    expect(apiLink('twk', 'HookBuilder'), isNull);
  });

  test('cards, two a row, the last row filled out', () {
    const card = (link: 'a.md', title: 'A', image: 'a.svg', text: 'x | y');
    const shown = r'[![A](a.svg)](a.md)<br>**[A](a.md)**<br>x \| y';
    expect(
      cards([card, card, card]),
      '| | |\n| --- | --- |\n'
      '| $shown | $shown |\n'
      '| $shown |  |\n\n',
    );
  });
}
