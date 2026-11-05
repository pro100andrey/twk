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
    expect(t, containsLine(contains('Yes')));
    expect(t, containsLine(contains('No')));
    expect(t, containsLine(contains('for good?')));
  });

  testTwk('yes: and no: label the answers; y and n still answer', (t) async {
    bool? result;
    var done = false;
    await t.pumpWidget(
      Overlay(
        child: Builder(
          builder: (context) => KeyBindings({
            'd': () => unawaited(
              showConfirm(
                context,
                'Delete 3 files?',
                yes: 'Delete',
                no: 'Keep',
              ).then((v) {
                result = v;
                done = true;
              }),
            ),
          }, child: const Text('under')),
        ),
      ),
      size: (40, 12),
    );
    await t.press('d');
    await t.pump(const Duration(milliseconds: 200));
    expect(t, containsLine(contains('Delete')));
    expect(t, containsLine(contains('Keep')));
    expect(t, isNot(containsLine(contains('Yes'))));
    expect(t, isNot(containsLine(contains('No '))));
    await t.press('n');
    await t.pump(const Duration(milliseconds: 200));
    expect(done, isTrue);
    expect(result, isFalse);
  });
}
