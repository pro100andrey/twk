// A page's Code tab made into a Dart library whose `codeWidget()` returns
// the widget it builds. A Code is one of:
//
//   file         a program (`main` calling `runApp`): its main runs with
//                runApp replaced by a function that keeps the widget;
//   state-given  a `State<W>` class (W declared here when it is not);
//   members      build() and other members of a State: put in one;
//   body         the body of build(): put in one;
//   cli          a console program, its main `Cli.runWithArgs(args, f)`:
//                written as it is to lib/cli/f.dart, as the gallery keeps
//                it, and run in lib/cli/run.dart's CliRun as the stage
//                runs it (the same file, copied beside it), so that its
//                traceback names the same file and lines.
//
// Imports of twk, twk_rich, twk_rich's image library and twk_term are added
// to each, whether it names them or not.

/// How a Code was made into a library.
enum WrapMode {
  /// A program: its `main` runs, `runApp` keeping the widget.
  file,

  /// A `State<W>` whose widget the Code does not declare.
  stateGiven,

  /// `build()` and other members of a State.
  members,

  /// The body of `build()`.
  body,

  /// A console program, run in the gallery's CliRun.
  cli,
}

/// A Code made into a library: its source, how it was made, the files
/// beside it it needs, by their path in the package, and for each line of
/// `dart` the line of the Code it was made from (`codeLines`).
typedef Wrapped = ({
  String dart,
  WrapMode mode,
  Map<String, String> files,
  List<int?> codeLines,
});

/// For each line of [dart], the line of [code] (from 1) it was made from:
/// the first not taken yet whose text is the same but for its indent;
/// null for a line the wrapping wrote, and for a blank or a bracket alone,
/// which say nothing of where they came from.
List<int?> codeLinesOf(String dart, String code) {
  final free = <String, List<int>>{};
  for (final (i, l) in code.split('\n').indexed) {
    final t = l.trim();
    if (t.length > 2) {
      (free[t] ??= []).add(i + 1);
    }
  }
  return [
    for (final l in dart.split('\n'))
      if (free[l.trim()] case final at? when at.isNotEmpty)
        at.removeAt(0)
      else
        null,
  ];
}

Wrapped _made(
  String dart,
  WrapMode mode,
  String code, [
  Map<String, String> files = const {},
]) => (
  dart: dart,
  mode: mode,
  files: files,
  codeLines: codeLinesOf(dart, code),
);

/// One item at the top level of a Code: its lines (its leading comments
/// and annotations among them), the first of its own, and whether it is a
/// declaration that stays at the top level (a class, an import, a const).
typedef _Item = ({List<String> lines, String head, bool top});

final _top = RegExp(
  '^((final |abstract |sealed |base |interface )*'
  '(class|enum|mixin|extension|typedef) |import )',
);

/// Splits [src] into its top-level items: runs of lines that start at
/// column 0 where no bracket is open, each with the comments and
/// annotations before it.
List<_Item> _items(String src) {
  final lines = src.split('\n');
  final depths = <(int, bool)>[];
  var depth = 0;
  ({String q, bool raw})? str;
  for (final l in lines) {
    depths.add((depth, str != null));
    var i = 0;
    while (i < l.length) {
      if (str != null) {
        if (!str.raw && l[i] == r'\') {
          i += 2;
          continue;
        }
        if (l.startsWith(str.q, i)) {
          i += str.q.length;
          str = null;
          continue;
        }
        i++;
        continue;
      }
      if (l.startsWith('//', i)) {
        break;
      }
      final raw =
          l[i] == 'r' &&
          i + 1 < l.length &&
          (l[i + 1] == "'" || l[i + 1] == '"') &&
          (i == 0 || !RegExp(r'\w').hasMatch(l[i - 1]));
      final j = raw ? i + 1 : i;
      if (l[j] == "'" || l[j] == '"') {
        final q = l.startsWith(l[j] * 3, j) ? l[j] * 3 : l[j];
        str = (q: q, raw: raw);
        i = j + q.length;
        continue;
      }
      final c = l[i];
      if ('{(['.contains(c)) {
        depth++;
      } else if ('})]'.contains(c)) {
        depth--;
      }
      i++;
    }
    // a string in single quotes ends with its line
    if (str != null && str.q.length == 1) {
      str = null;
    }
  }
  final out = <({List<String> lines, String head})>[];
  ({List<String> lines, String head})? cur;
  var pending = <String>[];
  for (final (k, l) in lines.indexed) {
    final (d, inString) = depths[k];
    final atTop =
        d == 0 &&
        !inString &&
        RegExp(r'^\S').hasMatch(l) &&
        !RegExp(r'^[})\]]').hasMatch(l);
    if (atTop && (l.startsWith('//') || l.startsWith('@'))) {
      pending.add(l);
      continue;
    }
    if (atTop) {
      cur = (lines: [...pending, l], head: l);
      pending = [];
      out.add(cur);
      continue;
    }
    if (cur != null) {
      if (pending.isNotEmpty) {
        cur.lines.addAll(pending);
        pending = [];
      }
      cur.lines.add(l);
    } else if (l.trim().isNotEmpty) {
      pending.add(l);
    }
  }
  if (pending.isNotEmpty) {
    out.add((lines: pending, head: pending.first));
  }
  return [
    for (final it in out)
      (
        lines: it.lines,
        head: it.head,
        top:
            _top.hasMatch(it.head.trimLeft()) ||
            it.head.trimLeft().startsWith('const '),
      ),
  ];
}

