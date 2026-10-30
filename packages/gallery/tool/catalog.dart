// Writes the widget catalog, doc/widgets/ at the repository's root, from
// the gallery: an index of the groups (README.md), a page a group
// (<group>.md) listing its widgets, and a page a widget
// (<group>/<page>.md) with its pictures (doc/shots/, tool/shots.dart),
// what it is, the Dart of its Code tab, its options and links. Each page
// opens with front matter (title, group, package, about, images, route)
// for a site to read. Run from this package's directory after the
// gallery's pages or pictures changed:
//
//   dart run tool/catalog.dart
//
// `xtask catalog` runs it and fails where that changed a file.
import 'dart:convert';
import 'dart:io';

import 'package:gallery/gallery.dart';
import 'package:path/path.dart' as p;

/// What each group is, a line under its title in the index.
const groupAbout = {
  'Text':
      'Paragraphs and spans of styled text, wrapped, cut off, aligned, '
      'and right to left.',
  'Layout':
      'Boxes, rows and columns, stacks, grids and wraps: where a '
      'child goes and how much room it gets.',
  'Style':
      'Themes, the terminal’s brightness, and colors that run across '
      'a background or text.',
  'Scrolling':
      'Lists, scroll views and scrollbars, built as they scroll '
      'into view.',
  'Data': 'Tables, trees, charts, gauges, sparklines and calendars.',
  'Editing':
      'Text fields and what is drawn around them, text areas and completion '
      'as the user types.',
  'Controls':
      'Buttons, checkboxes and switches, choices, sliders, forms, '
      'tabs and status bars.',
  'Overlays':
      'Dialogs, toasts, tooltips, popovers, menus and the command '
      'palette, over the app.',
  'Animation':
      'Spinners, progress, and widgets that animate as their '
      'values change.',
  'Mouse':
      'Clicks, drags, hovers and the wheel, and where the mouse is '
      'let through.',
  'Focus and keys':
      'The focus, moved by Tab and the mouse, and the keys '
      'bound where it is.',
  'Navigation':
      'Routes, a scaffold of panes, steppers, breadcrumbs and '
      'pages.',
  'Foundation': 'Notifiers and listenables that widgets build on.',
  'Framework':
      'Stateful and inherited widgets, builders, keys and the '
      'element tree.',
  'App':
      'The app around it all: the screen modes, a fixed viewport, '
      'output kept in the scrollback, the window title, notifications and '
      'a command-line tool’s console.',
  'Screen readers': 'What the widgets are to a screen reader.',
  'Debugging':
      'The log console, the frame overlay, the repaint rainbow '
      'and repaint boundaries.',
  'Rich':
      'Markdown, code, diffs, JSON, big text, QR codes and program '
      'output with its colors.',
  'Images':
      'PNG and JPEG pictures, in the terminal’s graphics or in '
      'block characters.',
  'Terminal': 'A program running in a widget, on a pseudo-terminal.',
};

/// The room the stage gives a widget on a screen of 120 × 36, which a
/// Code that says a size from it ([GalleryPage.codeIn]) is written for.
const room = StageRoom(56, 26);

/// The repository's root, from this package's directory, which the tool
/// and its tests run in.
final String root = p.normalize(p.join(Directory.current.path, '..', '..'));

