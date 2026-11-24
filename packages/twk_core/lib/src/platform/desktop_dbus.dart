/// [DesktopNotifications] over D-Bus ([DbusConnection]): the
/// `org.freedesktop.Notifications` service of the session bus (KDE's,
/// GNOME's, dunst, mako...). From dart:io: `io.dart` only.
library;

import 'dart:async';

import '../terminal/sequences.dart'
    show DesktopNotification, NotificationUrgency, notificationText;
import 'dbus.dart';
import 'desktop.dart';

const _service = 'org.freedesktop.Notifications';
const _path = '/org/freedesktop/Notifications';
const _bus = 'org.freedesktop.DBus';
const _busPath = '/org/freedesktop/DBus';

/// The desktop's notification service of the session bus at [address],
/// null where, within [within] all told, the bus can't be reached or has
/// no such service, running (`NameHasOwner`) or one it can start
/// (`ListActivatableNames`): none is started here, only by a
/// notification. [appName] names the app on each notification that names
/// none.
Future<DesktopNotifications?> openDbusNotifications(
  String address, {
  required String appName,
  Duration within = const Duration(seconds: 1),
}) async {
  DbusConnection? held;
  Future<DesktopNotifications?> open() async {
    final bus = held = await DbusConnection.connect(address, within: within);
    if (bus == null) {
      return null;
    }
    Future<List<Object?>> ask(String member, [String? name]) => bus.call(
      destination: _bus,
      path: _busPath,
      interface: _bus,
      member: member,
      signature: name == null ? '' : 's',
      values: [?name],
    );
    try {
      await ask(
        'AddMatch',
        "type='signal',interface='$_service',path='$_path'",
      );
      final running = (await ask('NameHasOwner', _service)).single == true;
      if (!running) {
        final names = (await ask('ListActivatableNames')).single;
        if (names is! List || !names.contains(_service)) {
          await bus.close();
          return null;
        }
      }
    } on Object {
      await bus.close();
      return null;
    }
    return _DbusNotifications(bus, appName);
  }

  // one deadline for all of it; past it the connection made is let go,
  // which fails what it still waits for
  final opening = open();
  try {
    return await dbusWithin(opening, within);
  } on TimeoutException {
    await held?.close();
    return null;
  }
}

/// How long [DesktopNotifications.close] waits for the notifications
/// asked for before it to be shown.
const _closeLimit = Duration(seconds: 1);

/// How long a call of the service's is waited for, after which what was
/// asked is taken for not done: a service that stopped answering holds up
/// no later notification of the same id.
const _callLimit = Duration(seconds: 5);

/// [call] given up on after [_callLimit] ([dbusWithin]).
Future<List<Object?>> _guarded(Future<List<Object?>> call) =>
    dbusWithin(call, _callLimit);

/// `&`, `<` and `>` as the body's markup writes them.
String _escaped(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

final class _DbusNotifications implements DesktopNotifications {
  _DbusNotifications(this._bus, this._appName) {
    _signals = _bus.signals.listen((s) {
      if (s.interface != _service || s.values.isEmpty) {
        return;
      }
      final shown = s.values[0];
      switch (s.member) {
        case 'ActionInvoked' when s.values.length > 1:
          if (s.values[1] != 'default') {
            break;
          }
          if (!_ids.containsKey(shown)) {
            // before the reply that shows it was read through: told when
            // it is
            _early.add(shown);
          } else if (_reported.remove(shown) ?? false) {
            _activated.add(_ids[shown]!);
          }
        case 'NotificationClosed':
          _reported.remove(shown);
          // the id's current one only: a newer one of the id goes on
          if (_ids.remove(shown) case final id?
              when identical(_shown[id], _of.remove(shown))) {
            _shown.remove(id)?.ignore();
          }
      }
    });
  }

  final DbusConnection _bus;
  final String _appName;
  late final StreamSubscription<DbusSignal> _signals;
  final _activated = StreamController<String>.broadcast();

  /// The service's id of the notification of each id of its own, once the
  /// service told it; null where it was not shown.
  final _shown = <String, Future<int?>>{};

  /// Which of [_shown]'s futures told each id of the service's.
  final _of = <Object?, Future<int?>>{};

  /// Its own id, by the service's.
  final _ids = <Object?, String>{};

  /// Whether a click on each, by the service's id, is to be told.
  final _reported = <Object?, bool>{};

  /// The service's ids clicked before the reply that showed them was read
  /// through.
  final _early = <Object?>{};

  /// Whether the service takes markup in a body (its capability
  /// `body-markup`), whose `&`, `<` and `>` are then escaped; asked once,
  /// with the first notification.
  Future<bool>? _markup;
  var _closed = false;

  @override
  Stream<String> get activated => _activated.stream;

  Future<bool> _takesMarkup() => _markup ??=
      _guarded(
        _bus.call(
          destination: _service,
          path: _path,
          interface: _service,
          member: 'GetCapabilities',
        ),
      ).then(
        (r) => (r.single as List?)?.contains('body-markup') ?? false,
        onError: (Object _) => false,
      );

  @override
  void notify(
    DesktopNotification notification, {
    required String id,
    required bool report,
  }) {
    final text = notificationText(notification, lines: true);
    if (_closed || text == null) {
      return;
    }
    final before = _shown[id] ?? Future<int?>.value();
    final done = Completer<int?>();
    _shown[id] = done.future;
    unawaited(
      before
          .then((replaced) async {
            if (_closed) {
              return null;
            }
            final markup = await _takesMarkup();
            final reply = await _guarded(
              _bus.call(
                destination: _service,
                path: _path,
                interface: _service,
                member: 'Notify',
                signature: 'susssasa{sv}i',
                values: [
                  if (text.appName.isEmpty) _appName else text.appName,
                  replaced ?? 0,
                  text.icon,
                  text.title,
                  if (markup) _escaped(text.body) else text.body,
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
              ),
            );
            final shown = reply.single! as int;
            _ids[shown] = id;
            _of[shown] = done.future;
            if (_early.remove(shown) && report) {
              _activated.add(id);
            } else {
              _reported[shown] = report;
            }
            return shown;
          })
          .then(done.complete, onError: (Object _) => done.complete(null)),
    );
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
        _of.remove(n)?.ignore();
        try {
          await _guarded(
            _bus.call(
              destination: _service,
              path: _path,
              interface: _service,
              member: 'CloseNotification',
              signature: 'u',
              values: [n],
            ),
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
      await dbusWithin(Future.wait(_shown.values), _closeLimit);
    } on TimeoutException {
      // dropped
    }
    _closed = true;
    await _bus.close();
    await _activated.close();
  }
}
