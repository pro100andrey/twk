// The ANSI page.
part of 'text.dart';

/// [child] as tall as it is, cut to the room where that is lower: the
/// stage cuts a widget taller than its room, as the design's does, and so
/// a column of rows that do not fit is cut, not overflowing.
final class _Cut extends SingleChildRenderObjectWidget {
  const _Cut({super.child});

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderCut createRenderObject(BuildContext context) => _RenderCut();
}

final class _RenderCut extends RenderObject with RenderObjectWithChildMixin {
  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(
      BoxConstraints(c.minW, c.maxW, 0, BoxConstraints.unbounded),
      parentUsesSize: true,
    );
    width = c.constrainW(child.width);
    height = c.constrainH(child.height);
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child == null) {
      return;
    }
    ctx.canvas
      ..save()
      ..clipRect(0, 0, width, height);
    paintChild(ctx, child);
    ctx.canvas.restore();
  }
}

// ------------------------------------------------------------ ANSI

const Map<String, (String, String, String)> _outputs = {
  'test': (' dart test ', 'dart test', _testOutput),
  'ls': (' ls --color ', 'ls --color', _lsOutput),
  'log': (' tail server.log ', 'tail server.log', _logOutput),
};

const _ansiWidth = 56;

/// A piece every 40 ms, as a program writes.
const _pieceMs = 40;

/// The ticks the output stays whole before it comes again.
const _ansiHold = 60;

/// [text] as a Dart string of adjacent literals, a line each, its controls
/// escaped (\x1B, \r, \n).
List<String> _dartAnsi(String name, String text) {
  String esc(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\x1B', r'\x1B')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\x07', r'\x07');
  final lines = [
    for (final m in RegExp(r'[^\n]*\n|[^\n]+$').allMatches(text)) m[0]!,
  ];
  return [
    'const $name =',
    for (final (i, l) in lines.indexed)
      "    '${esc(l)}'${i == lines.length - 1 ? ';' : ''}",
  ];
}

