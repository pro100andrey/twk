// kReleaseMode and kDebugMode, the build's mode as constants; and the three
// value typedefs that go with VoidCallback.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  test('a test runs in debug mode: kDebugMode, not kReleaseMode', () {
    expect(kReleaseMode, isFalse);
    expect(kDebugMode, isTrue);
  });

  test('ValueChanged, ValueGetter and ValueSetter name the function types', () {
    final seen = <int>[];
    ValueChanged<int> changed = seen.add;
    ValueGetter<int> get = () => seen.length;
    ValueSetter<int> set = seen.add;
    changed(1);
    set(2);
    expect(get(), 2);
    expect(seen, [1, 2]);
  });
}
