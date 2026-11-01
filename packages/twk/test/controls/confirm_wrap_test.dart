// showConfirm with a question longer than the dialog: it wraps above the
// answers, which stay in the dialog.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('a long question wraps and both answers are shown', (t) async {
    await t.pumpWidget(
      Overlay(
        child: Builder(
          builder: (context) => KeyBindings({
            'd': () => unawaited(
              showConfirm(
                context,
                'Do you really want to delete all of the files in this '
                'directory and everything below it, for good?',
              ),
            ),
          }, child: const Text('under')),
        ),
      ),
      size: (40, 12),
    );
    await t.press('d');
    await t.pump(const Duration(milliseconds: 200));
    final text = t.lines.join('\n');
    expect(text, contains('Yes'));
    expect(text, contains('No'));
    expect(text, contains('for good?'));
  });
}
