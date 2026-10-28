/// `twk create`: [CreateCommand], and what it does as functions:
/// [createPlan], [packageNameOf], [packageNameError], [isCheckout] and
/// [checkoutOfCommand].
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max;

import 'package:args/command_runner.dart';
import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;

import 'templates/templates.dart';

/// `twk create`: unpacks a template ([templates]), a package packed with
/// mold, into a directory under a new package's name: a package that
/// runs, analyzes and passes its tests as it is.
final class CreateCommand extends Command<int> {
  /// Sets up `twk create`'s options: `--template`, `--name`,
  /// `--path-to-twk`, `--force`, `--dry-run` and `--list`.
  CreateCommand() {
    argParser
      ..addOption(
        'template',
        abbr: 't',
        valueHelp: 'name',
        allowed: [for (final t in templates) t.name],
        allowedHelp: {for (final t in templates) t.name: t.description},
        defaultsTo: templates.first.name,
        help: 'The kind of app.',
      )
      ..addOption(
        'name',
        valueHelp: 'package',
        help:
            "The package's name (default: the directory's, in lower case, "
            'other characters than letters, digits and _ as _).',
      )
      ..addOption(
        'path-to-twk',
        valueHelp: 'dir',
        help:
            'The checkout of the twk repository to take twk, twk_test, '
            'twk_dev and twk_lints from by path (default: the one this '
            'command runs from, else pub).',
      )
      ..addFlag(
        'force',
        negatable: false,
        help:
            'Write into a directory that is not empty, over the files of '
            'the same paths.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Name the files it would write, and which of them over a file '
            'there, writing none.',
      )
      ..addFlag('list', negatable: false, help: 'List the templates.');
  }

  @override
  String get name => 'create';

  @override
  String get invocation =>
      'twk create <dir> [--template=<name>] [--name=<package>] '
      '[--path-to-twk=<dir>] [--force] [--dry-run]';

  @override
  String get description =>
      'Start a new app from a template.\n\n'
      'Unpacks the template, a package packed with mold, into <dir>, made '
      'with its parents if it is not there, under the package name: a '
      'pubspec that takes twk, twk_test, twk_dev and twk_lints by path '
      'from a checkout of the twk repository, or from pub, '
      "analysis_options.yaml (with twk_lints' recommended rules), "
      'bin/main.dart, the app in lib/, a testTwk test of it in test/, a '
      'README and a .gitignore. A directory that is not empty is refused '
      'unless --force, which writes over the files of the same paths and '
      'leaves the others. --dry-run names the files it would write, and '
      'which over a file there; --list names the templates.';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.flag('list')) {
      final width = templates.map((t) => t.name.length).reduce(max);
      for (final t in templates) {
        stdout.writeln('${t.name.padRight(width)}  ${t.description}');
      }
      return 0;
    }
    final rest = args.rest;
    if (rest.isEmpty) {
      usageException('No directory to create the app in.');
    }
    if (rest.length > 1) {
      usageException('One directory at most.');
    }
    final dir = p.normalize(p.absolute(rest.single));
    final name = args.option('name') ?? packageNameOf(p.basename(dir));
    if (packageNameError(name) case final error?) {
      usageException(
        args.option('name') == null
            ? '$error; --name=<package> gives the package another'
            : error,
      );
    }
    final String? checkout;
    if (args.option('path-to-twk') case final given?) {
      checkout = p.normalize(p.absolute(given));
      if (!isCheckout(checkout)) {
        stderr.writeln(
          'twk create: no checkout of twk at $checkout: it has no '
          'packages/twk, packages/twk_test, packages/twk_dev and '
          'packages/twk_lints',
        );
        return 1;
      }
    } else {
      checkout = await checkoutOfCommand();
    }
    final template = templates.firstWhere(
      (t) => t.name == args.option('template'),
    );
    final dryRun = args.flag('dry-run');
    final UnpackPlan plan;
    try {
      plan = createPlan(
        template,
        name,
        dir: dir,
        checkout: checkout,
        overwrite: args.flag('force'),
      );
      if (!dryRun) {
        await const Unbundler().apply(plan, onWarning: _warn);
      }
    } on ValidationException catch (e) {
      for (final error in e.errors) {
        stderr.writeln('twk create: ${_hinted(error)}');
      }
      return 1;
    } on IOException catch (e) {
      stderr.writeln('twk create: $e');
      return 1;
    }
    final files = plan.templateFiles.toList()
      ..sort((a, b) => a.to.compareTo(b.to));
    stdout
      ..writeln(
        '${dryRun ? 'twk create --dry-run: would write' : 'twk create:'} '
        '$name, of the template ${template.name}, in $dir:',
      )
      ..writeln(
        [
          for (final file in files)
            '  ${file.to}${switch (file) {
              PlannedFile(identicalToExisting: true) => ' (the same there)',
              PlannedFile(overwrites: true) => ' (over the one there)',
              _ => '',
            }}',
        ].join('\n'),
      )
      ..writeln(
        checkout == null
            ? 'twk, twk_test, twk_dev and twk_lints from pub, at '
                  '^$twkVersion.'
            : 'twk, twk_test, twk_dev and twk_lints by path, from '
                  '$checkout.',
      );
    if (!dryRun) {
      stdout
        ..writeln()
        ..writeln('  cd ${rest.single}')
        ..writeln('  dart pub get')
        ..writeln('  dart run bin/main.dart')
        ..writeln('  dart run twk_dev:twk run bin/main.dart  # hot reloaded')
        ..writeln('  dart test');
    }
    return 0;
  }
}

