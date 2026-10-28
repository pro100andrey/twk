// An answer that streams in, shown by an app in the inline mode as a chat
// shows it: the blocks of it that settle go to the terminal's history, in
// order, while the rest is live in the region above the prompt; in the
// fullscreen mode the same app shows the answer as MarkdownView does.
import 'dart:async';
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

/// An answer of a block of each common kind, taller than the terminal.
const answer = r'''
# Reading a file

Use `File` from `dart:io` and read the whole of it at once.

```dart
final text =
    await File('a.txt')
        .readAsString();
```

For a large file:

- open it with `openRead`;
- decode the bytes;
- split the lines.

> Lines end in `\n` here.

That is all.
''';

/// What the history shows of [answer] at 30 columns, a blank row above
/// each block.
const shown = [
  '',
  'Reading a file',
  '',
  'Use File from dart:io and read',
  'the whole of it at once.',
  '',
  ' final text =',
  "     await File('a.txt')",
  '         .readAsString();',
  '',
  'For a large file:',
  '',
  '• open it with openRead;',
  '• decode the bytes;',
  '• split the lines.',
  '',
  r'│ Lines end in \n here.',
  '',
  'That is all.',
];

/// Of each block of [answer], the end of its rows in [shown].
const ends = [2, 5, 9, 11, 15, 17, 19];

void main() {
  testTwk('an answer taller than the terminal: each block goes to the '
      'history as it settles, in order, the rest live above the prompt', (
    t,
  ) async {
    final pieces = StreamController<String>();
    await t.pumpWidget(
      Answer(pieces.stream),
      mode: ScreenMode.inline,
      size: (30, 8),
      history: [r'$ ask'],
    );
    // pieces of 7 characters, and one that ends within the code block
    final code = answer.indexOf('        .readAsString');
    final cuts = {
      for (var at = 7; at < answer.length; at += 7) at,
      code,
      answer.length,
    }.toList()..sort();
    final settled = MarkdownStream();
    var at = 0;
    for (final cut in cuts) {
      final piece = answer.substring(at, cut);
      at = cut;
      pieces.add(piece);
      settled.add(piece);
      await t.pump();
      final rows = [...t.scrollback, ...t.lines];
      while (rows.last.isEmpty) {
        rows.removeLast();
      }
      final history = settled.settled == 0 ? 0 : ends[settled.settled - 1];
      final region = t.binding.twkApp.screen.height;
      final reason = 'after $at characters';
      // the history: the blocks settled, each once, in order
      expect(rows.length - region, 1 + history, reason: reason);
      expect(rows.take(1 + history), [
        r'$ ask',
        ...shown.take(history),
      ], reason: reason);
      // the region: a blank row, the blocks not settled, the prompt
      expect(rows.last, '> prompt', reason: reason);
      final live = rows.sublist(1 + history, rows.length - 1);
      expect(live.first, '', reason: reason);
      if (at == code) {
        expect(live, ['', ' final text =', "     await File('a.txt')"]);
        expect(t.scrollback, [r'$ ask', '']);
      }
    }
    expect(t.scrollback, hasLength(greaterThan(10)));
    await pieces.close();
    await t.pump();
    expect(
      [...t.scrollback, ...t.lines],
      [
        r'$ ask',
        ...shown,
        '',
        '> prompt',
      ],
    );
  });

  testTwk('a block is built once for the history; the live view updates no '
      'more elements than a MarkdownView of the answer does', (t) async {
    final pieces = [
      for (var at = 0; at < answer.length; at += 7)
        answer.substring(at, math.min(at + 7, answer.length)),
    ];
    final text = StringBuffer();
    var viewUpdates = 0;
    var before = <Element, Widget>{};
    for (final piece in pieces) {
      text.write(piece);
      await t.pumpWidget(
        MarkdownView('$text'),
        mode: ScreenMode.inline,
        size: (30, 30),
      );
      final after = elementsOf(find.byType(MarkdownView).evaluate().single);
      viewUpdates += updated(before, after);
      before = after;
    }

    final stream = StreamController<String>();
    final built = <MdBlock>[];
    await t.pumpWidget(Answer(stream.stream, built: built.add));
    var liveUpdates = 0;
    before = {};
    for (final piece in pieces) {
      stream.add(piece);
      await t.pump();
      final after = elementsOf(find.byType(MarkdownView).evaluate().single);
      liveUpdates += updated(before, after);
      before = after;
    }
    await stream.close();
    await t.pump();
    printOnFailure(
      'MarkdownView: $viewUpdates elements updated; the live view: '
      '$liveUpdates',
    );
    expect(built, parseMarkdown(answer));
    expect(liveUpdates, lessThanOrEqualTo(viewUpdates));
  });

  testTwk('a reference whose definition settled before its block is a link '
      'in the history; one defined later shows its text there', (t) async {
    final pieces = StreamController<String>();
    await t.pumpWidget(
      Answer(pieces.stream),
      mode: ScreenMode.inline,
      size: (30, 6),
    );
    pieces.add('[a]: https://a.dev\n\nSee [a] and [b].\n\nMore');
    await t.pump();
    final rows = t.lines;
    expect(rows.take(3), ['', 'See a and [b].', '']);
    expect(t.cell(4, 1).link, 'https://a.dev');
    expect(t.cell(10, 1).link, isNull);
    pieces.add('.\n\n[b]: https://b.dev\n');
    await pieces.close();
    await t.pump();
    expect(t.lines.take(5), ['', 'See a and [b].', '', 'More.', '']);
    expect(t.cell(11, 1).link, isNull);
  });

  testTwk('in the fullscreen mode the answer shows in place as a '
      'MarkdownView shows it, a blank row above it', (t) async {
    await t.pumpWidget(const MarkdownView(answer), size: (30, 24));
    final view = t.lines.take(shown.length - 1).toList();
    final pieces = StreamController<String>();
    await t.pumpWidget(Answer(pieces.stream));
    for (var at = 0; at < answer.length; at += 7) {
      pieces.add(answer.substring(at, math.min(at + 7, answer.length)));
      await t.pump();
    }
    await pieces.close();
    await t.pump();
    expect(t.lines.take(shown.length), ['', ...view]);
    expect(t.lines.take(shown.length), shown);
  });
}