final _ansi = GalleryPage(
  group: 'Text',
  title: 'ANSI',
  options: const [
    ChoiceOption(
      'output',
      'output',
      values: ['test', 'ls', 'log'],
      labels: ['dart test', 'ls', 'log'],
    ),
    ChoiceOption('read', 'read with', values: ['parseAnsi', 'AnsiStream']),
    ChoiceOption(
      'piece',
      'piece',
      values: [7, 16, 64],
      labels: ['7 chars', '16', '64'],
    ),
  ],
  build: (context, o) => inRoom((rw, rh) {
    final (title, _, output) = _outputs[o.choice<String>('output')]!;
    final rows = parseAnsi(output).length;
    final w = math.min(_ansiWidth, rw);
    Widget view(List<List<Span>> lines, List<Widget> read) {
      final theme = Theme.of(context);
      // cut to the stage's room where it is lower, as the design's stage
      // cuts it
      return _Cut(
        child: SizedBox(
          width: w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            gap: 1,
            children: [
              SizedBox(
                height: rows + 2,
                child: Box(
                  border: Border.all(
                    type: BorderType.rounded,
                    style: theme.border,
                  ),
                  titles: [BorderTitle(title, style: theme.muted)],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in lines)
                        Text.rich(line, wrap: TextWrap.none),
                    ],
                  ),
                ),
              ),
              ...read,
            ],
          ),
        ),
      );
    }

    if (o.choice<String>('read') == 'parseAnsi') {
      final lines = parseAnsi(output);
      return Builder(
        builder: (context) => view(lines, [
          Text.rich([
            Span('read: ', Theme.of(context).muted),
            Span(
              '${output.length} characters at once, ${lines.length} lines',
            ),
          ]),
        ]),
      );
    }
    final size = o.choice<int>('piece');
    final pieces = (output.length + size - 1) ~/ size;
    final cycle = (pieces + _ansiHold) * _pieceMs;
    return Timed((context, ms, wake) {
      final theme = Theme.of(context);
      final tick = ms % cycle ~/ _pieceMs;
      wake(ms - ms % cycle + (tick + 1) * _pieceMs);
      // the pieces read by this tick, as the Code's timer reads them
      final stream = AnsiStream();
      var read = 0;
      var piece = '';
      for (var k = 1; k <= tick && read < output.length; k++) {
        final end = math.min(read + size, output.length);
        piece = output.substring(read, end);
        stream.add(piece);
        read = end;
        if (read == output.length) {
          stream.close();
        }
      }
      return view(stream.lines, [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich([
              Span('read: ', theme.muted),
              Span('$read of ${output.length} characters, $size at a time'),
            ]),
            Text.rich([
              Span('piece: ', theme.muted),
              if (piece.isEmpty) Span('nothing', theme.muted),
              // its controls as the pictures of them: ␛ ␍ ␤
              for (final c in piece.runes)
                if (c < 0x20)
                  Span(String.fromCharCode(0x2400 + c), theme.muted)
                else
                  Span(String.fromCharCode(c)),
            ]),
          ],
        ),
      ]);
    });
  }),
  codeIn: (o, room) {
    final (title, what, output) = _outputs[o.choice<String>('output')]!;
    final (rw, _) = codeRoomOf(room);
    final w = math.min(_ansiWidth, rw);
    final rows = parseAnsi(output).length;
    List<String> box(String lines) => [
      '      SizedBox(',
      '        height: ${rows + 2},',
      '        child: Box(',
      '          border: .all(type: .rounded, style: theme.border),',
      "          titles: [BorderTitle('$title', style: theme.muted)],",
      '          child: Column(',
      '            crossAxisAlignment: .start,',
      codeLine([
        '            children: [for (final line in $lines) ',
        'Text.rich(line, wrap: .none)],',
      ]),
      '          ),',
      '        ),',
      '      ),',
    ];
    final head = [
      '// what `$what` wrote to a terminal, its colours in SGR sequences',
      ..._dartAnsi('_output', output),
      '',
    ];
    if (o.choice<String>('read') == 'parseAnsi') {
      return [
        ...head,
        'final _lines = parseAnsi(_output);',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  return SizedBox(',
        '    width: $w,',
        '    child: Column(',
        '      mainAxisSize: .min,',
        '      crossAxisAlignment: .stretch,',
        '      gap: 1,',
        '      children: [',
        for (final l in box('_lines')) '  $l',
        '        Text.rich([',
        "          Span('read: ', theme.muted),",
        codeLine([
          r"          Span('${_output.length} characters at once, ",
          r"${_lines.length} lines'),",
        ]),
        '        ]),',
        '      ],',
        '    ),',
        '  );',
        '}',
      ].join('\n');
    }
    final size = o.choice<int>('piece');
    return [
      ...head,
      codeLine([
        '// a piece of $size characters every $_pieceMs ms, as a program ',
        'writes;',
      ]),
      '// whole for $_ansiHold ticks, then again',
      'const _size = $size;',
      'const _hold = $_ansiHold;',
      'final _pieces = (_output.length + _size - 1) ~/ _size;',
      'var _stream = AnsiStream();',
      'var _tick = 0;',
      'var _read = 0;',
      "var _piece = '';",
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_pieceMs),',
      '    (_) => setState(_next),',
      '  );',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _timer.cancel();',
      '  super.dispose();',
      '}',
      '',
      'void _next() {',
      '  _tick = (_tick + 1) % (_pieces + _hold);',
      '  if (_tick == 0) {',
      '    _stream = AnsiStream();',
      '    _read = 0;',
      "    _piece = '';",
      '  } else if (_read < _output.length) {',
      '    // a piece may end within a sequence: the rest of it waits',
      '    final end = (_read + _size).clamp(0, _output.length);',
      '    _piece = _output.substring(_read, end);',
      '    _stream.add(_piece);',
      '    _read = end;',
      '    if (_read == _output.length) _stream.close();',
      '  }',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return SizedBox(',
      '    width: $w,',
      '    child: Column(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .stretch,',
      '      gap: 1,',
      '      children: [',
      for (final l in box('_stream.lines')) '  $l',
      '        Column(',
      '          mainAxisSize: .min,',
      '          crossAxisAlignment: .start,',
      '          children: [',
      '            Text.rich([',
      "              Span('read: ', theme.muted),",
      codeLine([
        r"              Span('$_read of ${_output.length} characters, ",
        r"$_size at a time'),",
      ]),
      '            ]),',
      '            Text.rich([',
      "              Span('piece: ', theme.muted),",
      "              if (_piece.isEmpty) Span('nothing', theme.muted),",
      '              // its controls as the pictures of them: ␛ ␍ ␤',
      '              for (final c in _piece.runes)',
      '                c < 0x20',
      codeLine([
        '                    ? Span(String.fromCharCode(0x2400 + c), ',
        'theme.muted)',
      ]),
      '                    : Span(String.fromCharCode(c)),',
      '            ]),',
      '          ],',
      '        ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

const _testOutput =
    '\r\x1B[K00:00 \x1B[32m+0\x1B[0m: loading '
    'test/view_test.dart\r\x1B[K00:00 \x1B[32m+3\x1B[0m: '
    'test/view_test.dart: lists and their markers\r\x1B[K00:01 '
    '\x1B[32m+9\x1B[0m: test/stream_test.dart: a block settled '
    'once\r\x1B[K00:01 \x1B[32m+12\x1B[0m \x1B[33m~1\x1B[0m: '
    'test/code_test.dart: tabs\r\x1B[K00:02 \x1B[32m+16\x1B[0m '
    '\x1B[33m~1\x1B[0m: test/diff_test.dart: a gap row\r\x1B[K00:02 '
    '\x1B[32m+16\x1B[0m \x1B[33m~1\x1B[0m \x1B[31m-1\x1B[0m: '
    'test/diff_test.dart: a gap row [E]\n'
    "  Expected: '⋯ 21 unchanged lines'\n"
    "    Actual: '⋯ 20 unchanged lines'\n"
    '     Which: is different.\n'
    '\n'
    '  \x1B[2mtest/diff_test.dart 88:7  main.<fn>\x1B[22m\n'
    '\r\x1B[K00:03 \x1B[32m+21\x1B[0m \x1B[33m~1\x1B[0m '
    '\x1B[31m-1\x1B[0m: \x1B[31mSome tests failed.\x1B[0m\n';

const _lsOutput =
    '\x1B[0mCHANGELOG.md  LICENSE       \x1B[01;34mtest\x1B[0m\n'
    '\x1B[01;34mdesign\x1B[0m        \x1B[01;34mpackages\x1B[0m      '
    '\x1B[01;34mtool\x1B[0m\n'
    '\x1B[01;34mexample\x1B[0m       pubspec.yaml  '
    '\x1B[01;31mtwk-0.1.0.tar.gz\x1B[0m\n'
    '\x1B[01;36mlatest\x1B[0m        README.md\n'
    '\x1B[01;34mlib\x1B[0m           \x1B[01;32mrun.sh\x1B[0m\n';

const _logOutput =
    '\x1B[2m09:41:00\x1B[22m \x1B[32mINFO \x1B[39m serving '
    '\x1B[4m\x1B]8;;http://localhost:8080\x1B\\http://localhost:8080\x1B]8;;\x1B\\\x1B[24m\n'
    '\x1B[2m09:41:02\x1B[22m \x1B[32mINFO \x1B[39m GET /items '
    '\x1B[38;5;34m200\x1B[39m 4 ms\n'
    '\x1B[2m09:41:03\x1B[22m \x1B[33mWARN \x1B[39m slow query: '
    '\x1B[1m812 ms\x1B[22m\n'
    '\x1B[2m09:41:05\x1B[22m \x1B[1;31mERROR\x1B[0m GET /items/42 '
    '\x1B[30;48;5;203m 500 \x1B[0m timed out\n'
    '\x1B[2m09:41:05\x1B[22m \x1B[38:2::150:120:220mDEBUG\x1B[39m '
    '\x1B[3mretry 1 of 3\x1B[23m\n'
    '\x1B[2m09:41:06\x1B[22m \x1B[32mINFO \x1B[39m GET /items/42 '
    '\x1B[38;5;34m200\x1B[39m 9 ms\n';