/// What unpacking [template] as a package named [name] into [dir] does,
/// as mold plans it, its pubspec taking twk, twk_dev, twk_lints and
/// twk_test as [withTwkFrom] says for [checkout]: mold's `Unbundler.apply`
/// writes it, making [dir] and the directories on the way to it that are
/// not there.
///
/// Into a directory that is not empty with [overwrite] alone, each file
/// of the template over the one of the same path, the others left as
/// they are. Throws a [ValidationException] when mold refuses the unpack.
///
/// mold's variables put a value in place of a literal, while a package
/// taken by path or by version is a YAML of another shape, so the pubspec
/// is rewritten as mold plans it rather than by the template, so what
/// the plan says of it, whether the one there is the same among it, is
/// about the pubspec written.
UnpackPlan createPlan(
  Template template,
  String name, {
  required String dir,
  String? checkout,
  bool overwrite = false,
}) => const Unbundler().plan(
  bytes: template.archive,
  targetDir: dir,
  vars: {packageNameVariable: name},
  overwrite: overwrite,
  withContent: false,
  rewrite: (path, bytes) => path == 'pubspec.yaml'
      ? utf8.encode(withTwkFrom(utf8.decode(bytes), checkout: checkout))
      : bytes,
  onWarning: _warn,
);

/// [error]'s message, with the option of `twk create` that gets past it
/// where there is one: mold's speaks of an overwrite, not of `--force`.
String _hinted(ValidationError error) => switch (error.code) {
  MoldCode.targetOccupied => '${error.message} --force writes into it.',
  _ => error.message,
};

void _warn(ValidationError warning) =>
    stderr.writeln('twk create: ${warning.message}');

/// [text] as a package name: in lower case, other characters than
/// letters, digits and `_` as `_`.
String packageNameOf(String text) =>
    text.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '_');

/// What makes [name] no name for the package, null when it is one: a
/// lower case letter first, then lower case letters, digits and `_`, none
/// of the words pub refuses and none of the packages it depends on.
String? packageNameError(String name) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    return '"$name" is not a package name: a lower case letter first, then '
        'lower case letters, digits and _';
  }
  if (_reserved.contains(name)) {
    return '"$name" is a reserved word';
  }
  if (_taken.contains(name)) {
    return '"$name" is the name of a package the app depends on';
  }
  return null;
}

/// The words pub refuses as a package's name, the reserved words of Dart
/// among them.
final Set<String> _reserved =
    'abstract as assert await break case catch class const continue '
            'covariant default deferred do else enum export extends '
            'external false final finally for hide if implements import in '
            'inline interface is late library mixin new null of on operator '
            'part required rethrow return sealed set super switch this '
            'throw true try type var void while with yield'
        .split(' ')
        .toSet();

/// The packages a project depends on, which it cannot be named as.
const _taken = {
  'pro_lints',
  'test',
  'twk',
  'twk_core',
  'twk_dev',
  'twk_lints',
  'twk_test',
};

/// Whether [dir] is a checkout of the twk repository: it has the packages
/// a project takes by path.
bool isCheckout(String dir) =>
    const [
      'twk',
      'twk_test',
      'twk_dev',
      'twk_lints',
    ].every(
      (package) =>
          File(p.join(dir, 'packages', package, 'pubspec.yaml')).existsSync(),
    );

/// The checkout of the twk repository this command runs from: the nearest
/// directory from this package's library up, or from the script's, that
/// [isCheckout]; null when there is none.
Future<String?> checkoutOfCommand() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:twk_dev/twk_dev.dart'),
  );
  for (final uri in [?library, Platform.script]) {
    if (uri.scheme != 'file') {
      continue;
    }
    for (var dir = p.dirname(uri.toFilePath()); ; dir = p.dirname(dir)) {
      if (isCheckout(dir)) {
        return dir;
      }
      if (p.dirname(dir) == dir) {
        break;
      }
    }
  }
  return null;
}
