// An app in Theme.adaptive, for a run in a pseudo-terminal that switches
// its color scheme (tool/pty_run.py --scheme, color_scheme_test.dart): the
// name of the theme it is in on the theme's background, above a panel of
// half white over the terminal's default background. It quits once it has
// shown the light scheme's background: at the frame after the one that
// painted over the light default background the terminal reported after
// its switch. --seconds (3 by default) bounds it: it quits then whatever
// it has shown.
import 'dart:async';

// the libraries of twk it runs on, not all of twk: it compiles in about
// 60 % of the time
import 'package:twk/src/binding/binding.dart';
import 'package:twk/src/framework/framework.dart';
import 'package:twk/src/layout/layout.dart';
import 'package:twk/src/style/style.dart';
import 'package:twk/src/text/text.dart';
import 'package:twk_core/twk_core.dart';

Future<void> main(List<String> args) async {
  var seconds = 3.0;
  for (final a in args) {
    if (a.startsWith('--seconds=')) {
      seconds = double.parse(a.substring('--seconds='.length));
    }
  }
  final binding = AppBinding(await Terminal.open());
  final bound = Timer(
    Duration(milliseconds: (seconds * 1000).round()),
    binding.quit,
  );
  var light = false;
  await binding.run(
    InputListener(
      onEvent: (e) {
        if (e is ColorSchemeReport) {
          light = e.brightness == Brightness.light;
        } else if (light &&
            e is ColorReport &&
            e.which == 11 &&
            Brightness.ofRgb(e.rgb) == Brightness.light) {
          // the frame this report asks for paints over the light
          // background; the one after it, once that one is written, quits
          binding.scheduleFrameCallback(
            (_) => binding.scheduleFrameCallback((_) => binding.quit()),
          );
        }
        return false;
      },
      child: const Theme.adaptive(child: _Show()),
    ),
  );
  bound.cancel();
}

final class _Show extends StatelessWidget {
  const _Show();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Box(
          style: theme.background,
          child: Text('theme ${theme.brightness.name}', style: theme.text),
        ),
        const Box(
          style: Style(bg: Color.rgb(255, 255, 255), bgAlpha: 64),
          child: Text('half white'),
        ),
      ],
    );
  }
}
