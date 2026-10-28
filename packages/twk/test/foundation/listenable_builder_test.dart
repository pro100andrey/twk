import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  group('a ListenableBuilder', () {
    test('rebuilds in the next frame when its listenable notifies, once for '
        'any number of notifications', () {
      final log = <String>[];
      final notifier = ChangeNotifier();
      final tree = _Tree()
        ..pump(
          ListenableBuilder(
            listenable: notifier,
            builder: (context, child) => _Logged('built', log),
          ),
        );
      expect(log, ['built build']);
      log.clear();
      notifier
        ..notifyListeners()
        ..notifyListeners();
      expect(log, isEmpty);
      tree.frame();
      expect(log, ['built build']);
    });

    test('rebuilds only its subtree, not the child it hands to its '
        'builder', () {
      final log = <String>[];
      final notifier = ChangeNotifier();
      final tree = _Tree()
        ..pump(
          _Logged(
            'parent',
            log,
            ListenableBuilder(
              listenable: notifier,
              builder: (context, child) {
                log.add('builder');
                return _Logged('inner', log, child!);
              },
              child: _Logged('child', log),
            ),
          ),
        );
      expect(log, [
        'parent build',
        'builder',
        'inner build',
        'child build',
      ]);
      log.clear();
      notifier.notifyListeners();
      tree.frame();
      expect(log, ['builder', 'inner build']);
    });

    test('listens to the listenable of a new widget instead of the old '
        'one', () {
      final log = <String>[];
      final a = ChangeNotifier();
      final b = ChangeNotifier();
      Widget builder(Listenable listenable) => ListenableBuilder(
        listenable: listenable,
        builder: (context, child) => _Logged('built', log),
      );
      final tree = _Tree()..pump(builder(a));
      expect(a.hasListeners, isTrue);
      tree.pump(builder(b));
      expect(a.hasListeners, isFalse);
      expect(b.hasListeners, isTrue);
      log.clear();
      b.notifyListeners();
      tree.frame();
      expect(log, ['built build']);
    });

    test('stops listening when its element is unmounted', () {
      final notifier = ChangeNotifier();
      final tree = _Tree()
        ..pump(
          ListenableBuilder(
            listenable: notifier,
            builder: (context, child) => const _Leaf(),
          ),
        );
      expect(notifier.hasListeners, isTrue);
      tree.pump(const _Leaf());
      expect(notifier.hasListeners, isFalse);
    });
  });

  group('a ValueListenableBuilder', () {
    test('builds with the value and again with each new one, not the child '
        'it hands to its builder', () {
      final log = <String>[];
      final notifier = ValueNotifier(1);
      final tree = _Tree()
        ..pump(
          ValueListenableBuilder<int>(
            valueListenable: notifier,
            builder: (context, value, child) {
              log.add('builder $value');
              return _Logged('inner', log, child!);
            },
            child: _Logged('child', log),
          ),
        );
      expect(log, ['builder 1', 'inner build', 'child build']);
      log.clear();
      notifier.value = 2;
      tree.frame();
      expect(log, ['builder 2', 'inner build']);
    });

    test('listens to the listenable of a new widget instead of the old one, '
        'and stops when its element is unmounted', () {
      final log = <String>[];
      final a = ValueNotifier('a');
      final b = ValueNotifier('b');
      Widget builder(ValueListenable<String> listenable) =>
          ValueListenableBuilder<String>(
            valueListenable: listenable,
            builder: (context, value, child) {
              log.add(value);
              return const _Leaf();
            },
          );
      final tree = _Tree()
        ..pump(builder(a))
        ..pump(builder(b));
      expect(log, ['a', 'b']);
      expect(a.hasListeners, isFalse);
      b.value = 'c';
      tree.frame();
      expect(log, ['a', 'b', 'c']);
      tree.pump(const _Leaf());
      expect(b.hasListeners, isFalse);
    });
  });
}

/// A tree under one [BuildOwner], pumped the way a frame loop does.
final class _Tree {
  final owner = BuildOwner();
  RootElement? _root;

  /// Shows [widget] at the top of the tree and runs a frame.
  void pump(Widget widget) {
    _root = RootWidget(child: widget).attach(owner, _root);
    frame();
  }

  /// Rebuilds what is dirty, then unmounts what was removed.
  void frame() {
    owner
      ..buildScope()
      ..finalizeTree();
  }
}

/// Logs each build as `<name> build`, and shows [child].
final class _Logged extends StatelessWidget {
  const _Logged(this.name, this.log, [this.child = const _Leaf()]);

  final String name;
  final List<String> log;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    log.add('$name build');
    return child;
  }
}

final class _Leaf extends LeafRenderObjectWidget {
  const _Leaf();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLeaf();
}

final class _RenderLeaf extends RenderObject {
  @override
  void performLayout(BoxConstraints c) {
    width = c.minW;
    height = c.minH;
  }

  @override
  void paint(PaintContext ctx) {}
}
