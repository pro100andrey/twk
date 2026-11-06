import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_api_names/api_names.dart';

/// A package `demo` in a temporary directory, with the [files] under it.
Directory demo(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('twk_api_names_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  files['pubspec.yaml'] = 'name: demo\nenvironment:\n  sdk: ^3.5.0\n';
  files['.dart_tool/package_config.json'] =
      '{"configVersion": 2, "packages": [{"name": "demo", '
      '"rootUri": "../", "packageUri": "lib/", '
      '"languageVersion": "3.5"}]}';
  files.forEach((path, text) {
    File('${dir.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  });
  return dir;
}

void main() {
  group('publicNames', () {
    test('follows exports through a barrel, with show and hide', () async {
      final dir = demo({
        'lib/src/a.dart': '''
class Alpha {}
class Beta {}
class Gamma {}
class _Private {}
mixin Mix {}
enum Color { red }
typedef Cb = void Function();
extension Ext on int {}
extension type Id(int v) {}
void run() {}
const answer = 42;
int counter = 0;
int get size => 1;
set size(int v) {}
int get readOnly => 1;
''',
        'lib/demo.dart': '''
export 'src/a.dart' hide Gamma, _Private;
''',
        'lib/small.dart': '''
export 'src/a.dart' show Alpha, run;
''',
      });
      final names = await publicNames(dir.path);
      expect(
        names.map((n) => n.line),
        [
          'demo.dart class Alpha',
          'demo.dart class Beta',
          'demo.dart enum Color',
          'demo.dart extension Ext',
          'demo.dart extension type Id',
          'demo.dart mixin Mix',
          'demo.dart typedef Cb',
          'demo.dart function run',
          'demo.dart const answer',
          'demo.dart variable counter',
          'demo.dart getter readOnly',
          'demo.dart getter size',
          'small.dart class Alpha',
          'small.dart function run',
        ]..sort(),
      );
    });

    test('leaves out lib/src and part files', () async {
      final dir = demo({
        'lib/src/hidden.dart': 'class Hidden {}\n',
        'lib/whole.dart': "part 'whole_part.dart';\nclass Whole {}\n",
        'lib/whole_part.dart': "part of 'whole.dart';\nclass InPart {}\n",
      });
      final names = await publicNames(dir.path);
      expect(names.map((n) => n.line), [
        'whole.dart class InPart',
        'whole.dart class Whole',
      ]);
    });
  });

  test('renderNames sorts, one line each, ending in a newline', () {
    expect(
      renderNames(const [
        ApiName('b.dart', 'class', 'B'),
        ApiName('a.dart', 'class', 'A'),
        ApiName('a.dart', 'class', 'A'),
      ]),
      'a.dart class A\nb.dart class B\n',
    );
    expect(renderNames(const []), '');
  });

  group('Rules.parse', () {
    test('reads ban and allow lines, skipping comments', () {
      final rules = Rules.parse('''
# a comment

ban Link -- says nothing
allow pkg Link -- it is a hyperlink
''');
      expect(rules.banned, {'Link': 'says nothing'});
      expect(rules.allowed.single.package, 'pkg');
      expect(rules.allowed.single.name, 'Link');
      expect(rules.allowed.single.reason, 'it is a hyperlink');
    });

    test('refuses an exception without a reason', () {
      expect(() => Rules.parse('allow pkg Link\n'), throwsFormatException);
      expect(() => Rules.parse('allow pkg Link --  \n'), throwsFormatException);
      expect(() => Rules.parse('ban Link\n'), throwsFormatException);
    });
  });

  group('checkRules', () {
    final rules = Rules.parse('''
ban Link -- vague
allow pkg Link -- right here
''');
    const link = ApiName('pkg.dart', 'class', 'Link');
    const other = ApiName('pkg.dart', 'class', 'Other');

    test('passes a name with its exception', () {
      expect(
        checkRules(rules, {
          'pkg': [link, other],
        }),
        isEmpty,
      );
    });

    test('names a banned name and what to do', () {
      final problems = checkRules(Rules.parse('ban Link -- vague\n'), {
        'pkg': [link, other],
      });
      expect(problems, hasLength(1));
      expect(problems.single, contains('pkg exports `Link`'));
      expect(problems.single, contains('allow pkg Link -- <why>'));
      expect(problems.single, contains('Rename it'));
    });

    test('an exception is for its package only', () {
      final problems = checkRules(rules, {
        'pkg': [link],
        'second': [link],
      });
      expect(problems.single, contains('second exports `Link`'));
    });

    test('fails an exception that matches no name', () {
      final problems = checkRules(rules, {
        'pkg': [other],
      });
      expect(problems, hasLength(1));
      expect(problems.single, contains('allows `Link` in pkg'));
      expect(problems.single, contains('Remove the line'));
    });
  });
}
