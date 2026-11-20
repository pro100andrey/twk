/// [DriverScreen], the screen of an app a driver test runs.
///
/// @docImport 'matchers.dart';
/// @docImport 'tester.dart';
library;

import '../vt.dart';
import 'finders.dart';
import 'screen_file.dart' show cellsText;
import 'screen_subject.dart';

/// The screen of an app run as a process (`DriverApp.screen`), as the frame
/// the app drew last shows it. The matchers of the screen read it as they
/// read a [TwkTester]'s: `expect(app.screen, containsLine('Saved'))`,
/// [hasTextAt], [styleAt], [cursorAt], [matchesScreen].
///
/// A [Finder] cannot say where it is drawn on a screen of a process: its
/// widgets are in the app's, and finding them is a call to the app
/// (`DriverApp.rect`). The matchers' `within` fails saying so; pass
/// `withinRect: await app.rect(find.byType(ListView))`.
final class DriverScreen implements ScreenSubject {
  /// The screen [vt] holds.
  DriverScreen(this.vt);

  @override
  final Vt vt;

  @override
  List<String> get lines => vt.lines.sublist(vt.history.length);

  /// Inline mode: the lines scrolled off the top of the screen, oldest
  /// first.
  List<String> get scrollback => vt.lines.sublist(0, vt.history.length);

  @override
  List<String> linesIn(CellRect region) {
    final left = region.x < 0 ? 0 : region.x;
    final top = region.y < 0 ? 0 : region.y;
    final right = region.x + region.width < vt.width
        ? region.x + region.width
        : vt.width;
    final bottom = region.y + region.height < vt.height
        ? region.y + region.height
        : vt.height;
    return [
      for (var y = top; y < bottom; y++)
        cellsText(vt, y, left, right).trimRight(),
    ];
  }

  @override
  (int, int) get cursor => (vt.cx, vt.cy);

  @override
  bool get cursorVisible => vt.cursorVisible;

  @override
  CellRect rect(Finder finder) => throw StateError(
    'a finder finds widgets of the app, which is a process: its cells are '
    'read with await app.rect(finder), and passed as withinRect',
  );

  @override
  String get context => 'the widget tree is in the report of the failed test';

  @override
  String toString() => lines.join('\n');
}
