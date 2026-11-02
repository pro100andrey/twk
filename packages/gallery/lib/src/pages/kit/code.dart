// The Dart a page's Code tab writes: calls broken as dart format breaks
// them, a State's timer, a line too long for its file.

/// The lines of the call [head]([args])[tail] at [indent], as dart format
/// writes it: on one line where it fits in [width] columns, else an
/// argument a line with a comma after each.
///
/// [width] is 78 for a call in a State's member, 80 where the pages of a
/// group were written to the whole line: each page keeps the Code it has.
List<String> call(
  int indent,
  String head,
  List<String> args,
  String tail, {
  int width = 78,
}) {
  final pad = ' ' * indent;
  final one = '$pad$head(${args.join(', ')})$tail';
  if (one.length <= width) {
    return [one];
  }
  return [
    '$pad$head(',
    for (final a in args) '$pad  $a,',
    '$pad)$tail',
  ];
}

/// The lines of a State whose timer calls [body] every [ms].
List<String> timerLines(int ms, List<String> body) => [
  'late final Timer _timer;',
  '',
  '@override',
  'void initState() {',
  '  super.initState();',
  '  _timer = Timer.periodic(',
  '    const Duration(milliseconds: $ms),',
  for (final l in body) '    $l',
  '  );',
  '}',
  '',
  '@override',
  'void dispose() {',
  '  _timer.cancel();',
  '  super.dispose();',
  '}',
];

/// [parts] as one line of the Code, a line too long for its file.
String codeLine(List<String> parts) => parts.join();
