import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/src/unicode/bidi.dart';
import 'package:twk_core/src/unicode/unicode.dart' show unicodeVersion;

/// Where the conformance files of the tables' Unicode version are kept once
/// downloaded: at 7.6 and 6.6 MB they are too large to commit.
final _cache = Directory('.dart_tool/ucd/$unicodeVersion');

/// The conformance file [name] of the Unicode version of the tables,
/// downloaded on first use; null when it can't be.
Future<File?> _conformance(String name) async {
  final file = File('${_cache.path}/$name');
  if (file.existsSync()) {
    return file;
  }
  final url = 'https://www.unicode.org/Public/$unicodeVersion/ucd/$name';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    _cache.createSync(recursive: true);
    final part = File('${file.path}.part');
    await response.pipe(part.openWrite());
    return part.renameSync(file.path);
  } on IOException {
    return null;
  } finally {
    client.close();
  }
}

/// A character of each class, for BidiTest.txt, which gives classes; none
/// is a bracket.
const _sample = <BidiClass, int>{
  BidiClass.l: 0x61,
  BidiClass.r: 0x05D0,
  BidiClass.al: 0x0627,
  BidiClass.en: 0x31,
  BidiClass.es: 0x2B,
  BidiClass.et: 0x24,
  BidiClass.an: 0x0660,
  BidiClass.cs: 0x2C,
  BidiClass.nsm: 0x0300,
  BidiClass.bn: 0xAD,
  BidiClass.b: 0x2029,
  BidiClass.s: 0x09,
  BidiClass.ws: 0x20,
  BidiClass.on: 0x21,
  BidiClass.lre: 0x202A,
  BidiClass.lro: 0x202D,
  BidiClass.rle: 0x202B,
  BidiClass.rlo: 0x202E,
  BidiClass.pdf: 0x202C,
  BidiClass.lri: 0x2066,
  BidiClass.rli: 0x2067,
  BidiClass.fsi: 0x2068,
  BidiClass.pdi: 0x2069,
};

/// The classes rule X9 removes, which the conformance files give no level.
const _removed = <BidiClass>{
  BidiClass.lre,
  BidiClass.rle,
  BidiClass.lro,
  BidiClass.rlo,
  BidiClass.pdf,
  BidiClass.bn,
};

/// What [text], one paragraph and one line, resolves to: the level of each
/// code point and the code points in visual order, both by code point index
/// and without those rule X9 removes; and the paragraph level.
({List<int?> levels, List<int> order, int paragraph}) _run(
  String text,
  TextDirection? direction,
) {
  final bidi = BidiText(text, direction: direction);
  final lineLevels = bidi.lineLevels(0, text.length);
  final index = <int, int>{}; // code unit -> code point index
  final levels = <int?>[];
  for (var i = 0; i < text.length;) {
    final cp = text.codePointAt(i);
    index[i] = levels.length;
    levels.add(_removed.contains(bidiClassOf(cp)) ? null : lineLevels[i]);
    i += cp > 0xFFFF ? 2 : 1;
  }
  final order = <int>[];
  for (final run in bidi.visualRuns(0, text.length)) {
    final starts = [
      for (
        var i = run.start;
        i < run.end;
        i += text.codePointAt(i) > 0xFFFF ? 2 : 1
      )
        index[i]!,
    ];
    for (final k in run.level.isOdd ? starts.reversed : starts) {
      if (levels[k] != null) {
        order.add(k);
      }
    }
  }
  return (levels: levels, order: order, paragraph: bidi.paragraphs[0].level);
}

List<int?> _levels(String field) => [
  for (final t in field.trim().split(RegExp(r'\s+')))
    if (t.isNotEmpty) int.tryParse(t),
];

List<int> _ints(String field) => [
  for (final t in field.trim().split(RegExp(r'\s+')))
    if (t.isNotEmpty) int.parse(t),
];

extension on String {
  int codePointAt(int i) {
    final c = codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < length) {
      final lo = codeUnitAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        return 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
      }
    }
    return c;
  }
}

