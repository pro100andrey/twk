// Shows each page of the gallery in twk's tester and writes, for the
// check of its Code, what its stage shows: the Code at the start, the
// room the stage gave the widget, and the cells of the widget (of the app
// in it where the widget draws a terminal around it) at the route's time.
//
//   dart run tool/code_check/stages.dart <out.json> [route…]
//
// Without routes, every page of the catalog, dark, 120x36, at 2 s, and
// the routes of [_more].
import 'dart:convert';
import 'dart:io';

import 'package:gallery/gallery.dart';
import 'package:gallery/src/shell/stage.dart';
import 'package:gallery/src/shell/tokens.dart' show galleryThemes;
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

/// When the stage is read, unless the route says `t=`.
const _t = Duration(milliseconds: 2000);

/// The routes checked besides each page's own, for a page whose options
/// make another Code: App › Cli's other programs.
const _more = ['#/app/cli?o=program:install', '#/app/cli?o=program:check'];

void main(List<String> args) {
  final [out, ...given] = args;
  final routes = given.isNotEmpty
      ? given
      : [
          for (final g in catalog)
            for (final p in g.pages) '#/${slug(g.title)}/${slug(p.title)}',
          ..._more,
        ];
  final results = <String, Object?>{};
  for (final route in routes) {
    final r = results[route] = <String, Object?>{};
    // each in a terminal of its own: a page that moves on the app's clock
    // counts from when it was shown
    for (final (what, read) in [('code', _code), ('stage', _stage)]) {
      testTwk('$route: $what', (t) async {
        if (r['error'] != null || (what == 'stage' && r['code'] == null)) {
          return;
        }
        try {
          await read(t, route, r);
        } on Object catch (e, stack) {
          r['error'] = '$e';
          r['stack'] = '$stack'.split('\n').take(12).join('\n');
        }
      });
    }
  }
  tearDownAll(() => File(out).writeAsStringSync(jsonEncode(results)));
}

/// The parameters of [route] but `keys=`, `type=` and `t=`, with `t=`
/// at [at].
String _at(String route, Duration at) {
  final [path, ...query] = route.split('?');
  final params = [
    for (final p in query.join('?').split('&'))
      if (p.isNotEmpty && !RegExp('^(keys|type|t)=').hasMatch(p)) p,
    't=${at.inMilliseconds}',
  ];
  return '$path?${params.join('&')}';
}

/// The terminal [route] asks for: its size (120x36) and its theme's
/// background, and the gallery's name of the theme.
({(int, int) size, int background, String theme}) _terminal(
  GalleryRoute route,
) {
  final size = switch (route.size?.split('x')) {
    [final w, final h] => (int.parse(w), int.parse(h)),
    _ => (120, 36),
  };
  final theme = route.theme ?? 'dark';
  final data = galleryThemes[theme]!.$2;
  return (
    size: size,
    background: (data.background.bg?.value ?? 0) & 0xFFFFFF,
    theme: theme,
  );
}

/// Shows the gallery at [route], its clock stopped at [at], and returns
/// its shell.
Future<GalleryShellState> _open(
  TwkTester t,
  String route,
  Duration at,
) async {
  final term = _terminal(GalleryRoute.parse(route));
  await t.pumpWidget(
    galleryApp(route: GalleryRoute.parse(_at(route, at))),
    size: term.size,
    duration: Duration.zero,
    backgroundRgb: term.background,
  );
  await t.pump();
  return t.state<GalleryShellState>(find.byType(GalleryShell));
}

/// The Code a program started at 0 runs, and what the page says of it: a
/// page that sets its own options as time goes on has another Code by the
/// route's time.
Future<void> _code(TwkTester t, String route, Map<String, Object?> r) async {
  final parsed = GalleryRoute.parse(route);
  final shell = await _open(t, route, Duration.zero);
  final def = shell.page.def;
  r['key'] = shell.page.key;
  r['code'] = shell.code;
  r['theme'] = _terminal(parsed).theme;
  r['ms'] = (parsed.t ?? _t).inMilliseconds;
  r['keys'] = parsed.keys;
  r['type'] = parsed.type ?? '';
  r['terminal'] = def?.codeInTerminalColors ?? false;
}

/// The stage at the route's time, after its keys: the room it gave the
/// widget and the widget's cells, or those of the Code's app in it.
Future<void> _stage(TwkTester t, String route, Map<String, Object?> r) async {
  final parsed = GalleryRoute.parse(route);
  final at = parsed.t ?? _t;
  final shell = await _open(t, route, at);
  final def = shell.page.def!;
  for (final key in parsed.keys) {
    await t.press(key);
    await t.pump();
  }
  if (parsed.type case final type? when type.isNotEmpty) {
    await t.type(type);
    await t.pump();
  }
  final rest = at - t.clock.elapsed;
  await t.pump(rest.isNegative ? Duration.zero : rest);

  final stages = find.byType(Stage).evaluate().toList();
  if (stages.isEmpty) {
    r['error'] = 'no stage: the page shows its Code tab';
    return;
  }
  final stage = stages.single.renderObject! as RenderStage;
  final child = stage.child;
  if (child == null) {
    r['error'] = 'the stage has no widget';
    return;
  }
  final s = t.rect(find.byType(Stage));
  var rect = (
    x: s.x + child.parentData.dx,
    y: s.y + child.parentData.dy,
    width: child.width,
    height: child.height,
  );
  var room = shell.room;
  if (def.codeInTerminalColors) {
    // the stage is the app's terminal, all of it
    room = StageRoom(rect.width, rect.height);
  } else if (def.terminalAround) {
    final apps = find.byType(CodeApp);
    if (apps.evaluate().isEmpty) {
      r['noApp'] = true;
      return;
    }
    rect = t.rect(apps);
    room = StageRoom(rect.width, rect.height);
  }
  r['room'] = {'w': room?.width, 'h': room?.height};
  r['rect'] = {
    'x': rect.x,
    'y': rect.y,
    'w': rect.width,
    'h': rect.height,
  };
  final vt = t.vt;
  r['cells'] = [
    for (var y = rect.y; y < rect.y + rect.height && y < vt.height; y++)
      [
        for (var x = rect.x; x < rect.x + rect.width && x < vt.width; x++)
          if (vt.cell(x, y) case final c) [c.text, c.fg, c.bg, c.attrs, c.role],
      ],
  ];
}
