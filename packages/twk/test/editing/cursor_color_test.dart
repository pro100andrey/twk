// The terminal's cursor color a focused TextField and TextArea ask for: the
// theme's (ThemeData.cursorColor), written with the caret and given back
// when another caret shows the terminal's own.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const _orange = Color.rgb(0xff, 0x5f, 0x00);
const _set = '\x1b]12;#ff5f00\x1b\\';
const _reset = '\x1b]112\x1b\\';

String _written(TwkTester t) => t.terminal.frames.map(latin1.decode).join();

Color? _asked(TwkTester t) => t.binding.twkApp.screen.presenter.cursorColor;

void main() {
  for (final area in [false, true]) {
    final name = area ? 'TextArea' : 'TextField';
    Widget editor(TextEditingController c) => area
        ? TextArea(controller: c, autofocus: true)
        : TextField(controller: c, autofocus: true);

    testTwk("a $name with the focus asks for the theme's cursor color, "
        "written once, and the terminal's own back when the theme has none", (
      t,
    ) async {
      final c = TextEditingController(text: 'ab');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark.copyWith(cursorColor: _orange),
          child: editor(c),
        ),
        size: (10, 2),
      );
      expect(_asked(t), _orange);
      expect(RegExp(RegExp.escape(_set)).allMatches(_written(t)), hasLength(1));
      await t.type('c');
      await t.pump();
      expect(
        RegExp(RegExp.escape(_set)).allMatches(_written(t)),
        hasLength(1),
        reason: 'not again while it stays',
      );
      expect(_written(t), isNot(contains(_reset)));
      // the theme without one: the next caret shows the terminal's own
      await t.pumpWidget(
        Theme(data: ThemeData.dark, child: editor(c)),
      );
      expect(_asked(t), isNull);
      expect(_written(t), contains(_reset));
    });

    testTwk('a $name under a theme without a cursor color writes none', (
      t,
    ) async {
      final c = TextEditingController(text: 'ab');
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme(data: ThemeData.dark, child: editor(c)),
        size: (10, 2),
      );
      expect(_asked(t), isNull);
      expect(_written(t), isNot(contains(']12;')));
      expect(_written(t), isNot(contains(']112')));
    });
  }

  test('ThemeData.cursorColor is kept by copyWith, compared and blended', () {
    final a = ThemeData.dark.copyWith(cursorColor: _orange);
    expect(a.cursorColor, _orange);
    expect(a.copyWith(brightness: Brightness.light).cursorColor, _orange);
    expect(a == ThemeData.dark, isFalse);
    expect(a.hashCode == ThemeData.dark.hashCode, isFalse);
    final b = ThemeData.dark.copyWith(cursorColor: const Color.rgb(0, 0, 0));
    expect(ThemeData.lerp(a, b, 0.5).cursorColor, const Color.rgb(128, 48, 0));
    expect(ThemeData.lerp(a, ThemeData.dark, 0.25).cursorColor, _orange);
    expect(ThemeData.lerp(a, ThemeData.dark, 0.75).cursorColor, isNull);
  });
}
