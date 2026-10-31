// The testing guide's tests (doc/guides/testing.md): the input and focus
// guide's form filled in from the keyboard and with the mouse, read through
// the screen and through its widgets.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/guides/focus.dart' show SignIn;

void main() {
  testTwk('the name, Tab, the password, and Ctrl+S saves', (t) async {
    await t.pumpWidget(const SignIn(), size: (40, 10));
    await t.type('ann');
    await t.press('tab');
    await t.type('secret');
    await t.press('ctrl+s');
    await t.pump();
    expect(t, containsLine(contains('hi, ann')));
    expect(t, containsLine(contains('Password ••••••')));

    // the second field holds what the screen hides
    final password = t.widget<TextField>(find.byType(TextField).at(1));
    expect(password.controller!.text, 'secret');
  });

  testTwk('a click on the button with no name asks for one', (t) async {
    await t.pumpWidget(const SignIn(), size: (40, 10));
    // a Button draws its label itself: find.text finds Texts only
    final button = find.byWidgetPredicate(
      (w) => w is Button && w.label == 'Sign in',
      description: 'the Sign in button',
    );
    await t.clickOn(button);
    await t.pump();
    expect(find.text('a name, please'), findsOneWidget);

    // the status shows on the button's row, after it
    final status = t.rect(find.text('a name, please'));
    expect(status.y, t.rect(button).y);
    expect(t, hasTextAt(status.x, status.y, 'a name, please'));
  });
}
