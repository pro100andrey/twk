// Link: its URL as a hyperlink, and, as the design draws it, lighter and
// bold while the mouse is over it; with no hover the mouse left to the
// terminal.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show MouseTracking, MouseTrackingBackend;
import 'package:twk_test/twk_test.dart';

const ThemeData theme = ThemeData.dark;
final Color primary = theme.primary.fg!;

/// [child] at the top left, as small as it is, in the dark theme.
Widget dark(Widget child) => Theme(
  data: theme,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [child],
  ),
);

MouseTracking tracking(TwkTester t) =>
    (t.binding.twkApp.terminal as MouseTrackingBackend).mouseTracking;

void main() {
  testTwk('primary and underlined; the mouse over it takes its color 0.35 '
      'of the way to the text color, in bold, and back as it leaves', (
    t,
  ) async {
    await t.pumpWidget(
      dark(const Link('https://dart.dev', text: 'Dart')),
      size: (10, 2),
    );
    final rest = allOf(
      hasFg(primary),
      hasAttr(Attr.underline),
      isNot(hasAttr(Attr.bold)),
    );
    expect(t, styleAt(1, 0, rest));
    await t.mouse(MouseKind.move, 1, 0);
    await t.pump();
    // 0x5fa8ff 0.35 of the way to 0xe6e8eb
    expect(
      t,
      styleAt(
        1,
        0,
        allOf(
          hasFg(const Color.rgb(0x8e, 0xbe, 0xf8)),
          hasAttr(Attr.bold | Attr.underline),
        ),
      ),
    );
    await t.mouse(MouseKind.move, 8, 1);
    await t.pump();
    expect(t, styleAt(1, 0, rest));
  });

  testTwk('an empty hoverStyle: no hover, and the mouse unread', (t) async {
    await t.pumpWidget(
      dark(const Link('https://dart.dev', text: 'Dart', hoverStyle: Style())),
      size: (10, 2),
    );
    expect(tracking(t), MouseTracking.off);
    expect(t, styleAt(1, 0, allOf(hasFg(primary), isNot(hasAttr(Attr.bold)))));
  });
}
