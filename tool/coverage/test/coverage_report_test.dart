import 'package:test/test.dart';
import 'package:twk_coverage/coverage_report.dart';
import 'package:twk_doc_snippets/declarations.dart';
import 'package:twk_doc_snippets/packages.dart';

void main() {
  const source = '''
/// A box.
class Box {
  /// Its size.
  int size() {
    return 1;
  }

  /// Grows it.
  void grow() {
    print('grown');
  }

  void _shrink() {
    print('shrunk');
  }
}
''';
  final declarations = declarationsOf(source);

  test('ranges joins consecutive lines', () {
    expect(ranges([1, 2, 3, 5, 7, 8]), '1-3, 5, 7-8');
    expect(ranges([]), '');
  });

  test('a public member with a line no test runs is a gap, with those '
      'lines; a private one and a type are not', () {
    final f = FileCoverage('lib/box.dart', declarations, {
      4: 1,
      5: 1,
      9: 1,
      10: 0,
      13: 0,
      14: 0,
    });
    final [(d, missed, all)] = f.uncoveredPublic();
    expect((d.name, all), ('Box.grow', 2));
    expect(missed, [10]);
    expect(f.uncovered, [10, 13, 14]);
    expect(f.lines, 6);
  });

  test('a file no test loads counts every public member as a gap', () {
    final f = FileCoverage('lib/box.dart', declarations, null);
    expect(f.loaded, isFalse);
    expect(f.uncoveredPublic(), isEmpty);
    expect(
      [for (final d in f.publicDeclarations) d.name],
      [
        'Box.size',
        'Box.grow',
      ],
    );
    final t = Totals.of([f]);
    expect((t.gaps, t.unloaded, t.notLoaded), (2, 2, 1));
    expect((t.lines, t.percent), (0, '-'));
  });

  test('browserOnly finds an import of a library only a browser has', () {
    expect(browserOnly("import 'dart:js_interop';\n"), isTrue);
    expect(browserOnly("import 'dart:js_interop_unsafe';\n"), isTrue);
    expect(browserOnly("import 'package:web/web.dart' as web;\n"), isTrue);
    expect(browserOnly('import "dart:html";\n'), isTrue);
    expect(browserOnly("import 'dart:io';\n// import 'dart:html';\n"), isFalse);
    expect(browserOnly("import 'package:webby/webby.dart';\n"), isFalse);
  });

  test('a browser-only file no test loads is listed as such, and not '
      'counted as a gap', () {
    final files = [
      FileCoverage('lib/a.dart', declarations, {4: 1, 9: 1}),
      FileCoverage('lib/c.dart', declarations, null),
      FileCoverage('lib/w.dart', declarations, null, browser: true),
    ];
    final t = Totals.of(files);
    expect((t.gaps, t.unloaded, t.notLoaded, t.browser), (2, 2, 1, 1));
    final report = coverageReport(
      const RepoPackage('/r', 'packages/p', 'p'),
      files,
      'abc1234',
      passed: true,
    );
    expect(
      report,
      contains(
        '**2** public declarations no test runs all of: 0 with lines no '
        'test runs, 2 in the 1 file no test loads; the 1 browser-only file '
        'not counted.',
      ),
    );
    final order = [
      '## Files no test loads',
      '- `packages/p/lib/c.dart`: `Box.size`, `Box.grow`',
      '## Browser-only files',
      '- `packages/p/lib/w.dart`: `Box.size`, `Box.grow`',
      '## Files by uncovered lines',
    ];
    var at = 0;
    for (final line in order) {
      final i = report.indexOf(line, at);
      expect(i, greaterThanOrEqualTo(0), reason: 'no "$line" after $at');
      at = i;
    }
  });

  test('a file of constants no test loads has no gaps: the compiler makes '
      'their values, no test runs them', () {
    final f = FileCoverage(
      'lib/glyphs.dart',
      declarationsOf('''
/// Glyphs.
const glyphs = ['a', 'b'];

/// Sizes.
abstract final class Sizes {
  /// The least.
  static const least = 1;
}
'''),
      null,
    );
    expect(f.publicDeclarations, isEmpty);
    expect(Totals.of([f]).gaps, 0);
  });

  test('the report lists the public gaps first, then the files no test '
      'loads, then the files by uncovered lines, most first', () {
    final files = [
      FileCoverage('lib/a.dart', declarations, {4: 1, 9: 1, 10: 0}),
      FileCoverage('lib/b.dart', declarations, {4: 0, 5: 0, 9: 0, 10: 0}),
      FileCoverage('lib/c.dart', declarations, null),
      FileCoverage('lib/d.dart', declarations, {4: 1}),
    ];
    final report = coverageReport(
      const RepoPackage('/r', 'packages/p', 'p'),
      files,
      'abc1234',
      passed: false,
    );
    expect(report, contains('At abc1234,'));
    expect(report, contains('**37.5 %** of 8 lines'));
    expect(
      report,
      contains(
        '**5** public declarations no test runs all of: 3 with lines no '
        'test runs, 2 in the 1 file no test loads.',
      ),
    );
    expect(report, contains('The tests failed'));
    final order = [
      '## Public declarations',
      '### `packages/p/lib/b.dart` (4 lines)',
      '- `4` method `Box.size`: 2 of 2 lines (4-5)',
      '### `packages/p/lib/a.dart` (1 line)',
      '## Files no test loads',
      '- `packages/p/lib/c.dart`: `Box.size`, `Box.grow`',
      '## Files by uncovered lines',
      '| `packages/p/lib/b.dart` | 4 | 4 | 4-5, 9-10 |',
      '| `packages/p/lib/a.dart` | 1 | 3 | 10 |',
      '1 file has every line run.',
    ];
    var at = 0;
    for (final line in order) {
      final i = report.indexOf(line, at);
      expect(i, greaterThanOrEqualTo(0), reason: 'no "$line" after $at');
      at = i;
    }
  });
}
