import 'package:test/test.dart';
import 'package:twk_core/src/byte_sink.dart';

void main() {
  test('the view is reused while the length is the same', () {
    final sink = ByteSink(8)..ascii('abc');
    final a = sink.view;
    expect(String.fromCharCodes(a), 'abc');
    expect(identical(sink.view, a), isTrue);
    sink
      ..reset()
      ..ascii('xyz');
    expect(String.fromCharCodes(sink.view), 'xyz');
    sink.ascii('0123456789'); // grows: a new buffer, a new view
    expect(String.fromCharCodes(sink.view), 'xyz0123456789');
  });

  test('grows from any initial capacity', () {
    for (final capacity in [0, 1, 3]) {
      final sink = ByteSink(capacity)
        ..ascii('hello')
        ..decimal(12345);
      expect(String.fromCharCodes(sink.view), 'hello12345');
    }
  });
}