void main() {
  final out = Directory(p.join(root, 'doc', 'widgets'));
  if (out.existsSync()) {
    out.deleteSync(recursive: true);
  }
  // by group and title, as the gallery registers them
  final pages = <(String, String), GalleryPage>{};
  for (final page in galleryPages) {
    if (pages.containsKey((page.group, page.title))) {
      throw StateError('two pages ${page.title} in ${page.group}');
    }
    pages[(page.group, page.title)] = page;
  }
  var written = 0;
  void write(String path, String text) {
    File(p.join(out.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    written++;
  }

  final missing = catalog
      .map((g) => g.title)
      .where((t) => !groupAbout.containsKey(t));
  if (missing.isNotEmpty) {
    throw StateError('groupAbout says nothing of ${missing.join(', ')}');
  }
  write('README.md', indexPage());
  for (final group in catalog) {
    write('${slug(group.title)}.md', groupPage(group));
    for (final page in group.pages) {
      write(
        p.join(slug(group.title), '${slug(page.title)}.md'),
        widgetPage(group, page, pages[(group.title, page.title)]),
      );
    }
  }
  stdout.writeln('${p.relative(out.path)}: $written pages');
}

/// The package [page] of [group] needs, besides twk.
String packageOf(CatalogGroup group, CatalogPage page) =>
    group.source.startsWith('packages/') ? p.basename(group.source) : 'twk';

/// Front matter of [fields], each value a JSON string, which YAML reads.
String frontMatter(Map<String, Object?> fields) => [
  '---',
  for (final MapEntry(:key, :value) in fields.entries)
    if (value != null) '$key: ${jsonEncode(value)}',
  '---',
  '',
].join('\n');

/// The picture of [page] of [group] in [theme], as a path from the
/// repository's root.
String shot(CatalogGroup group, CatalogPage page, String theme) =>
    'packages/gallery/doc/shots/${slug(group.title)}/${slug(page.title)}'
    '.$theme.svg';

/// [path], a path from the repository's root, as a link from a file
/// [depth] directories below doc/widgets/.
String fromDoc(String path, int depth) => '${'../' * (depth + 2)}$path';

/// The route of [page] of [group] in the gallery.
String route(CatalogGroup group, CatalogPage page) =>
    '#/${slug(group.title)}/${slug(page.title)}';

String indexPage() {
  final b =
      StringBuffer(
          frontMatter({
            'title': 'Widget catalog',
            'about': 'Every widget the twk gallery shows, by group.',
          }),
        )
        ..write('''
# Widget catalog

Every widget of [twk](../../packages/twk/README.md), its console for
command-line tools among them, and those of
[twk_rich](../../packages/twk_rich/README.md) and
[twk_term](../../packages/twk_term/README.md) the gallery shows, by group.
Each has a page of its own: its pictures in the dark and the light theme,
the Dart that builds it, its options in the gallery and links to its API.
The pictures are the gallery's golden screens; to see a widget live, run
the gallery, `dart run packages/gallery/bin/gallery.dart`.

''')
        ..write(
          cards([
            for (final group in catalog)
              (
                link: '${slug(group.title)}.md',
                title: group.title,
                image: fromDoc(shot(group, group.pages.first, 'dark'), 0),
                text:
                    '${groupAbout[group.title]} ${_count(group.pages.length)}.',
              ),
          ]),
        );
  return '$b';
}

String groupPage(CatalogGroup group) {
  final b =
      StringBuffer(
          frontMatter({
            'title': group.title,
            'about': groupAbout[group.title],
            'pages': group.pages.length,
          }),
        )
        ..write('''
# ${group.title}

${groupAbout[group.title]}

[All groups](README.md)

''')
        ..write(
          cards([
            for (final page in group.pages)
              (
                link: '${slug(group.title)}/${slug(page.title)}.md',
                title: page.title,
                image: fromDoc(shot(group, page, 'dark'), 0),
                text: switch (packageOf(group, page)) {
                  'twk' => page.about,
                  final package => '${page.about} In `$package`.',
                },
              ),
          ]),
        );
  return '$b';
}

String widgetPage(CatalogGroup group, CatalogPage page, GalleryPage? def) {
  final package = packageOf(group, page);
  final about = def?.about ?? page.about;
  final b =
      StringBuffer(
        frontMatter({
          'title': page.title,
          'group': group.title,
          'package': package,
          'about': about,
          'image': shot(group, page, 'dark'),
          'image_light': shot(group, page, 'light'),
          'route': route(group, page),
        }),
      )..write('''
# ${page.title}

$about

| Dark | Light |
| --- | --- |
| ![${_alt(page.title)}, dark](${fromDoc(shot(group, page, 'dark'), 1)}) | ![${_alt(page.title)}, light](${fromDoc(shot(group, page, 'light'), 1)}) |

''');
  if (package != 'twk') {
    b.write(
      'In [$package](${fromDoc('packages/$package/README.md', 1)}), '
      'besides twk.\n\n',
    );
  }
  final options = def == null ? null : Options.initial(def);
  if (def != null && options != null) {
    if (def.codeOf(options, room) case final code?) {
      b.write('''
## Code

The Dart that builds it, as the gallery's Code tab shows it with the
options as they start:

```dart
$code
```

''');
    }
    if (def.options.isNotEmpty) {
      b.write('''
## Options

What the gallery lets you change, and what each starts at:

| option | values | starts at |
| --- | --- | --- |
''');
      for (final o in def.options) {
        final starts = _cell(options.label(o.key));
        b.writeln('| ${o.label} | ${_cell(_values(o))} | $starts |');
      }
      b.writeln();
    }
  }
  final api = [
    for (final name in page.title.split(', '))
      if (apiLink(package, name) case final link?) '[`$name`]($link)',
  ];
  b.write('''
## More

''');
  if (api.isNotEmpty) {
    b.writeln('- API: ${api.join(', ')}.');
  }
  final others = [
    for (final other in group.pages)
      if (other != page) '[${other.title}](${slug(other.title)}.md)',
  ];
  if (others.isNotEmpty) {
    b.writeln('- Also in ${group.title}: ${others.join(', ')}.');
  }
  b.write('''
- Live in the gallery:
  `dart run packages/gallery/bin/gallery.dart --route='${route(group, page)}'`.
- [${group.title}](../${slug(group.title)}.md) · [All groups](../README.md)
''');
  return '$b';
}

/// The values of [option], as the inspector names them.
String _values(PageOption option) => switch (option) {
  final ChoiceOption o => o.names.join(', '),
  final ColorOption o => o.values.join(', '),
  SwitchOption() => 'on, off',
  final SliderOption o => '${o.show(o.min)} to ${o.show(o.max)}',
};

/// The documentation of [name] on pub.dev, for a class [package]'s
/// library of the same name exports from its own files: twk's alone, the
/// one published. Not one of `package:twk/hooks.dart` or
/// `package:twk/provider.dart`, libraries of their own, nor one declared
/// and not exported.
String? apiLink(String package, String name) {
  if (package != 'twk' || !RegExp(r'^[A-Z]\w*$').hasMatch(name)) {
    return null;
  }
  final library = p.join(root, 'packages', package, 'lib', '$package.dart');
  return exportedClasses(library).contains(name)
      ? 'https://pub.dev/documentation/$package/latest/$package/$name-class.html'
      : null;
}

final _exported = <String, Set<String>>{};

/// The public classes the library at [path] declares, in it or in its
/// parts, or exports from the files of its package, following each
/// `export` with its `show` or `hide`.
Set<String> exportedClasses(String path) => _exported[path] ??= () {
  final source = File(path).readAsStringSync();
  // a library's parts declare its classes too
  final parts = [
    for (final m in RegExp(
      "^part '([^']+)';",
      multiLine: true,
    ).allMatches(source))
      File(p.join(p.dirname(path), m[1])).readAsStringSync(),
  ];
  final classes = {
    for (final m in RegExp(
      '^(?:(?:abstract|base|final|interface|sealed|mixin) )*class '
      r'([A-Z]\w*)',
      multiLine: true,
    ).allMatches([source, ...parts].join('\n')))
      m[1]!,
  };
  for (final m in RegExp(
    r"^export '([^']+)'\s*(show|hide)?([^;]*);",
    multiLine: true,
  ).allMatches(source)) {
    if (m[1]!.startsWith('package:')) {
      continue;
    }
    final names = {
      for (final n in m[3]!.split(','))
        if (n.trim().isNotEmpty) n.trim(),
    };
    final from = exportedClasses(p.join(p.dirname(path), m[1]));
    classes.addAll(switch (m[2]) {
      'show' => from.intersection(names),
      'hide' => from.difference(names),
      _ => from,
    });
  }
  return classes;
}();

/// [items] as cards, two a row of a table: each its picture and title,
/// both linking to its page, and a line under them.
String cards(
  List<({String link, String title, String image, String text})> items,
) {
  String card(({String link, String title, String image, String text}) i) =>
      '[![${_alt(i.title)}](${i.image})](${i.link})<br>'
      '**[${i.title}](${i.link})**<br>${_cell(i.text)}';
  final b = StringBuffer('| | |\n| --- | --- |\n');
  for (var i = 0; i < items.length; i += 2) {
    final right = i + 1 < items.length ? card(items[i + 1]) : '';
    b.writeln('| ${card(items[i])} | $right |');
  }
  return '$b\n';
}

String _count(int n) => n == 1 ? 'One page' : '$n pages';

String _alt(String title) => title.replaceAll(RegExp(r'[\[\]]'), '');

/// [text] in a cell of a Markdown table: its bars escaped.
String _cell(String text) => text.replaceAll('|', r'\|');
