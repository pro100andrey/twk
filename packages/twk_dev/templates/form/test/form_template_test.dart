import 'package:form_template/form_template.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  test('a name is not blank, an email has one @ between text, an age is '
      '18 or more', () {
    expect(validateName(' '), 'a name, please');
    expect(validateName('Ann'), isNull);
    expect(validateEmail('ann'), 'an email: a@b');
    expect(validateEmail('ann@example.com'), isNull);
    expect(validateAge(17), '18 or older');
    expect(validateAge(18), isNull);
  });

  testTwk('Ctrl+S on an empty form says what is wrong under each field', (
    t,
  ) async {
    await t.pumpWidget(const SignupForm(), size: (60, 14));
    await t.press('ctrl+s');
    await t.pump();
    expect(t, containsLine(contains('a name, please')));
    expect(t, containsLine(contains('an email: a@b')));
    expect(find.byType(StatusMessage), findsNothing);
  });

  testTwk('Enter goes from field to field; once all are right the button '
      'signs up', (t) async {
    await t.pumpWidget(const SignupForm(), size: (60, 14));
    await t.type('Ann');
    await t.press('enter');
    await t.type('ann@example.com');
    await t.press('enter');
    // Down steps the age down: 29
    await t.press('down enter');
    await t.pump();
    // on the checkbox, which keeps Enter: Space checks it, Tab goes on
    await t.press('space tab enter');
    await t.pump();
    expect(
      t,
      containsLine(
        '✓ Signed up: Ann <ann@example.com>, 29, with the newsletter',
      ),
    );
  });

  testTwk('once submitted, an age under 18 is said so as it changes', (
    t,
  ) async {
    await t.pumpWidget(const SignupForm(), size: (60, 14));
    await t.press('ctrl+s');
    await t.press('tab tab');
    for (var i = 0; i < 13; i++) {
      await t.press('down');
    }
    await t.pump();
    expect(t, containsLine(contains('age    17')));
    expect(t, containsLine(contains('18 or older')));
  });

  testTwk('the fields take q; Ctrl+Q quits', (t) async {
    await t.pumpWidget(const SignupForm());
    await t.type('q');
    await t.pump();
    expect(t, containsLine(contains('name   q')));
    await t.press('ctrl+q');
    expect(t.isRunning, isFalse);
  });
}
