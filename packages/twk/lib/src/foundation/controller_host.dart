/// [ControllerHost]: the one widget a controller serves at a time, and the
/// handover from that widget to one built in its place.
library;

import 'dart:async' show Timer, scheduleMicrotask;

import '../../log.dart' show LogLevel, log;

import '../framework/framework.dart' show StartTimer, State;

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
/// is no `State` needs). A host typed as an interface a `State` implements
/// is a `State` all the same. An old host may stay mounted for a while — a
/// dialog's entry fading out while the next opens — so a host still
/// mounted is checked again after a grace of two seconds, and only one
/// that is mounted then too is a mistake: it is logged at
/// `LogLevel.error` with a [StateError] naming both hosts, which does not
/// end the app. The grace runs on the clock the constructor's `timerOf`
/// gives for the host: for a `State`, the app's (`State.appTimer`, the
/// `AppClock` the binding puts above the app), with no wiring; a host that
/// is no `State` says it with `timerOf`. Where there is none — no app above
/// the host — two hosts mounted at the handover cannot be waited on, and
/// the check throws the [StateError] instead, in debug mode only, as an
/// uncaught error.
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
  /// [timerOf] says which clock the grace of a host that stays mounted
  /// runs on, null where there is none (no app above that host: the check
  /// throws, in debug mode); where it is given its answer stands, null
  /// included. Where it is not, a `State` gives the app's, any other host
  /// none.
  ControllerHost({
    bool Function(H host)? mounted,
    StartTimer? Function(H host)? timerOf,
  }) : _mounted = mounted == null ? null : ((host) => mounted(host as H)),
       _timerOf = timerOf == null ? null : ((host) => timerOf(host as H));

  final bool Function(Object host)? _mounted;
  final StartTimer? Function(Object host)? _timerOf;

  H? _host;
  // each pending grace with the two hosts it waits on
  final _graces = <Timer, (Object, Object)>{};
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

  StartTimer? _timerOfHost(H host) {
    final timerOf = _timerOf;
    if (timerOf != null) {
      return timerOf(host);
    }
    return host is State ? host.appTimer : null;
  }

  void _checkOneHost(H old, {bool grace = true}) {
    final current = _host;
    if (current == null || identical(current, old)) {
      return;
    }
    if (_isMounted(old) && _isMounted(current)) {
      final startTimer = grace ? _timerOfHost(current) : null;
      if (startTimer != null) {
        late final Timer timer;
        timer = startTimer(_overlapGrace, () {
          _graces.remove(timer);
          _checkOneHost(old, grace: false);
        });
        _graces[timer] = (old, current);
        return;
      }
      final error = StateError(
        'A controller has two hosts in the tree at once: $old and $current. '
        'The first is dead now, the last one attached serves the controller. '
        'Give each widget a controller of its own.',
      );
      if (grace) {
        // no clock to wait on: the mistake is not told from a fade-out
        throw error;
      }
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
    // a host leaving the tree ends the overlaps it is in; those of other
    // hosts go on
    _cancelGraces(host);
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

  // those of [host], or all
  void _cancelGraces([H? host]) {
    _graces.removeWhere((timer, hosts) {
      if (host != null &&
          !identical(hosts.$1, host) &&
          !identical(hosts.$2, host)) {
        return false;
      }
      timer.cancel();
      return true;
    });
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
