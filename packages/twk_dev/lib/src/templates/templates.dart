/// The templates of `twk create`: packages in `templates/<name>/` of
/// twk_dev, packed with mold by `tool/pack_templates.dart` into the
/// `<name>.g.dart` here.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import 'app.g.dart';
import 'dashboard.g.dart';
import 'form.g.dart';
import 'inline.g.dart';

/// A kind of app `twk create` starts: its [name], what it is in a line
/// ([description]) and its package packed with mold, in base64 ([packed]).
final class Template {
  /// A template named [name].
  const Template({
    required this.name,
    required this.description,
    required this.packed,
  });

  /// What `--template` names it.
  final String name;

  /// What it is, in a line, as `--list` shows it.
  final String description;

  /// Its package packed with mold, in base64.
  final String packed;

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
];

/// The mold variable a template's package name replaces.
const packageNameVariable = 'package_name';

/// The packages a template takes by path from the twk repository, which
/// `twk create` takes from a checkout or pub ([withTwkFrom]).
const twkPackages = ['twk', 'twk_dev', 'twk_lints', 'twk_test'];

/// The version of twk, twk_test, twk_dev and twk_lints a project takes
/// from pub.
const twkVersion = '0.1.0';

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
/// path, or does not override by path just the packages of [overridden].
///
/// twk and twk_test take the packages under them by version and the
/// others take them by path, so a template overrides twk and twk_core with
/// the repository's ([overridden], `dependency_overrides`): a project from
/// a checkout with the checkout's, one from pub not at all.
String withTwkFrom(String pubspec, {String? checkout}) {
  String source(String package) => checkout == null
      ? ' ^$twkVersion'
      : '\n    path: ${_yaml(p.join(checkout, 'packages', package))}';
  var result = pubspec;
  for (final package in twkPackages) {
    final dependency = RegExp('^  $package:\n    path: .*\$', multiLine: true);
    if (!dependency.hasMatch(result)) {
      throw StateError('The pubspec takes no $package by path');
    }
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
const overridden = ['twk', 'twk_core'];

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
