// The Rich group of the gallery.
import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Pen, RenderParagraph;
import 'package:twk_rich/twk_rich.dart';

import '../motion.dart';
import '../page.dart';
import 'common.dart';

/// The pages of the Rich group that draw.
final richPages = <GalleryPage>[
  _markdownView,
  _codeView,
  _syntaxThemeScope,
  _diffView,
  _jsonView,
  _bigText,
  _qrCode,
  _ansi,
];

// ------------------------------------------------------------ shared

/// [room] as the page's Code reads it: 56 × 20 before the stage was laid
/// out.
(int, int) _roomOf(StageRoom room) =>
    room == StageRoom.unbounded ? (56, 20) : (room.width, room.height);

/// [build] with the stage's room.
Widget _inRoom(Widget Function(int w, int h) build) => LayoutBuilder(
  builder: (context, c) {
    const most = 1 << 20;
    return build(
      c.maxW < BoxConstraints.unbounded ? c.maxW : most,
      c.maxH < BoxConstraints.unbounded ? c.maxH : most,
    );
  },
);

/// [parts] as one line of the Code, a line too long for this file.
String _l(List<String> parts) => parts.join();

int _clamp(int v, int low, int high) => math.max(low, math.min(high, v));

/// Builds [builder] with the gallery's time in milliseconds, again at each
/// time it asks for with `wake`: what the Code's timers move, on the
/// gallery's clock, so that a route's `t=` stills it.
final class _Timed extends StatefulWidget {
  const _Timed(this.builder);

  final Widget Function(BuildContext context, int ms, void Function(int) wake)
  builder;

  @override
  State<_Timed> createState() => _TimedState();
}

final class _TimedState extends State<_Timed> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final built = widget.builder(
      context,
      _motion.now.inMilliseconds,
      (at) => _motion.wakeAt(Duration(milliseconds: at)),
    );
    _motion.end();
    return built;
  }
}

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

/// The frame of the dots spinner at [ms]: twk's Spinner on the gallery's
/// clock.
String _spinnerAt(int ms) {
  final frames = SpinnerFrames.dots.frames;
  return frames[ms ~/
      SpinnerFrames.dots.interval.inMilliseconds %
      frames.length];
}

