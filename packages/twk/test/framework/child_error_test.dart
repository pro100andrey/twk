// What a child throws while an element updates it — its createRenderObject,
// updateRenderObject or initState — is shown like a build that threw, by
// the nearest component element above it; what a rebuild throws past that
// as well; and an exception that escapes a build scope leaves the elements
// it did not reach to the next one.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

/// A tree whose owner records each error as `element: error` in the list
/// that comes with it, and shows `error` in its place.
(Tree, List<String>) reporting() {
  final reports = <String>[];
  final tree = Tree(
    onBuildError: (element, error, stack) {
      reports.add('$element: $error');
      return const Leaf('error');
    },
  );
  return (tree, reports);
}

/// The labels of the children of the [TestMulti] at the top of [tree].
List<String> labels(Tree tree) => [
  for (final c in (tree.host.child! as TestMulti).children) '$c',
];

/// A leaf whose createRenderObject throws.
final class _BadCreate extends LeafRenderObjectWidget {
  const _BadCreate();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      throw StateError('create');
}

/// A [Leaf] whose updateRenderObject throws when [throws] is set.
final class _BadUpdate extends LeafRenderObjectWidget {
  const _BadUpdate(this.label, {this.throws = false});

  final String label;
  final bool throws;

  @override
  TestLeaf createRenderObject(BuildContext context) => TestLeaf(label);

  @override
  void updateRenderObject(BuildContext context, TestLeaf renderObject) {
    if (throws) {
      throw StateError('update');
    }
    renderObject.label = label;
  }
}

/// A state whose initState throws; its deactivate and dispose are logged.
final class _BadInit extends StatefulWidget {
  const _BadInit(this.log);

  final List<String> log;

  @override
  State<_BadInit> createState() => _BadInitState();
}

final class _BadInitState extends State<_BadInit> {
  @override
  void initState() {
    super.initState();
    throw StateError('init');
  }

  @override
  void deactivate() {
    widget.log.add('deactivate');
    super.deactivate();
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Leaf('never');
}

/// An inherited [value].
final class _Value extends InheritedWidget {
  const _Value(this.value, {required super.child});

  final int value;

  @override
  bool updateShouldNotify(_Value oldWidget) => value != oldWidget.value;
}

/// A leaf labelled with the [_Value] above it, whose updateRenderObject
/// throws when that is 2.
final class _Dependent extends LeafRenderObjectWidget {
  const _Dependent();

  String _label(BuildContext context) =>
      'v${context.dependOnInheritedWidgetOfExactType<_Value>()!.value}';

  @override
  TestLeaf createRenderObject(BuildContext context) =>
      TestLeaf(_label(context));

  @override
  void updateRenderObject(BuildContext context, TestLeaf renderObject) {
    final label = _label(context);
    if (label == 'v2') {
      throw StateError('dependent');
    }
    renderObject.label = label;
  }
}

/// A leaf whose render object's layout throws.
final class _BadLayout extends LeafRenderObjectWidget {
  const _BadLayout();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBadLayout();
}

final class _RenderBadLayout extends RenderObject {
  @override
  void performLayout(BoxConstraints c) => throw StateError('layout');

