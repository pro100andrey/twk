// On a terminal that counts the East Asian ambiguous characters two cells
// wide, the marks of Glyphs.unicode fall back to Glyphs.ascii's; the log
// says why once, and does not blame the app field by field. A mark the app
// chose still has its own warning.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import '../text/ambiguous.dart';

Widget column(Glyphs glyphs) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: Column(
    children: [
      Slider(value: 0.5, onChanged: (_) {}),
      Switch(value: true, onChanged: (_) {}),
      Button('Go', onPressed: () {}),
    ],
  ),
);

List<String> warnings(WideApp app) => [
  for (final r in app.binding.twkApp.logs.records)
    if (r.level == LogLevel.warning) r.message,
];

void main() {
  test('the default marks give one line naming the terminal, not one for '
      'each field', () async {
    final app = await WideApp.start(
      column(Glyphs.unicode),
    );
    final log = warnings(app);
    await app.quit();
    expect(log, hasLength(1));
    expect(log.single, contains('ambiguous'));
    expect(log.single, isNot(startsWith('Glyphs.')));
  });

  test('a mark the app chose has its own warning, besides that line', () async {
    final app = await WideApp.start(
      column(Glyphs.unicode.copyWith(switchKnob: '🙂')),
    );
    final log = warnings(app);
    await app.quit();
    expect(log.where((m) => m.contains('ambiguous')), hasLength(1));
    expect(
      log.where((m) => m.startsWith("Glyphs.switchKnob '🙂' is 2 cells")),
      hasLength(1),
    );
    expect(log, hasLength(2));
  });

  test('Glyphs.ascii warns of nothing', () async {
    final app = await WideApp.start(column(Glyphs.ascii));
    final log = warnings(app);
    await app.quit();
    expect(log, isEmpty);
  });
}
