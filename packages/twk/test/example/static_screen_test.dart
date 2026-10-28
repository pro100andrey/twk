// The static screen of example/static_screen.dart, full screen and inline:
// a header, two boxes of wrapped text side by side, a footer; q quits.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/static_screen.dart' show StaticScreen;

void main() {
  testTwk('full screen, the boxes share the width and take the lines the '
      'header and the footer leave', (t) async {
    await t.pumpWidget(const StaticScreen(), size: (50, 16));
    expect(
      t,
      matchesScreen('''
 twk  widgets for terminal UIs
╭ Layout ───────────────╮ ╭ Text ────────────────╮
│ A Column stacks the   │ │ Text breaks its      │
│ header, this row and  │ │ lines between words  │
│ the footer, and       │ │ to fit its box.      │
│ Expanded gives the    │ │ Resize the terminal: │
│ row the lines the     │ │ the boxes share the  │
│ other two leave. In   │ │ new width and the    │
│ the row two Expanded  │ │ text is wrapped      │
│ boxes share the       │ │ again.               │
│ width, a gap of one   │ │                      │
│ cell between them.    │ │                      │
│                       │ │                      │
│                       │ │                      │
╰───────────────────────╯ ╰──────────────────────╯
q quit
'''),
    );
    expect(t, styleAt(1, 0, hasAttr(Attr.bold | Attr.reverse)));
    expect(t, styleAt(2, 1, hasAttr(Attr.bold)));
    expect(t, styleAt(2, 15, hasAttr(Attr.dim)));
  });

  testTwk('a resize shares the new width and wraps the text again', (
    t,
  ) async {
    await t.pumpWidget(const StaticScreen(), size: (50, 16));
    await t.resize(36, 16);
    await t.pump();
    expect(
      t,
      matchesScreen('''
 twk  widgets for terminal UIs
╭ Layout ────────╮ ╭ Text ─────────╮
│ A Column       │ │ Text breaks   │
│ stacks the     │ │ its lines     │
│ header, this   │ │ between words │
│ row and the    │ │ to fit its    │
│ footer, and    │ │ box. Resize   │
│ Expanded gives │ │ the terminal: │
│ the row the    │ │ the boxes     │
│ lines the      │ │ share the new │
│ other two      │ │ width and the │
│ leave. In the  │ │ text is       │
│ row two        │ │ wrapped       │
│ Expanded boxes │ │ again.        │
╰────────────────╯ ╰───────────────╯
q quit
'''),
    );
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(const StaticScreen());
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  testTwk('inline, the screen is as tall as the text in its boxes, below the '
      'history, and stays there when q quits', (t) async {
    await t.pumpWidget(
      const StaticScreen(),
      size: (50, 24),
      mode: ScreenMode.inline,
      history: [r'$ dart run example/static_screen.dart --inline'],
    );
    await t.press('q');
    expect(t.isRunning, isFalse);
    expect(
      t,
      matchesScreen(r'''
$ dart run example/static_screen.dart --inline
 twk  widgets for terminal UIs
╭ Layout ───────────────╮ ╭ Text ────────────────╮
│ A Column stacks the   │ │ Text breaks its      │
│ header, this row and  │ │ lines between words  │
│ the footer, and       │ │ to fit its box.      │
│ Expanded gives the    │ │ Resize the terminal: │
│ row the lines the     │ │ the boxes share the  │
│ other two leave. In   │ │ new width and the    │
│ the row two Expanded  │ │ text is wrapped      │
│ boxes share the       │ │ again.               │
│ width, a gap of one   │ │                      │
│ cell between them.    │ │                      │
╰───────────────────────╯ ╰──────────────────────╯
q quit
'''),
    );
  });
}
