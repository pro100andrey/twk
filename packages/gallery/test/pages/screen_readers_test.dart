// The Screen readers › Semantics page: the lines a screen reader reads of
// its form, each control in one of them, as its options change them.
import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

/// What the page shows over the lines a screen reader reads.
const _over = 'A screen reader reads:';

/// Opens the page, its options at [options] (a route's `o=`), in a
/// terminal of 120 × 36.
Future<void> _open(TwkTester t, [String options = '']) async {
  final o = options.isEmpty ? '' : '&o=$options';
  await t.pumpWidget(
    galleryApp(
      route: GalleryRoute.parse('#/screen-readers/semantics?t=2000$o'),
    ),
    size: (120, 36),
  );
  // the page reads its form at the start of the frame after the one that
  // built it
  await t.pump();
  await t.pump();
}

/// The lines the page shows under [_over], up to the first blank one or
/// the bottom of the box around the page, each cut at the stage's border.
List<String> _read(TwkTester t) {
  final row = t.lines.indexWhere((line) => line.contains(_over));
  expect(row, isNonNegative, reason: 'the page shows "$_over"');
  final column = t.lines[row].indexOf(_over);
  final lines = <String>[];
  for (final line in t.lines.skip(row + 1)) {
    final read = line.substring(column).split('│').first.trim();
    if (read.isEmpty || line.contains('└')) {
      break;
    }
    lines.add(read);
  }
  return lines;
}

void main() {
  testTwk('a screen reader reads each control of the form in one line, '
      'the dialog alone over the page under it', (t) async {
    await _open(t);
    expect(_read(t), [
      'heading Sign in',
      'checkbox Remember me, not checked',
      'switch Dark mode, on',
      'progressbar Upload: 40%',
      'button More',
      'button Cancel',
      'dialog Popup',
      'the notice on top',
    ]);
  });

  testTwk('without BlockSemantics the page under the dialog is read too; '
      'without its label the bar is read by its value', (t) async {
    await _open(t, 'block:false;label:false');
    expect(_read(t), [
      'heading Sign in',
      'checkbox Remember me, not checked',
      'switch Dark mode, on',
      'progressbar 40%',
      'button More',
      'button Cancel',
      'dialog Popup',
      'the page under it',
      'the notice on top',
    ]);
  });

  testTwk('a press of More moves the bar on, read once still', (t) async {
    await _open(t);
    // the focus from the list to the checkbox, the switch, then More
    for (final key in ['tab', 'tab', 'tab', 'enter']) {
      await t.press(key);
      await t.pump();
    }
    await t.pump();
    expect(
      _read(t).where((line) => line.startsWith('progressbar')),
      ['progressbar Upload: 50%'],
    );
  });
}
