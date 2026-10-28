// ControllerHost: the host attached last is the host, whoever had it; a
// host detaching lets go for itself alone; what is to happen when none
// takes over runs after the build, only then and not once disposed.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

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
}
