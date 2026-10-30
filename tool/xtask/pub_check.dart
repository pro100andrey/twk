// Whether a package is ready for pub.dev, as pub.dev would say:
//
//   pub [--min=N] [--scored] PATH...
//
// For each package (a path in it, relative to the root): `publish_to` must
// not be `none` (which the dry-run doesn't check; the rest is still run
// and shown); `dart pub publish --dry-run` must find no error (its
// warnings are shown, not failed: one of them is any uncommitted file);
// every file git tracks in its lib/ and bin/ must be in the archive the
// dry run lists (a `.pubignore` pattern that reaches into lib/ leaves out
// code the package imports, which the dry run, analyzing nothing, passes);
// a package with `screenshots:` needs libwebp's cwebp, webpinfo and
// gif2webp on the PATH, without which pana gives none of the 10 points of
// its example and screenshots and says only that a file was not found;
// and pana's score out of 160 is shown with what lost points, failed when
// it is under N (no floor without --min). pana is `dart pub global run
// pana` (skipped, said so, where it isn't activated); it scores a copy of
// the package resolved from pub.dev, so a package that depends on another
// of this repository's, by a path or not published yet, its dev
// dependencies too (pub.dev asked first: their formatter's and analyzer's
// options are not found without them), is not scored, and said so; with
// --scored, as right before its upload, that fails it. Both need the
// network.
import 'dart:convert';
import 'dart:io';

import 'package:xtask/xtask.dart';
import 'package:xtask_kit/xtask_kit.dart' show publishedFiles;

import 'cpus.dart';
import 'verbs.dart';

/// The verb: checks each package [c]'s arguments name.
Future<int> pubCheck(VerbContext c, Cpus cpus) async {
  int? min;
  var scored = false;
  final paths = <String>[];
  for (final arg in c.args) {
    if (arg == '--scored') {
      scored = true;
    } else if (arg.startsWith('--min=')) {
      min = int.tryParse(arg.substring('--min='.length));
      if (min == null) {
        c.log('pub: --min takes a number of points, not $arg');
        return ExitCode.invalidFile;
      }
    } else {
      paths.add(arg);
    }
  }
  if (paths.isEmpty) {
    c.log('pub: give a path in each package to check');
    return ExitCode.invalidFile;
  }
  final globals = await c.capture(['dart', 'pub', 'global', 'list']);
  final pana = RegExp('^pana ', multiLine: true).hasMatch(globals.stdout);
  var failed = false;
  for (final path in paths) {
    final dir = packageOf(c.root, path);
    if (dir == null) {
      c.log('pub: no pubspec.yaml in $path or above it');
      return ExitCode.invalidFile;
    }
    if (isPrivate(c.file('$dir/pubspec.yaml').readAsStringSync())) {
      // the rest still said: what else stands in the way
      c.log('$dir: publish_to: none, so not publishable');
      failed = true;
    }
    c.log('$dir: dart pub publish --dry-run');
    final dry = await c.capture(
      offBenchCore(c, cpus, ['dart', 'pub', 'publish', '--dry-run']),
      workingDirectory: dir,
    );
    final validation = validationOf(
      '${dry.stdout}\n${dry.stderr}',
      exitCode: dry.exitCode,
    );
    validation.lines.forEach(c.log);
    if (validation.hasErrors) {
      failed = true;
    }
    final tracked = await c.capture([
      'git',
      'ls-files',
      '-z',
      'lib',
      'bin',
    ], workingDirectory: dir);
    final left = unshippedCode(
      publishedFiles(dry.stdout) ?? const [],
      tracked.stdout.split('\u0000').where((path) => path.isNotEmpty),
    );
    if (left.isNotEmpty) {
      c.log('$dir: the archive leaves out code git tracks:');
      for (final path in left) {
        c.log('  $path');
      }
      failed = true;
    }
    if (!pana) {
      c.log(
        '$dir: pana skipped, not activated (dart pub global activate pana)',
      );
      continue;
    }
    if (screenshotTools(
          c.file('$dir/pubspec.yaml').readAsStringSync(),
          (tool) => c.which(tool) != null,
        )
        case final missing when missing.isNotEmpty) {
      c.log(
        '$dir: its screenshots need ${missing.join(', ')} on the PATH, '
        "which pana converts them with (libwebp's tools: libwebp-utils on "
        'Arch, webp on Debian and Homebrew); without them it gives none of '
        'the 10 points of the example and screenshots',
      );
      failed = true;
      continue;
    }
    final unpublished = [
      for (final name in repositoryDependencies(
        c.file('$dir/pubspec.yaml').readAsStringSync(),
        _repositoryPackages(c.root),
      ))
        if ((await c.capture([
              'curl',
              '-fsS',
              '-o',
              '/dev/null',
              'https://pub.dev/api/packages/$name',
            ])).exitCode !=
            0)
          name,
    ];
    if (unpublished.isNotEmpty) {
      c.log(
        '$dir: not scored, it depends on ${unpublished.join(', ')}, which '
        'pana cannot resolve outside this repository (not on pub.dev yet)',
      );
      if (scored) {
        c.log('$dir: --scored, and pana gave no score');
        failed = true;
      }
      continue;
    }
    c.log('$dir: pana');
    final run = await c.capture(
      offBenchCore(c, cpus, [
        'dart',
        'pub',
        'global',
        'run',
        'pana',
        '--no-warning',
        '--json',
        dir,
      ]),
      timeout: const Duration(minutes: 15),
    );
    final score = PanaScore.parse(run.stdout);
    if (score == null) {
      c.log('$dir: pana gave no report (exit ${run.exitCode})');
      c.log(run.stderr.trim());
      failed = true;
      continue;
    }
    if (score.unpublished case final missing?) {
      c.log(
        '$dir: not scored, it depends on $missing, which pana cannot '
        'resolve outside this repository (by a path, or not on pub.dev yet)',
      );
      if (scored) {
        c.log('$dir: --scored, and pana gave no score');
        failed = true;
      }
      continue;
    }
    score.lines.forEach(c.log);
    if (min != null && score.granted < min) {
      c.log('$dir: ${score.granted} points, under --min=$min');
      failed = true;
    }
  }
  return failed ? ExitCode.taskFailed : ExitCode.success;
}

