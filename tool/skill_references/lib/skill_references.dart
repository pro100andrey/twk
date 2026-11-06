/// The twk skill's references, `skills/twk/references/`, written from the
/// widget catalog (`doc/widgets/`) and the guides (`doc/guides/`).
///
/// The catalog is read as the Markdown `packages/gallery/tool/catalog.dart`
/// wrote (its front matter is JSON strings, its pages have the same
/// sections), not from the gallery, so that this needs no build of the
/// gallery; the `skill-references` task runs after `catalog`, so what is
/// read is not stale.
///
/// Nothing here reads the disk or the clock: [buildReferences] is a function
/// of the texts it is given, so that the same catalog gives the same bytes.
library;

/// The marker line at the top of each generated reference that is not a
/// copy of a guide.
const generatedNote =
    '<!-- Written by tool/skill_references from doc/widgets; do not edit. -->';

/// The guides left out of the references, by file name, each with its
/// reason. None: every guide of `doc/guides/` is for a person building an
/// app, and `doc/internals/` (for contributors) is not read at all.
const Map<String, String> guidesLeftOut = {};

/// A reference could not be written from what the catalog has.
final class ReferenceError implements Exception {
  /// Says what [message] is wrong.
  const ReferenceError(this.message);

  /// What is wrong, naming the page.
  final String message;

  @override
  String toString() => 'skill_references: $message';
}

/// One page of the catalog: a widget.
final class WidgetPage {
  /// A page with its front matter and the sections kept from its body.
  const WidgetPage({
    required this.title,
    required this.about,
    required this.package,
    required this.api,
    required this.sections,
  });

  /// The widget's name, as the gallery names the page ("Checkbox, Switch").
  final String title;

  /// The catalog's one sentence on it.
  final String about;

  /// The package that has it.
  final String package;

  /// The Markdown line that links to its API, or null.
  final String? api;

  /// The Code and Options sections, headings a level down.
  final String sections;
}

/// One group of the catalog and its widgets, in the catalog's order.
final class WidgetGroup {
  /// A group [title] with the file [slug] of its page.
  const WidgetGroup(this.slug, this.title, this.about, this.widgets);

  /// The group's file name without `.md`.
  final String slug;

  /// The group's name ("Focus and keys").
  final String title;

  /// The catalog's line on the group.
  final String about;

  /// The group's widgets, in the order of its page.
  final List<({String path, WidgetPage page})> widgets;
}

/// The front matter of [text] (a JSON string a key) and the body after it.
(Map<String, String>, String) splitFrontMatter(String text) {
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first != '---') {
    return ({}, text);
  }
  final end = lines.indexOf('---', 1);
  if (end < 0) {
    return ({}, text);
  }
  final fields = <String, String>{};
  for (final line in lines.sublist(1, end)) {
    final colon = line.indexOf(': ');
    if (colon < 0) {
      continue;
    }
    final value = line.substring(colon + 2);
    fields[line.substring(0, colon)] = value.startsWith('"')
        ? _unquote(value)
        : value;
  }
  return (fields, lines.sublist(end + 1).join('\n'));
}

String _unquote(String json) {
  final out = StringBuffer();
  for (var i = 1; i < json.length - 1; i++) {
    final c = json[i];
    if (c != r'\') {
      out.write(c);
      continue;
    }
    final n = json[++i];
    switch (n) {
      case 'n':
        out.write('\n');
      case 't':
        out.write('\t');
      case 'u':
        out.writeCharCode(int.parse(json.substring(i + 1, i + 5), radix: 16));
        i += 4;
      default:
        out.write(n);
    }
  }
  return out.toString();
}

