// ControllerHost: the host attached last is the host, whoever had it; a
// host detaching lets go for itself alone; what is to happen when none
// takes over runs after the build, only then and not once disposed.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

import '../framework/harness.dart';

void main() {
  test('the host attached last is the host; attach returns the one it '
      'took over from, none for itself again', () {
    final hosts = ControllerHost<String>();
    expect(hosts.host, isNull);
    expect(hosts.attach('a'), isNull);
    expect(hosts.attach('a'), isNull);
    expect(hosts.attach('b'), 'a');
    expect(hosts.host, 'b');
    expect(hosts.isHost('b'), isTrue);
    expect(hosts.isHost('a'), isFalse);
  });

  test('a host detaching lets go for itself alone: one passed over '
      'changes nothing, and its orphaned callback never runs', () async {
    final hosts = ControllerHost<String>();
    final log = <String>[];
    hosts
      ..attach('old')
      ..attach('new');
    expect(hosts.detach('old', () => log.add('old orphaned')), isFalse);
    expect(hosts.host, 'new');
    await Future<void>.delayed(Duration.zero);
    expect(log, isEmpty);
  });

  test('orphaned runs after the build, unless a host attached meanwhile '
      'or the controller was disposed', () async {
    final hosts = ControllerHost<String>()..attach('a');
    final log = <String>[];
    expect(hosts.detach('a', () => log.add('orphaned')), isTrue);
    expect(hosts.host, isNull);
    expect(log, isEmpty, reason: 'not while the widgets build');
    await Future<void>.delayed(Duration.zero);
    expect(log, ['orphaned']);

    hosts
      ..attach('a')
      ..detach('a', () => log.add('taken over'))
      ..attach('b');
    await Future<void>.delayed(Duration.zero);
    expect(log, ['orphaned']);

    hosts
      ..detach('b', () => log.add('disposed'))
      ..afterBuild(() => log.add('after the build'))
      ..dispose();
    await Future<void>.delayed(Duration.zero);
    expect(log, ['orphaned']);
    expect(hosts.isDisposed, isTrue);
  });

  test('afterBuild runs in a microtask, in order', () async {
    final hosts = ControllerHost<int>();
    final log = <int>[];
    hosts
      ..afterBuild(() => log.add(1))
      ..afterBuild(() => log.add(2));
    scheduleMicrotask(() => log.add(3));
    expect(log, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(log, [1, 2, 3]);
  });

  group('two hosts in the tree at once', () {
    Future<List<Object>> errorsOf(void Function() body) async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        body();
        await Future<void>.delayed(Duration.zero);
      }, (e, _) => errors.add(e));
      return errors;
    }

    test(
      'two views of one controller fail after the build, naming both',
      () async {
        final hosts = ControllerHost<State>();
        final tree = Tree();
        final errors = await errorsOf(() {
          tree.pump(
            Multi([
              _View(hosts, key: const ValueKey('a')),
              _View(hosts, key: const ValueKey('b')),
            ]),
          );
        });
        expect(errors, hasLength(1));
        expect(errors.single, isA<StateError>());
        expect('${errors.single}', contains('two hosts'));
      },
    );

    test('a key change builds the new state before the old is disposed: '
        'no failure', () async {
      final hosts = ControllerHost<State>();
      final tree = Tree();
      final errors = await errorsOf(() {
        tree
          ..pump(_View(hosts, key: const ValueKey('a')))
          ..pump(_View(hosts, key: const ValueKey('b')))
          ..pump(Multi([_View(hosts, key: const ValueKey('c'))]))
          ..pump(Multi([_View(hosts, key: const ValueKey('d'))]));
      });
      expect(errors, isEmpty);
    });

    test('a GlobalKey reparenting moves the state and attaches no second '
        'host: no failure', () async {
      final hosts = ControllerHost<State>();
      final key = GlobalKey<State<_View>>();
      final tree = Tree();
      final errors = await errorsOf(() {
        tree
          ..pump(Multi([Single(child: _View(hosts, key: key))]))
          ..pump(Multi([Wrapper(_View(hosts, key: key))]));
      });
      expect(errors, isEmpty);
      expect(hosts.host, same(key.currentState));
    });

    test('a host that is no State needs the mounted callback to be '
        'checked', () async {
      final unknown = ControllerHost<String>();
      final live = ControllerHost<String>(mounted: (_) => true);
      final errors = await errorsOf(() {
        unknown
          ..attach('a')
          ..attach('b');
        live
          ..attach('a')
          ..attach('b');
      });
      expect(errors, hasLength(1), reason: 'only the one that can tell');
      expect(unknown.host, 'b');
      expect(live.host, 'b');
    });
  });
}

final class _View extends StatefulWidget {
  const _View(this.hosts, {super.key});

  final ControllerHost<State> hosts;

  @override
  State<_View> createState() => _ViewState();
}

final class _ViewState extends State<_View> {
  @override
  void initState() {
    super.initState();
    widget.hosts.attach(this);
  }

  @override
  void dispose() {
    widget.hosts.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Leaf('view');
}