void main() {
  group(
    'UAX #9 conformance (Unicode $unicodeVersion)',
    timeout: const Timeout(Duration(minutes: 5)),
    () {
      File? classes;
      File? characters;
      setUpAll(() async {
        classes = await _conformance('BidiTest.txt');
        characters = await _conformance('BidiCharacterTest.txt');
      });

      test('BidiTest.txt', () {
        final file = classes;
        if (file == null) {
          markTestSkipped('BidiTest.txt could not be downloaded');
          return;
        }
        var levels = <int?>[];
        var order = <int>[];
        var cases = 0;
        final failures = <String>[];
        for (final (n, raw) in file.readAsLinesSync().indexed) {
          final line = raw.split('#').first.trim();
          if (line.isEmpty) {
            continue;
          }
          if (line.startsWith('@Levels:')) {
            levels = _levels(line.substring('@Levels:'.length));
            continue;
          }
          if (line.startsWith('@Reorder:')) {
            order = _ints(line.substring('@Reorder:'.length));
            continue;
          }
          if (line.startsWith('@')) {
            continue;
          }
          final [input, bits] = line.split(';');
          final text = String.fromCharCodes([
            for (final name in input.trim().split(RegExp(r'\s+')))
              _sample[BidiClass.values.byName(name.toLowerCase())]!,
          ]);
          final set = int.parse(bits.trim(), radix: 16);
          for (final (bit, direction) in [
            (1, null),
            (2, TextDirection.ltr),
            (4, TextDirection.rtl),
          ]) {
            if (set & bit == 0) {
              continue;
            }
            cases++;
            final got = _run(text, direction);
            if (!_equal(got.levels, levels) || !_equal(got.order, order)) {
              failures.add(
                'line ${n + 1} ($input, ${direction ?? 'auto'}): levels '
                '${got.levels}, order ${got.order}',
              );
            }
          }
        }
        expect(cases, greaterThan(700000));
        expect(
          failures,
          isEmpty,
          reason:
              '${cases - failures.length} of $cases passed; first failures:\n'
              '${failures.take(20).join('\n')}',
        );
      });

      test('BidiCharacterTest.txt', () {
        final file = characters;
        if (file == null) {
          markTestSkipped('BidiCharacterTest.txt could not be downloaded');
          return;
        }
        var cases = 0;
        final failures = <String>[];
        for (final (n, raw) in file.readAsLinesSync().indexed) {
          final line = raw.split('#').first.trim();
          if (line.isEmpty) {
            continue;
          }
          final [cps, dir, paragraph, levels, order] = line.split(';');
          final text = String.fromCharCodes([
            for (final cp in cps.trim().split(' ')) int.parse(cp, radix: 16),
          ]);
          final direction = switch (dir) {
            '0' => TextDirection.ltr,
            '1' => TextDirection.rtl,
            _ => null,
          };
          cases++;
          final got = _run(text, direction);
          if (got.paragraph != int.parse(paragraph) ||
              !_equal(got.levels, _levels(levels)) ||
              !_equal(got.order, _ints(order))) {
            failures.add(
              'line ${n + 1}: paragraph ${got.paragraph}, levels '
              '${got.levels}, order ${got.order}',
            );
          }
        }
        expect(cases, greaterThan(90000));
        expect(
          failures,
          isEmpty,
          reason:
              '${cases - failures.length} of $cases passed; first failures:\n'
              '${failures.take(20).join('\n')}',
        );
      });
    },
  );

  group('properties', () {
    test('Bidi_Class, defaults of unassigned code points included', () {
      expect(bidiClassOf(0x61), BidiClass.l);
      expect(bidiClassOf(0x05D0), BidiClass.r);
      expect(bidiClassOf(0x0627), BidiClass.al);
      expect(bidiClassOf(0x0661), BidiClass.an);
      expect(bidiClassOf(0x0300), BidiClass.nsm);
      expect(bidiClassOf(0x2067), BidiClass.rli);
      expect(bidiClassOf(0x10800), BidiClass.r, reason: 'Cypriot');
      expect(bidiClassOf(0x05FF), BidiClass.r, reason: 'unassigned Hebrew');
      expect(bidiClassOf(0x20CF), BidiClass.et, reason: 'unassigned currency');
      expect(bidiClassOf(0xFDD0), BidiClass.bn, reason: 'noncharacter');
      expect(bidiClassOf(0xE0001), BidiClass.bn, reason: 'language tag');
    });

    test('Bidi_Mirroring_Glyph', () {
      expect(bidiMirror(0x28), 0x29);
      expect(bidiMirror(0x29), 0x28);
      expect(bidiMirror(0xAB), 0xBB);
      expect(bidiMirror(0x2264), 0x2265);
      expect(bidiMirror(0x61), 0x61);
    });
  });

  group('BidiText', () {
    test('text without right-to-left characters is left to right', () {
      final bidi = BidiText('plain text, 42 (ok)');
      expect(bidi.isLeftToRight, isTrue);
      expect(bidi.levels.every((l) => l == 0), isTrue);
      expect(bidi.visual(0, 19), 'plain text, 42 (ok)');
    });

    test('a right-to-left word in a left-to-right line', () {
      const text = 'abc \u05D0\u05D1\u05D2 def';
      final bidi = BidiText(text);
      expect(bidi.paragraphs.single.direction, TextDirection.ltr);
      expect(bidi.visualRuns(0, text.length).map((r) => (r.start, r.level)), [
        (0, 0),
        (4, 1),
        (7, 0),
      ]);
      expect(bidi.visual(0, text.length), 'abc \u05D2\u05D1\u05D0 def');
    });

    test('a right-to-left paragraph mirrors its brackets', () {
      const text = '\u05D0\u05D1\u05D2 (abc)';
      final bidi = BidiText(text);
      expect(bidi.paragraphs.single.direction, TextDirection.rtl);
      expect(bidi.visual(0, text.length), '(abc) \u05D2\u05D1\u05D0');
    });

    test('marks stay after their bases', () {
      // shin with shin dot and qamats, lamed, vav with holam, final mem
      const text = '\u05E9\u05C1\u05B8\u05DC\u05D5\u05B9\u05DD';
      expect(
        BidiText(text).visual(0, text.length),
        '\u05DD\u05D5\u05B9\u05DC\u05E9\u05C1\u05B8',
      );
    });

    test('numbers keep their order in right-to-left text', () {
      const text = '\u05D0 123 \u05D1';
      expect(BidiText(text).visual(0, text.length), '\u05D1 123 \u05D0');
    });

    test('a forced direction', () {
      final bidi = BidiText('abc', direction: TextDirection.rtl);
      expect(bidi.paragraphs.single.level, 1);
      expect(bidi.levels, [2, 2, 2]);
      expect(bidi.visual(0, 3), 'abc');
      expect(
        BidiText('\u05D0\u05D1', direction: TextDirection.ltr).levels,
        [1, 1],
      );
    });

    test('paragraphs end after their separators, CR LF counted as one', () {
      const text = 'abc\r\n\u05D0\u05D1\u2029x';
      final bidi = BidiText(text);
      expect(bidi.paragraphs.map((p) => (p.start, p.end, p.level)), [
        (0, 5, 0),
        (5, 8, 1),
        (8, 9, 0),
      ]);
      expect(bidi.paragraphAt(6).level, 1);
      expect(bidi.paragraphAt(text.length).start, 8);
      expect(BidiText('').paragraphs.map((p) => (p.start, p.end)), [(0, 0)]);
    });

    test('rule L1 resets separators and trailing whitespace per line', () {
      const text = '\u05D0 \u05D1\t\u05D2';
      final bidi = BidiText(text, direction: TextDirection.ltr);
      expect(bidi.levels, [1, 1, 1, 1, 1]);
      expect(bidi.lineLevels(0, 5), [1, 1, 1, 0, 1]);
      expect(bidi.lineLevels(0, 2), [1, 0], reason: 'a line ending at 2');
    });

    test('surrogate pairs share a level and stay whole', () {
      const text = 'a \u{10800}\u{10801}';
      final bidi = BidiText(text);
      expect(bidi.levels, [0, 0, 1, 1, 1, 1]);
      expect(bidi.visual(0, text.length), 'a \u{10801}\u{10800}');
    });

    test('isolates keep their content out of the surrounding text', () {
      // a left-to-right name, isolated, in a right-to-left sentence
      const text = '\u05D0 \u2068abc 1\u2069 \u05D1';
      final bidi = BidiText(text);
      expect(bidi.paragraphs.single.level, 1);
      expect(
        bidi.visual(0, text.length),
        '\u05D1 \u2069abc 1\u2068 \u05D0',
      );
    });
  });
}

bool _equal(List<int?> a, List<int?> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
