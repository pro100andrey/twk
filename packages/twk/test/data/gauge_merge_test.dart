// A line gauge keeps the styles it merges until a setter changes one of
// their inputs, and paints the new ones after the change.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show hasFg, styleAt, testTwk;

const _red = Color.rgb(255, 0, 0);
const _green = Color.rgb(0, 255, 0);
const _blue = Color.rgb(0, 0, 255);
const _grey = Color.rgb(1, 2, 3);

Widget _gauge({
  Style style = const Style(),
  Style filled = const Style(),
  Style unfilled = const Style(),
}) => LineGauge(
  ratio: 0.5,
  style: style,
  filledStyle: filled,
  unfilledStyle: unfilled,
);

void main() {
  group('LineGauge styles', () {
    testTwk('are painted anew where style, filledStyle or unfilledStyle '
        'changes, and as they were where none does', (t) async {
      Future<void> show(Widget w) => t.pumpWidget(w, size: (8, 1));
      await show(_gauge(style: const Style(fg: _grey)));
      expect(t, styleAt(0, 0, hasFg(_grey)));
      expect(t, styleAt(7, 0, hasFg(_grey)));
      // nothing changed: the same
      await show(_gauge(style: const Style(fg: _grey)));
      expect(t, styleAt(0, 0, hasFg(_grey)));
      expect(t, styleAt(7, 0, hasFg(_grey)));
      // the style under both parts
      await show(_gauge(style: const Style(fg: _red)));
      expect(t, styleAt(0, 0, hasFg(_red)));
      expect(t, styleAt(7, 0, hasFg(_red)));
      // the filled part's
      await show(
        _gauge(
          style: const Style(fg: _red),
          filled: const Style(fg: _green),
        ),
      );
      expect(t, styleAt(0, 0, hasFg(_green)));
      expect(t, styleAt(7, 0, hasFg(_red)));
      // the rest's
      await show(
        _gauge(
          style: const Style(fg: _red),
          filled: const Style(fg: _green),
          unfilled: const Style(fg: _blue),
        ),
      );
      expect(t, styleAt(0, 0, hasFg(_green)));
      expect(t, styleAt(7, 0, hasFg(_blue)));
    });
  });
}
