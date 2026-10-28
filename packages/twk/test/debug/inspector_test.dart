// The Inspector on its own, for what the service extensions never hand
// it: an element without a render object, which has only its id for a
// layout, and an object that is no node, whose properties are an error.
// The rest of it is tested through the extensions, in
// binding/service_extensions_test.dart.
import 'package:test/test.dart';
import 'package:twk/src/debug/inspector.dart';
import 'package:twk/twk.dart';

/// An inspector of no tree.
Inspector empty() =>
    Inspector(root: () => null, app: () => null, hitTest: (_, _, _) {});

void main() {
  test('the layout of an element with no render object, one not mounted '
      'yet, is its id alone', () {
    final inspector = empty();
    final element = const _Label().createElement();
    expect(inspector.renderObjectOf(element), isNull);
    final id = inspector.idOf(element);
    expect(inspector.layout(element), {'id': id});
  });

  test('the properties of what is neither an element nor a render object '
      'are an ArgumentError', () {
    expect(
      () => empty().properties('a node'),
      throwsA(
        isA<ArgumentError>()
            .having((e) => e.name, 'name', 'node')
            .having((e) => e.message, 'message', 'not a node'),
      ),
    );
  });
}

/// Text, built: an element of its own with a render object only below it,
/// once mounted.
final class _Label extends StatelessWidget {
  const _Label();

  @override
  Widget build(BuildContext context) => const Text('a');
}
