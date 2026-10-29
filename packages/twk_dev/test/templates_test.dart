// The templates of `twk create`: each package in templates/ is packed into
// the source `twk create` unpacks as tool/pack_templates.dart packs it
// now, `twk create` offers each of them, and each takes the packages of
// twk by a path in the repository, which `twk create` rewrites.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/templates/templates.dart';

import '../tool/pack_templates.dart';
import 'twk.dart';

void main() {
  test('each template is packed as it is: after a change, '
      '`dart run tool/pack_templates.dart` packs it again, mold warning of '
      'nothing', () async {
    final package = await packageDirectory();
    for (final dir in templateDirectories(package)) {
      final packed = File(packedPath(package, p.basename(dir)));
      final warnings = <String>[];
      final source = await packedSource(
        dir,
        onWarning: (warning) => warnings.add('$warning'),
      );
      expect(warnings, isEmpty, reason: p.relative(dir, from: package));
      expect(
        packed.existsSync() ? packed.readAsStringSync() : null,
        source,
        reason:
            '${p.relative(dir, from: package)} changed since it was '
            'packed: dart run tool/pack_templates.dart',
      );
    }
  });

  test(
    'twk create offers each template in templates/, a package named '
    'after it that takes twk, twk_dev, twk_lints and twk_test by path',
    () async {
      final package = await packageDirectory();
      final dirs = templateDirectories(package);
      expect(
        [for (final t in templates) t.name]..sort(),
        [for (final dir in dirs) p.basename(dir)],
      );
      for (final dir in dirs) {
        final pubspec = File(p.join(dir, 'pubspec.yaml')).readAsStringSync();
        expect(pubspec, startsWith('name: ${p.basename(dir)}_template\n'));
        for (final twk in twkPackages) {
          expect(
            pubspec,
            contains('\n  $twk:\n    path: '),
            reason: '${p.basename(dir)} takes $twk by path',
          );
        }
        expect(
          withTwkFrom(pubspec),
          isNot(contains('path:')),
          reason: '${p.basename(dir)} takes nothing else by path',
        );
      }
    },
  );

  test('a pubspec that takes a package of twk by no path is a StateError', () {
    expect(
      () => withTwkFrom('name: app\ndependencies:\n  twk: ^0.1.0\n'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'The pubspec takes no twk by path',
        ),
      ),
    );
  });
  test('a pubspec without the overrides of twk, twk_core, twk_term and '
      'twk_test by path, or with others, is a StateError', () {
    const dependencies =
        'name: app\n'
        'dependencies:\n'
        '  twk:\n'
        '    path: ../../twk\n'
        '  twk_dev:\n'
        '    path: ../../twk_dev\n'
        '  twk_lints:\n'
        '    path: ../../twk_lints\n'
        '  twk_test:\n'
        '    path: ../../twk_test\n';
    Matcher refused(String overrides) => throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'message',
        'The pubspec overrides $overrides by path, not twk, twk_core, '
            'twk_term, twk_test',
      ),
    );
    expect(() => withTwkFrom(dependencies), refused('nothing'));
    expect(
      () => withTwkFrom(
        '${dependencies}dependency_overrides:\n'
        '  twk_core:\n'
        '    path: ../../twk_core\n',
      ),
      refused('twk_core'),
    );
    // the last line with no line break after it
    expect(
      withTwkFrom(
        '${dependencies}dependency_overrides:\n'
        '  twk:\n'
        '    path: ../../twk\n'
        '  twk_core:\n'
        '    path: ../../twk_core\n'
        '  twk_term:\n'
        '    path: ../../twk_term\n'
        '  twk_test:\n'
        '    path: ../../twk_test',
      ),
      isNot(contains('dependency_overrides')),
    );
  });

  test('an override not by path is a StateError that names it, wherever '
      'it is in the block, and leaves no line of the block behind', () {
    const dependencies =
        'name: app\n'
        'dependencies:\n'
        '  twk:\n'
        '    path: ../../twk\n'
        '  twk_dev:\n'
        '    path: ../../twk_dev\n'
        '  twk_lints:\n'
        '    path: ../../twk_lints\n'
        '  twk_test:\n'
        '    path: ../../twk_test\n';
    Matcher refused(String entry) => throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'message',
        'The pubspec overrides $entry by no path alone on the line under '
            'its name: an override of a template is a path',
      ),
    );
    const twk = '  twk:\n    path: ../../twk\n';
    const core =
        '  twk_core:\n    path: ../../twk_core\n'
        '  twk_term:\n    path: ../../twk_term\n'
        '  twk_test:\n    path: ../../twk_test\n';
    for (final block in [
      '$twk$core  meta: ^1.16.0\n',
      '  meta: ^1.16.0\n$twk$core',
      '$twk  meta:\n    git: https://example.org/meta.git\n$core',
      // a path, but not in the form a template writes it
      '$twk$core  meta: {path: ../meta}\n',
    ]) {
      expect(
        () => withTwkFrom('${dependencies}dependency_overrides:\n$block'),
        refused('meta'),
        reason: block,
      );
    }
    // what follows the block stays
    expect(
      withTwkFrom(
        '${dependencies}dependency_overrides:\n$twk$core'
        'flutter:\n  generate: true\n',
      ),
      endsWith('  twk_test: ^0.1.0\nflutter:\n  generate: true\n'),
    );
  });
}
