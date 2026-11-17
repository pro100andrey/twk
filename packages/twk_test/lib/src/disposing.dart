import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// [object], disposed when the test ends (a tear-down), and returned.
///
/// For a controller or a node made where it is used, so the test does not
/// leave it undisposed, which `testTwk` fails a test for (`trackDisposables`):
///
/// ```dart
/// testTwk('typing fills the field', (t) async {
///   final name = disposing(TextEditingController());
///   await t.pumpWidget(TextField(controller: name));
///   await t.type('Ann');
///   expect(name.text, 'Ann');
/// });
/// ```
///
/// A cascade works on the result: `disposing(TreeController())..expand('a')`.
T disposing<T extends ChangeNotifier>(T object) {
  addTearDown(object.dispose);
  return object;
}
