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
    void use(
      ValueChanged<int> changed,
      ValueSetter<int> setter,
      ValueGetter<int> getter,
    ) {
      changed(1);
      setter(2);
      expect(getter(), 2);
    }

    use(seen.add, seen.add, () => seen.length);
    expect(seen, [1, 2]);
  });
}