/// The elements under [root], [root] too, with the widget of each.
Map<Element, Widget> elementsOf(Element root) {
  final elements = <Element, Widget>{};
  void visit(Element element) {
    elements[element] = element.widget;
    element.visitChildren(visit);
  }

  visit(root);
  return elements;
}

/// How many elements of [after] are new or have another widget than in
/// [before].
int updated(Map<Element, Widget> before, Map<Element, Widget> after) => [
  for (final MapEntry(key: element, value: widget) in after.entries)
    if (!identical(before[element], widget)) element,
].length;

/// An agent's answer as it streams in, [pieces], as an app in the inline
/// mode shows it: the blocks of it that settle go to the terminal's
/// history, the rest is live in the region, above the prompt. Each block
/// built for the history goes to [built].
final class Answer extends StatefulWidget {
  const Answer(this.pieces, {this.built, super.key});

  final Stream<String> pieces;

  final void Function(MdBlock block)? built;

  @override
  State<Answer> createState() => _AnswerState();
}

final class _AnswerState extends State<Answer> {
  final _answer = MarkdownStream();

  /// What the history shows, oldest first.
  final _history = <MdBlock>[];

  late final StreamSubscription<String> _pieces;

  @override
  void initState() {
    super.initState();
    _pieces = widget.pieces.listen(
      (piece) => _update(() => _answer.add(piece)),
      onDone: () => _update(_answer.close),
    );
  }

  @override
  void dispose() {
    unawaited(_pieces.cancel());
    super.dispose();
  }

  void _update(void Function() change) => setState(() {
    change();
    final settled = _answer.takeSettled();
    if (settled.isNotEmpty) {
      _history.addAll(settled);
      // the region gives back the rows they took in it
      AppBinding.of(context).twkApp.shrinkRegion();
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Static(
        items: _history,
        builder: (_, block) {
          widget.built?.call(block);
          return _spaced(MarkdownView.blocks([block]));
        },
      ),
      _spaced(
        MarkdownView.blocks(_answer.live, definitions: _answer.definitions),
      ),
      const Text('> prompt'),
    ],
  );

  /// [child] with a blank row above, as the blocks of a view are apart.
  static Widget _spaced(Widget child) =>
      Padding(padding: const EdgeInsets.only(top: 1), child: child);
}
