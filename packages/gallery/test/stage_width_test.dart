// No page's stage widens with the screen: what a page shows has a width
// of its own, as it would in an app, not the stage's. Each page shown on
// a screen of 200 and of 253 columns, wide enough for any page's own
// width, says the same stage size (its `W × H` under the stage); a page
// whose stage shows no size is not held to it. ListTile's list once took
// the whole stage, 181 columns of it on a wide terminal.
import 'package:gallery/testing.dart';
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

import 'support/gallery.dart';

final _size = RegExp(r'(\d+) × (\d+)');

/// The stage size shown under the page at [route], or null where none.
Future<String?> _stage(TwkTester t, String route) async {
  await showRoute(t, route);
  for (final line in t.lines.reversed) {
    final size = _size.allMatches(line).lastOrNull;
    if (size != null) {
      return '${size[1]} × ${size[2]}';
    }
  }
  return null;
}

void main() {
  for (final place in pagePlaces) {
    testTwk('${place.path} is as wide on a wider screen', (t) async {
      final wide = await _stage(t, '#/${place.path}?size=200x36');
      final wider = await _stage(t, '#/${place.path}?size=253x36');
      expect(wider, wide);
      takeOwnError(t, place.path);
    });
  }
}
