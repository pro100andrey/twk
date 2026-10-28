// The retained render objects must leave the surface exactly as a full
// repaint of the same state would.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A render tree filling a whole screen.
base class View {
  View(this.width, this.height) : screen = Screen(width, height) {
    pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    owner = PipelineOwner(() {});
  }

  int width;
  int height;
  final Screen screen;
  late final int pen;
  late final PipelineOwner owner;

  /// The terminal was resized.
  void resize(int w, int h) {
    width = w;
    height = h;
    screen.resize(w, h);
    owner.markAllDirty();
  }

  void frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
  }

  List<String> rows() => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
      ].join().trimRight(),
  ];
}

/// What [body] prints.
List<String> printed(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => lines.add(line),
    ),
  );
  return lines;
}

/// Whether asserts run, as debug reports need.
bool get debug {
  var on = false;
  assert(on = true, 'debug only');
  return on;
}

/// A [RenderLog] filling a whole screen.
final class LogView extends View {
  LogView(super.width, super.height) {
    log = RenderLog(pen: pen, itemPen: (_, _) => pen);
    owner.root = log;
  }

  late final RenderLog log;
}

void main() {
  test('lines appended between frames are all painted', () {
    final v = LogView(20, 6);
    for (final s in ['one', 'two', 'three']) {
      v.log.add(s);
    }
    v.frame();
    v.log
      ..add('four')
      ..add('five');
    v.frame();
    expect(v.rows(), [' one', ' two', ' three', ' four', ' five', '']);
  });

  test('lines appended while the window starts to scroll are painted', () {
    final v = LogView(20, 6);
    for (var i = 0; i < 5; i++) {
      v.log.add('line $i');
    }
    v.frame();
    for (var i = 5; i < 8; i++) {
      v.log.add('line $i');
    }
    v.frame();
    expect(v.rows(), [for (var i = 2; i < 8; i++) ' line $i']);
  });

  test('repaintAll repaints lines whose pen changed', () {
    final v = LogView(20, 3);
    var highlighted = -1;
    final styles = v.screen.styles;
    final plain = styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    final hot = styles.pen(const Pen(bg: Color.rgb(90, 0, 0)));
    final log = RenderLog(
      pen: plain,
      itemPen: (i, _) => i == highlighted ? hot : plain,
    );
    v.owner.root = log;
    for (var i = 0; i < 3; i++) {
      log.add('line $i');
    }
    v.frame();
    highlighted = 1;
    log.repaintAll();
    v.frame();
    final cells = v.screen.surface.styles;
    expect(cells[1 * 20 + 2], isNot(cells[0 * 20 + 2]));
    expect(styles.bgOf(cells[1 * 20 + 2]), const Color.rgb(90, 0, 0));
  });

  test('a full log scrolls and paints the exposed lines', () {
    final v = LogView(20, 3);
    for (var i = 0; i < 5; i++) {
      v.log.add('line $i');
    }
    v.frame();
    v.log
      ..add('line 5')
      ..add('line 6');
    v.frame();
    expect(v.rows(), [' line 4', ' line 5', ' line 6']);
  });

  test('a log repaints everything after a resize away and back', () {
    final v = LogView(20, 4);
    for (var i = 0; i < 6; i++) {
      v.log.add('line $i');
    }
    v.frame();
    // two resize events before the next frame; the surface was cleared
    v.screen
      ..resize(20, 3)
      ..resize(20, 4);
    v.owner.markAllDirty();
    v.frame();
    expect(v.rows(), [for (var i = 2; i < 6; i++) ' line $i']);
  });

  test('a root without a background of its own leaves nothing behind', () {
    final v = View(10, 2);
    final title = RenderText('hello', v.pen);
    v.owner.root = RenderColumn([(title, 1), (RenderText('x', v.pen), 1)]);
    v.frame();
    title.text = 'hi';
    v.frame();
    expect(v.rows(), ['hi', 'x']);
  });

  test('repaint boundaries need an opaque background', () {
    final v = View(10, 2);
    final glass = v.screen.styles.pen(
      const Pen(bg: Color.rgb(255, 0, 0), bgAlpha: 128),
    );
    for (final root in [
      RenderText('x', glass, boundary: true),
      RenderBox(pen: glass, boundary: true),
      RenderLog(pen: glass, itemPen: (_, _) => glass),
    ]) {
      v.owner.root = root;
      expect(v.frame, throwsA(isA<AssertionError>()), reason: '$root');
    }
  });

  test('a log scrolled up stays filled when the view grows', () {
    final v = LogView(12, 4);
    for (var i = 0; i < 10; i++) {
      v.log.add('line $i');
    }
    v.frame();
    v.log.scrollBy(-1);
    v.frame();
    expect(v.rows(), [for (var i = 5; i < 9; i++) ' line $i']);
    v
      ..resize(12, 8)
      ..frame();
    expect(v.rows(), [for (var i = 2; i < 10; i++) ' line $i']);
    v.log.scrollBy(1);
    v.frame();
    expect(v.rows(), [for (var i = 2; i < 10; i++) ' line $i']);
  });

  test('a log taller than the screen scrolls without a blank row', () {
    final v = View(10, 4);
    final log = RenderLog(pen: v.pen, itemPen: (_, _) => v.pen);
    v.owner.root = RenderColumn([(RenderText('hdr', v.pen), 1), (log, 6)]);
    for (var i = 0; i < 10; i++) {
      log.add('line $i');
    }
    expect(printed(v.frame), [
      if (debug)
        endsWith(' warning A RenderFlex overflowed by 3 rows on the bottom.'),
    ]);
    expect(v.rows(), ['hdr', ' line 4', ' line 5', ' line 6']);
    log.scrollBy(-1);
    v.frame();
    log.scrollBy(1);
    v.frame();
    expect(v.rows(), ['hdr', ' line 4', ' line 5', ' line 6']);
  });

  test('a boundary repaints only inside its ancestors', () {
    final v = View(10, 3);
    final c = RenderText('C', v.pen, boundary: true);
    // the inner column gets 2 rows, its children want 3: C is cut off
    final inner = RenderColumn([
      (RenderText('A', v.pen), 1),
      (RenderText('B', v.pen), 1),
      (c, 1),
    ]);
    v.owner.root = RenderBox(
      pen: v.pen,
      boundary: true,
      child: RenderColumn([(inner, 2), (RenderText('below', v.pen), null)]),
    );
    expect(printed(v.frame), [
      if (debug)
        endsWith(' warning A RenderFlex overflowed by 1 row on the bottom.'),
    ]);
    expect(v.rows(), ['A', 'B', 'below']);
    c.text = 'D';
    v.frame();
    expect(v.rows(), ['A', 'B', 'below']);
  });

  test('changing a pen repaints', () {
    final v = View(10, 1);
    final red = v.screen.styles.pen(const Pen(bg: Color.rgb(90, 0, 0)));
    final text = RenderText('x', v.pen, boundary: true);
    v.owner.root = text;
    v.frame();
    text.pen = red;
    v.frame();
    final bg = v.screen.styles.bgOf(v.screen.surface.styles[0]);
    expect(bg, const Color.rgb(90, 0, 0));

    final box = RenderBox(pen: v.pen, boundary: true);
    v.owner.root = box;
    v.frame();
    box.pen = red;
    v.frame();
    expect(
      v.screen.styles.bgOf(v.screen.surface.styles[0]),
      const Color.rgb(90, 0, 0),
    );
  });

  group('replacing children', () {
    test('removing the child clears its area', () {
      final v = View(10, 2);
      final box = RenderBox(
        pen: v.pen,
        boundary: true,
        child: RenderText('hello', v.pen),
      );
      v.owner.root = box;
      v.frame();
      box.child = null;
      v.frame();
      expect(v.rows(), ['', '']);
    });

    test('switching back to an earlier child paints it again', () {
      final v = View(10, 2);
      final a = RenderText('AAAA', v.pen);
      final b = RenderText('BBBB', v.pen);
      final box = RenderBox(pen: v.pen, boundary: true, child: a);
      v.owner.root = box;
      v.frame();
      box.child = b;
      v.frame();
      expect(v.rows(), ['BBBB', '']);
      box.child = a;
      v.frame();
      expect(v.rows(), ['AAAA', '']);
    });

    test('a replaced child no longer paints', () {
      final v = View(10, 3);
      final old = RenderLog(pen: v.pen, itemPen: (_, _) => v.pen);
      final box = RenderBox(pen: v.pen, boundary: true, child: old);
      v.owner.root = box;
      old.add('old 1');
      v.frame();
      box.child = RenderText('new view', v.pen);
      v.frame();
      old.add('old 2');
      v.frame();
      expect(v.rows(), ['new view', '', '']);
      expect(old.parent, isNull);
      expect(old.owner, isNull);
    });

    test('a smaller child replacing a larger one leaves nothing behind', () {
      final v = View(10, 3);
      final log = RenderLog(pen: v.pen, itemPen: (_, _) => v.pen);
      for (final s in ['l1', 'l2', 'l3']) {
        log.add(s);
      }
      final box = RenderBox(pen: v.pen, boundary: true, child: log);
      v.owner.root = box;
      v.frame();
      box.child = RenderText('title', v.pen, boundary: true);
      v.frame();
      expect(v.rows(), ['title', '', '']);
    });

    test('a new root replaces the old one', () {
      final v = View(10, 2);
      final old = RenderText('old', v.pen, boundary: true);
      v.owner.root = old;
      v.frame();
      v.owner.root = RenderText('new', v.pen, boundary: true);
      v.frame();
      old.text = 'stale';
      v.frame();
      expect(v.rows(), ['new', '']);
    });
  });
}
