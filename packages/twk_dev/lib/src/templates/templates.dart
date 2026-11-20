/// The templates of `twk create`: packages in `templates/<name>/` of
/// twk_dev, packed with mold by `tool/pack_templates.dart` into the
/// `<name>.g.dart` here.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import 'app.g.dart';
import 'bloc.g.dart';
import 'dashboard.g.dart';
import 'form.g.dart';
import 'inline.g.dart';
import 'riverpod.g.dart';
import 'ssh.g.dart';
import 'web.g.dart';

/// A kind of app `twk create` starts: its [name], what it is in a line
/// ([description]) and its package packed with mold, in base64 ([packed]).
final class Template {
  /// A template named [name].
  const Template({
    required this.name,
    required this.description,
    required this.packed,
    this.run = const [
      'dart run bin/main.dart',
      'dart run twk_dev:twk run bin/main.dart  # hot reloaded',
    ],
  });

  /// What `--template` names it.
  final String name;

  /// What it is, in a line, as `--list` shows it.
  final String description;

  /// Its package packed with mold, in base64.
  final String packed;

  /// The commands that run the app, after `dart pub get`, as `twk create`
  /// shows them: hot reloaded unless the app is not one `twk run` runs.
  final List<String> run;

  /// The archive mold unpacks.
  List<int> get archive => base64.decode(packed);
}

/// The templates, the first the default.
const templates = [
  Template(
    name: 'app',
    description: 'full screen: a list beside a detail pane, the keys below',
    packed: kAppTemplateBase64,
  ),
  Template(
    name: 'inline',
    description: 'inline below the prompt: what is said goes to the scrollback',
    packed: kInlineTemplateBase64,
  ),
  Template(
    name: 'form',
    description: 'full screen: a form whose fields are validated',
    packed: kFormTemplateBase64,
  ),
  Template(
    name: 'dashboard',
    description:
        'full screen: panels of live readings in a chart, a gauge and bars',
    packed: kDashboardTemplateBase64,
  ),
  Template(
    name: 'ssh',
    description: 'served over SSH: each client that logs in gets its own app',
    packed: kSshTemplateBase64,
    run: ['dart run bin/main.dart  # then: ssh -t -p 2222 localhost'],
  ),
  Template(
    name: 'web',
    description: 'in a browser, on xterm.js, built with dart2wasm',
    packed: kWebTemplateBase64,
    run: [
      'dart compile wasm web/main.dart -o web/main.wasm',
      'python3 -m http.server -d web 8080  # then: http://localhost:8080',
    ],
  ),
  Template(
    name: 'riverpod',
    description: 'full screen: a counter with its state in riverpod providers',
    packed: kRiverpodTemplateBase64,
  ),
  Template(
    name: 'bloc',
    description: 'full screen: a counter with its state in a bloc cubit',
    packed: kBlocTemplateBase64,
  ),
];

/// The mold variable a template's package name replaces.
const packageNameVariable = 'package_name';

/// The packages a template takes by path from the twk repository, which
/// `twk create` takes from a checkout or pub ([withTwkFrom]).
const twkPackages = ['twk', 'twk_dev', 'twk_lints', 'twk_test'];

/// The version of twk, twk_test, twk_dev and twk_lints a project takes
/// from pub.
const twkVersion = '0.3.0';

/// The packages a template takes by path that only some of them do, each
/// with its version on pub: [withTwkFrom] rewrites those a pubspec has,
/// like the [twkPackages], which it must have.
const optionalTwkPackages = {
  'twk_bloc': '0.1.0',
  'twk_riverpod': '0.1.0',
  'twk_ssh': '0.1.0',
  'twk_web': '0.1.0',
};

/// The [optionalTwkPackages] not on pub yet (`publish_to: none` in their
/// pubspecs): a project takes them from a checkout only. Drop a package
/// from it when it is published.
const unpublishedTwkPackages = {
  'twk_bloc',
  'twk_riverpod',
  'twk_ssh',
  'twk_web',
};

/// A template takes packages of twk that are not on pub, and `twk create`
/// has no checkout to take them from.
final class UnpublishedPackages implements Exception {
  /// The refusal of a template that takes [packages].
  UnpublishedPackages(this.packages);

  /// The packages the template takes that are not published.
  final List<String> packages;