/// The names of the packages under [root]'s `packages/`.
Set<String> _repositoryPackages(String root) => {
  for (final dir in Directory('$root/packages').listSync())
    if (File('${dir.path}/pubspec.yaml') case final pubspec
        when pubspec.existsSync())
      if (RegExp(
            r'^name:\s*(\S+)',
            multiLine: true,
          ).firstMatch(pubspec.readAsStringSync())
          case final m?)
        m[1]!,
};

/// The packages of [packages] that a pubspec's text depends on by a version
/// (`name: ^0.1.0`, on the line of its name), its dev dependencies too:
/// what pana resolves from pub.dev. One by a path is left to pana, which
/// says it cannot find it.
List<String> repositoryDependencies(String pubspec, Set<String> packages) {
  final names = <String>[];
  String? section;
  for (final line in const LineSplitter().convert(pubspec)) {
    if (RegExp(r'^(\w+):').firstMatch(line) case final top?) {
      section = top[1];
      continue;
    }
    if (section != 'dependencies' && section != 'dev_dependencies') {
      continue;
    }
    if (RegExp(r'^  (\w+):\s*[^\s#]').firstMatch(line) case final dep?
        when packages.contains(dep[1])) {
      names.add(dep[1]!);
    }
  }
  return names;
}

/// The files of [tracked], paths in the package that git tracks in its
/// lib/ and bin/, that are not among [shipped], the files the dry run
/// lists: code an upload would leave out.
List<String> unshippedCode(Iterable<String> shipped, Iterable<String> tracked) {
  final archived = shipped.toSet();
  return [
    for (final path in tracked)
      if (!archived.contains(path)) path,
  ];
}

/// The tools of libwebp that pana converts a package's screenshots with,
/// those of them [onPath] does not find, when the pubspec's text lists
/// `screenshots:`; none when it lists none.
List<String> screenshotTools(String pubspec, bool Function(String) onPath) =>
    RegExp('^screenshots:', multiLine: true).hasMatch(pubspec)
    ? [
        for (final tool in const ['cwebp', 'webpinfo', 'gif2webp'])
          if (!onPath(tool)) tool,
      ]
    : const [];

