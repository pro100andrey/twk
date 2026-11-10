import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// [object], disposed when the test ends (a tear-down), and returned.
///
/// For a controller or a node made where it is used, so the test does not
/// leave it undisposed: `trackDisposables` of `testTwk` fails a test that does.
T disposing<T extends ChangeNotifier>(T object) {
  addTearDown(object.dispose);
  return object;
}
