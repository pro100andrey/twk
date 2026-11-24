/// The desktop's notification service as a `Terminal` uses it where its
/// terminal shows no notification of its own
/// (`NotificationProtocol.dbus`): what `io.dart` makes over D-Bus
/// (`openDesktopNotifications`), and the web has none of.
library;

import '../terminal/sequences.dart' show DesktopNotification;

/// The desktop's notification service, open: `org.freedesktop.Notifications`
/// on the session bus.
abstract interface class DesktopNotifications {
  /// Shows [notification] as [id], in place of the one of [id] still
  /// shown; asks for a click on it to be told ([activated]) where
  /// [report].
  void notify(
    DesktopNotification notification, {
    required String id,
    required bool report,
  });

  /// Takes the notification of [id] down where it is still shown.
  void closeNotification(String id);

  /// The id of each notification clicked that asked for it.
  Stream<String> get activated;

  /// Lets the service go; the notifications shown stay.
  Future<void> close();
}
