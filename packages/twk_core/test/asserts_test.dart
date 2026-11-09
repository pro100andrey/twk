import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  test('the probe answers true under dart test, and the pipeline reads it', () {
    expect(debugAssertsEnabled, isTrue);
    expect(PipelineOwner.debugOverflowIndicatorByDefault, isTrue);
  });
}