/// The anchor GitHub gives the heading [title]: lower case, punctuation
/// dropped, spaces hyphens.
String anchorOf(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
    .replaceAll(' ', '-');

const _codeIntro =
    "The Dart that builds it, as the gallery's Code tab shows it with the\n"
    'options as they start:';
const _optionsIntro =
    'What the gallery lets you change, and what each starts at:';

/// Reads the widget page [text] of [path] (relative to `doc/widgets/`).
WidgetPage readWidgetPage(String path, String text) {
  final (front, body) = splitFrontMatter(text);
  final title = front['title'];
  final about = front['about'];
  if (title == null || about == null) {
    throw ReferenceError(
      'doc/widgets/$path: no title or about in its front matter',
    );
  }
  final sections = <String, List<String>>{};
  List<String>? current;
  var inFence = false;
  for (final line in body.split('\n')) {
    if (line.startsWith('```')) {
      inFence = !inFence;
    }
    if (!inFence && line.startsWith('## ')) {
      current = sections.putIfAbsent(line.substring(3), () => []);
    } else {
      current?.add(line);
    }
  }
  final more = sections['More'] ?? const [];
  final api = more.where((l) => l.startsWith('- API: ')).firstOrNull;
  final out = StringBuffer();
  for (final name in const ['Code', 'Options']) {
    final lines = sections[name];
    if (lines == null) {
      continue;
    }
    var text = lines.join('\n').trim();
    for (final intro in const [_codeIntro, _optionsIntro]) {
      if (text.startsWith(intro)) {
        text = text.substring(intro.length).trim();
      }
    }
    out.write('### $name\n\n$text\n\n');
  }
  return WidgetPage(
    title: title,
    about: about,
    package: front['package'] ?? 'twk',
    api: api?.substring(2),
    sections: out.toString().trimRight(),
  );
}

final _groupLink = RegExp(r'\*\*\[[^\]]+\]\(([a-z0-9-]+)\.md\)\*\*');
final _widgetLink = RegExp(
  r'\*\*\[[^\]]+\]\(([a-z0-9-]+/[a-z0-9-]+\.md)\)\*\*',
);

/// The groups of the catalog in [docWidgets], its files by path under
/// `doc/widgets/`: `README.md` for the groups' order, `<group>.md` for a
/// group and its widgets' order, `<group>/<page>.md` for a widget.
List<WidgetGroup> readCatalog(Map<String, String> docWidgets) {
  String need(String path) =>
      docWidgets[path] ??
      (throw ReferenceError('doc/widgets/$path is missing'));
  final slugs = [
    for (final m in _groupLink.allMatches(need('README.md'))) m.group(1)!,
  ];
  if (slugs.isEmpty) {
    throw const ReferenceError('doc/widgets/README.md lists no group');
  }
  final groups = <WidgetGroup>[];
  for (final slug in slugs) {
    final (front, body) = splitFrontMatter(need('$slug.md'));
    final paths = [for (final m in _widgetLink.allMatches(body)) m.group(1)!];
    final onDisk = docWidgets.keys.where((k) => k.startsWith('$slug/')).toSet();
    if (paths.toSet().length != paths.length ||
        !paths.toSet().containsAll(onDisk) ||
        !onDisk.containsAll(paths)) {
      throw ReferenceError(
        'doc/widgets/$slug.md and its pages disagree on the widgets',
      );
    }
    groups.add(
      WidgetGroup(slug, front['title'] ?? slug, front['about'] ?? '', [
        for (final path in paths)
          (path: path, page: readWidgetPage(path, need(path))),
      ]),
    );
  }
  return groups;
}

/// `widgets.md`: every widget a line, by group.
String renderIndex(List<WidgetGroup> groups) {
  final b = StringBuffer()
    ..writeln(generatedNote)
    ..writeln('# twk widgets')
    ..writeln()
    ..writeln(
      'Every widget, one line each: its name and what it is, by group. '
      "A group's file has each widget's options and the Dart that builds it.",
    );
  for (final g in groups) {
    b
      ..writeln()
      ..writeln('## ${g.title}')
      ..writeln()
      ..writeln('${g.about} File: `widgets/${g.slug}.md`.')
      ..writeln();
    for (final w in g.widgets) {
      final pkg = w.page.package == 'twk' ? '' : ' (`${w.page.package}`)';
      b.writeln('- ${w.page.title}$pkg: ${w.page.about}');
    }
  }
  return b.toString();
}

/// `widgets/<group>.md`: the group's widgets with their code.
String renderGroup(WidgetGroup g) {
  final b = StringBuffer()
    ..writeln(generatedNote)
    ..writeln('# ${g.title}')
    ..writeln()
    ..writeln(g.about)
    ..writeln()
    ..writeln('[All widgets](../widgets.md)');
  final anchors = <String>{};
  for (final w in g.widgets) {
    if (!anchors.add(anchorOf(w.page.title))) {
      throw ReferenceError(
        'doc/widgets/${w.path}: another page of ${g.title} has its title',
      );
    }
    b
      ..writeln()
      ..writeln('## ${w.page.title}')
      ..writeln()
      ..writeln(w.page.about);
    if (w.page.package != 'twk') {
      b
        ..writeln()
        ..writeln('Package: `${w.page.package}`.');
    }
    if (w.page.api != null) {
      b
        ..writeln()
        ..writeln(w.page.api);
    }
    if (w.page.sections.isNotEmpty) {
      b
        ..writeln()
        ..writeln(w.page.sections);
    }
  }
  return b.toString();
}

final _image = RegExp(r'!\[[^\]]*\]\([^)]*\)(<br>)?');
final _link = RegExp(r'(?<!!)\[([^\]]*)\]\(([^)\s]*)\)');
final _guideFile = RegExp(r'^[a-z0-9-]+\.md$');
final _groupFile = RegExp(r'^\.\./widgets/[a-z0-9-]+\.md$');
final _pageFile = RegExp(r'^\.\./widgets/([a-z0-9-]+/[a-z0-9-]+\.md)$');

/// [guide] with what would be dead inside the references dropped: pictures,
/// and links to anything that is not a guide, a widget or an address (the
/// text stays). A link to a widget page goes to its group's file, at the
/// widget's heading; [anchors] has `file#anchor` for each `<group>/<page>.md`.
String rewriteGuide(String name, String guide, Map<String, String> anchors) {
  // The fenced blocks are code, left as they are; a link's text may run
  // over a line, so the text between them is rewritten whole.
  final out = StringBuffer();
  var last = 0;
  for (final fence in _fence.allMatches(guide)) {
    out
      ..write(_rewriteProse(name, guide.substring(last, fence.start), anchors))
      ..write(fence.group(0));
    last = fence.end;
  }
  out.write(_rewriteProse(name, guide.substring(last), anchors));
  return out.toString();
}

final _fence = RegExp(r'^```.*?^```[^\n]*$', multiLine: true, dotAll: true);

String _rewriteProse(String name, String prose, Map<String, String> anchors) =>
    prose.replaceAll(_image, '').replaceAllMapped(_link, (m) {
      final text = m.group(1)!;
      final target = m.group(2)!;
      if (RegExp('^[a-z]+:|^#').hasMatch(target)) {
        return m.group(0)!;
      }
      final hash = target.indexOf('#');
      final file = hash < 0 ? target : target.substring(0, hash);
      if (_guideFile.hasMatch(file) || _groupFile.hasMatch(file)) {
        return m.group(0)!;
      }
      if (file == '../widgets/README.md') {
        return '[$text](../widgets.md)';
      }
      final page = _pageFile.firstMatch(file)?.group(1);
      if (page != null) {
        final to =
            anchors[page] ??
            (throw ReferenceError('guides/$name links to $file, not a page'));
        return '[$text](../widgets/$to)';
      }
      return text;
    });

/// Every file of the references, by its path under `skills/twk/references/`,
/// from [docWidgets] (the files of `doc/widgets/` by path) and [docGuides]
/// (the files of `doc/guides/` by name).
///
/// Throws a [ReferenceError] where a guide links to a widget page that is
/// not there or to a guide that is left out.
Map<String, String> buildReferences({
  required Map<String, String> docWidgets,
  required Map<String, String> docGuides,
}) {
  final groups = readCatalog(docWidgets);
  final files = <String, String>{'widgets.md': renderIndex(groups)};
  final anchors = <String, String>{};
  for (final g in groups) {
    files['widgets/${g.slug}.md'] = renderGroup(g);
    for (final w in g.widgets) {
      anchors[w.path] = '${g.slug}.md#${anchorOf(w.page.title)}';
    }
  }
  for (final name in docGuides.keys.toList()..sort()) {
    if (!guidesLeftOut.containsKey(name)) {
      files['guides/$name'] = rewriteGuide(name, docGuides[name]!, anchors);
    }
  }
  for (final MapEntry(:key, :value) in files.entries) {
    if (!key.startsWith('guides/')) {
      continue;
    }
    for (final m in _link.allMatches(value)) {
      final file = m.group(2)!.split('#').first;
      if (_guideFile.hasMatch(file) && !files.containsKey('guides/$file')) {
        throw ReferenceError('$key links to $file, which is not there');
      }
    }
  }
  return files;
}
