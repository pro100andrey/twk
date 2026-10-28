// Description lists: the terms of each group in a column of their own, a
// long value wrapped under its column, a term too long cut off with `…`,
// each value under its term at a narrow width, widgets as values, what a
// screen reader reads and what a selection copies.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// What a screen reader reads of the app [t] runs.
List<String> read(TwkTester t) => t.binding.semantics.lines;

final _server = [
  DescriptionItem.text('Status', 'Running'),
  DescriptionItem.text('IP Address', '192.168.1.42'),
  const DescriptionItem.group('Limits'),
  DescriptionItem.text('CPU', '2'),
  DescriptionItem.text('Memory', '4 GB'),
];

void main() {
  testTwk('aligns the values of each group after its longest term, a '
      'blank row and the heading between groups', (t) async {
    await t.pumpWidget(
      Theme.terminal(child: DescriptionList(items: _server)),
      size: (40, 7),
    );
    expect(t.lines, [
      'Status:     Running',
      'IP Address: 192.168.1.42',
      '',
      'Limits',
      'CPU:    2',
      'Memory: 4 GB',
      '',
    ]);
    // the terms muted, the values in the text's style, the heading bold
    expect(t, styleAt(0, 0, hasFg(const Color.indexed(245))));
    expect(t, isNot(styleAt(12, 0, hasFg(const Color.indexed(245)))));
    expect(t, styleAt(0, 3, hasAttr(Attr.bold)));
  });

  testTwk('puts the terms on the right of their column, after the separator '
      'given and the gap given', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: DescriptionList(
          items: _server,
          termAlign: TextAlign.right,
          separator: '',
          gap: 3,
        ),
      ),
      size: (40, 6),
    );
    expect(t.lines, [
      '    Status   Running',
      'IP Address   192.168.1.42',
      '',
      'Limits',
      '   CPU   2',
      'Memory   4 GB',
    ]);
  });

  testTwk('a term column of the width given, for every group', (t) async {
    await t.pumpWidget(
      Theme.terminal(child: DescriptionList(items: _server, termWidth: 9)),
      size: (40, 6),
    );
    expect(t.lines, [
      'Status:   Running',
      'IP Addre… 192.168.1.42',
      '',
      'Limits',
      'CPU:      2',
      'Memory:   4 GB',
    ]);
  });

  testTwk('wraps a long value under its own column', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: DescriptionList(
          items: [
            DescriptionItem.text('Name', 'web'),
            DescriptionItem.text(
              'Note',
              'the quick brown fox jumps over the lazy dog',
            ),
            DescriptionItem.text('Port', '80'),
          ],
        ),
      ),
      size: (30, 4),
    );
    expect(t.lines, [
      'Name: web',
      'Note: the quick brown fox',
      '      jumps over the lazy dog',
      'Port: 80',
    ]);
  });

  testTwk('cuts off a term longer than its share of the width with `…`, '
      'the column at that share', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: DescriptionList(
          items: [
            DescriptionItem.text('Memory Usage Statistics', '342 MB'),
            DescriptionItem.text('IP', '10.0.0.1'),
          ],
        ),
      ),
      size: (30, 2),
    );
    // 0.4 of 30 columns: 12
    expect(t.lines, ['Memory Usag… 342 MB', 'IP:${' ' * 10}10.0.0.1']);
    await t.pumpWidget(
      Theme.terminal(
        child: DescriptionList(
          maxTermFraction: 0.5,
          items: [
            DescriptionItem.text('Memory Usage Statistics', '342 MB'),
            DescriptionItem.text('IP', '10.0.0.1'),
          ],
        ),
      ),
      size: (30, 2),
    );
    expect(t.lines, ['Memory Usage S… 342 MB', 'IP:${' ' * 13}10.0.0.1']);
  });

  testTwk('below the width it stacks at, each value goes under its term, '
      'indented, and back beside it once it is wide enough', (t) async {
    await t.pumpWidget(
      Theme.terminal(child: DescriptionList(items: _server)),
      size: (20, 9),
    );
    expect(t.lines, [
      'Status:',
      '  Running',
      'IP Address:',
      '  192.168.1.42',
      '',
      'Limits',
      'CPU:',
      '  2',
      'Memory:',
    ]);
    await t.pumpWidget(
      Theme.terminal(
        child: DescriptionList(items: _server, stackBelowWidth: 20),
      ),
      size: (20, 6),
    );
    // 0.4 of 20 columns: a column of 8
    expect(t.lines.first, 'Status:  Running');
  });

  testTwk('a widget value is laid out in the room its column has: a badge, '
      'a bar as wide as the column, rich text', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: DescriptionList(
          items: [
            const DescriptionItem(
              'Health',
              Badge('ok', kind: StatusKind.success),
              semanticsValue: 'ok',
            ),
            const DescriptionItem('Load', ProgressBar(value: 0.5)),
            DescriptionItem(
              'Disk',
              Text.rich(['12 GB'.bold, const Span(' of 64 GB')]),
            ),
          ],
        ),
      ),
      size: (40, 3),
    );
    expect(t.lines, [
      'Health:  ok',
      'Load:   ${'█' * 16}',
      'Disk:   12 GB of 64 GB',
    ]);
    // the bar fills the 32 columns after the term column: half of them
    expect(t, styleAt(8, 0, hasBg(Color.green)));
    expect(t, styleAt(8, 2, hasAttr(Attr.bold)));
    expect(t, isNot(styleAt(14, 2, hasAttr(Attr.bold))));
  });

  testTwk("the values take the style given, over the theme's text, and a "
      'value of text its own over that', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: DescriptionList(
          valueStyle: const Style(attrs: Attr.italic),
          termStyle: const Style(attrs: Attr.underline),
          items: [
            DescriptionItem.text('A', 'x'),
            DescriptionItem.text(
              'B',
              'y',
              style: const Style(attrs: Attr.bold),
            ),
            const DescriptionItem('C', Text('z')),
          ],
        ),
      ),
      size: (40, 3),
    );
    expect(
      t,
      styleAt(
        0,
        0,
        allOf(hasAttr(Attr.underline), hasFg(const Color.indexed(245))),
      ),
    );
    expect(t, styleAt(3, 0, hasAttr(Attr.italic)));
    expect(t, styleAt(3, 1, allOf(hasAttr(Attr.italic), hasAttr(Attr.bold))));
    expect(t, styleAt(3, 2, hasAttr(Attr.italic)));
  });

  testTwk('would be as wide as its widest row, and as tall as its rows at '
      'a width', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicWidth(child: DescriptionList(items: _server)),
            const Text('|'),
          ],
        ),
      ),
      size: (40, 6),
    );
    expect(t.lines, [
      'Status:     Running     |',
      'IP Address: 192.168.1.42',
      '',
      'Limits',
      'CPU:    2',
      'Memory: 4 GB',
    ]);
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: DescriptionList(items: _server.sublist(0, 2)),
            ),
            const Text('-'),
          ],
        ),
      ),
      size: (20, 6),
    );
    expect(t.lines.take(5), [
      'Status:',
      '  Running',
      'IP Address:',
      '  192.168.1.42',
      '-',
    ]);
  });

  testTwk('a screen reader reads each pair as `term: value`, the whole term '
      'and the value, a heading as one', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: DescriptionList(
          items: [
            DescriptionItem.text('Memory Usage Statistics', '342 MB'),
            const DescriptionItem.group('Health'),
            const DescriptionItem('State', Badge('ok'), semanticsValue: 'ok'),
            DescriptionItem(
              'Disk',
              Text.rich(['12 GB'.bold, const Span(' free')]),
            ),
            const DescriptionItem('Load', ProgressBar(value: 0.25)),
            const DescriptionItem(
              'Note',
              Padding(padding: EdgeInsets.zero, child: Text('none')),
            ),
          ],
        ),
      ),
      size: (30, 7),
    );
    expect(read(t), [
      'Memory Usage Statistics: 342 MB',
      'heading Health',
      'State: ok',
      'Disk: 12 GB free',
      // a widget other than a Text: its term, then what it reads as
      'Load',
      'progressbar 25%',
      'Note',
      'none',
    ]);
  });

  testTwk('can be selected as text in a SelectionArea: a row copies as its '
      'term and its value', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: SelectionArea(
          onCopy: copies.add,
          child: DescriptionList(items: _server),
        ),
      ),
      size: (40, 6),
    );
    await t.mouse(MouseKind.down, 0, 0);
    await t.mouse(MouseKind.drag, 18, 0);
    await t.mouse(MouseKind.up, 18, 0);
    await t.pump();
    expect(copies, ['Status:\nRunning']);
  });
}
