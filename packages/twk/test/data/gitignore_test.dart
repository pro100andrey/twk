// Gitignore: the patterns of a .gitignore as git reads them, a table of
// cases of each rule (comments and blank lines, trailing spaces, negation,
// directory-only, anchoring, *, ?, [...], **, escapes), what match decides
// of a path itself and what ignores says of one below an ignored
// directory.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// A case: the text of the file, a path, whether it is a directory, and
/// whether the path is ignored.
typedef Case = (String text, String path, bool isDirectory, bool ignored);

const file = false;
const dir = true;

const cases = <String, List<Case>>{
  'a name matches at any depth': [
    ('foo', 'foo', file, true),
    ('foo', 'a/b/foo', file, true),
    ('foo', 'a/foo', dir, true),
    ('foo', 'foobar', file, false),
    ('foo', 'barfoo', file, false),
  ],
  'blank lines and comments are no patterns': [
    ('\n# foo\n\n', 'foo', file, false),
    ('# foo', '# foo', file, false),
    (r'\#foo', '#foo', file, true),
  ],
  "spaces at a line's end are dropped, but one a backslash keeps": [
    ('foo   ', 'foo', file, true),
    (r'foo\ ', 'foo ', file, true),
    (r'foo\ ', 'foo', file, false),
    ('foo\r', 'foo', file, true),
  ],
  '! re-includes what an earlier pattern ignored; the last match decides': [
    ('*.log\n!keep.log', 'keep.log', file, false),
    ('*.log\n!keep.log', 'a/keep.log', file, false),
    ('*.log\n!keep.log', 'run.log', file, true),
    ('!keep.log\n*.log', 'keep.log', file, true),
    (r'\!foo', '!foo', file, true),
  ],
  'a / at the end matches directories only': [
    ('build/', 'build', dir, true),
    ('build/', 'build', file, false),
    ('build/', 'src/build', dir, true),
  ],
  'a / at the start or in the middle anchors to the directory': [
    ('/foo', 'foo', file, true),
    ('/foo', 'a/foo', file, false),
    ('doc/frotz', 'doc/frotz', dir, true),
    ('doc/frotz', 'a/doc/frotz', dir, false),
    ('doc/frotz/', 'doc/frotz', dir, true),
    ('doc/frotz/', 'doc/frotz', file, false),
  ],
  '* and ? match within a name, never /': [
    ('*.dart', 'main.dart', file, true),
    ('*.dart', 'lib/src/main.dart', file, true),
    ('*.dart', 'main.dart.bak', file, false),
    ('/lib/*.dart', 'lib/a.dart', file, true),
    ('/lib/*.dart', 'lib/src/a.dart', file, false),
    ('a?c', 'abc', file, true),
    ('a?c', 'abbc', file, false),
    ('/a?c', 'a/c', file, false),
  ],
  '[...] matches one of what it lists, ! or ^ first what it does not; '
      'one not closed nothing': [
    ('[ab].txt', 'a.txt', file, true),
    ('[ab].txt', 'c.txt', file, false),
    ('[a-c].txt', 'b.txt', file, true),
    ('[a-c].txt', 'd.txt', file, false),
    ('[!a-c].txt', 'd.txt', file, true),
    ('[!a-c].txt', 'a.txt', file, false),
    ('[^a].txt', 'b.txt', file, true),
    ('[]].txt', '].txt', file, true),
    ('[a-].txt', '-.txt', file, true),
    ('[.txt', '[.txt', file, false),
    ('[.txt\n*.txt', 'a.txt', file, true),
    ('/x[!a]y', 'x/y', file, false),
  ],
  '** matches any directories': [
    ('**/foo', 'foo', file, true),
    ('**/foo', 'a/b/foo', file, true),
    ('**/foo/bar', 'x/foo/bar', file, true),
    ('abc/**', 'abc/x', file, true),
    ('abc/**', 'abc/x/y', file, true),
    ('abc/**', 'abc', dir, false),
    ('a/**/b', 'a/b', file, true),
    ('a/**/b', 'a/x/y/b', file, true),
    ('a/**/b', 'b', file, false),
    ('a**b', 'axxb', file, true),
    ('a**b', 'ax/xb', file, false),
    ('**', 'any/thing', file, true),
  ],
  'a backslash makes the next character an ordinary one': [
    (r'\*.txt', '*.txt', file, true),
    (r'\*.txt', 'a.txt', file, false),
    (r'a\?', 'a?', file, true),
    (r'a\?', 'ab', file, false),
    ('a.b', 'aXb', file, false),
    ('(a)+', '(a)+', file, true),
  ],
  'what is below an ignored directory is ignored with it': [
    ('build/', 'build/out.o', file, true),
    ('build/\n!build/keep', 'build/keep', file, true),
    ('/lib', 'lib/src/a.dart', file, true),
    ('lib/a', 'lib/b', file, false),
  ],
};

void main() {
  group('Gitignore.ignores', () {
    for (final MapEntry(key: rule, value: table) in cases.entries) {
      test(rule, () {
        for (final (text, path, isDirectory, ignored) in table) {
          expect(
            Gitignore(text).ignores(path, isDirectory: isDirectory),
            ignored,
            reason:
                '${text.replaceAll('\n', r'\n')} on $path'
                '${isDirectory ? ' (a directory)' : ''}',
          );
        }
      });
    }
  });

  group('Gitignore.match', () {
    test('tells whether the patterns decide: ignored, re-included, or '
        'neither', () {
      final ignore = Gitignore('*.log\n!keep.log\n');
      expect(ignore.match('run.log'), isTrue);
      expect(ignore.match('keep.log'), isFalse);
      expect(ignore.match('main.dart'), isNull);
    });

    test('looks at the path itself, not at the directories above it', () {
      final ignore = Gitignore('build/');
      expect(ignore.match('build/out.o'), isNull);
      expect(ignore.ignores('build/out.o'), isTrue);
    });

    test('a text of comments and blank lines is empty', () {
      expect(Gitignore('# none\n\n   \n').isEmpty, isTrue);
      expect(Gitignore('# one\nfoo').isEmpty, isFalse);
    });
  });
}
