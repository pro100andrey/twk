import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_skill_references/skill_references.dart';

/// A widget page as `catalog.dart` writes it.
String page(String title, String about, {String package = 'twk'}) =>
    '''
---
title: "$title"
group: "Controls"
package: "$package"
about: "$about"
image: "packages/gallery/doc/shots/controls/x.dark.svg"
route: "#/controls/x"
---
# $title

$about

| Dark | Light |
| --- | --- |
| ![$title, dark](../../../packages/gallery/doc/shots/controls/x.dark.svg) | ![$title, light](../../../packages/gallery/doc/shots/controls/x.light.svg) |

## Code

The Dart that builds it, as the gallery's Code tab shows it with the
options as they start:

```dart
// ## not a heading
Widget build(BuildContext context) => $title();
```

## Options

What the gallery lets you change, and what each starts at:

| option | values | starts at |
| --- | --- | --- |
| tall | on, off | false |

## More

- API: [`$title`](https://pub.dev/documentation/twk/latest/twk/$title-class.html).
- Live in the gallery:
  `dart run packages/gallery/bin/gallery.dart --route='#/controls/x'`.
- [Controls](../controls.md) · [All groups](../README.md)
''';

Map<String, String> catalog({String buttonAbout = 'A label pressed.'}) => {
  'README.md': '''
---
title: "Widget catalog"
---
| | |
| --- | --- |
| [![Controls](x.svg)](controls.md)<br>**[Controls](controls.md)**<br>Buttons. 2 pages. | |
''',
  'controls.md': '''
---
title: "Controls"
about: "Buttons and fields."
pages: 2
---
# Controls

| | |
| --- | --- |
| [![Button](x.svg)](controls/button.md)<br>**[Button](controls/button.md)**<br>x | [![Rich, Text](x.svg)](controls/rich-text.md)<br>**[Rich, Text](controls/rich-text.md)**<br>y |
''',
  'controls/button.md': page('Button', buttonAbout),
  'controls/rich-text.md': page('Rich, Text', 'Spans.', package: 'twk_rich'),
};

const guide = '''
---
title: "Layout"
---
# Layout

See [testing](testing.md#a), [the catalog](../widgets/README.md), [a group](../widgets/controls.md),
[Button](../widgets/controls/button.md), [the survey](../internals/perf/survey.md),
[a site](https://example.com/a) and [a
wrapped](../../packages/twk/x.md) link.

| ![Button](../../packages/gallery/doc/shots/controls/x.dark.svg)<br>**[Button](../widgets/controls/button.md)** |

```dart
final a = [x](../../packages/not_touched.md);
```
''';

Map<String, String> build({Map<String, String>? widgets}) => buildReferences(
  docWidgets: widgets ?? catalog(),
  docGuides: {'layout.md': guide, 'testing.md': '# Testing\n'},
);

