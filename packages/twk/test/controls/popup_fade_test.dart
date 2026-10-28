// The popups of Select, MultiSelect, DatePicker and Autocomplete fade in
// from what is under them over popupFadeIn, 120 ms by default, as the
// other overlays do; zero shows them at once.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData theme = ThemeData.dark;
const ms = Duration(milliseconds: 1);

const List<Choice<String>> fruit = [
  Choice('a', 'Apple'),
  Choice('b', 'Banana'),
];

/// [child] at the top left of an overlay on the dark theme's background.
Widget app(Widget child) => Theme(
  data: theme,
  child: Box(
    style: theme.background,
    child: Overlay(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [child],
      ),
    ),
  ),
);

/// A [Select] of [fruit] with the focus, its popup fading in over [fadeIn]
/// where given.
Widget select({Duration? fadeIn}) => fadeIn == null
    ? Select<String>(
        choices: fruit,
        value: null,
        onChanged: (_) {},
        autofocus: true,
      )
    : Select<String>(
        choices: fruit,
        value: null,
        onChanged: (_) {},
        autofocus: true,
        popupFadeIn: fadeIn,
      );

/// A [MultiSelect] of [fruit] with the focus, its popup fading in over
/// [fadeIn] where given.
Widget multi({Duration? fadeIn}) => fadeIn == null
    ? MultiSelect<String>(
        choices: fruit,
        values: const {},
        onChanged: (_) {},
        autofocus: true,
      )
    : MultiSelect<String>(
        choices: fruit,
        values: const {},
        onChanged: (_) {},
        autofocus: true,
        popupFadeIn: fadeIn,
      );

/// A [DatePicker] with the focus, its calendar fading in over [fadeIn]
/// where given.
Widget date({Duration? fadeIn}) {
  final today = DateTime(2026, 10, 22);
  return fadeIn == null
      ? DatePicker(
          value: today,
          today: today,
          onChanged: (_) {},
          autofocus: true,
        )
      : DatePicker(
          value: today,
          today: today,
          onChanged: (_) {},
          autofocus: true,
          popupFadeIn: fadeIn,
        );
}

/// A field with an [Autocomplete] of [fruit]'s labels around it, its list
/// fading in over [fadeIn] where given.
Widget complete({Duration? fadeIn}) {
  final c = TextEditingController();
  addTearDown(c.dispose);
  Iterable<Suggestion> suggestions(String query) => [
    for (final f in fruit)
      if (f.label.toLowerCase().contains(query)) Suggestion(f.label),
  ];
  final field = SizedBox(
    width: 20,
    child: TextField(controller: c, autofocus: true),
  );
  return fadeIn == null
      ? Autocomplete(controller: c, suggestions: suggestions, child: field)
      : Autocomplete(
          controller: c,
          suggestions: suggestions,
          popupFadeIn: fadeIn,
          child: field,
        );
}

/// Each popup: how it is built, how it is opened, and a cell of it in
/// the theme's surface, under no highlight.
final popups =
    <
      String,
      ({
        Widget Function({Duration? fadeIn}) build,
        Future<void> Function(TwkTester t) open,
        (int, int) cell,
      })
    >{
      'Select': (build: select, open: (t) => t.press('enter'), cell: (0, 2)),
      'MultiSelect': (
        build: multi,
        open: (t) => t.press('enter'),
        cell: (0, 2),
      ),
      'DatePicker': (
        build: date,
        open: (t) => t.press('alt+down'),
        cell: (1, 2),
      ),
      'Autocomplete': (
        build: complete,
        open: (t) => t.type('a'),
        cell: (0, 2),
      ),
    };

void main() {
  final surface = theme.surface.bg!;
  final background = theme.background.bg!;

  for (final MapEntry(key: name, value: popup) in popups.entries) {
    final (x, y) = popup.cell;

    testTwk("$name's popup fades in over 120 ms by default", (t) async {
      await t.pumpWidget(app(popup.build()), size: (40, 14));
      await t.pump();
      expect(t, styleAt(x, y, hasBg(background)));
      await popup.open(t);
      await t.pump();
      await t.pump(ms * 60);
      expect(
        t,
        styleAt(x, y, isNot(anyOf(hasBg(background), hasBg(surface)))),
      );
      await t.pump(ms * 60);
      await t.pump();
      expect(t, styleAt(x, y, hasBg(surface)));
    });

    testTwk("$name's popup with a popupFadeIn of zero shows at once", (
      t,
    ) async {
      await t.pumpWidget(
        app(popup.build(fadeIn: Duration.zero)),
        size: (40, 14),
      );
      await t.pump();
      await popup.open(t);
      await t.pump();
      expect(t, styleAt(x, y, hasBg(surface)));
    });
  }
}
