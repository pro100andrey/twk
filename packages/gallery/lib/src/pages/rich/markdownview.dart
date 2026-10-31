// The MarkdownView page.
part of 'rich.dart';

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

/// The MarkdownView page's `content` option.
const _markdownViewContent = ChoiceOption<String>(
  'content',
  'content',
  values: ['document', 'answer'],
  labels: ['document', 'chat answer'],
);

/// The MarkdownView page's `codeWrap` option.
const _markdownViewCodeWrap = ChoiceOption<String>(
  'codeWrap',
  'code wrap',
  values: ['grapheme', 'word', 'none'],
);

/// The MarkdownView page's `width` option.
final _markdownViewWidth = SliderOption(
  'width',
  'width',
  min: 30,
  max: 72,
  initial: 50,
  format: (v) => '$v cells',
);

/// The MarkdownView page's `links` option.
final _markdownViewLinks = ChoiceOption<String>(
  'links',
  'links go to',
  values: const ['terminal', 'app', 'app only'],
  labels: const ['the terminal', 'the app', 'the app only'],
  disabled: (o) => o(_markdownViewContent) != 'document',
);

final _markdownView = GalleryPage(
  group: _group,
  title: 'MarkdownView',
  options: [
    _markdownViewContent,
    _markdownViewCodeWrap,
    _markdownViewWidth,
    // onLinkTap: the app's own links, a heading's scrolled to by the
    // MarkdownController; the app's only, hyperlinks: false, no OSC 8 for
    // the terminal to open
    _markdownViewLinks,
  ],
  build: (context, o) => inRoom((rw, rh) {
    final theme = Theme.of(context);
    final w = math.min(o(_markdownViewWidth).toInt(), rw);
    final h = clampTo(rh, 6, 24);
    final wrap = TextWrap.values.byName(o(_markdownViewCodeWrap));
    if (o(_markdownViewContent) == 'document' &&
        o(_markdownViewLinks) != 'terminal') {
      return SizedBox(
        width: w,
        height: h,
        child: _AppLinks(
          codeWrap: wrap,
          hyperlinks: o(_markdownViewLinks) == 'app',
        ),
      );
    }
    if (o(_markdownViewContent) == 'document') {
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
    return Timed((context, ms, wake) {
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
  heightIn: (o, room) => clampTo(room.height, 6, 24),
  codeIn: (o, room) {
    final (rw, rh) = codeRoomOf(room);
    final w = math.min(o(_markdownViewWidth).toInt(), rw);
    final h = clampTo(rh, 6, 24);
    final codeWrap = o.nameOf(_markdownViewCodeWrap);
    final wrap = codeWrap == 'grapheme' ? '' : ', codeWrap: .$codeWrap';
    if (o(_markdownViewContent) == 'document' &&
        o(_markdownViewLinks) != 'terminal') {
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
        if (o(_markdownViewLinks) == 'app only')
          '              hyperlinks: false,',
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
    if (o(_markdownViewContent) == 'document') {
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
      codeLine([
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
      codeLine([
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
      codeLine([
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
