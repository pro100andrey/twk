import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  group('a ChangeNotifier', () {
    test('calls its listeners in the order they were added, one added '
        'twice twice', () {
      final log = <String>[];
      void a() => log.add('a');
      final notifier = ChangeNotifier()
        ..addListener(a)
        ..addListener(() => log.add('b'))
        ..addListener(a)
        ..notifyListeners();
      expect(log, ['a', 'b', 'a']);
      log.clear();
      notifier
        ..removeListener(a)
        ..notifyListeners();
      expect(log, ['b', 'a']);
    });

    test('has listeners while any is added', () {
      void a() {}
      final notifier = ChangeNotifier();
      expect(notifier.hasListeners, isFalse);
      notifier.addListener(a);
      expect(notifier.hasListeners, isTrue);
      notifier.removeListener(() {});
      expect(notifier.hasListeners, isTrue);
      notifier.removeListener(a);
      expect(notifier.hasListeners, isFalse);
    });

    test('calls a listener added while it notifies from the next '
        'notification on', () {
      final log = <String>[];
      final notifier = ChangeNotifier();
      notifier.addListener(() {
        log.add('a');
        notifier.addListener(() => log.add('b'));
      });
      notifier.notifyListeners();
      expect(log, ['a']);
      log.clear();
      notifier.notifyListeners();
      expect(log, ['a', 'b']);
    });

    test('does not call a listener once it is removed while it notifies, '
        'and calls the others in order', () {
      final log = <String>[];
      final notifier = ChangeNotifier();
      void c() => log.add('c');
      late void Function() a;
      a = () {
        log.add('a');
        notifier
          ..removeListener(a)
          ..removeListener(c);
      };
      notifier
        ..addListener(a)
        ..addListener(() => log.add('b'))
        ..addListener(c)
        ..addListener(() => log.add('d'))
        ..notifyListeners();
      expect(log, ['a', 'b', 'd']);
      log.clear();
      notifier.notifyListeners();
      expect(log, ['b', 'd']);
    });

    test('has no listeners once the last removed itself while it '
        'notifies', () {
      final seen = <bool>[];
      final notifier = ChangeNotifier();
      late void Function() a;
      a = () {
        notifier.removeListener(a);
        seen.add(notifier.hasListeners);
      };
      notifier
        ..addListener(a)
        ..notifyListeners();
      expect(seen, [false]);
      expect(notifier.hasListeners, isFalse);
    });

    test('notified again by a listener, finishes the outer notification '
        'without the listeners removed in the inner one', () {
      final log = <String>[];
      final notifier = ChangeNotifier();
      void b() => log.add('b');
      var first = true;
      notifier
        ..addListener(() {
          log.add('a');
          if (first) {
            first = false;
            notifier
              ..removeListener(b)
              ..notifyListeners();
          }
        })
        ..addListener(b)
        ..addListener(() => log.add('c'))
        ..notifyListeners();
      expect(log, ['a', 'a', 'c', 'c']);
      log.clear();
      notifier.notifyListeners();
      expect(log, ['a', 'c']);
    });

    test('reports a listener that throws to the zone and calls the '
        'others', () {
      final log = <String>[];
      final errors = <Object>[];
      final notifier = ChangeNotifier()
        ..addListener(() => throw StateError('a'))
        ..addListener(() => log.add('b'));
      runZonedGuarded(
        notifier.notifyListeners,
        (error, _) => errors.add(error),
      );
      expect(log, ['b']);
      expect(errors, [isA<StateError>()]);
    });

    test('drops its listeners when disposed, and is not to be used again '
        'except to remove one', () {
      void a() {}
      final notifier = ChangeNotifier()
        ..addListener(a)
        ..dispose();
      expect(notifier.hasListeners, isFalse);
      notifier.removeListener(a);
      expect(() => notifier.addListener(a), throwsA(isA<AssertionError>()));
      expect(notifier.notifyListeners, throwsA(isA<AssertionError>()));
      expect(notifier.dispose, throwsA(isA<AssertionError>()));
    });

    test('is not to be disposed while it notifies', () {
      final errors = <Object>[];
      final notifier = ChangeNotifier();
      notifier.addListener(notifier.dispose);
      runZonedGuarded(
        notifier.notifyListeners,
        (error, _) => errors.add(error),
      );
      expect(errors, [isA<AssertionError>()]);
    });

    test('can be mixed in', () {
      var calls = 0;
      _Mixed()
        ..addListener(() => calls++)
        ..notifyListeners();
      expect(calls, 1);
    });
  });

  group('a ValueNotifier', () {
    test('notifies when its value is set to one not equal to it', () {
      final values = <int>[];
      final notifier = ValueNotifier(1);
      notifier
        ..addListener(() => values.add(notifier.value))
        ..value = 1
        ..value = 2
        ..value = 2
        ..value = 3;
      expect(values, [2, 3]);
      expect(notifier.value, 3);
    });

    test('is a ValueListenable', () {
      expect(ValueNotifier('a'), isA<ValueListenable<String>>());
    });
  });

  group('Listenable.merge', () {
    test('adds a listener to each listenable, skipping nulls, and removes '
        'it from each', () {
      var calls = 0;
      void listener() => calls++;
      final a = ChangeNotifier();
      final b = ValueNotifier(0);
      final merged = Listenable.merge([a, null, b])..addListener(listener);
      a.notifyListeners();
      b.value = 1;
      expect(calls, 2);
      merged.removeListener(listener);
      expect(a.hasListeners, isFalse);
      expect(b.hasListeners, isFalse);
    });
  });
}

final class _Mixed with ChangeNotifier {}
