import 'package:test/test.dart';

import 'harness.dart';

void main() {
  test("setState inside the state's own build fails an assert with a hint, "
      'where the mark would be lost', () {
    final reports = <Object>[];
    final tree = Tree(
      onBuildError: (element, error, stack) {
        reports.add(error);
        return const Leaf('error');
      },
    );
    final log = <String>[];
    tree.pump(
      Probe(
        'p',
        log,
        builder: (s) {
          if (s.count == 0) {
            s.change(() => s.count++);
          }
          return Leaf('n=${s.count}');
        },
      ),
    );
    expect(reports, hasLength(1));
    expect(
      reports.single,
      isA<AssertionError>().having(
        (e) => e.message,
        'message',
        allOf(contains('inside its own build'), contains('post-frame')),
      ),
    );
  });

  test('setState outside a build rebuilds as before', () {
    final log = <String>[];
    final tree = Tree()..pump(Probe('p', log));
    log.clear();
    final state = tree.stateOf<ProbeState>();
    state.change(() => state.count++);
    tree.frame();
    expect(log, ['p build']);
  });
}