  /// What is wrong and what to do about it.
  String get message =>
      '${packages.join(', ')} ${packages.length == 1 ? 'is' : 'are'} not '
      'published to pub yet, so a project that takes '
      '${packages.length == 1 ? 'it' : 'them'} can only be made from a '
      'checkout of the twk repository: --path-to-twk=<dir> names one, or '
      'run twk from one';

  @override
  String toString() => message;
}

/// [pubspec], a template's, with the [twkPackages] it takes by a path in
/// the repository taken by path from the twk repository checked out at
/// [checkout] or, when null, from pub at [twkVersion].
///
/// A template's pubspec takes them by paths relative to it in the
/// repository, which a project elsewhere cannot; whether a project takes
/// them by path or by version is a choice of `twk create`, not of the
/// template, so it is made here rather than by mold. A package by path is
/// in the block form, `path:` alone on the line under its name, as the
/// templates write it: a flow mapping or a comment among its lines is
/// none. Throws a [StateError] when [pubspec] does not take one of them by
/// path, or does not override by path just the packages of [overridden];
/// and an [UnpublishedPackages] when [checkout] is null and it takes one of
/// the [unpublishedTwkPackages].
///
/// twk, twk_test and twk_dev take the packages under them by version and
/// the others take them by path, so a template overrides twk, twk_core,
/// twk_driver and twk_term with the repository's ([overridden],
/// `dependency_overrides`): a project from a checkout with the checkout's,
/// one from pub not at all.
String withTwkFrom(String pubspec, {String? checkout}) {
  if (checkout == null) {
    final unpublished = [
      for (final package in unpublishedTwkPackages)
        if (RegExp(
          '^  $package:\n    path: ',
          multiLine: true,
        ).hasMatch(pubspec))
          package,
    ];
    if (unpublished.isNotEmpty) {
      throw UnpublishedPackages(unpublished..sort());
    }
  }
  String source(String package) => checkout == null
      ? ' ^${optionalTwkPackages[package] ?? twkVersion}'
      : '\n    path: ${_yaml(p.join(checkout, 'packages', package))}';
  var result = pubspec;
  for (final package in twkPackages) {
    final dependency = RegExp('^  $package:\n    path: .*\$', multiLine: true);
    if (!dependency.hasMatch(result)) {
      throw StateError('The pubspec takes no $package by path');
    }
    result = result.replaceFirst(dependency, '  $package:${source(package)}');
  }
  for (final package in optionalTwkPackages.keys) {
    final dependency = RegExp('^  $package:\n    path: .*\$', multiLine: true);
    result = result.replaceFirst(dependency, '  $package:${source(package)}');
  }
  final block = _overrides.firstMatch(result)?[0] ?? '';
  final named = <String>{};
  for (final m in _entry.allMatches(block)) {
    final name = m[1]!;
    if (!_byPath.hasMatch(m[0]!)) {
      throw StateError(
        'The pubspec overrides $name by no path alone on the line under '
        'its name: an override of a template is a path',
      );
    }
    named.add(name);
  }
  if (named.length != overridden.length || !named.containsAll(overridden)) {
    throw StateError(
      'The pubspec overrides ${named.isEmpty ? 'nothing' : named.join(', ')} '
      'by path, not ${overridden.join(', ')}',
    );
  }
  // the line break that ends the block kept for what follows it
  return result.replaceFirstMapped(
    _overrides,
    (m) => checkout == null
        ? (m[0]!.endsWith('\n') ? '\n' : '')
        : [
            '\ndependency_overrides:',
            for (final package in overridden) '  $package:${source(package)}',
            '',
          ].join('\n'),
  );
}

/// The packages a template overrides with the repository's.
const overridden = ['twk', 'twk_core', 'twk_driver', 'twk_term'];

/// A template's overrides: the block, every line of it indented.
final _overrides = RegExp(r'\ndependency_overrides:\n(?:  .*(?:\n|$))+');

/// An entry of [_overrides]: its name's line and the lines under it.
final _entry = RegExp(r'^  (\S+):.*(?:\n    .*)*', multiLine: true);

/// An entry of [_overrides] that takes its package by a path, alone.
final _byPath = RegExp(r'^  \S+:\n    path: [^\n]*$');

/// [text] as a YAML scalar: plain where it can be, else single-quoted.
String _yaml(String text) => RegExp(r'^[\w./~+@-]+$').hasMatch(text)
    ? text
    : "'${text.replaceAll("'", "''")}'";
