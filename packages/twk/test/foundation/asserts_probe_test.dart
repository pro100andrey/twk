import 'package:test/test.dart';
import 'package:twk/twk.dart' as twk;
import 'package:twk_core/twk_core.dart' as core;

void main() {
  test('twk and twk_core give one answer to "are asserts on"', () {
    expect(twk.debugAssertsEnabled, isTrue);
    expect(twk.debugAssertsEnabled, core.debugAssertsEnabled);
  });
}
