// The examples of the CommonMark spec and of GFM's extensions, parsed and
// written as HTML the way the reference implementations write it.
//
// spec.json holds the examples of the CommonMark Spec 0.31.2 by John
// MacFarlane (https://spec.commonmark.org/0.31.2/spec.json), gfm.json those
// of the tables, task list items, strikethrough and autolinks extensions of
// the GitHub Flavored Markdown Spec 0.29-gfm (https://github.github.com/gfm/);
// both under CC BY-SA 4.0.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'html.dart';

/// The CommonMark examples left out, by why.
const unsupported = {
  'raw HTML is text': [
    21, 31, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, //
    160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187,
    188, 189, 190, 191, 201, 308, 309, 344, 475, 476, 477, 491, 494, 524,
    536, 613, 614, 615, 616, 617, 623, 625, 626, 627, 628, 629, 630, 631,
    642, 643,
  ],
  'a reference is parsed before its label is known to be defined: within '
      'link text it is text, where CommonMark makes it the link and the '
      'link around it text': [
    533,
  ],
  'brackets that leave emphasis in them unmatched, which emphasis around '
      'them may match, are text rather than a shortcut reference: the label '
      'is not known to be defined when they are parsed': [
    564,
  ],
  'a full reference whose label is not defined is text whole, where '
      'CommonMark makes its label the text of the reference that follows': [
    569,
    571,
  ],
  'character references by names HTML 4 does not have are text': [25],
  "GFM's extended autolinks make links of URLs and email addresses in the "
      'text': [
    606,
    608,
    611,
    612,
  ],
};

/// The examples in the spec file [name] of this directory.
List<({int number, String section, String markdown, String html})> examples(
  String name,
) => [
  for (final example in jsonDecode(
    File('test/markdown/$name').readAsStringSync(),
  ) as List<Object?>)
    if (example case {
      'example': final int number,
      'section': final String section,
      'markdown': final String markdown,
      'html': final String html,
    })
      (number: number, section: section, markdown: markdown, html: html),
];

/// The blocks of the Markdown document [markdown], its references resolved.
List<MdBlock> resolved(String markdown) {
  final stream = MarkdownStream(markdown);
  return resolveReferences(stream.blocks, stream.definitions);
}

void main() {
  final skipped = {
    for (final MapEntry(key: reason, value: numbers) in unsupported.entries)
      for (final number in numbers) number: reason,
  };
  final commonMark = examples('spec.json');

  group('CommonMark 0.31.2', () {
    for (final example in commonMark) {
      test(
        'example ${example.number}: ${example.section}',
        () => expect(html(resolved(example.markdown)), example.html),
        skip: skipped[example.number],
      );
    }
  });

  group('GFM 0.29 extensions', () {
    for (final example in examples('gfm.json')) {
      test(
        'example ${example.number}: ${example.section}',
        () => expect(html(resolved(example.markdown)), example.html),
      );
    }
  });

  test('every example left out fails', () {
    final failing = [
      for (final example in commonMark)
        if (skipped.containsKey(example.number) &&
            html(resolved(example.markdown)) != example.html)
          example.number,
    ];
    expect(failing, skipped.keys.toList()..sort());
  });
}
