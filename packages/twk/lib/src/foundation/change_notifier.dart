/// Objects that call their listeners when they change: a [Listenable],
/// a [ValueListenable], and the [ChangeNotifier] and [ValueNotifier] that
/// implement them.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'listenable_builder.dart' show ListenableBuilder, ValueListenableBuilder;

/// A function with no arguments and no result, such as a listener.
typedef VoidCallback = void Function();

/// An object that calls its listeners when it changes.
///
/// See also:
///
///  * [ChangeNotifier], which implements it.
///  * [ListenableBuilder], which rebuilds what it builds when one changes.
abstract class Listenable {
  /// For subclasses.
  const Listenable();

  /// A listenable whose listeners are added to each of [listenables], the
  /// null ones skipped: they are called whenever any of them changes.
  factory Listenable.merge(Iterable<Listenable?> listenables) =
      _MergingListenable;

  /// Calls [listener] whenever this object changes.
  void addListener(VoidCallback listener);

  /// Stops calling [listener], once for each time it was added; a listener
  /// that is not added is ignored.
  void removeListener(VoidCallback listener);
}

/// A [Listenable] with a current [value], whose listeners are called when
/// the value changes.
///
/// See also:
///
///  * [ValueNotifier], which implements it.
///  * [ValueListenableBuilder], which builds from the value.
abstract class ValueListenable<T> extends Listenable {
  /// For subclasses.
  const ValueListenable();

  /// The current value.
  T get value;
}

/// A [Listenable] whose listeners [notifyListeners] calls, to extend or mix
/// in.
///
/// As in Flutter, the listeners are called in the order they were added,
/// one added twice twice. A listener added while they are called is called
/// from the next notification on; one removed meanwhile is not called once
/// it is removed, also by a notification a listener started. A listener
/// that throws is reported to the current [Zone]'s error handler, and the
/// others are still called. A notifier is not used after [dispose], except
/// to remove a listener.
///
/// A model that tells the widgets showing it when it changes:
///
/// ```dart
/// final class Cart extends ChangeNotifier {
///   final _items = <String>[];
///
///   List<String> get items => List.unmodifiable(_items);
///
///   void add(String item) {
///     _items.add(item);
///     notifyListeners();
///   }
/// }
/// ```
///
/// See also:
///
///  * [ValueNotifier], for one value.
///  * [ListenableBuilder], which shows a notifier's state.
mixin class ChangeNotifier implements Listenable {
  // a listener removed while notifying is null until the outermost
  // notification ends, so that the running ones keep their indices
  final _listeners = <VoidCallback?>[];
  // the notifyListeners calls running
  var _notifying = 0;
  // the null listeners
  var _removed = 0;
  var _disposed = false;

  /// Whether any listener is added.
  @protected
  @visibleForTesting
  bool get hasListeners => _listeners.length > _removed;

  @override
  void addListener(VoidCallback listener) {
    assert(!_disposed, '$this used after dispose()');
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    final i = _listeners.indexOf(listener);
    if (i < 0) {
      return;
    }
    if (_notifying > 0) {
      _listeners[i] = null;
      _removed++;
    } else {
      _listeners.removeAt(i);
    }
  }

  /// Drops the listeners; afterwards the notifier is not used, except to
  /// remove a listener. Not called while the listeners are.
  @mustCallSuper
  void dispose() {
    assert(!_disposed, '$this used after dispose()');
    assert(_notifying == 0, '$this disposed while notifying its listeners');
    _disposed = true;
    _listeners.clear();
    _removed = 0;
  }

  /// Calls the listeners added so far; with none it returns at once.
  @protected
  @visibleForTesting
  void notifyListeners() {
    assert(!_disposed, '$this used after dispose()');
    if (_listeners.isEmpty) {
      return;
    }
    _notifying++;
    final end = _listeners.length;
    for (var i = 0; i < end; i++) {
      final listener = _listeners[i];
      if (listener == null) {
        continue;
      }
      try {
        listener();
      } on Object catch (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
      }
    }
    _notifying--;
    if (_notifying == 0 && _removed > 0) {
      _listeners.removeWhere((listener) => listener == null);
      _removed = 0;
    }
  }
}

/// A [ChangeNotifier] that holds a [value] and notifies its listeners when
/// the value is set to one not equal to it.
///
/// ```dart
/// final count = ValueNotifier(0)..addListener(() => print('changed'));
/// count.value++; // prints "changed"
/// count.value = 1; // equal: prints nothing
/// ```
///
/// A value that changes in place (a list added to) does not notify: set
/// a new one, or notify from a [ChangeNotifier] of its own.
///
/// See also:
///
///  * [ValueListenableBuilder], which shows the value.
class ValueNotifier<T> extends ChangeNotifier implements ValueListenable<T> {
  /// A notifier holding [_value] at first.
  ValueNotifier(this._value);

  T _value;

  /// The value held; setting one not equal to it (`==`) notifies the
  /// listeners.
  @override
  T get value => _value;

  set value(T newValue) {
    if (_value == newValue) {
      return;
    }
    _value = newValue;
    notifyListeners();
  }
}

/// The listenable of [Listenable.merge].
final class _MergingListenable extends Listenable {
  _MergingListenable(this._listenables);

  final Iterable<Listenable?> _listenables;

  @override
  void addListener(VoidCallback listener) {
    for (final listenable in _listenables) {
      listenable?.addListener(listener);
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    for (final listenable in _listenables) {
      listenable?.removeListener(listener);
    }
  }
}
