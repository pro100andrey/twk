/// What a [TickerMode] that is off mutes: [Muteable], and the [MuteGroup]
/// that sets a list of them from it.
library;

import 'package:meta/meta.dart';

import '../framework/framework.dart';
import 'ticker.dart' show TickerMode;

/// Something that stands still while muted, and goes on when unmuted.
@internal
abstract interface class Muteable {
  /// Whether it is muted.
  bool get muted;
  set muted(bool on);
}

/// A list of [Muteable]s set together from the [TickerMode] at a context.
@internal
final class MuteGroup<T extends Muteable> {
  final _items = <T>[];

  /// The items, as they were added.
  Iterable<T> get items => _items;

  /// Adds [item] and returns it.
  T add(T item) {
    _items.add(item);
    return item;
  }

  /// Removes [item]; one that is not there is left.
  void remove(T item) => _items.remove(item);

  /// Mutes all of them, or unmutes them, as the [TickerMode] at [context]
  /// is off or on; the caller is told when it changes.
  void sync(BuildContext context) => mute(!TickerMode.of(context));

  /// Sets all of them to [on].
  void mute(bool on) {
    for (final item in _items) {
      item.muted = on;
    }
  }
}