/// A Dart constant [name] holding [text], a string a line: legible in the
/// Code tab, which highlights a line at a time.
List<String> _dartString(String name, String text) {
  final lines = text.split('\n');
  return [
    for (final (i, l) in lines.indexed)
      ...() {
        final q = l.contains("'") && !l.contains('"') ? '"' : "'";
        final body = l
            .replaceAll(r'\', r'\\')
            .replaceAll(r'$', r'\$')
            .replaceAll(q, '\\$q');
        final nl = i < lines.length - 1 ? r'\n' : '';
        final end = i == lines.length - 1 ? ';' : '';
        final head = i == 0 ? 'const $name =\n    ' : '    ';
        // a line too long for 80 columns in two strings, split at a blank
        final cut = body.lastIndexOf(' ', math.min(72, body.length));
        if (6 + body.length + nl.length + end.length > 80 && cut > 0) {
          return [
            '$head$q${body.substring(0, cut + 1)}$q',
            '    $q${body.substring(cut + 1)}$nl$q$end',
          ];
        }
        return ['$head$q$body$nl$q$end'];
      }(),
  ];
}

// ------------------------------------------------------------ MarkdownView

// thinking, then 5 characters every 40 ms, as a model's tokens come; whole
// for 3.5 s, then asked again
const _think = 700;
const _piece = 40;
const _pieceLength = 5;
const _hold = 3500;
const int _pieces = (_answer.length + _pieceLength - 1) ~/ _pieceLength;
const int _cycle = _think + _pieces * _piece + _hold;

final _markdownView = GalleryPage(
  group: 'Rich',
  title: 'MarkdownView',
  options: [
    const ChoiceOption(
      'content',
      'content',
      values: ['document', 'answer'],
      labels: ['document', 'chat answer'],
    ),
    const ChoiceOption(
      'codeWrap',
      'code wrap',
      values: ['grapheme', 'word', 'none'],
    ),
    SliderOption(
      'width',
      'width',
      min: 30,
      max: 72,
      initial: 50,
      format: (v) => '$v cells',
    ),
    // onLinkTap: the app's own links, a heading's scrolled to by the
    // MarkdownController; the app's only, hyperlinks: false, no OSC 8 for
    // the terminal to open
    ChoiceOption(
      'links',
      'links go to',
      values: const ['terminal', 'app', 'app only'],
      labels: const ['the terminal', 'the app', 'the app only'],
      disabled: (o) => o['content'] != 'document',
    ),
  ],
  build: (context, o) => _inRoom((rw, rh) {
    final theme = Theme.of(context);
    final w = math.min(o.number('width').toInt(), rw);
    final h = _clamp(rh, 6, 24);
    final wrap = TextWrap.values.byName(o.choice('codeWrap'));
    if (o.choice<String>('content') == 'document' && o['links'] != 'terminal') {
      return SizedBox(
        width: w,
        height: h,
        child: _AppLinks(codeWrap: wrap, hyperlinks: o['links'] == 'app'),
      );
    }
    if (o.choice<String>('content') == 'document') {
      return SizedBox(
        width: w,
        height: h,
        child: Scrollbar(
          style: theme.border,
          child: SingleChildScrollView(
            child: MarkdownView(_doc, codeWrap: wrap),
          ),
        ),
      );
    }
    return _Timed((context, ms, wake) {
      final tt = ms % _cycle;
      final base = ms - tt;
      final thinking = tt < _think;
      final piece = thinking
          ? 0
          : math.min(_pieces, (tt - _think) ~/ _piece + 1);
      final shown = math.min(_answer.length, piece * _pieceLength);
      // the piece that came since the frame before
      final from = math.min(shown, math.max(0, piece - 1) * _pieceLength);
      final done = shown == _answer.length;
      wake(
        done
            ? base + _cycle
            : base + (thinking ? _think : _think + piece * _piece),
      );
      const took = (_think + _pieces * _piece) / 1000;
      return SizedBox(
        width: w,
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          gap: 1,
          children: [
            Text.rich([
              Span('› ', theme.primary.merge(const Style(attrs: Attr.bold))),
              const Span(_question, Style(attrs: Attr.bold)),
            ]),
            Expanded(
              child: Scrollbar(
                style: theme.border,
                // follows the end while it shows it
                child: ListView(
                  stickToBottom: true,
                  children: [
                    MarkdownView(
                      _answer.substring(0, shown),
                      appended: _answer.substring(from, shown),
                      codeWrap: wrap,
                    ),
                  ],
                ),
              ),
            ),
            Row(
              gap: 1,
              children: [
                if (done)
                  Text('✓', style: theme.success)
                else
                  // Spinner(style: theme.primary), on the gallery's clock
                  Text(_spinnerAt(ms), style: theme.primary),
                Text(
                  done
                      ? 'answered in ${took.toStringAsFixed(1)} s'
                      : thinking
                      ? 'thinking…'
                      : 'answering…',
                  style: theme.muted,
                ),
              ],
            ),
          ],
        ),
      );
    });
  }),
  heightIn: (o, room) => _clamp(room.height, 6, 24),
  codeIn: (o, room) {
    final (rw, rh) = _roomOf(room);
    final w = math.min(o.number('width').toInt(), rw);
    final h = _clamp(rh, 6, 24);
    final codeWrap = o.label('codeWrap');
    final wrap = codeWrap == 'grapheme' ? '' : ', codeWrap: .$codeWrap';
    if (o.choice<String>('content') == 'document' && o['links'] != 'terminal') {
      return [
        ..._dartString('_notes', _doc),
        '',
        'final _md = MarkdownController();',
        'String? _tapped;',
        '',
        '@override',
        'void dispose() {',
        '  _md.dispose();',
        '  super.dispose();',
        '}',
        '',
        '// the app opens its links itself: one to a heading scrolls to it',
        'void _tap(String destination, String? title) {',
        '  setState(() => _tapped = destination);',
        '  _md.scrollToHeading(destination);',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) => SizedBox(',
        '  width: $w,',
        '  height: $h,',
        '  child: Column(',
        '    crossAxisAlignment: .stretch,',
        '    gap: 1,',
        '    children: [',
        '      Expanded(',
        '        child: Scrollbar(',
        '          style: Theme.of(context).border,',
        '          child: SingleChildScrollView(',
        '            child: MarkdownView(',
        '              _notes,',
        '              controller: _md,',
        '              onLinkTap: _tap,',
        if (codeWrap != 'grapheme') '              codeWrap: .$codeWrap,',
        if (o['links'] == 'app only') '              hyperlinks: false,',
        '            ),',
        '          ),',
        '        ),',
        '      ),',
        '      Text.rich([',
        "        Span('tapped: ', Theme.of(context).muted),",
        '        switch (_tapped) {',
        "          null => Span('nothing', Theme.of(context).muted),",
        '          final tapped => Span(tapped),',
        '        },',
        '      ]),',
        '    ],',
        '  ),',
        ');',
      ].join('\n');
    }
    if (o.choice<String>('content') == 'document') {
      return [
        ..._dartString('_notes', _doc),
        '',
        '@override',
        'Widget build(BuildContext context) => SizedBox(',
        '  width: $w,',
        '  height: $h,',
        '  child: Scrollbar(',
        '    style: Theme.of(context).border,',
        '    child: SingleChildScrollView(',
        '      child: MarkdownView(_notes$wrap),',
        '    ),',
        '  ),',
        ');',
      ].join('\n');
    }
    return [
      "const _question = '$_question';",
      ..._dartString('_answer', _answer),
      '',
      "// thinking, then 5 characters every 40 ms, as a model's tokens",
      '// come; whole for 3.5 s, then asked again',
      'const _think = $_think;',
      'const _piece = $_piece;',
      'const _hold = $_hold;',
      _l([
        'final _pieces = (_answer.length + ${_pieceLength - 1}) ~/ ',
        '$_pieceLength;',
      ]),
      'var _ms = 0;',
      'late final Timer _timer;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  final cycle = _think + _pieces * _piece + _hold;',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: _piece),',
      '    (_) => setState(() => _ms = (_ms + _piece) % cycle),',
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
      '  final theme = Theme.of(context);',
      '  final thinking = _ms < _think;',
      '  final piece = thinking ? 0 : (_ms - _think) ~/ _piece + 1;',
      '  final shown = (piece * $_pieceLength).clamp(0, _answer.length);',
      '  // the piece that came since the frame before',
      '  final from = ((piece - 1) * $_pieceLength).clamp(0, shown);',
      '  final done = shown == _answer.length;',
      '  final took = (_think + _pieces * _piece) / 1000;',
      '  return SizedBox(',
      '    width: $w,',
      '    height: $h,',
      '    child: Column(',
      '      crossAxisAlignment: .stretch,',
      '      gap: 1,',
      '      children: [',
      '        Text.rich([',
      _l([
        "          Span('› ', theme.primary.merge(const Style(attrs: ",
        'Attr.bold))),',
      ]),
      '          Span(_question, const Style(attrs: Attr.bold)),',
      '        ]),',
      '        Expanded(',
      '          child: Scrollbar(',
      '            style: theme.border,',
      '            // follows the end while it shows it',
      '            child: ListView(',
      '              stickToBottom: true,',
      '              children: [',
      '                MarkdownView(',
      '                  _answer.substring(0, shown),',
      '                  appended: _answer.substring(from, shown),',
      if (codeWrap != 'grapheme') '                  codeWrap: .$codeWrap,',
      '                ),',
      '              ],',
      '            ),',
      '          ),',
      '        ),',
      '        Row(',
      '          gap: 1,',
      '          children: [',
      _l([
        "            if (done) Text('✓', style: theme.success) else ",
        'Spinner(style: theme.primary),',
      ]),
      '            Text(',
      r"              done ? 'answered in ${took.toStringAsFixed(1)} s'",
      "                  : thinking ? 'thinking…' : 'answering…',",
      '              style: theme.muted,',
      '            ),',
      '          ],',
      '        ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

// ------------------------------------------------------------ CodeView

const Map<String, String> _sources = {
  'dart': _dartSource,
  'python': _pythonSource,
  'rust': _rustSource,
  'go': _goSource,
  'javascript': _javascriptSource,
  'typescript': _typescriptSource,
  'json': _jsonSource,
  'yaml': _yamlSource,
  'bash': _bashSource,
  'diff': _diffSource,
  'plain': _plainSource,
};

/// Each language twk_rich highlights, and plain text, which it does not.
const Map<String, Language> _languages = {
  'dart': dartLanguage,
  'python': pythonLanguage,
  'rust': rustLanguage,
  'go': goLanguage,
  'javascript': javascriptLanguage,
  'typescript': typescriptLanguage,
  'json': jsonLanguage,
  'yaml': yamlLanguage,
  'bash': bashLanguage,
  'diff': diffLanguage,
  'plain': Language.plain,
};

// The lines changed since the last commit, as an editor marks them in its
// gutter: a CodeSign by line number, + added and ~ changed; the number of
// the line in the source, from 1.
const _changed = {
  'dart': {14: '~', 18: '+'},
  'python': {8: '~', 13: '+', 14: '+'},
  'rust': {10: '~'},
  'go': {13: '~', 14: '~'},
  'javascript': {13: '~', 16: '+'},
  'typescript': {14: '~', 22: '+'},
  'json': {3: '~', 17: '+', 18: '+'},
  'yaml': {14: '+', 21: '~'},
  'bash': {6: '~', 18: '+', 19: '+'},
  'diff': {9: '~'},
  'plain': {7: '~', 16: '+'},
};

/// The CodeView page's first line number less 1: what the gutter's
/// numbers are past the source's own.
int _past(Options o) => o.choice<int>('first') - 1;

/// The rows CodeView takes of the source of [o] in a Scrollbar [w] wide:
/// each line broken as twk's Text breaks it in what the gutter leaves.
int _codeRowsIn(Options o, int w) {
  final lines = _sources[o.choice<String>('lang')]!.split('\n');
  final digits = '${_past(o) + lines.length}'.length;
  final gutter =
      (o.flag('signs') ? 2 : 0) + (o.flag('numbers') ? digits + 1 : 0);
  final width = math.max(1, w - 1 - gutter);
  final wrap = TextWrap.values.byName(o.choice('wrap'));
  var rows = 0;
  for (final line in lines) {
    // tabs to the next multiple of 4, as CodeView expands them
    final text = StringBuffer();
    for (final c in line.split('')) {
      text.write(c == '\t' ? ' ' * (4 - text.length % 4) : c);
    }
    rows += RenderParagraph([
      ('$text', const Pen()),
    ], wrap: wrap).getMaxIntrinsicHeight(width);
  }
  return rows;
}

final _codeView = GalleryPage(
  group: 'Rich',
  title: 'CodeView',
  options: [
    const ChoiceOption(
      'lang',
      'language',
      values: [
        'dart',
        'python',
        'rust',
        'go',
        'javascript',
        'typescript',
        'json',
        'yaml',
        'bash',
        'diff',
        'plain',
      ],
      labels: [
        'Dart',
        'Python',
        'Rust',
        'Go',
        'JavaScript',
        'TypeScript',
        'JSON',
        'YAML',
        'Bash',
        'diff',
        'plain',
      ],
    ),
    const SwitchOption('numbers', 'line numbers', initial: true),
    const SwitchOption('signs', 'changes'),
    const ChoiceOption(
      'wrap',
      'wrap',
      values: ['none', 'word', 'grapheme'],
      initial: 'word',
    ),
    SliderOption(
      'width',
      'width',
      min: 24,
      max: 80,
      initial: 56,
      format: (v) => '$v cells',
    ),
    const ChoiceOption(
      'rows',
      'rows',
      values: [null, 10],
      labels: ['all', '10'],
    ),
    // an excerpt of a file: its lines numbered from where it starts, the
    // signs and the controller's lines by those numbers
    const ChoiceOption('first', 'first line', values: [1, 120]),
    // the controller's: scrollToLine, highlightLines, query
    const ChoiceOption(
      'goto',
      'to line $_goto',
      values: ['none', 'least', 'middle'],
      labels: ['none', 'least', '½'],
    ),
    const ChoiceOption(
      'lit',
      'highlight',
      values: ['none', '14', '13–16'],
    ),
    const SwitchOption('find', 'find'),
  ],
  build: (context, o) => _inRoom((rw, rh) {
    final theme = Theme.of(context);
    final w = math.min(o.number('width').toInt(), rw);
    final lang = o.choice<String>('lang');
    final view = _controlled(o)
        // a new State, and with it a controller asked anew, for each set
        // of options
        ? _CodeWithController(o, key: ValueKey(_codeKey(o)))
        : SingleChildScrollView(child: _codeViewOf(theme, o, lang, null));
    return SizedBox(
      width: w,
      height: _codeHeight(o, w, rh),
      child: Scrollbar(style: theme.border, child: view),
    );
  }),
  heightIn: (o, room) => _codeHeight(
    o,
    math.min(o.number('width').toInt(), room.width),
    room.height,
  ),
  codeIn: (o, room) {
    final (rw, rh) = _roomOf(room);
    final w = math.min(o.number('width').toInt(), rw);
    final lang = o.choice<String>('lang');
    final source = _sources[lang]!.split('\n');
    final h = _codeHeight(o, w, rh);
    final ctl = _controlled(o);
    // Go is indented with tabs: a string with \t in it, which CodeView
    // expands to the next multiple of tabWidth (4)
    final tabs = source.any((l) => l.contains('\t'));
    final src = tabs
        ? [
            "const _source = '''",
            for (final l in source)
              l
                  .replaceAll(r'\', r'\\')
                  .replaceAll(r'$', r'\$')
                  .replaceAll('\t', r'\t'),
            "''';",
          ]
        : ["const _source = r'''", ...source, "''';"];
    final past = _past(o);
    final args = [
      if (ctl) 'controller: _code',
      // plain text, the default: no language
      if (lang != 'plain') 'language: ${lang}Language',
      if (o.flag('numbers')) 'lineNumbers: true',
      if (past > 0) 'firstLineNumber: ${past + 1}',
      if (o.flag('signs')) 'signs: changes',
      if (o.label('wrap') != 'none') 'wrap: .${o.label('wrap')}',
    ];
    // the controller, asked before the view is laid out: what it asks is
    // made as the view is first laid out
    final asks = [
      if (o['goto'] == 'least') '  ..scrollToLine(${past + _goto})',
      if (o['goto'] == 'middle')
        '  ..scrollToLine(${past + _goto}, alignment: 0.5)',
      if (o['lit'] == '14') '  ..highlightLines([${past + 14}])',
      if (o['lit'] == '13–16') '  ..highlightRange(${past + 13}, ${past + 16})',
    ];
    final make =
        'CodeViewController('
        "${o.flag('find') ? "query: '${_queries[lang]}'" : ''})";
    final view = [
      '        child: CodeView(',
      '          _source,',
      for (final a in args) '          $a,',
      '        ),',
    ];
    return [
      ...src,
      '',
      if (ctl) ...[
        if (o.flag('find'))
          '// n and N go round what it finds while the view has the focus',
        if (asks.isEmpty)
          'final _code = $make;'
        else ...[
          'final _code = $make',
          ...asks.sublist(0, asks.length - 1),
          '${asks.last};',
        ],
        '',
        '@override',
        'void dispose() {',
        '  _code.dispose();',
        '  super.dispose();',
        '}',
        '',
      ],
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      if (o.flag('signs')) ...[
        '  // the lines changed since the last commit, by their numbers',
        '  final changes = {',
        for (final MapEntry(:key, :value) in _changed[lang]!.entries)
          _l([
            "    ${past + key}: CodeSign('$value', style: ",
            "${value == '+' ? 'theme.success' : 'theme.warning'}),",
          ]),
        '  };',
      ],
      '  return SizedBox(',
      '    width: $w,',
      '    height: $h,',
      '    child: Scrollbar(',
      '      style: theme.border,',
      if (ctl) ...[
        '      // with a controller it scrolls its lines itself',
        for (final l in view) l.substring(2),
      ] else ...[
        '      child: SingleChildScrollView(',
        ...view,
        '      ),',
      ],
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The line the CodeView page's controller scrolls to.
const _goto = 18;

/// What the CodeView page's controller finds in each language, in lower
/// case: smartcase ignores the case.
const _queries = {
  'dart': 'count',
  'python': 'task',
  'rust': 'word',
  'go': 'greet',
  'javascript': 'repos',
  'typescript': 'shape',
  'json': 'commits',
  'yaml': 'sdk',
  'bash': 'target',
  'diff': 'greet',
  'plain': 'release',
};

/// Whether the CodeView page's options give the view a controller.
bool _controlled(Options o) =>
    o['goto'] != 'none' || o['lit'] != 'none' || o.flag('find');

/// The options that make the CodeView page's controller, as a key.
String _codeKey(Options o) => [
  for (final k in const [
    'lang',
    'numbers',
    'first',
    'signs',
    'wrap',
    'width',
    'rows',
    'goto',
    'lit',
    'find',
  ])
    o.label(k),
].join('/');

/// The CodeView page's height: its rows, as far as the room and the rows
/// option let it be.
int _codeHeight(Options o, int w, int rh) {
  final rows = o.choice<int?>('rows');
  final h = math.min(_codeRowsIn(o, w), rh);
  return rows == null ? h : math.min(h, rows);
}

/// The CodeView page's view of [lang], given [controller].
CodeView _codeViewOf(
  ThemeData theme,
  Options o,
  String lang,
  CodeViewController? controller,
) => CodeView(
  _sources[lang]!,
  controller: controller,
  language: _languages[lang]!,
  lineNumbers: o.flag('numbers'),
  firstLineNumber: _past(o) + 1,
  signs: o.flag('signs')
      ? {
          for (final MapEntry(:key, :value) in _changed[lang]!.entries)
            _past(o) + key: CodeSign(
              value,
              style: value == '+' ? theme.success : theme.warning,
            ),
        }
      : null,
  wrap: TextWrap.values.byName(o.choice('wrap')),
);

/// The CodeView page's view with a controller, made and asked as the
/// options say.
final class _CodeWithController extends StatefulWidget {
  const _CodeWithController(this.o, {super.key});

  final Options o;

  @override
  State<_CodeWithController> createState() => _CodeWithControllerState();
}

final class _CodeWithControllerState extends State<_CodeWithController> {
  late final CodeViewController _code = () {
    final o = widget.o;
    final past = _past(o);
    final code = CodeViewController(
      query: o.flag('find') ? _queries[o.choice<String>('lang')]! : '',
    );
    switch (o['goto']) {
      case 'least':
        code.scrollToLine(past + _goto);
      case 'middle':
        code.scrollToLine(past + _goto, alignment: 0.5);
    }
    switch (o['lit']) {
      case '14':
        code.highlightLines([past + 14]);
      case '13–16':
        code.highlightRange(past + 13, past + 16);
    }
    return code;
  }();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _codeViewOf(
    Theme.of(context),
    widget.o,
    widget.o.choice<String>('lang'),
    _code,
  );
}

// ------------------------------------------------------------ SyntaxThemeScope

/// The source the SyntaxThemeScope page shows, a line each.
const _scoped = [
  '/// Says hello to the user, twice.',
  '@override',
  'Widget build(BuildContext context) {',
  "  final name = 'user', times = 2;",
  r"  return Text('Hello, $name! ' * times);",
  '}',
];

/// The theme of its own the SyntaxThemeScope page sets: the kinds it
/// leaves unset in the style of the text around them.
const _ownSyntax = SyntaxTheme(
  keyword: Style(attrs: Attr.bold),
  type: Style(attrs: Attr.bold),
  string: Style(attrs: Attr.italic),
  variable: Style(attrs: Attr.underline),
  comment: Style(attrs: Attr.dim),
);

final _syntaxThemeScope = GalleryPage(
  group: 'Rich',
  title: 'SyntaxThemeScope',
  options: const [
    ChoiceOption(
      'syntax',
      'syntax theme',
      values: ['copyWith', 'own', 'none'],
    ),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final view = CodeView('${_scoped.join('\n')}\n', language: dartLanguage);
    return switch (o.choice<String>('syntax')) {
      'copyWith' => SyntaxThemeScope(
        theme: SyntaxTheme.from(theme).copyWith(
          keyword: theme.error.merge(const Style(attrs: Attr.bold)),
          string: theme.warning,
          comment: theme.muted,
        ),
        child: view,
      ),
      'own' => SyntaxThemeScope(theme: _ownSyntax, child: view),
      _ => view,
    };
  },
  code: (o) {
    final source = ["const _source = r'''", ..._scoped, "''';", ''];
    return switch (o.choice<String>('syntax')) {
      'none' => [
        ...source,
        '// no scope above it: SyntaxTheme.of finds none and',
        '// derives the styles from the Theme',
        '@override',
        'Widget build(BuildContext context) =>',
        '    const CodeView(_source, language: dartLanguage);',
      ],
      'own' => [
        ...source,
        '// a theme of its own: the kinds it leaves unset are',
        '// drawn in the style of the text around them',
        'const _syntax = SyntaxTheme(',
        '  keyword: Style(attrs: Attr.bold),',
        '  type: Style(attrs: Attr.bold),',
        '  string: Style(attrs: Attr.italic),',
        '  variable: Style(attrs: Attr.underline),',
        '  comment: Style(attrs: Attr.dim),',
        ');',
        '',
        '@override',
        'Widget build(BuildContext context) => const SyntaxThemeScope(',
        '  theme: _syntax,',
        '  child: CodeView(_source, language: dartLanguage),',
        ');',
      ],
      _ => [
        ...source,
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  return SyntaxThemeScope(',
        '    // the theme derived from the Theme, three kinds',
        '    // of token changed',
        '    theme: SyntaxTheme.from(theme).copyWith(',
        '      keyword: theme.error.merge(const .new(attrs: Attr.bold)),',
        '      string: theme.warning,',
        '      comment: theme.muted,',
        '    ),',
        '    child: const CodeView(_source, language: dartLanguage),',
        '  );',
        '}',
      ],
    }.join('\n');
  },
);

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
  build: (context, o) => _inRoom((rw, rh) {
    final side = o.choice<String>('layout') == 'sideBySide';
    final plain = o.choice<String>('language') == 'plain';
    final w = math.min(rw, side ? 100 : 64);
    final h = _clamp(rh, 6, 22);
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
    return _Timed((context, ms, wake) {
      final k = ms ~/ _step;
      wake((k + 1) * _step);
      return view(_edited(k % (_edits.length + 4)));
    });
  }),
  heightIn: (o, room) => _clamp(room.height, 6, 22),
  codeIn: (o, room) {
    final (rw, rh) = _roomOf(room);
    final side = o.choice<String>('layout') == 'sideBySide';
    final w = math.min(rw, side ? 100 : 64);
    final h = _clamp(rh, 6, 22);
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
      _l([
        '      .fold(_before, (text, edit) => ',
        r'text.replaceFirst(edit.$1, edit.$2));',
      ]),
      ...view(between('after')),
      '}',
    ].join('\n');
  },
);

// ------------------------------------------------------------ BigText

const _fieldWidth = 30;

/// The BigText page's text of two lines, one wider than the other.
const _bigLines = 'twk\ngallery';

/// Whether the BigText page's text is of one line, which BigText is as wide
/// as: align then moves nothing.
bool _oneLine(Options o) => o.choice<String>('text') != 'lines';
const _maxLength = 24;

/// The page's state the field last kept its text in
/// (`PageControl.state`), for the Code: the text typed, kept while the
/// gallery runs.
Map<String, Object?>? _bigState;

String get _typed => _bigState?['text'] as String? ?? 'Hello';

/// The clock from 9:41 at [ms], a second a tick.
String _clockText(int ms) {
  final s = 9 * 3600 + 41 * 60 + ms ~/ 1000;
  String two(int n) => '$n'.padLeft(2, '0');
  return '${two(s ~/ 3600 % 24)}:${two(s ~/ 60 % 60)}:${two(s % 60)}';
}

/// The rows BigText and its field take in [room], as the design's size:
/// the text in the first font it fits in, in what the field leaves.
int _bigHeightIn(Options o, StageRoom room) {
  final name = o.choice<String>('font');
  // no field under it
  final clock = o.choice<String>('text') != 'typed';
  final big =
      RenderBigText(
        switch (o.choice<String>('text')) {
          'clock' => _clockText(0),
          'lines' => _bigLines,
          _ => _typed,
        },
        fonts: name == 'fit'
            ? BigFont.sizes
            : [BigFont.values.firstWhere((f) => f.name == name)],
      )..layout(
        BoxConstraints(
          0,
          room.width,
          0,
          clock ? room.height : math.max(0, room.height - 4),
        ),
      );
  return clock ? big.height : big.height + 4;
}

final _bigText = GalleryPage(
  group: 'Rich',
  title: 'BigText',
  options: const [
    ChoiceOption(
      'font',
      'font',
      values: ['fit', 'large', 'block', 'thin', 'small'],
    ),
    ChoiceOption(
      'text',
      'text',
      values: ['typed', 'clock', 'lines'],
      labels: ['typed', 'clock', 'two lines'],
    ),
    // each line across the widest: of a text of more than one
    ChoiceOption(
      'align',
      'align',
      values: ['left', 'center', 'right'],
      disabled: _oneLine,
    ),
    ColorOption(
      'color',
      'style',
      values: ['primary', 'accent', 'success', 'warning', 'info'],
      initial: 'primary',
    ),
  ],
  build: (context, o) {
    final name = o.choice<String>('font');
    final font = name == 'fit'
        ? null
        : BigFont.values.firstWhere((f) => f.name == name);
    final style = o.colorStyle(context, 'color');
    if (o.choice<String>('text') == 'lines') {
      return BigText(
        _bigLines,
        font: font,
        align: TextAlign.values.byName(o.choice('align')),
        style: style,
      );
    }
    if (o.choice<String>('text') == 'clock') {
      return _Timed((context, ms, wake) {
        wake((ms ~/ 1000 + 1) * 1000);
        return BigText(_clockText(ms), font: font, style: style);
      });
    }
    return _TypedBig(font: font, style: style);
  },
  heightIn: _bigHeightIn,
  code: (o) {
    final name = o.choice<String>('font');
    final font = name == 'fit' ? '' : ', font: BigFont.$name';
    final color = o.color('color');
    if (o.choice<String>('text') == 'lines') {
      final align = o.choice<String>('align');
      return [
        '@override',
        'Widget build(BuildContext context) => BigText(',
        "  '${_bigLines.replaceAll('\n', r'\n')}',",
        if (font.isNotEmpty) '  font: BigFont.$name,',
        if (align != 'left') '  align: .$align,',
        '  style: Theme.of(context).$color,',
        ');',
      ].join('\n');
    }
    if (o.choice<String>('text') == 'clock') {
      return [
        '// a clock from 9:41, a second a tick',
        'var _now = DateTime(2026, 10, 19, 9, 41);',
        'late final Timer _timer;',
        '',
        '@override',
        'void initState() {',
        '  super.initState();',
        '  _timer = Timer.periodic(',
        '    const Duration(seconds: 1),',
        _l([
          '    (_) => setState(() => _now = _now.add(const Duration(seconds: ',
          '1))),',
        ]),
        '  );',
        '}',
        '',
        '@override',
        'void dispose() {',
        '  _timer.cancel();',
        '  super.dispose();',
        '}',
        '',
        r"String _two(int n) => '$n'.padLeft(2, '0');",
        '',
        '@override',
        'Widget build(BuildContext context) => BigText(',
        r"  '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',",
        if (font.isNotEmpty) '  font: BigFont.$name,',
        '  style: Theme.of(context).$color,',
        ');',
      ].join('\n');
    }
    final text = _typed
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$');
    return [
      "final _controller = TextEditingController(text: '$text');",
      "final _focus = FocusNode(debugLabel: 'text');",
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _focus.addListener(() => setState(() {}));',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _controller.dispose();',
      '  _focus.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    gap: 1,',
      '    children: [',
      '      // what the field and the gap leave: the font that fits in it',
      _l([
        '      Flexible(child: BigText(_controller.text$font, ',
        'style: theme.$color)),',
      ]),
      '      SizedBox(',
      '        width: $_fieldWidth,',
      '        child: Box(',
      '          border: .all(',
      '            type: .rounded,',
      '            style: _focus.hasFocus ? theme.primary : theme.border,',
      '          ),',
      '          child: TextField(',
      '            controller: _controller,',
      '            focusNode: _focus,',
      "            placeholder: 'type here',",
      '            maxLength: $_maxLength,',
      '            onChanged: (_) => setState(() {}),',
      '          ),',
      '        ),',
      '      ),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// BigText of what is typed in the field under it, as the Code builds it.
final class _TypedBig extends StatefulWidget {
  const _TypedBig({required this.font, required this.style});

  final BigFont? font;
  final Style style;

  @override
  State<_TypedBig> createState() => _TypedBigState();
}

final class _TypedBigState extends State<_TypedBig> {
  late final Map<String, Object?> _state = PageControl.of(context).state;
  late final _controller = TextEditingController(
    text: _state['text'] as String? ?? 'Hello',
  );
  final _focus = FocusNode(debugLabel: 'text');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bigState = _state;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      gap: 1,
      children: [
        // what the field and the gap leave: the font that fits in it
        Flexible(
          child: BigText(
            _controller.text,
            font: widget.font,
            style: widget.style,
          ),
        ),
        PageHints(
          hints: const [('type', 'big text'), ('←→', 'move')],
          child: SizedBox(
            width: _fieldWidth,
            child: Box(
              border: Border.all(
                type: BorderType.rounded,
                style: _focus.hasFocus ? theme.primary : theme.border,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                placeholder: 'type here',
                maxLength: _maxLength,
                onChanged: (text) => setState(() => _state['text'] = text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ QrCode

/// The texts the QrCode page encodes, by the names its option gives them.
const _qrTexts = {
  'link': 'https://pub.dev/packages/twk',
  'wifi': 'WIFI:S:twk;T:WPA;P:secret;;',
  'digits': '20261019',
};

/// How many times the QrCode page has run [QrSymbol.encode]: its tests
/// count them.
var qrEncodes = 0;

/// The symbols the QrCode page has encoded, by text and level: its build
/// and its heightIn draw the same one, and a choice made again finds it.
final _qrSymbols = <(String, QrErrorCorrection), QrSymbol>{};

/// The symbol the QrCode page draws, with the options at [o].
QrSymbol _qrSymbolOf(Options o) {
  final text = _qrTexts[o.choice<String>('text')]!;
  final level = QrErrorCorrection.values.byName(o.choice('level'));
  return _qrSymbols[(text, level)] ??= () {
    qrEncodes++;
    return QrSymbol.encode(text, level: level);
  }();
}

/// The quiet zone the QrCode page gives [symbol] in [rows]: the option's
/// [quiet] modules, fewer where the symbol with them would be taller, so
/// that the whole symbol shows (as its Code's LayoutBuilder works it out).
int _qrQuietIn(QrSymbol symbol, int quiet, int rows) =>
    ((2 * rows - symbol.size) ~/ 2).clamp(0, quiet);

/// The rows of [symbol] without a quiet zone.
int _qrLeast(QrSymbol symbol) => (symbol.size + 1) ~/ 2;

final _qrCode = GalleryPage(
  group: 'Rich',
  title: 'QrCode',
  options: [
    // the smallest symbol first: version 1, which a screen of 24 rows
    // shows whole
    const ChoiceOption(
      'text',
      'text',
      values: ['link', 'wifi', 'digits'],
      initial: 'digits',
    ),
    const ChoiceOption(
      'level',
      'level',
      values: ['low', 'medium', 'quartile', 'high'],
      initial: 'medium',
    ),
    SliderOption(
      'quiet',
      'quiet zone',
      min: 0,
      max: 4,
      initial: 4,
      format: (v) => '$v modules',
    ),
    // light modules on dark: what fewer scanners read
    const SwitchOption('invert', 'inverted'),
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final symbol = _qrSymbolOf(o);
    final quiet = o.number('quiet').toInt();
    final invert = o.flag('invert');
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 2,
        children: [
          QrCode.symbol(
            symbol,
            quietZone: _qrQuietIn(symbol, quiet, constraints.maxH),
            dark: invert ? QrCode.white : QrCode.black,
            light: invert ? QrCode.black : QrCode.white,
          ),
          Text.rich([
            Span('version ', theme.muted),
            Span('${symbol.version}\n'),
            Span('mask ', theme.muted),
            Span('${symbol.mask}\n'),
            Span('mode ', theme.muted),
            Span(symbol.mode.name),
            // taller than the room even without a quiet zone, so cut off
            // at its bottom: the rows it needs
            if (_qrLeast(symbol) > constraints.maxH) ...[
              Span('\n\nneeds ', theme.warning),
              Span('${_qrLeast(symbol)} rows'),
            ],
          ]),
        ],
      ),
    );
  },
  // all of it asked for, as the design's size: the code's rows, its quiet
  // zone narrowed to the room, the three lines beside it; a symbol taller
  // than the room even without one is cut off at its bottom
  heightIn: (o, room) {
    final symbol = _qrSymbolOf(o);
    final quiet = _qrQuietIn(symbol, o.number('quiet').toInt(), room.height);
    return math.max((symbol.size + 2 * quiet + 1) ~/ 2, 3);
  },
  code: (o) {
    final text = _qrTexts[o.choice<String>('text')];
    final level = o.choice<String>('level');
    final quiet = o.number('quiet').toInt();
    final one = "  final symbol = QrSymbol.encode('$text', level: .$level);";
    // the quiet zone that leaves the symbol whole in the rows there are
    final zone = quiet == 0
        ? '0'
        : '((2 * constraints.maxH - symbol.size) ~/ 2).clamp(0, $quiet)';
    return [
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  // the mode of fewest bits, the smallest version, the',
      '  // mask the penalty rules score lowest',
      if (one.length <= 80)
        one
      else ...[
        '  final symbol = QrSymbol.encode(',
        "    '$text',",
        '    level: .$level,',
        '  );',
      ],
      '  return LayoutBuilder(',
      '    builder: (context, constraints) => Row(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .start,',
      '      gap: 2,',
      '      children: [',
      if (o.flag('invert'))
        '        // in half blocks, white on black; in fewer rows than it'
      else
        '        // in half blocks, black on white; in fewer rows than it',
      '        // asks for, a narrower quiet zone, the whole symbol shown',
      '        QrCode.symbol(',
      '          symbol,',
      '          quietZone: $zone,',
      if (o.flag('invert')) ...[
        '          dark: QrCode.white,',
        '          light: QrCode.black,',
      ],
      '        ),',
      '        Text.rich([',
      "          Span('version ', theme.muted),",
      r"          Span('${symbol.version}\n'),",
      "          Span('mask ', theme.muted),",
      r"          Span('${symbol.mask}\n'),",
      "          Span('mode ', theme.muted),",
      '          Span(symbol.mode.name),',
      '          // taller than the rows there are even without a quiet',
      "          // zone: cut off at its bottom, which a camera can't read",
      '          if ((symbol.size + 1) ~/ 2 > constraints.maxH) ...[',
      r"            Span('\n\nneeds ', theme.warning),",
      r"            Span('${(symbol.size + 1) ~/ 2} rows'),",
      '          ],',
      '        ]),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

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
  build: (context, o) => _inRoom((rw, rh) {
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
    return _Timed((context, ms, wake) {
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
    final (rw, _) = _roomOf(room);
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
      _l([
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
        _l([
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
      _l([
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
      _l([
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
      _l([
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

/// The MarkdownView page's document whose links the app opens: one to a
/// heading scrolls to it by the controller; what was tapped under it.
final class _AppLinks extends StatefulWidget {
  const _AppLinks({required this.codeWrap, required this.hyperlinks});

  final TextWrap codeWrap;
  final bool hyperlinks;

  @override
  State<_AppLinks> createState() => _AppLinksState();
}

final class _AppLinksState extends State<_AppLinks> {
  final _md = MarkdownController();
  String? _tapped;
  var _serial = 0;

  @override
  void dispose() {
    _md.dispose();
    super.dispose();
  }

  void _tap(String destination, String? title) {
    setState(() {
      _tapped = destination;
      _serial++;
    });
    _md.scrollToHeading(destination);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    gap: 1,
    children: [
      Expanded(
        child: Scrollbar(
          style: Theme.of(context).border,
          child: SingleChildScrollView(
            child: MarkdownView(
              _doc,
              controller: _md,
              onLinkTap: _tap,
              codeWrap: widget.codeWrap,
              hyperlinks: widget.hyperlinks,
            ),
          ),
        ),
      ),
      LitLine([
        ('tapped: ', true),
        (_tapped ?? 'nothing', _tapped == null),
      ], serial: _serial),
    ],
  );
}

// ------------------------------------------------------------ the texts

const _doc = '''
# Release notes

**twk_rich** puts *rich text* in the terminal: Markdown, code and diffs, each a widget.

Jump to [what is new](#what-is-new) or [still to come](#still-to-come).

## What is new

- `MarkdownView` streams an answer in
- `CodeView` highlights ten languages
  - Dart, Rust, Go and Python
  - JSON, YAML and Bash
- `DiffView` marks the words that changed

1. Add the package:
2. Import `package:twk_rich/twk_rich.dart`
3. Show a document

```bash
dart pub add twk_rich
```

```dart
final notes = await File('NOTES.md').readAsString();
runApp(SingleChildScrollView(
  child: MarkdownView(notes),
));
```

> Every block is a widget: this quote, the lists above and the table below.

| widget       | shows       | scrolls |
|:-------------|:------------|:-------:|
| MarkdownView | documents   |   no    |
| CodeView     | source code |   no    |
| DiffView     | changes     |   yes   |

### Still to come

- [x] tables and task lists
- [ ] ~~images~~ pictures in cells

Read the [guide](https://dart.dev/tools) for more.

---''';

const _question = 'How do I read a file in Dart?';

const _answer = r'''
To read a file, use `File` from `dart:io`:

```dart
import 'dart:io';

Future<void> main() async {
  final text = await File('notes.txt').readAsString();
  print(text.split('\n').length);
}
```

For a **large** file, read it as a stream of lines instead:

- `openRead()` gives its bytes in chunks;
- `utf8.decoder` and `LineSplitter` make lines of them.

| method         | gives          |
|----------------|----------------|
| `readAsString` | the whole text |
| `openRead`     | bytes, a chunk at a time |

> Both throw a `FileSystemException` where the file is missing.''';

const _dartSource = r'''
import 'package:twk/twk.dart';

/// Counts the presses of the space bar.
final class Counter extends StatefulWidget {
  const Counter({super.key, this.start = 0});

  final int start;

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  late var _count = widget.start;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'space': () => setState(() => _count++)},
    child: Text('Pressed $_count times, ${_count.isEven ? 'even' : 'odd'}'),
  );
}''';

const _pythonSource = '''
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Task:
    """A task on the board, and who it waits on."""
    title: str
    done: bool = False
    owners: list[str] = field(default_factory=list)


def summary(tasks: list[Task]) -> str:
    waiting = [t for t in tasks if not t.done]
    names = sorted({o for t in waiting for o in t.owners})
    return f"{len(waiting)} open of {len(tasks)}, waiting on {', '.join(names) or 'nobody'}"


if __name__ == "__main__":
    print(summary([Task("Ship it", owners=["user"]), Task("Docs", True)]))''';

const _rustSource = '''
use std::collections::HashMap;

/// The words of a text by how often they come, the most first.
fn word_counts(text: &str) -> Vec<(&str, usize)> {
    let mut counts: HashMap<&str, usize> = HashMap::new();
    for word in text.split_whitespace() {
        *counts.entry(word).or_insert(0) += 1;
    }
    let mut pairs: Vec<_> = counts.into_iter().collect();
    pairs.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    pairs
}

fn main() {
    let text = "the cat and the hat and the bat";
    for (word, n) in word_counts(text).iter().take(3) {
        println!("{word:>5} {n}");
    }
}''';

const _goSource = '''
package main

import (
\t"fmt"
\t"strings"
)

// Greeter greets places by name, in a language of its own.
type Greeter struct {
\tHello string
}

func (g Greeter) Greet(names ...string) string {
\treturn fmt.Sprintf("%s, %s!", g.Hello, strings.Join(names, " and "))
}

func main() {
\tg := Greeter{Hello: "Привіт"}
\tfmt.Println(g.Greet("Kyiv", "Lviv"))
}''';

const _javascriptSource = r'''
// The most starred repositories of a user, the forks left out.
const API = "https://api.github.com";

async function topRepos(user, count = 3) {
  const res = await fetch(`${API}/users/${user}/repos`);
  if (!res.ok) {
    throw new Error(`GitHub said ${res.status}`);
  }
  const repos = await res.json();
  return repos
    .filter((r) => !r.fork)
    .sort((a, b) => b.stargazers_count - a.stargazers_count)
    .slice(0, count)
    .map(({ name, stargazers_count: stars }) => ({ name, stars }));
}

const user = process.argv[2] ?? "dart-lang";
for (const { name, stars } of await topRepos(user)) {
  console.log(`${name.padEnd(24)} ★ ${stars}`);
}''';

const _typescriptSource = r'''
/** A shape, by its kind. */
type Shape =
  | { kind: "circle"; radius: number }
  | { kind: "rect"; width: number; height: number };

interface Labeled<T> {
  readonly label: string;
  value: T;
}

function area(shape: Shape): number {
  switch (shape.kind) {
    case "circle":
      return Math.PI * shape.radius ** 2;
    case "rect":
      return shape.width * shape.height;
  }
}

const shapes: Labeled<Shape>[] = [
  { label: "plate", value: { kind: "circle", radius: 12 } },
  { label: "door", value: { kind: "rect", width: 90, height: 200 } },
];
export const areas = shapes.map(({ label, value }) => `${label}: ${area(value).toFixed(1)}`);''';

const _jsonSource = '''
{
  "name": "twk-gallery",
  "version": "0.4.0",
  "private": true,
  "description": "Every widget of twk, live, with the Dart that builds it",
  "keywords": ["terminal", "tui", "dart"],
  "scripts": {
    "start": "dart run bin/gallery.dart",
    "test": "dart test",
    "golden": "TWK_UPDATE_GOLDENS=1 dart test test/goldens_test.dart"
  },
  "engines": { "dart": ">=3.10.0" },
  "contributors": [
    { "name": "user", "email": "user@example.com", "commits": 1412 },
    { "name": "bot", "email": null, "commits": 87 }
  ],
  "ratio": 0.9425,
  "stable": false,
  "pages": 141
}''';

const _yamlSource = r'''
# The checks, as CI runs them on each push.
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        sdk: [stable, beta]
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: ${{ matrix.sdk }}
      - run: dart pub get
      - run: dart analyze --fatal-infos
      - name: Tests
        run: dart test --reporter expanded
        timeout-minutes: 15
        continue-on-error: false''';

const _bashSource = r'''
#!/usr/bin/env bash
# Builds the gallery for each platform, and says how big each came out.
set -euo pipefail

readonly out="${OUT_DIR:-build}"
targets=(linux-x64 linux-arm64 macos-arm64)

mkdir -p "$out"
for target in "${targets[@]}"; do
  echo "building for $target…"
  if ! dart compile exe bin/gallery.dart \
      --target-os "${target%%-*}" -o "$out/gallery-$target"; then
    echo "failed: $target" >&2
    exit 1
  fi
done

# the sizes, the largest first
du -h "$out"/gallery-* | sort -rh | while read -r size file; do
  printf '%-28s %s\n' "$(basename "$file")" "$size"
done
echo "done in ${SECONDS}s"''';

const _diffSource = r'''
diff --git a/bin/greet.dart b/bin/greet.dart
index 3b18e51..a9c0d2f 100644
--- a/bin/greet.dart
+++ b/bin/greet.dart
@@ -3,4 +3,5 @@ import 'dart:io';
 /// Greets [name] on the terminal.
-String greet(String name) {
-  return 'Hello, ' + name + '!';
+String greet(String name, {String language = 'en'}) {
+  final hello = {'en': 'Hello', 'uk': 'Привіт'}[language];
+  return '$hello, $name!';
 }
@@ -17,7 +18,8 @@ List<String> readNames(String path) {
 void main(List<String> args) {
   final names = readNames(args.first);
+  final language = args.length > 1 ? args[1] : 'en';
   for (final name in names) {
-    print(greet(name));
+    print(greet(name, language: language));
   }
   print('Greeted ${names.length} names.');
 }''';

const _plainSource = '''
Release checklist

Before the tag
  1. Every package's tests pass on stable and beta.
  2. The goldens match: no file under test/goldens changed.
  3. The benchmark is no slower than the last release's.
  4. CHANGELOG.md says what changed, in the words a user reads.

The tag
  Bump the version in each pubspec.yaml, the same in all of them,
  commit "Release 0.4.0", and tag it v0.4.0.

After it
  - Publish the packages in order: twk_core first, then twk, then
    the rest, each after the one it depends on.
  - Announce it where the users are.
  - Open the milestone of the next one.

Owners: the release is cut by whoever merged last; nobody waits on
anybody else to start it.''';

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

// ------------------------------------------------------------ JsonView

/// What the JsonView page shows: a package's description.
const Map<String, Object?> _package = {
  'name': 'twk',
  'version': '0.1.0',
  'description': 'Widgets for terminal apps, laid out as Flutter lays them',
  'private': true,
  'score': 0.97,
  'homepage': null,
  'environment': {'sdk': '^3.13.5'},
  'dependencies': {'args': '^2.7.0', 'meta': '^1.16.0', 'path': '^1.9.1'},
  'scripts': ['quick', 'handover', 'bench'],
};

/// [value] as the Code writes it in a const map, [indent] blanks in.
List<String> _dartOf(Object? value, int indent) {
  final pad = ' ' * indent;
  String scalar(Object? v) => switch (v) {
    final String s => "'$s'",
    _ => '$v',
  };
  final one = switch (value) {
    final Map<String, Object?> m =>
      '{${m.entries.map((e) => "'${e.key}': ${scalar(e.value)}").join(', ')}}',
    final List<Object?> l => '[${l.map(scalar).join(', ')}]',
    _ => scalar(value),
  };
  return ['$pad$one'];
}

const _jsonW = 50;

/// The rows of the view in a room [room] rows high: 14, or those it has
/// but the two of the line under it, 2 at least.
int _jsonRows(int room) => math.max(2, math.min(14, room - 2));

final _jsonView = GalleryPage(
  group: 'Rich',
  title: 'JsonView',
  options: const [
    ChoiceOption('depth', 'expanded depth', values: [1, 2, 0]),
    SwitchOption('sort', 'sort keys'),
    ChoiceOption(
      'cut',
      'strings cut at',
      values: [200, 24],
      labels: ['200', '24'],
    ),
  ],
  build: (context, o) => _inRoom(
    (w, h) => _Json(
      height: _jsonRows(h),
      depth: o.choice('depth'),
      sortKeys: o.flag('sort'),
      cut: o.choice('cut'),
    ),
  ),
  // the view, and the line under it
  heightIn: (o, room) => _jsonRows(room.height) + 2,
  codeIn: (o, room) {
    final depth = o.choice<int>('depth');
    final (_, h) = _roomOf(room);
    return [
      'static const _package = {',
      for (final MapEntry(:key, :value) in _package.entries)
        ..._dartOf(value, 0).map((v) => "  '$key': $v,"),
      '};',
      '',
      if (depth == 1)
        'final _view = JsonViewController();'
      else
        'final _view = JsonViewController(expandedDepth: $depth);',
      "var _copied = '';",
      '',
      '@override',
      'void dispose() {',
      '  _view.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SizedBox(',
      '        width: $_jsonW,',
      '        height: ${_jsonRows(h)},',
      '        child: JsonView(',
      '          value: _package,',
      '          controller: _view,',
      if (o.flag('sort')) '          sortKeys: true,',
      if (o.choice<int>('cut') != 200)
        '          maxStringLength: ${o.choice<int>('cut')},',
      '          onPathCopied: (path) => setState(() => _copied = path),',
      '        ),',
      '      ),',
      '      Text.rich([',
      "        Span('copied: ', theme.muted),",
      '        if (_copied.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      '          Span(_copied),',
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The package in a JsonView [height] rows tall, and the path copied
/// last.
final class _Json extends StatefulWidget {
  const _Json({
    required this.height,
    required this.depth,
    required this.sortKeys,
    required this.cut,
  });

  final int height;
  final int depth;
  final bool sortKeys;
  final int cut;

  @override
  State<_Json> createState() => _JsonState();
}

final class _JsonState extends State<_Json> {
  late final Map<String, Object?> _kept = PageControl.of(context).state;

  String get _copied => _kept['copied'] as String? ?? '';
  int get _serial => _kept['serial'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    // kept while the gallery runs, one for each depth
    final view =
        (_kept['view:${widget.depth}'] ??= JsonViewController(
              expandedDepth: widget.depth,
            ))
            as JsonViewController;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: _jsonW,
          height: widget.height,
          child: JsonView(
            key: ValueKey(widget.depth),
            value: _package,
            controller: view,
            sortKeys: widget.sortKeys,
            maxStringLength: widget.cut,
            onPathCopied: (path) => setState(() {
              _kept['copied'] = path;
              _kept['serial'] = _serial + 1;
            }),
          ),
        ),
        LitLine([
          ('copied: ', true),
          if (_copied.isEmpty) ('nothing', true) else (_copied, false),
        ], serial: _serial),
      ],
    );
  }
}
