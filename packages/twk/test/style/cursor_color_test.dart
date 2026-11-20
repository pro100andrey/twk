// The cursor color of the default theme as the binding gives it: the
// terminal's own (OSC 12), else its text color (OSC 10), else none; and what
// the terminal reports later.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The cursor color [Theme.of] gives the widget below, as of its last build.
final class _Reads extends StatelessWidget {
  const _Reads(this.seen);

  final List<Color?> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(Theme.of(context).cursorColor);
    return const Text('x');
  }
}

void main() {
  testTwk('the terminal told its cursor color: the theme has it', (t) async {
    final seen = <Color?>[];
    await t.pumpWidget(
      _Reads(seen),
      backgroundRgb: 0x16181d,
      foregroundRgb: 0xd0d0d0,
      cursorRgb: 0xff8800,
    );
    expect(seen.last, const Color.rgb(0xff, 0x88, 0x00));
  });

  testTwk('it told its text color and not its cursor color (Konsole): the '
      'cursor is the text color', (t) async {
    final seen = <Color?>[];
    await t.pumpWidget(
      _Reads(seen),
      backgroundRgb: 0x16181d,
      foregroundRgb: 0xfcfcfc,
    );
    expect(seen.last, const Color.rgb(0xfc, 0xfc, 0xfc));
  });

  testTwk('it told neither: no cursor color', (t) async {
    final seen = <Color?>[];
    await t.pumpWidget(_Reads(seen), backgroundRgb: 0x16181d);
    expect(seen.last, isNull);
  });

  testTwk('a cursor color it reports later (after a color scheme change) '
      'is taken, and the widgets reading the theme are rebuilt', (t) async {
    final seen = <Color?>[];
    await t.pumpWidget(
      _Reads(seen),
      backgroundRgb: 0x16181d,
      foregroundRgb: 0xd0d0d0,
      cursorRgb: 0xff8800,
    );
    await t.type('\x1b]12;rgb:11/22/33\x1b\\');
    await t.pump();
    expect(seen.last, const Color.rgb(0x11, 0x22, 0x33));
  });
}