/// Whether a pubspec's text says `publish_to: none`.
bool isPrivate(String pubspec) => RegExp(
  r'''^publish_to:\s*['"]?none['"]?\s*(#.*)?$''',
  multiLine: true,
).hasMatch(pubspec);

/// What `dart pub publish --dry-run` said of a package, which exited with
/// [exitCode]: its validation, from `Validating package...` on (the file
/// list before it left out), and whether it found an error. It exits
/// non-zero on a warning too, so the exit code alone doesn't tell them
/// apart: an error is an error said, or a non-zero exit with no count of
/// warnings (`Package has 1 warning.`), as when the dependencies do not
/// resolve or the pubspec does not parse.
({List<String> lines, bool hasErrors}) validationOf(
  String output, {
  int exitCode = 0,
}) {
  final lines = const LineSplitter().convert(output);
  final at = lines.indexWhere((l) => l.startsWith('Validating package'));
  final kept = [
    for (final line in at < 0 ? lines : lines.skip(at))
      if (line.trim().isNotEmpty) line,
  ];
  return (
    lines: kept,
    hasErrors:
        lines.any(
          (l) =>
              l.startsWith('Package validation found the following error') ||
              l.contains("can't be published yet"),
        ) ||
        (exitCode != 0 &&
            !lines.any(
              (l) => RegExp(r'^Package has \d+ warnings?\.').hasMatch(l),
            )),
  );
}

/// pana's report of a package, read from its `--json` output.
final class PanaScore {
  PanaScore._(this.granted, this.max, this.sections, this.unpublished);

  /// The report in pana's [stdout], which before it holds what `pub`
  /// printed while pana resolved itself; null when there is none.
  static PanaScore? parse(String stdout) {
    final at = stdout.indexOf(RegExp(r'^\{', multiLine: true));
    if (at < 0) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(stdout.substring(at));
    } on FormatException {
      return null;
    }
    if (json case {
      'scores': {
        'grantedPoints': final int granted,
        'maxPoints': final int max,
      },
      'report': {'sections': final List<Object?> raw},
    }) {
      final sections = [
        for (final s in raw)
          if (s case {
            'title': final String title,
            'grantedPoints': final int got,
            'maxPoints': final int of,
            'summary': final String summary,
          })
            (title: title, granted: got, max: of, summary: summary),
      ];
      final missing = RegExp(
        r'could not find package (\w+) at ',
      ).firstMatch(sections.map((s) => s.summary).join('\n'));
      return PanaScore._(granted, max, sections, missing?.group(1));
    }
    return null;
  }

  /// The points granted, of [max].
  final int granted;

  /// The points there are, 160 today.
  final int max;

  /// Each section of the report: its title, points and pana's Markdown.
  final List<({String title, int granted, int max, String summary})> sections;

  /// The dependency pana could not resolve the package's copy without, or
  /// null: one of this repository's, by a path or not on pub.dev yet.
  final String? unpublished;

  /// The score, then each section's, and under a section short of its
  /// points the items that lost them with the first line of pana's reason.
  List<String> get lines => [
    'pana: $granted/$max points',
    for (final s in sections) ...[
      '  ${s.granted}/${s.max} ${s.title}',
      if (s.granted < s.max) ...lostIn(s.summary),
    ],
  ];

  /// The items of a section's summary that lost points (`### [x] ...`),
  /// each with the first line of what pana says under it.
  static List<String> lostIn(String summary) {
    final lines = const LineSplitter().convert(summary);
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final item = RegExp(r'^### \[x\] (.*)$').firstMatch(lines[i]);
      if (item == null) {
        continue;
      }
      out.add('    - ${item.group(1)}');
      final reason = lines
          .skip(i + 1)
          .takeWhile((l) => !l.startsWith('### '))
          .map((l) => l.trim())
          .firstWhere(
            (l) => l.isNotEmpty && !l.startsWith('<'),
            orElse: () => '',
          );
      if (reason.isNotEmpty) {
        out.add('      $reason');
      }
    }
    return out;
  }
}
