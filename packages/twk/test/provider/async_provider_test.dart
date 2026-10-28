// FutureProvider and StreamProvider: the initial data, then what the
// future or the stream gives, its errors, and when it is listened to.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

Widget _watcher(List<String> log) =>
    Built('watcher', log, (context) => Text('${context.watch<int>()}'));

void main() {
  group('FutureProvider', () {
    testTwk('provides initialData until the future completes, then its '
        'value; the future is made when the value is first read', (t) async {
      final log = <String>[];
      final completer = Completer<int>();
      Widget app(Widget child) => FutureProvider<int>(
        create: (_) {
          log.add('created');
          return completer.future;
        },
        initialData: 0,
        child: child,
      );
      await t.pumpWidget(app(const Text('-')), size: (4, 1));
      expect(log, isEmpty);
      await t.pumpWidget(app(_watcher(log)));
      expect(t.lines, ['0']);
      expect(log, ['watcher', 'created']);
      log.clear();
      await t.act(() => completer.complete(5));
      expect(t.lines, ['5']);
      expect(log, ['watcher']);
    });

    testTwk('catchError gives the value in place of an error', (t) async {
      // made in the app's zone, which an error does not leave
      late Completer<int> completer;
      await t.pumpWidget(
        FutureProvider<int>(
          create: (_) => (completer = Completer()).future,
          initialData: 0,
          catchError: (_, error) => -1,
          child: _watcher([]),
        ),
        size: (4, 1),
      );
      await t.act(() => completer.completeError(StateError('boom')));
      expect(t.lines, ['-1']);
    });

    testTwk('without catchError, an error is logged and the value stays', (
      t,
    ) async {
      late Completer<int> completer;
      await t.pumpWidget(
        FutureProvider<int>(
          create: (_) => (completer = Completer()).future,
          initialData: 3,
          child: _watcher([]),
        ),
        size: (4, 1),
      );
      await t.act(() => completer.completeError(const FormatException('x')));
      expect(t.lines, ['3']);
      expect(loggedErrors(t), [isA<FormatException>()]);
    });

    testTwk('with a value, listens to it when it is placed in the tree; a '
        'new future replaces it, what the old one gives is ignored', (
      t,
    ) async {
      final first = Completer<int>();
      final second = Completer<int>();
      final child = _watcher([]);
      await t.pumpWidget(
        FutureProvider.value(
          value: first.future,
          initialData: 0,
          child: child,
        ),
        size: (4, 1),
      );
      await t.pumpWidget(
        FutureProvider.value(
          value: second.future,
          initialData: 0,
          child: child,
        ),
      );
      await t.act(() => first.complete(1));
      expect(t.lines, ['0']);
      await t.act(() => second.complete(2));
      expect(t.lines, ['2']);
    });

    testTwk('a future that ends after the provider left the tree sets '
        'nothing: its value, its error, catchError', (t) async {
      final log = <String>[];
      // made in the app's zone, which an error does not leave
      late Completer<int> value;
      late Completer<int> caught;
      late Completer<int> logged;
      await t.pumpWidget(
        Column(
          children: [
            FutureProvider<int>(
              create: (_) => (value = Completer()).future,
              initialData: 0,
              child: _watcher(log),
            ),
            FutureProvider<int>(
              create: (_) => (caught = Completer()).future,
              initialData: 0,
              catchError: (_, e) {
                log.add('catchError');
                return -1;
              },
              child: _watcher(log),
            ),
            FutureProvider<int>(
              create: (_) => (logged = Completer()).future,
              initialData: 0,
              child: _watcher(log),
            ),
          ],
        ),
        size: (4, 3),
      );
      expect([for (final l in t.lines) l.trim()], ['0', '0', '0']);
      await t.pumpWidget(const Text('gone'));
      log.clear();
      await t.act(() {
        value.complete(5);
        caught.completeError(StateError('boom'));
        logged.completeError(StateError('boom'));
      });
      expect(t.lines.first, 'gone');
      expect(log, isEmpty);
      expect(loggedErrors(t), isEmpty);
    });
  });

  group('StreamProvider', () {
    testTwk('provides initialData, then each value the stream gives that '
        'is not == the last; the stream is listened to from the first '
        'read until the provider leaves the tree', (t) async {
      final log = <String>[];
      final controller = StreamController<int>();
      addTearDown(controller.close);
      await t.pumpWidget(
        StreamProvider<int>(
          create: (_) => controller.stream,
          initialData: 0,
          child: _watcher(log),
        ),
        size: (4, 1),
      );
      expect(t.lines, ['0']);
      expect(controller.hasListener, isTrue);
      log.clear();
      await t.act(() => controller.add(4));
      expect(t.lines, ['4']);
      await t.act(() => controller.add(4));
      expect(log, ['watcher']);
      await t.pumpWidget(const Text('gone'));
      expect(controller.hasListener, isFalse);
    });

    testTwk('catchError gives the value in place of an error', (t) async {
      final controller = StreamController<int>();
      addTearDown(controller.close);
      await t.pumpWidget(
        StreamProvider<int>.value(
          value: controller.stream,
          initialData: 0,
          catchError: (_, error) => 99,
          child: _watcher([]),
        ),
        size: (4, 1),
      );
      await t.act(() => controller.addError(StateError('boom')));
      expect(t.lines, ['99']);
    });
  });
}
