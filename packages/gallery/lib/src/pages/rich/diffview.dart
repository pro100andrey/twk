// The DiffView page.
part of 'rich.dart';

// ------------------------------------------------------------ DiffView

const _path = 'bin/greet.dart';

/// A step of the live edit.
const _step = 1000;

/// The text after the first [k] of the edits.
String _edited(int k) => _edits
    .take(k)
    .fold(_before, (text, edit) => text.replaceFirst(edit.$1, edit.$2));

final String _after = _edited(_edits.length);

final _diffView = GalleryPage(
  group: 'Rich',
  title: 'DiffView',
  options: const [
    ChoiceOption('layout', 'layout', values: ['unified', 'sideBySide']),
    ChoiceOption(
      'context',
      'context',
      values: [3, 1, 0],
      labels: ['3 lines', '1', '0'],
    ),
    SwitchOption('live', 'edit live'),
    // the code's language: that of the file's path, or none
    ChoiceOption(
      'language',
      'language',
      values: ['path', 'plain'],
      labels: ["the path's", 'plain'],
    ),
  ],
  build: (context, o) => inRoom((rw, rh) {
    final side = o.choice<String>('layout') == 'sideBySide';
    final plain = o.choice<String>('language') == 'plain';
    final w = math.min(rw, side ? 100 : 64);
    final h = clampTo(rh, 6, 22);
    Widget view(String after) => SizedBox(
      width: w,
      height: h,
      child: Scrollbar(
        style: Theme.of(context).border,
        child: DiffView(
          Diff.between(
            _before,
            after,
            context: o.choice('context'),
            path: _path,
          ),
          layout: side ? DiffLayout.sideBySide : DiffLayout.unified,
          language: plain ? Language.plain : null,
        ),
      ),
    );
    if (!o.flag('live')) {
      return view(_after);
    }
    return Timed((context, ms, wake) {
      final k = ms ~/ _step;
      wake((k + 1) * _step);
      return view(_edited(k % (_edits.length + 4)));
    });
  }),
  heightIn: (o, room) => clampTo(room.height, 6, 22),
  codeIn: (o, room) {
    final (rw, rh) = codeRoomOf(room);
    final side = o.choice<String>('layout') == 'sideBySide';
    final w = math.min(rw, side ? 100 : 64);
    final h = clampTo(rh, 6, 22);
    final context = o.choice<int>('context');
    final args = [
      if (side) ', layout: .sideBySide',
      if (o.choice<String>('language') == 'plain') ', language: Language.plain',
    ].join();
    String between(String after) =>
        'Diff.between(_before, $after'
        "${context == 3 ? '' : ', context: $context'}, path: '$_path')";
    List<String> view(String diff) => [
      '  return SizedBox(',
      '    width: $w,',
      '    height: $h,',
      '    child: Scrollbar(',
      '      style: Theme.of(context).border,',
      '      child: DiffView($diff$args),',
      '    ),',
      '  );',
    ];
    final head = ["const _before = r'''", ..._before.split('\n'), "''';", ''];
    if (!o.flag('live')) {
      return [
        ...head,
        "const _after = r'''",
        ..._after.split('\n'),
        "''';",
        '',
        'final _diff = ${between('_after')};',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        ...view('_diff'),
        '}',
      ].join('\n');
    }
    return [
      ...head,
      '// the edit as an agent makes it, a step a second, then again',
      'const _edits = [',
      for (final (a, b) in _edits) "  (r'''$a''', r'''$b'''),",
      '];',
      'var _step = 0;',
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_step),',
      '    (_) => setState(() => _step = (_step + 1) % (_edits.length + 4)),',
      '  );',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _timer.cancel();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final after = _edits',
      '      .take(_step)',
      codeLine([
        '      .fold(_before, (text, edit) => ',
        r'text.replaceFirst(edit.$1, edit.$2));',
      ]),
      ...view(between('after')),
      '}',
    ].join('\n');
  },
);

const _before = r'''
import 'dart:io';

/// Greets [name] on the terminal.
String greet(String name) {
  return 'Hello, ' + name + '!';
}

/// The names to greet, one a line.
List<String> readNames(String path) {
  final file = File(path);
  final lines = file.readAsLinesSync();
  return lines.where((l) => l.isNotEmpty).toList();
}

void main(List<String> args) {
  final names = readNames(args.first);
  for (final name in names) {
    print(greet(name));
  }
  print('Greeted ${names.length} names.');
}''';

const _edits = [
  (
    '/// Greets [name] on the terminal.',
    '/// Greets [name] on the terminal, in [language].',
  ),
  (
    'String greet(String name) {',
    "String greet(String name, {String language = 'en'}) {",
  ),
  (
    "  return 'Hello, ' + name + '!';\n"
        '}',
    "  return '\${hello[language]}, \$name!';\n"
        '}\n'
        '\n'
        "const hello = {'en': 'Hello', 'uk': 'Привіт'};",
  ),
  (
    '  final names = readNames(args.first);',
    '  final names = readNames(args.first);\n'
        "  final language = args.length > 1 ? args[1] : 'en';",
  ),
  (
    '    print(greet(name));',
    '    print(greet(name, language: language));',
  ),
  (
    '  }\n'
        "  print('Greeted \${names.length} names.');\n"
        '}',
    '  }\n'
        '}',
  ),
];
