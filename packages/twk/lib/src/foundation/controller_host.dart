/// [ControllerHost]: the one widget a controller serves at a time, and the
/// handover from that widget to one built in its place.
library;

import 'dart:async' show Timer, scheduleMicrotask;

import '../../log.dart' show LogLevel, log;

import '../binding/app_binding.dart' show AppBinding;
import '../framework/framework.dart' show State;

/// The host of a controller given to one widget at a time — the `State`
/// that serves its calls — kept by the controller, privately, and the
/// handover from one host to the next.
///
/// A widget built in place of another with the same controller (its key
/// changed) starts before the other is gone: as an only child, after the
/// other left the tree (`State.deactivate`) and before it is disposed;
/// among children, before the other even left the tree. So [attach] makes
/// the new host the host at once, whoever held the controller, and leaves
/// the controller as it is: what it holds — a message shown, a menu open,
/// a query typed — is the new host's to go on with, and the old host
/// learns it is no longer the host from [isHost], or from what [attach]
/// returns. [detach] lets go for the host alone: one the controller has
/// passed on from changes nothing.
///
/// So a host leaving the tree lets go of nothing then: in `dispose`, at
/// the end of the frame, it [detach]es, and by then one built in its place
/// has attached. What a controller does when its host leaves and none
/// takes over — a popup said closed, the listeners told — is the
/// `orphaned` callback of [detach], run after the build and only when no
/// host has attached by then; what a host tells the listeners of a change
/// made in a build waits for [afterBuild]. Nothing tells them while
/// widgets build.
///
/// A controller given to two widgets that are both in the tree is a
/// mistake: the first goes dead. A handover is not that, and happens in
/// one frame, so in debug mode [attach] checks after the build, not at
/// once, that the host it took over from is no longer mounted
/// (`State.mounted`, or the `mounted` of the constructor, which a host that
/// is no `State` needs). An old host may stay mounted for a while — a
/// dialog's entry fading out while the next opens — so a host still
/// mounted is checked again after a grace of two seconds, and only one
/// that is mounted then too (on the app's clock; with no app above the
/// host, at once) is a mistake: it is logged at
/// `LogLevel.error` with a [StateError] naming both hosts, which does not
/// end the app.
///
/// A controller of a popup, which its widget's state serves; it is said
/// closed when that widget leaves and none takes over:
///
/// ```dart
/// final class PopupController extends ChangeNotifier {
///   final host = ControllerHost<State<StatefulWidget>>();
///   var isOpen = false;
///
///   void close() {
///     isOpen = false;
///     notifyListeners();
///   }
///
///   // the state's initState: controller.host.attach(this);
///   // its dispose: controller.host.detach(this, controller.close);
///
///   @override
///   void dispose() {
///     host.dispose();
///     super.dispose();
///   }
/// }
/// ```
final class ControllerHost<H extends Object> {
  /// A handover with no host. [mounted] says whether a host is still in the
  /// tree, for the check that no two are at once; by default a `State`
  /// asks its own `mounted`, and any other host is taken as gone.
  ControllerHost({bool Function(H host)? mounted})
    : _mounted = mounted == null ? null : ((host) => mounted(host as H));

  final bool Function(Object host)? _mounted;

  H? _host;
  final _graces = <Timer>{};
  var _disposed = false;

  /// The host; null while the controller is given to no widget.
  H? get host => _host;

  /// Whether [host] is the host.
  bool isHost(H host) => identical(_host, host);

  /// Whether [dispose] was called.
  bool get isDisposed => _disposed;

  /// Makes [host] the host, in place of the one before, which it returns:
  /// the host it takes the controller over from, to take over what that
  /// one did for it. Null when there was none, or it was [host].
  H? attach(H host) {
    final old = _host;
    _host = host;
    if (identical(old, host)) {
      return null;
    }
    assert(() {
      if (old != null) {
        afterBuild(() => _checkOneHost(old));
      }
      return true;
    }(), 'the check that no two hosts are in the tree at once');
    return old;
  }

  bool _isMounted(H host) =>
      _mounted?.call(host) ?? (host is State && host.mounted);

  void _checkOneHost(H old, {bool grace = true}) {
    final current = _host;
    if (current == null || identical(current, old)) {
      return;
    }
    if (_isMounted(old) && _isMounted(current)) {
      // on the app's clock, where the host has an app above it
      final binding = grace && current is State
          ? AppBinding.maybeOf(current.context)
          : null;
      if (binding != null) {
        late final Timer timer;
        timer = binding.startTimer(_overlapGrace, () {
          _graces.remove(timer);
          _checkOneHost(old, grace: false);
        });
        _graces.add(timer);
        return;
      }
      final error = StateError(
        'A controller has two hosts in the tree at once: $old and $current. '
        'The first is dead now, the last one attached serves the controller. '
        'Give each widget a controller of its own.',
      );
      log(error.message, level: LogLevel.error, error: error);
    }
  }

  /// How long an old host may stay mounted, fading out or the like, before
  /// the two hosts are taken for a mistake.
  static const _overlapGrace = Duration(seconds: 2);

  /// [host] lets go of the controller: where it is still the host, there
  /// is none now, and [orphaned], if given, runs after the build unless a
  /// host has attached by then or the controller was disposed. Returns
  /// whether [host] was the host.
  bool detach(H host, [void Function()? orphaned]) {
    // a host leaving the tree ends the overlap, or the app is quitting
    _cancelGraces();
    if (!identical(_host, host)) {
      return false;
    }
    _host = null;
    if (orphaned != null) {
      afterBuild(() {
        if (_host == null) {
          orphaned();
        }
      });
    }
    return true;
  }

  void _cancelGraces() {
    for (final timer in _graces) {
      timer.cancel();
    }
    _graces.clear();
  }

  /// Runs [callback] once the build under way is done (a microtask),
  /// unless the controller is disposed by then: for telling the listeners
  /// of what a build changed.
  void afterBuild(void Function() callback) {
    scheduleMicrotask(() {
      if (!_disposed) {
        callback();
      }
    });
  }

  /// The controller is disposed: it has no host, and what [afterBuild] and
  /// [detach] were to run later does not run.
  void dispose() {
    _cancelGraces();
    _disposed = true;
    _host = null;
  }
}
