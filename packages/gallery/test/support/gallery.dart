// What the gallery's tests share: the gallery opened at a route, keys
// pressed and text typed, and the screen read back. A test file whose
// keys or clock go at a pace of their own says so in a wrapper of one
// line around these.
import 'dart:convert';

import 'package:gallery/testing.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] in a terminal of [size] and pumps its
/// first frame. With [at], the gallery's clock stopped at that many
/// milliseconds unless the route says `t=`; with [run] too, the app's own
/// clock run on to it, so that what runs on twk's tickers is where it
/// would be then. A route must name a page of the catalog, or none.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = screenSize,
  int? at,
  bool run = false,
}) async {
  var parsed = GalleryRoute.parse(route);
  expect(namesAPage(parsed), isTrue, reason: '$route names no page');
  if (at != null && parsed.t == null) {
    parsed = GalleryRoute.parse(
      route.contains('?') ? '$route&t=$at' : '$route?t=$at',
    );
  }
  await t.pumpWidget(galleryApp(route: parsed), size: size);
  await t.pump(run && at != null ? Duration(milliseconds: at) : null);
}

/// Presses [keys] (apart by commas, `comma` for a comma), a frame after
/// each, then lets [after] go by.
Future<void> keys(
  TwkTester t,
  String keys, {
  Duration after = const Duration(milliseconds: 500),
}) async {
  for (final k in keys.split(',')) {
    await t.press(k == 'comma' ? ',' : k);
    await t.pump();
  }
  await t.pump(after);
}

/// Types [text], then lets 500 ms go by.
Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pump(const Duration(milliseconds: 500));
}

/// Delivers the mouse report [kind] at ([x], [y]), then a frame.
Future<void> mouse(TwkTester t, MouseKind kind, int x, int y) async {
  await t.mouse(kind, x, y);
  await t.pump();
}

/// A click at ([x], [y]): a press and a release.
Future<void> click(TwkTester t, int x, int y) async {
  await mouse(t, MouseKind.down, x, y);
  await mouse(t, MouseKind.up, x, y);
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// The line of the screen [text] is on; empty where it is on none.
String lineOf(TwkTester t, String text) =>
    t.lines.firstWhere((l) => l.contains(text), orElse: () => '');

/// The row of the screen [text] is first on; -1 for none.
int rowOf(TwkTester t, String text) =>
    t.lines.indexWhere((l) => l.contains(text));

/// Where [text] starts on the screen, the first time it does.
(int, int) at(TwkTester t, String text) {
  for (final (y, line) in t.lines.indexed) {
    final x = line.indexOf(text);
    if (x >= 0) {
      return (x, y);
    }
  }
  throw StateError('"$text" is not on the screen:\n${screen(t)}');
}

/// The texts the app put on the clipboard (OSC 52), in order.
List<String> clips(TwkTester t) => [
  for (final m in RegExp(r'\x1b\]52;c;([A-Za-z0-9+/=]*)').allMatches(
    utf8.decode([
      for (final f in t.terminal.frames) ...f,
    ], allowMalformed: true),
  ))
    utf8.decode(base64.decode(m.group(1)!)),
];

/// Takes the build that App › ErrorWidget fails on purpose, on that page, so
/// a test of every page fails on any other error.
void takeOwnError(TwkTester t, String route) {
  if (route.contains('app/errorwidget')) {
    expect(
      t.takeErrors().map((r) => r.message),
      everyElement(contains('_Weather failed to build')),
    );
  }
}

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];