/// [it]'s text, without the blank lines that end it.
String _text(_Item it) => it.lines.join('\n').trimRight();

const _runApp =
    'Future<void> _codeRunApp(Widget app, {Object? mode, Object? viewport, '
    'Object? terminal, Object? maxFps, Object? maxInlineRows, '
    'Object? clearInlineOnExit, Object? logs, Object? exitOnCtrlC, '
    'Object? screenReader, Object? bidi}) async => _codeApp = app;';

String _indent(String s, int n) =>
    s.split('\n').map((l) => l.isEmpty ? l : '${' ' * n}$l').join('\n');

/// A console program's main, and the function it runs.
final _cliMain = RegExp(
  r'^Future<void> main\(List<String> args\) =>\s*'
  r'Cli\.runWithArgs\(args, (\w+)(?:, [^;]*)?\);',
  multiLine: true,
);

/// The library for [src], a page's Code.
Wrapped wrap(String src) {
  if (_cliMain.firstMatch(src) case final m?) {
    final name = m[1]!;
    return _made(
      [
        "import 'package:twk/twk.dart';",
        '',
        "import 'cli/$name.dart' as program;",
        "import 'cli/run.dart';",
        '',
        'Widget codeWidget() =>',
        "    CliRun(script: cliScripts['$name']!, program: program.$name);",
        '',
      ].join('\n'),
      WrapMode.cli,
      src,
      {'lib/cli/$name.dart': src.endsWith('\n') ? src : '$src\n'},
    );
  }
  final items = _items(src);
  final given = [
    "import 'dart:async';",
    "import 'dart:math';",
    "import 'package:twk/log.dart';",
    "import 'package:twk/twk.dart';",
    // all the gallery's packages, whatever a Code names of them: a list of
    // their names would fail a Code that uses a widget added since
    "import 'package:twk_rich/image.dart';",
    "import 'package:twk_rich/twk_rich.dart';",
    "import 'package:twk_term/twk_term.dart';",
  ];
  final own = [
    for (final it in items)
      if (it.head.startsWith('import ')) _text(it),
  ];
  final head = [...own, ...given.where((i) => !own.contains(i)), ''];
  final main = RegExp(r'^(void|Future<void>) main\b');
  if (items.any((it) => main.hasMatch(it.head))) {
    final body = src
        .replaceFirstMapped(
          RegExp(r'^(void|Future<void>) main\(([^)]*)\)', multiLine: true),
          (m) =>
              '${m[1]} _codeMain('
              '${m[2]!.isEmpty ? '' : '[List<String> args = const []]'})',
        )
        .replaceAll(RegExp(r'\brunApp\('), '_codeRunApp(');
    final lines = [
      for (final it in _items(body))
        if (!it.head.startsWith('import ')) _text(it),
    ];
    return _made(
      [
        ...head,
        'Widget? _codeApp;',
        _runApp,
        '',
        'Widget codeWidget() {',
        '  _codeMain();',
        "  return _codeApp ?? (throw StateError('main did not call runApp'));",
        '}',
        '',
        lines.join('\n\n'),
        '',
      ].join('\n'),
      WrapMode.file,
      src,
    );
  }
  final tops = [
    for (final it in items)
      if (it.top && !it.head.startsWith('import ')) _text(it),
  ];
  final rest = [
    for (final it in items)
      if (!it.top) _text(it),
  ];
  // a State whose widget the Code does not declare: the Code is that
  // widget's state, the widget made here
  final state = RegExp(r'class (\w+) extends State<(\w+)>')
      .allMatches(src)
      .where((m) => !RegExp('class ${m[2]}\\b').hasMatch(src))
      .firstOrNull;
  if (state != null) {
    final (name, w) = (state[1]!, state[2]!);
    return _made(
      [
        ...head,
        'Widget codeWidget() => const $w();',
        '',
        'final class $w extends StatefulWidget {',
        '  const $w();',
        '  @override',
        '  State<$w> createState() => $name();',
        '}',
        '',
        [...rest, ...tops].join('\n\n'),
        '',
      ].join('\n'),
      WrapMode.stateGiven,
      src,
    );
  }
  final hasBuild = RegExp(
    r'^(@override\s*\n)?Widget build\(',
    multiLine: true,
  ).hasMatch(src);
  final cls = [
    'Widget codeWidget() => const _W();',
    '',
    'final class _W extends StatefulWidget {',
    '  const _W();',
    '  @override',
    '  State<_W> createState() => _S();',
    '}',
    '',
    'final class _S extends State<_W> with TickerProviderStateMixin {',
  ];
  if (hasBuild) {
    return _made(
      [
        ...head,
        ...cls,
        _indent(rest.join('\n\n'), 2),
        '}',
        '',
        tops.join('\n\n'),
        '',
      ].join('\n'),
      WrapMode.members,
      src,
    );
  }
  return _made(
    [
      ...head,
      ...cls,
      '  @override',
      '  Widget build(BuildContext context) {',
      _indent(rest.join('\n'), 4),
      '  }',
      '}',
      '',
      tops.join('\n\n'),
      '',
    ].join('\n'),
    WrapMode.body,
    src,
  );
}
