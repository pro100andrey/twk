import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  late BuildContext captured;

  Tree show() {
    final tree = Tree()
      ..pump(
        _Marker(
          1,
          child: _Holder((context) {
            captured = context;
            context.dependOnInheritedWidgetOfExactType<_Marker>();
          }),
        ),
      );
    return tree;
  }

  final lookups = <String, void Function(BuildContext)>{
    'dependOnInheritedWidgetOfExactType': (c) =>
        c.dependOnInheritedWidgetOfExactType<_Marker>(),
    'getInheritedWidgetOfExactType': (c) =>
        c.getInheritedWidgetOfExactType<_Marker>(),
    'getElementForInheritedWidgetOfExactType': (c) =>
        c.getElementForInheritedWidgetOfExactType<_Marker>(),
    'findAncestorWidgetOfExactType': (c) =>
        c.findAncestorWidgetOfExactType<_Marker>(),
    'findAncestorStateOfType': (c) => c.findAncestorStateOfType<_HolderState>(),
    'visitAncestorElements': (c) => c.visitAncestorElements((e) => true),
  };

  for (final MapEntry(:key, :value) in lookups.entries) {
    test('$key from an unmounted element fails an assert with a hint', () {
      show().pump(const Leaf('gone'));
      expect(
        () => value(captured),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            allOf(contains(key), contains('didChangeDependencies')),
          ),
        ),
      );
    });
  }

  test('a lookup in dispose fails the same way', () {
    final tree = Tree()
      ..pump(
        _Marker(
          1,
          child: _Holder((_) {}, onDispose: (c) => lookups.values.first(c)),
        ),
      );
    expect(
      () => tree.pump(const Leaf('gone')),
      throwsA(isA<AssertionError>()),
    );
  });

  test('lookups while active, in initState and in build still work', () {
    final tree = show();
    expect(captured.getInheritedWidgetOfExactType<_Marker>(), isNotNull);
    expect(captured.findAncestorWidgetOfExactType<_Marker>(), isNotNull);
    expect(tree.root, isNotNull);
  });
}

final class _Marker extends InheritedWidget {
  const _Marker(this.value, {required super.child});

  final int value;

  @override
  bool updateShouldNotify(_Marker oldWidget) => value != oldWidget.value;
}

final class _Holder extends StatefulWidget {
  const _Holder(this.onBuild, {this.onDispose});

  final void Function(BuildContext) onBuild;
  final void Function(BuildContext)? onDispose;

  @override
  State<_Holder> createState() => _HolderState();
}

final class _HolderState extends State<_Holder> {
  @override
  void dispose() {
    widget.onDispose?.call(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild(context);
    return const Leaf('holder');
  }
}