void main() {
  group('widgets.md', () {
    test(
      'has a line a widget with its about, by group, and the group file',
      () {
        final index = build()['widgets.md']!;
        expect(index, contains('## Controls'));
        expect(index, contains('File: `widgets/controls.md`'));
        expect(index, contains('- Button: A label pressed.\n'));
        expect(index, contains('- Rich, Text (`twk_rich`): Spans.\n'));
      },
    );
  });

  group('the front matter', () {
    String about(String json) =>
        page('X', 'unused').replaceFirst('about: "unused"', 'about: $json');

    test('decodes every escape of a JSON string', () {
      final read = readWidgetPage(
        'controls/x.md',
        about(r'"a \" \\ \/ \b\f\n\r\t é 😀"'),
      );
      expect(read.about, 'a " \\ / \b\f\n\r\t é \u{1f600}');
    });

    test('fails naming the page where an escape is malformed', () {
      for (final json in [r'"cut \u12"', r'"bad \q"', r'"\uzzzz"']) {
        expect(
          () => readWidgetPage('controls/x.md', about(json)),
          throwsA(
            isA<ReferenceError>().having(
              (e) => e.message,
              'message',
              contains('doc/widgets/controls/x.md'),
            ),
          ),
          reason: json,
        );
      }
    });
  });

  group('widgets/<group>.md', () {
    final text = build()['widgets/controls.md']!;

    test(
      'has each widget in the group page order, with code and options',
      () {
        expect(
          text.indexOf('## Button'),
          lessThan(text.indexOf('## Rich, Text')),
        );
        expect(
          text,
          contains('Widget build(BuildContext context) => Button();'),
        );
        expect(text, contains('// ## not a heading'));
        expect(
          text,
          contains('### Options\n\n| option | values | starts at |'),
        );
        expect(text, contains('Package: `twk_rich`.'));
        expect(text, contains('API: [`Button`](https://pub.dev'));
      },
    );

    test('has no picture, no image path and no gallery boilerplate', () {
      expect(text, isNot(contains('.svg')));
      expect(text, isNot(contains('![')));
      expect(text, isNot(contains('shots/')));
      expect(text, isNot(contains('The Dart that builds it')));
      expect(text, isNot(contains('Live in the gallery')));
    });
  });

  group('guides', () {
    test('code is left as it is: a span, a fence with its indent', () {
      const guide =
          'Call `handlers[i](event)` here, and write `![a](b.svg)`.\n\n'
          '- A list:\n\n'
          '  ```dart\n'
          '  callbacks[i](e);\n'
          '  ```\n\n'
          '~~~\n'
          '[a](b)\n'
          '~~~\n';
      expect(rewriteGuide('g.md', guide, const {}), guide);
    });

    test('a linked picture leaves its link, the picture gone', () {
      expect(
        rewriteGuide('g.md', 'See [![a](s.svg)](other.md).\n', const {}),
        'See [](other.md).\n',
      );
    });

    test('a link whose text is a code span is still a link', () {
      expect(
        rewriteGuide('g.md', 'See [`Text`](../dropped/x.md).\n', const {}),
        'See `Text`.\n',
      );
    });

    final text = build()['guides/layout.md']!;

    test('keep links to guides, groups and addresses', () {
      expect(text, contains('[testing](testing.md#a)'));
      expect(text, contains('[a group](../widgets/controls.md)'));
      expect(text, contains('[a site](https://example.com/a)'));
    });

    test('send the catalog to widgets.md and a widget to its heading', () {
      expect(text, contains('[the catalog](../widgets.md)'));
      expect(text, contains('[Button](../widgets/controls.md#button)'));
    });

    test('drop pictures, and links to what is not in the references', () {
      expect(text, isNot(contains('.svg')));
      expect(text, contains('the survey,'));
      expect(text, contains('a\nwrapped link'));
      expect(text, contains('**[Button](../widgets/controls.md#button)** |'));
    });

    test('leave fenced code as it is', () {
      expect(text, contains('final a = [x](../../packages/not_touched.md);'));
    });

    test('fail on a link to a widget page the catalog has not', () {
      expect(
        () => buildReferences(
          docWidgets: catalog(),
          docGuides: {'a.md': '[x](../widgets/controls/nope.md)'},
        ),
        throwsA(isA<ReferenceError>()),
      );
    });

    test('fail on a link to a guide that is not there', () {
      expect(
        () => buildReferences(
          docWidgets: catalog(),
          docGuides: {'a.md': '[x](nope.md)'},
        ),
        throwsA(
          isA<ReferenceError>().having(
            (e) => e.message,
            'message',
            contains('guides/a.md'),
          ),
        ),
      );
    });
  });

  group('the catalog', () {
    test('is read the same each time', () {
      expect(build(), build());
    });

    test('a change in a widget about reaches widgets.md and its group', () {
      final before = build();
      final after = build(
        widgets: catalog(buttonAbout: 'A label, pressed twice.'),
      );
      final changed = [
        for (final k in before.keys)
          if (before[k] != after[k]) k,
      ];
      expect(changed, ['widgets.md', 'widgets/controls.md']);
      expect(
        after['widgets.md'],
        contains('- Button: A label, pressed twice.'),
      );
    });

    test('fails naming the page where a group and its pages disagree', () {
      final widgets = catalog()..remove('controls/rich-text.md');
      expect(
        () => build(widgets: widgets),
        throwsA(
          isA<ReferenceError>().having(
            (e) => e.message,
            'message',
            contains('doc/widgets/controls.md'),
          ),
        ),
      );
    });
  });

  group('the repository own catalog and guides', () {
    final root = _root();
    Map<String, String> read(String dir) => {
      for (final e in Directory('$root/$dir').listSync(recursive: true))
        if (e is File && e.path.endsWith('.md'))
          e.path.substring(root.length + dir.length + 2): e.readAsStringSync(),
    };
    final files = buildReferences(
      docWidgets: read('doc/widgets'),
      docGuides: read('doc/guides'),
    );

    test('give references whose every link lands', () {
      final link = RegExp(r'(?<!!)\[[^\]]*\]\(([^)\s]*)\)');
      for (final MapEntry(:key, :value) in files.entries) {
        final prose = value.replaceAll(
          RegExp(r'^```.*?^```$', multiLine: true, dotAll: true),
          '',
        );
        for (final m in link.allMatches(prose)) {
          final target = m.group(1)!;
          if (RegExp('^[a-z]+:').hasMatch(target)) {
            continue;
          }
          final parts = target.split('#');
          final dir = key.contains('/')
              ? key.substring(0, key.lastIndexOf('/'))
              : '';
          final path = Uri.parse('/$dir/${parts.first}')
              .normalizePath()
              .path
              .substring(1);
          final text = parts.first.isEmpty ? value : files[path];
          expect(text, isNotNull, reason: '$key links to $target');
          if (parts.length > 1) {
            final anchors = {
              for (final h in RegExp(
                r'^#{1,6} (.*)$',
                multiLine: true,
              ).allMatches(text!))
                anchorOf(h.group(1)!),
            };
            expect(
              anchors,
              contains(parts[1]),
              reason: '$key links to $target',
            );
          }
        }
      }
    });

    test('have no picture', () {
      for (final MapEntry(:key, :value) in files.entries) {
        expect(value, isNot(contains('.svg')), reason: key);
        expect(value, isNot(contains('shots/')), reason: key);
      }
    });
  });
}

String _root() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/xtask.yaml').existsSync()) {
    dir = dir.parent;
  }
  return dir.path;
}
