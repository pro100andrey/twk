// What a SelectionArea leaves out (ExcludeSelection), and the order it
// selects in where one Selectable lies inside another.
import 'dart:math' show max;

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'selection_painted_test.dart' show area, column, drag, marked;

void main() {
  group('ExcludeSelection', () {
    testTwk('leaves its Texts out of a drag across it and of what is copied, '
        'and of what is painted selected', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSelection(child: Text('1\n2')),
                Text(' one\n two'),
              ],
            ),
          ),
        ),
        size: (10, 3),
      );
      expect(t.lines.take(2), ['1 one', '2 two']);
      // from the gutter of the first row to the end of the second
      await drag(t, (0, 0), [(5, 1)]);
      expect(copies, [' one\n two']);
      expect(marked(t, 0, 6), '.xxxx.');
      expect(marked(t, 1, 6), '.xxxx.');
    });

    testTwk('is skipped between the Texts around it', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            column(const [
              Text('head'),
              ExcludeSelection(child: Text('note')),
              Text('tail'),
            ]),
          ),
        ),
        size: (10, 4),
      );
      await drag(t, (0, 0), [(3, 2)]);
      expect(copies, ['head\n\ntail']);
      expect(marked(t, 1, 6), '......');
    });

    testTwk('leaves a Selectable out too', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            column(const [
              Text('head'),
              ExcludeSelection(child: _Row('note')),
              Text('tail'),
            ]),
          ),
        ),
        size: (10, 4),
      );
      await drag(t, (0, 0), [(3, 2)]);
      expect(copies, ['head\n\ntail']);
    });

    testTwk('has a SelectionArea inside select on its own', (t) async {
      final outer = <String>[];
      final inner = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            outer,
            column([
              const Text('head'),
              ExcludeSelection(
                child: SelectionArea(
                  onCopy: inner.add,
                  child: const Text('note'),
                ),
              ),
              const Text('tail'),
            ]),
          ),
        ),
        size: (10, 4),
      );
      await drag(t, (0, 0), [(3, 2)]);
      expect(outer, ['head\n\ntail']);
      await drag(t, (1, 1), [(3, 1)]);
      expect(inner, ['ote']);
      expect(outer, ['head\n\ntail'], reason: 'nothing more of the outer');
      expect(marked(t, 0, 4), '....', reason: 'its selection was cleared');
    });
  });

  group('a Selectable with a child', () {
    testTwk('is selected before the Texts in it, whichever the mouse '
        'goes into', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            const _Over('code', child: Text('comment')),
          ),
        ),
        size: (10, 3),
      );
      expect(t.lines.take(2), ['code', 'comment']);
      // from the code line into the comment under it
      await drag(t, (1, 0), [(3, 1)]);
      expect(copies, ['ode\ncomm']);
    });
  });
}

/// [word] on a row, selected as a Selectable.
final class _Row extends LeafRenderObjectWidget {
  const _Row(this.word);

  final String word;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRow(word);
}

final class _RenderRow extends RenderObject with Selectable {
  _RenderRow(this.word);

  final String word;

  @override
  String get selectableText => word;

  @override
  (int, int) selectableRangeAt(int x, int y) {
    if (y < 0) {
      return (0, 0);
    }
    if (y > 0 || x >= word.length) {
      return (word.length, word.length);
    }
    final at = x < 0 ? 0 : x;
    return (at, at + 1);
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainWidth(word.length);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) {
    for (var c = 0; c < word.length; c++) {
      final style = selectionStyleAt(c, const Style());
      ctx.canvas.text(c, 0, word[c], style.penIn(ctx.canvas.styles));
    }
  }
}

/// [word] on a row, a [Selectable], with [child] on the row under it.
final class _Over extends SingleChildRenderObjectWidget {
  const _Over(this.word, {super.child});

  final String word;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOver(word);
}

final class _RenderOver extends RenderObject
    with Selectable, RenderObjectWithChildMixin {
  _RenderOver(this.word);

  final String word;

  @override
  String get selectableText => word;

  @override
  (int, int) selectableRangeAt(int x, int y) {
    if (y < 0) {
      return (0, 0);
    }
    if (y > 0 || x >= word.length) {
      return (word.length, word.length);
    }
    final at = x < 0 ? 0 : x;
    return (at, at + 1);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.constrainWidth(word.length);
      height = c.constrainHeight(1);
      return;
    }
    child.layout(c.loosen(), parentUsesSize: true);
    child.parentData
      ..dx = 0
      ..dy = 1;
    width = c.constrainWidth(max(word.length, child.width));
    height = c.constrainHeight(1 + child.height);
  }

  @override
  void paint(PaintContext ctx) {
    for (var c = 0; c < word.length; c++) {
      final style = selectionStyleAt(c, const Style());
      ctx.canvas.text(c, 0, word[c], style.penIn(ctx.canvas.styles));
    }
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}
