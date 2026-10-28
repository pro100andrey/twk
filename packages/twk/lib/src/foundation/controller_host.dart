/// [ControllerHost]: the one widget a controller serves at a time, and the
/// handover from that widget to one built in its place.
library;

import 'dart:async' show scheduleMicrotask;

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
  /// A handover with no host.
  ControllerHost();

  H? _host;
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
    return identical(old, host) ? null : old;
  }

  /// [host] lets go of the controller: where it is still the host, there
  /// is none now, and [orphaned], if given, runs after the build unless a
  /// host has attached by then or the controller was disposed. Returns
  /// whether [host] was the host.
  bool detach(H host, [void Function()? orphaned]) {
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
    _disposed = true;
    _host = null;
  }
}
