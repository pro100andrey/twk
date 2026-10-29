// The hidden cursor rests on what has the focus: where a terminal that
// marks the cursor's row (iTerm2's cursor guide) or follows it (macOS
// zoom) shows the focus, not where the frame wrote last.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk("the hidden cursor rests on the focused widget's first cell, "
      'whatever the frame wrote last', (t) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final label = ValueNotifier('a');
    addTearDown(label.dispose);
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('title'),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Focus(focusNode: first, child: const Text('one')),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Focus(focusNode: second, child: const Text('two')),
          ),
          ValueListenableBuilder(
            valueListenable: label,
            builder: (_, v, _) => Text(v),
          ),
        ],
      ),
      size: (20, 6),
    );
    first.requestFocus();
    await t.pump();
    expect(t.cursorVisible, isFalse);
    expect(t.cursor, (2, 1));

    // a frame that writes elsewhere leaves it there
    label.value = 'bbbbbbbb';
    await t.pump();
    expect(t.cursor, (2, 1));

    second.requestFocus();
    await t.pump();
    expect(t.cursor, (4, 2));
  });

  test('restCursor false leaves the hidden cursor where the frame wrote '
      'last, no byte spent on it', () async {
    final clock = FakeClock();
    final term = clock.run(() => HeadlessTerminal(width: 20, height: 4));
    final binding = clock.run(
      () => AppBinding(
        term,
        maxFps: 1000,
        clock: clock.stopwatch,
        restCursor: false,
      ),
    );
    final node = FocusNode();
    addTearDown(node.dispose);
    final done = clock.run(
      () => binding.run(
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 1),
          child: Focus(
            focusNode: node,
            autofocus: true,
            child: const Text('x'),
          ),
        ),
      ),
    );
    await clock.elapse(const Duration(milliseconds: 30));
    final presenter = binding.twkApp.screen.presenter;
    expect(presenter.restsCursor, isFalse);
    binding.quit();
    await clock.elapseUntil(done);
  });

  testTwk('a focused widget puts it on a cell of its own, the selected one', (
    t,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final row = ValueNotifier(1);
    addTearDown(row.dispose);
    await t.pumpWidget(
      Padding(
        padding: const EdgeInsets.only(left: 3, top: 1),
        child: Focus(
          focusNode: node,
          child: ValueListenableBuilder(
            valueListenable: row,
            builder: (_, r, _) => _Rows(r),
          ),
        ),
      ),
      size: (20, 6),
    );
    node.requestFocus();
    await t.pump();
    expect(t.cursor, (3 + 1, 1 + 1));
    row.value = 3;
    await t.pump();
    expect(t.cursor, (3 + 1, 1 + 3));
    // nothing selected: the widget's first cell again
    row.value = -1;
    await t.pump();
    expect(t.cursor, (3, 1));
    row.value = 2;
    await t.pump();
    expect(t.cursor, (3 + 1, 1 + 2));
    // focus gone: no widget to rest on, at home, not on the cell left
    node.unfocus();
    await t.pump();
    expect(t.cursorVisible, isFalse);
    expect(t.cursor, (0, 0));
  });

  testTwk('each object keeps its own cell: another one repainted after the '
      'focused one takes nothing from it', (t) async {
    final left = FocusNode();
    final right = FocusNode();
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    final leftRow = ValueNotifier(1);
    final rightRow = ValueNotifier(0);
    addTearDown(leftRow.dispose);
    addTearDown(rightRow.dispose);
    Widget list(FocusNode node, ValueNotifier<int> row) => Focus(
      focusNode: node,
      child: ValueListenableBuilder(
        valueListenable: row,
        builder: (_, r, _) => _Rows(r),
      ),
    );
    await t.pumpWidget(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          list(left, leftRow),
          const SizedBox(width: 2),
          list(right, rightRow),
        ],
      ),
      size: (30, 6),
    );
    left.requestFocus();
    await t.pump();
    expect(t.cursor, (1, 1));
    // the other list's selection repainted after: the cursor stays
    rightRow.value = 3;
    await t.pump();
    expect(t.cursor, (1, 1));
    right.requestFocus();
    await t.pump();
    expect(t.cursor, (12 + 1, 3));
    left.requestFocus();
    await t.pump();
    expect(t.cursor, (1, 1));
  });
}

/// Rows of text, the [selected] one put where the hidden cursor rests;
/// none below 0.
final class _Rows extends LeafRenderObjectWidget {
  const _Rows(this.selected);

  final int selected;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRows(selected);

  @override
  void updateRenderObject(BuildContext context, _RenderRows renderObject) {
    renderObject.selected = selected;
  }
}

final class _RenderRows extends RenderObject {
  _RenderRows(this._selected);

  int _selected;
  int get selected => _selected;
  set selected(int r) {
    if (r != _selected) {
      _selected = r;
      markNeedsPaint();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(10);
    height = c.constrainH(4);
  }

  @override
  void paint(PaintContext ctx) {
    for (var y = 0; y < height; y++) {
      ctx.canvas.text(0, y, y == _selected ? '> row $y' : '  row $y', 0);
    }
    if (_selected < 0) {
      clearRestCursor(ctx, this);
    } else {
      restCursor(ctx, this, 1, _selected);
    }
  }
}