  @override
  void paint(PaintContext ctx) {}
}

void main() {
  test('a createRenderObject that throws is reported for the component '
      'above, which shows what onBuildError returns; the siblings stay', () {
    final (tree, reports) = reporting();
    tree.pump(const Multi([Leaf('a'), Wrapper(_BadCreate()), Leaf('c')]));
    expect(labels(tree), ['a', 'error', 'c']);
    expect(reports, ['Wrapper: Bad state: create']);
    expect(tree.elementOf<Wrapper>().describe().flags, [DiagnosticsFlag.error]);

    // in place of a child it had
    tree
      ..pump(const Multi([Leaf('a'), Wrapper(Leaf('b')), Leaf('c')]))
      ..pump(const Multi([Leaf('a'), Wrapper(_BadCreate()), Leaf('c')]));
    expect(labels(tree), ['a', 'error', 'c']);
    expect(reports, hasLength(2));
  });

  test('what a render object widget mounted before its child threw leaves '
      'the tree, render objects and all', () {
    final (tree, reports) = reporting();
    final log = <String>[];
    tree.pump(
      Multi([
        const Leaf('x'),
        Wrapper(Multi([Leaf('a', log: log), const _BadCreate()])),
        const Leaf('y'),
      ]),
    );
    expect(labels(tree), ['x', 'error', 'y']);
    expect(log, ['unmount a']);
    expect(reports, hasLength(1));
  });

  test('a render object widget an update left half done leaves the tree '
      'with the children it held', () {
    final (tree, reports) = reporting();
    final log = <String>[];
    tree
      ..pump(Wrapper(Multi([Leaf('a', log: log), const _BadUpdate('b')])))
      ..pump(
        const Wrapper(
          Multi([OtherLeaf('a'), _BadUpdate('b', throws: true)]),
        ),
      );
    expect('${tree.host.child}', 'error');
    expect(log, ['unmount a']);
    expect(reports, ['Wrapper: Bad state: update']);
  });

  test('an updateRenderObject that throws shows the error in place of the '
      'component above; the siblings keep their render objects', () {
    final (tree, reports) = reporting();
    tree.pump(
      const Multi([Leaf('a'), Wrapper(_BadUpdate('b')), Leaf('c')]),
    );
    final before = (tree.host.child! as TestMulti).children.toList();
    tree.pump(
      const Multi([
        Leaf('a'),
        Wrapper(_BadUpdate('b', throws: true)),
        Leaf('c'),
      ]),
    );
    expect(labels(tree), ['a', 'error', 'c']);
    final after = (tree.host.child! as TestMulti).children;
    expect(after.first, same(before.first));
    expect(after.last, same(before.last));
    expect(reports, ['Wrapper: Bad state: update']);

    tree.pump(
      const Multi([Leaf('a'), Wrapper(_BadUpdate('b2')), Leaf('c')]),
    );
    expect(labels(tree), ['a', 'b2', 'c']);
    expect(tree.elementOf<Wrapper>().describe().flags, isEmpty);
  });

  test('a state whose initState threw shows the error, and is neither '
      'deactivated nor disposed when it leaves', () {
    final (tree, reports) = reporting();
    final log = <String>[];
    tree.pump(Multi([const Leaf('a'), Wrapper(_BadInit(log))]));
    expect(labels(tree), ['a', 'error']);
    expect(reports, ['Wrapper: Bad state: init']);
    tree.pump(const Multi([Leaf('a'), Wrapper(Leaf('b'))]));
    expect(labels(tree), ['a', 'b']);
    expect(log, isEmpty);
  });

  test('an updateRenderObject that throws when a dependency changed is '
      'reported for its element, the component above showing the error', () {
    final (tree, reports) = reporting();
    tree.pump(
      const _Value(
        1,
        child: Multi([Leaf('a'), Wrapper(_Dependent()), Leaf('c')]),
      ),
    );
    expect(labels(tree), ['a', 'v1', 'c']);
    tree.pump(
      const _Value(
        2,
        child: Multi([Leaf('a'), Wrapper(_Dependent()), Leaf('c')]),
      ),
    );
    expect(labels(tree), ['a', 'error', 'c']);
    expect(reports, ['_Dependent: Bad state: dependent']);
  });

  test('a build scope that an exception cut short leaves the elements it '
      'did not rebuild to the next one', () {
    final log = <String>[];
    final tree =
        Tree(
          onBuildError: (element, error, stack) =>
              Error.throwWithStackTrace(error, stack),
        )..pump(
          Multi([
            Probe(
              'b',
              log,
              builder: (s) =>
                  s.count == 1 ? throw StateError('b') : const Leaf('b'),
            ),
            Wrapper(Probe('c', log)),
          ]),
        );
    final [b, c] = tree.probes;
    b.change(() => b.count++);
    c.change(() => c.count++);
    log.clear();
    final scheduled = tree.scheduled;
    expect(tree.frame, throwsStateError);
    expect(log, ['b build']);
    expect(tree.scheduled, scheduled + 1);
    tree.frame();
    expect(log, ['b build', 'c build']);
  });

  test('without onBuildError, what a child throws while mounted goes out of '
      'the build scope, and what was mounted for it leaves the tree', () {
    final log = <String>[];
    final tree = Tree()
      ..pump(const Leaf('x'))
      ..show(
        Multi([
          const Leaf('x'),
          Wrapper(Multi([Leaf('a', log: log), const _BadCreate()])),
        ]),
      );
    expect(tree.frame, throwsStateError);
    expect(tree.host.child, isNull);
    tree.frame();
    expect(log, ['unmount a']);
  });

  test('an element whose render object shows an error says so', () {
    final tree = Tree()..pump(const Wrapper(_BadLayout()));
    final element = tree.elementOf<_BadLayout>();
    expect(
      () => element.renderObject!.layout(const BoxConstraints.tight(2, 1)),
      throwsStateError,
    );
    expect(element.describe().flags, contains(DiagnosticsFlag.error));
  });
}
