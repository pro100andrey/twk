// A route of the gallery shown in twk's tester as the golden screens and
// the Code check show it: on a terminal of the route's size whose
// background is its theme's, the clock stopped at its `t=`, its keys
// pressed and its text typed after the first frame.
import 'package:twk_test/twk_test.dart';

import '../../gallery.dart';

/// When a route is read unless it says `t=`.
const screenTime = Duration(milliseconds: 2000);

/// The terminal's size unless a route says `size=`.
const screenSize = (120, 36);

/// The terminal [route] asks for: its `size` ([screenSize] unless it says
/// `size=`), the gallery's name of its `theme`, and that theme's
/// `background` as 24-bit RGB.
({(int, int) size, String theme, int background}) routeTerminal(
  GalleryRoute route,
) {
  final size = switch (route.size?.split('x')) {
    [final w, final h] => (int.parse(w), int.parse(h)),
    _ => screenSize,
  };
  final theme = route.theme ?? 'dark';
  final data = galleryThemes[theme]!.$2;
  return (
    size: size,
    theme: theme,
    background: (data.background.bg?.value ?? 0) & 0xFFFFFF,
  );
}

/// [route] without its `keys=`, `type=` and `t=`, the clock stopped at
/// [at] instead: the route the gallery opens at, before what is pressed.
String routeAt(String route, Duration at) {
  final [path, ...query] = route.split('?');
  final params = [
    for (final p in query.join('?').split('&'))
      if (p.isNotEmpty && !RegExp('^(keys|type|t)=').hasMatch(p)) p,
    't=${at.inMilliseconds}',
  ];
  return '$path?${params.join('&')}';
}

/// Opens the gallery at [route] on its terminal ([routeTerminal]), the
/// clock stopped at [at], and pumps its first frame; returns the shell.
Future<GalleryShellState> openRoute(
  TwkTester t,
  String route,
  Duration at,
) async {
  final term = routeTerminal(GalleryRoute.parse(route));
  await t.pumpWidget(
    galleryApp(route: GalleryRoute.parse(routeAt(route, at))),
    size: term.size,
    duration: Duration.zero,
    backgroundRgb: term.background,
  );
  await t.pump();
  return t.state<GalleryShellState>(find.byType(GalleryShell));
}

/// Presses [route]'s `keys=` and types its `type=`, a frame after each,
/// then runs the clock to [at].
Future<void> playRoute(TwkTester t, GalleryRoute route, Duration at) async {
  for (final key in route.keys) {
    await t.press(key);
    await t.pump();
  }
  if (route.type case final type? when type.isNotEmpty) {
    await t.type(type);
    await t.pump();
  }
  final rest = at - t.clock.elapsed;
  await t.pump(rest.isNegative ? Duration.zero : rest);
}

/// Shows the gallery at [route] as a golden screen holds it: opened at
/// its time (`t=`, else [screenTime]) and played to it ([playRoute]);
/// returns the shell.
Future<GalleryShellState> showRoute(TwkTester t, String route) async {
  final parsed = GalleryRoute.parse(route);
  final at = parsed.t ?? screenTime;
  final shell = await openRoute(t, route, at);
  await playRoute(t, parsed, at);
  return shell;
}
