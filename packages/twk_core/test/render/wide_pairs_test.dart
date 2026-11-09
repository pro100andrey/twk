// A painter that writes Surface.cells itself and splits a wide glyph is
// reported in debug mode at the end of the paint flush, before the presenter
// diffs the surface: logged as an error and repaired, the app goes on.
import 'package:test/test.dart';
import 'package:twk_core/terminal.dart' show LogLevel, LogRecord;
import 'package:twk_core/twk_core.dart';

/// Paints [write] onto the surface's cells directly and damages row 0.
final class Raw extends RenderObject {
  Raw(this.write);

  final void Function(Surface s) write;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainWidth(10);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) {
    write(ctx.surface);
    ctx.surface.markDirty(0, 0, 10);
  }
}

/// The error records of painting [write]; the split halves are blanked.
List<LogRecord> paintRaw(void Function(Surface s) write) {
  final records = <LogRecord>[];
  final owner = PipelineOwner(() {})
    ..onLog = records.add
    ..root = Raw(write);
  final screen = Screen(10, 2);
  owner
    ..flushLayout(10, 2)
    ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));
  return records;
}

Matcher splits(String part) => allOf(
  hasLength(1),
  everyElement(
    isA<LogRecord>()
        .having((r) => r.level, 'level', LogLevel.error)
        .having(
          (r) => r.message,
          'message',
          allOf(contains(part), contains('breakWideAt')),
        ),
  ),
);

void main() {
  PipelineOwner.debugCheckIntrinsicsByDefault = true;
  test('a whole wide glyph is fine', () {
    expect(
      paintRaw((s) {
        s.cells[2] = 0x4e2d | kWide;
        s.cells[3] = kCont;
      }),
      isEmpty,
    );
  });

  test('a wide glyph the canvas cuts at the edge is blanked, not split', () {
    final screen = Screen(10, 2);
    PipelineOwner(() {})
      ..root = Raw((s) {
        screen.canvas.text(9, 0, '中', 0);
      })
      ..flushLayout(10, 2)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
  });

  test('a wide cell without its continuation is reported, not thrown', () {
    expect(
      paintRaw((s) => s.cells[2] = 0x4e2d | kWide),
      splits('no continuation cell'),
    );
  });

  test('a wide cell at the last column is reported, not thrown', () {
    expect(
      paintRaw((s) => s.cells[9] = 0x4e2d | kWide),
      splits('last column'),
    );
  });

  test('an orphan continuation cell is reported, not thrown', () {
    expect(
      paintRaw((s) => s.cells[4] = kCont),
      splits('no wide glyph'),
    );
  });

  test('a half overwritten beside the damage is reported, not thrown', () {
    expect(
      paintRaw((s) {
        s
          ..cells[0] = 0x4e2d | kWide
          ..cells[1] = kCont
          ..clearDamage()
          ..cells[0] = kBlank
          ..markDirty(0, 0, 1);
      }),
      splits('no wide glyph'),
    );
  });

  test('the split half is blanked', () {
    final screen = Screen(10, 2);
    final records = <LogRecord>[];
    final owner = PipelineOwner(() {})
      ..onLog = records.add
      ..root = Raw((s) => s.cells[2] = 0x4e2d | kWide)
      ..flushLayout(10, 2);
    final ctx = PaintContext(screen.canvas, screen.surface, screen.presenter);
    owner.flushPaint(ctx);
    expect(records, hasLength(1));
    expect(screen.surface.cells[2], kBlank);
  });
}
