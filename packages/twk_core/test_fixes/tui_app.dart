// An app written when the core's app was TuiApp (before 6d4f947).
import 'package:twk_core/twk_core.dart';

Future<void> main() async {
  final TuiApp app = TuiApp(await Terminal.open(), maxFps: 30);
  final pen = app.screen.styles.pen(const Pen(fg: Color.green));
  await app.run(RenderText('hello', pen), (event) => app.quit());
}

TuiApp? current;

void stop(TuiApp app) => app.quit();

final List<TuiApp> apps = <TuiApp>[];

final TuiApp Function(Terminal) open = TuiApp.new;

TuiApp asApp(Object o) => o as TuiApp;

// Left as it is: an undefined name in a type test reports
// type_test_with_undefined_name, which no data-driven fix answers. Rename
// this one by hand (the analyzer still reports it after dart fix).
bool isApp(Object o) => o is TuiApp;

void ifApp(Object o) {
  if (o case TuiApp(:final terminal)) print(terminal.info);
}
