// requestFocus on a disposed node is a bug of its owner, asserted; on a node
// not attached yet it stays the no-op it is documented to be.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  test('requestFocus on a node not attached is a no-op', () {
    final node = FocusNode()..requestFocus();
    expect(node.hasFocus, isFalse);
    node.dispose();
  });

  test('requestFocus after dispose asserts, naming the node', () {
    final node = FocusNode(debugLabel: 'gone')..dispose();
    expect(
      node.requestFocus,
      throwsA(
        isA<AssertionError>().having(
          (e) => '${e.message}',
          'message',
          allOf(contains('FocusNode(gone)'), contains('after dispose')),
        ),
      ),
    );
  });

  test('a scope requested after dispose asserts too', () {
    final scope = FocusScopeNode()..dispose();
    expect(scope.requestFocus, throwsA(isA<AssertionError>()));
  });

  test('giveBack skips a fallback disposed meanwhile, silently', () {
    final fallback = FocusScopeNode(debugLabel: 'gone')..dispose();
    expect(FocusNode.giveBack(null, fallback), isFalse);
  });
}
