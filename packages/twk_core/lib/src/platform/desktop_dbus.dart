/// [DesktopNotifications] over D-Bus ([DbusConnection]): the
/// `org.freedesktop.Notifications` service of the session bus (KDE's,
/// GNOME's, dunst, mako...). From dart:io: `io.dart` only.
library;

import 'dart:async';

import '../terminal/sequences.dart'
    show DesktopNotification, NotificationUrgency;
import 'dbus.dart';
import 'desktop.dart';

const _service = 'org.freedesktop.Notifications';
const _path = '/org/freedesktop/Notifications';

/// The desktop's notification service of the session bus at [address],
/// null where it can't be reached within [within] or answers no
/// `GetCapabilities` (none on the bus, nor one it can start). [appName]
/// names the app on each notification that names none.
Future<DesktopNotifications?> openDbusNotifications(
  String address, {
  required String appName,
  Duration within = const Duration(seconds: 1),
}) async {
  final bus = await DbusConnection.connect(address, within: within);
  if (bus == null) {
    return null;
  }
  try {
    await bus
        .call(
          destination: 'org.freedesktop.DBus',
          path: '/org/freedesktop/DBus',
          interface: 'org.freedesktop.DBus',
          member: 'AddMatch',
          signature: 's',
          values: ["type='signal',interface='$_service',path='$_path'"],
        )
        .timeout(within);
    await bus
        .call(
          destination: _service,
          path: _path,
          interface: _service,
          member: 'GetCapabilities',
        )
        .timeout(within);
  } on Object {
    await bus.close();
    return null;
  }
  return _DbusNotifications(bus, appName);
}

/// How long [DesktopNotifications.close] waits for the notifications
/// asked for before it to be shown.
const _closeLimit = Duration(seconds: 1);

final class _DbusNotifications implements DesktopNotifications {
  _DbusNotifications(this._bus, this._appName) {
    _signals = _bus.signals.listen((s) {
      if (s.interface != _service || s.values.isEmpty) {
        return;
      }
      final shown = s.values[0];
      switch (s.member) {
        case 'ActionInvoked' when s.values.length > 1:
          if (s.values[1] == 'default' && (_reported.remove(shown) ?? false)) {
            if (_ids[shown] case final id?) {
              _activated.add(id);
            }
          }
        case 'NotificationClosed':
          _reported.remove(shown);
          if (_ids.remove(shown) case final id?) {
            _shown.remove(id)?.ignore();
          }
      }
    });
  }

  final DbusConnection _bus;
  final String _appName;
  late final StreamSubscription<DbusSignal> _signals;
  final _activated = StreamController<String>.broadcast();

  /// The service's id of each notification shown, by its own, once told.
  final _shown = <String, Future<int?>>{};

  /// Its own id, by the service's.
  final _ids = <Object?, String>{};

  /// Whether a click on each, by the service's id, is to be told.
  final _reported = <Object?, bool>{};
  var _closed = false;

  @override
  Stream<String> get activated => _activated.stream;

  @override
  void notify(
    DesktopNotification notification, {
    required String id,
    required bool report,
  }) {
    if (_closed) {
      return;
    }
    final before = _shown[id] ?? Future<int?>.value();
    _shown[id] = before.then((replaced) async {
      if (_closed) {
        return null;
      }
      try {
        final reply = await _bus.call(
          destination: _service,
          path: _path,
          interface: _service,
          member: 'Notify',
          signature: 'susssasa{sv}i',
          values: [
            if (notification.appName.isEmpty)
              _appName
            else
              notification.appName,
            replaced ?? 0,
            notification.icon,
            notification.title,
            notification.body,
            [
              if (report) ...['default', 'Show'],
            ],
            <Object, Object>{
              'urgency': (
                signature: 'y',
                value: switch (notification.urgency) {
                  NotificationUrgency.low => 0,
                  NotificationUrgency.normal => 1,
                  NotificationUrgency.critical => 2,
                },
              ),
            },
            -1,
          ],
        );
        final shown = reply.single! as int;
        _ids[shown] = id;
        _reported[shown] = report;
        return shown;
      } on Object {
        return null;
      }
    });
  }

  @override
  void closeNotification(String id) {
    final shown = _shown.remove(id);
    if (shown == null || _closed) {
      return;
    }
    unawaited(
      shown.then((n) async {
        if (n == null || _closed) {
          return;
        }
        _reported.remove(n);
        _ids.remove(n);
        try {
          await _bus.call(
            destination: _service,
            path: _path,
            interface: _service,
            member: 'CloseNotification',
            signature: 'u',
            values: [n],
          );
        } on Object {
          // gone already
        }
      }),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    await _signals.cancel();
    // what was asked before is sent, unless the service no longer answers:
    // a guard on real time, as the terminal's own on close
    try {
      await Zone.root.run(
        () => Future.wait(_shown.values).timeout(_closeLimit),
      );
    } on TimeoutException {
      // dropped
    }
    _closed = true;
    await _bus.close();
    await _activated.close();
  }
}
