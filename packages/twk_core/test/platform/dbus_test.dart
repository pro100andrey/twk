// The core's own D-Bus client and the desktop's notification service over
// it, against a bus of the test's own: a Unix socket in a temporary
// directory that authenticates, answers Hello, AddMatch and the
// notification service's calls, and emits its signals, as a session bus
// with KDE's or GNOME's service on it would. No desktop needed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/platform/dbus.dart';
import 'package:twk_core/src/platform/desktop_dbus.dart';
import 'package:twk_core/src/platform/platform.dart'
    show openDesktopNotifications;
import 'package:twk_core/twk_core.dart'
    show DesktopNotification, NotificationUrgency;
import 'package:twk_test/twk_test.dart' show waitFor, waitUntil;

/// A bus with a notification service on it, or without one where not
/// [service]: what it was asked, each call's member and values.
final class _Bus {
  _Bus._(this._server, this.address, {required this.service}) {
    _server.listen(_accept);
  }

  static Future<_Bus> start({bool service = true}) async {
    final dir = Directory.systemTemp.createTempSync('twk_dbus');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/bus';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final bus = _Bus._(server, 'unix:path=$path', service: service);
    addTearDown(bus.close);
    return bus;
  }

  final ServerSocket _server;
  final String address;
  final bool service;
  final calls = <(String, List<Object?>)>[];

  /// Whether a notification shown is clicked at once, the signal sent
  /// with the reply.
  var clickOnNotify = false;
  final _clients = <Socket>[];
  var _serial = 0;
  var _shown = 0;

  List<List<Object?>> get notified => [
    for (final (m, v) in calls)
      if (m == 'Notify') v,
  ];

  void _accept(Socket s) {
    _clients.add(s);
    var authenticated = false;
    final pending = BytesBuilder();
    s.listen((bytes) {
      pending.add(bytes);
      if (!authenticated) {
        final text = latin1.decode(pending.toBytes());
        if (text.contains('BEGIN\r\n')) {
          authenticated = true;
          final rest = pending.toBytes().sublist(
            text.indexOf('BEGIN\r\n') + 7,
          );
          pending
            ..clear()
            ..add(rest);
        } else if (text.contains('AUTH EXTERNAL ') && text.endsWith('\r\n')) {
          s.add(ascii.encode('OK 0123456789abcdef\r\n'));
          return;
        } else {
          return;
        }
      }
      while (true) {
        final all = pending.toBytes();
        final n = DbusMessage.lengthOf(all);
        if (n == null || all.length < n) {
          return;
        }
        pending
          ..clear()
          ..add(all.sublist(n));
        _handle(s, DbusMessage.decode(Uint8List.sublistView(all, 0, n)));
      }
    });
  }

  void _reply(
    Socket s,
    DbusMessage call, [
    String sig = '',
    List<Object> v = const [],
  ]) => s.add(
    DbusMessage.encode(
      type: 2,
      serial: ++_serial,
      replySerial: call.serial,
      signature: sig,
      values: v,
    ),
  );

  void _handle(Socket s, DbusMessage m) {
    calls.add((m.member ?? '', m.values));
    switch (m.member) {
      case 'Hello':
        _reply(s, m, 's', [':1.7']);
      case 'AddMatch':
        _reply(s, m);
      case 'GetCapabilities' when service:
        _reply(s, m, 'as', [
          ['body', 'actions'],
        ]);
      case 'Notify':
        final replaces = m.values[1]! as int;
        final shown = replaces == 0 ? ++_shown : replaces;
        _reply(s, m, 'u', [shown]);
        if (clickOnNotify) {
          signal('ActionInvoked', 'us', [shown, 'default']);
        }
      case 'CloseNotification':
        _reply(s, m);
        signal('NotificationClosed', 'uu', [m.values[0]! as int, 3]);
      default:
        s.add(
          DbusMessage.encode(
            type: 3,
            serial: ++_serial,
            replySerial: m.serial,
            errorName: 'org.freedesktop.DBus.Error.ServiceUnknown',
            signature: 's',
            values: ['no ${m.member}'],
          ),
        );
    }
  }

  /// The service emits [member] with [values] of [signature].
  void signal(String member, String signature, List<Object> values) {
    for (final c in _clients) {
      c.add(
        DbusMessage.encode(
          type: 4,
          serial: ++_serial,
          path: '/org/freedesktop/Notifications',
          interface: 'org.freedesktop.Notifications',
          member: member,
          signature: signature,
          values: values,
        ),
      );
    }
  }

  Future<void> close() async {
    for (final c in _clients) {
      c.destroy();
    }
    await _server.close();
  }
}

void main() {
  test('a message written is read back: a header, and a body of a string, '
      'numbers, an array of strings, a dict of variants', () {
    final bytes = DbusMessage.encode(
      type: 1,
      serial: 9,
      path: '/org/freedesktop/Notifications',
      interface: 'org.freedesktop.Notifications',
      member: 'Notify',
      destination: 'org.freedesktop.Notifications',
      signature: 'susssasa{sv}i',
      values: [
        'tm',
        0,
        'dialog-information',
        'Тесты',
        'ok 🧪',
        ['default', 'Show'],
        <Object, Object>{
          'urgency': (signature: 'y', value: 2),
          'x-label': (signature: 's', value: 'v'),
        },
        -1,
      ],
    );
    expect(DbusMessage.lengthOf(bytes), bytes.length);
    final m = DbusMessage.decode(bytes);
    expect(m.type, 1);
    expect(m.serial, 9);
    expect(m.member, 'Notify');
    expect(m.destination, 'org.freedesktop.Notifications');
    expect(m.values, [
      'tm',
      0,
      'dialog-information',
      'Тесты',
      'ok 🧪',
      ['default', 'Show'],
      {'urgency': 2, 'x-label': 'v'},
      -1,
    ]);
  });

  test('a notification as Notify, the app named where it names none; one '
      'of the same id replaces it; closed by id', () async {
    final bus = await _Bus.start();
    final desktop = (await openDbusNotifications(bus.address, appName: 'tm'))!;
    addTearDown(desktop.close);
    desktop
      ..notify(
        const DesktopNotification(
          'Build',
          body: 'done',
          urgency: NotificationUrgency.critical,
          icon: 'dialog-information',
        ),
        id: 'b',
        report: false,
      )
      ..notify(
        const DesktopNotification('Build', body: 'again', appName: 'ci'),
        id: 'b',
        report: false,
      )
      ..closeNotification('b');
    await waitUntil(
      () => bus.calls.any((c) => c.$1 == 'CloseNotification'),
      'closed',
    );
    final [first, second] = bus.notified;
    expect(first, [
      'tm',
      0,
      'dialog-information',
      'Build',
      'done',
      <Object?>[],
      {'urgency': 2},
      -1,
    ]);
    expect(second[0], 'ci');
    expect(second[1], 1, reason: 'replaces the first');
    expect(
      bus.calls.lastWhere((c) => c.$1 == 'CloseNotification').$2,
      [1],
    );
  });

  test('a click is told for one that asked for it, once; one that comes '
      'with the reply that shows it too', () async {
    final bus = await _Bus.start();
    final desktop = (await openDbusNotifications(bus.address, appName: 'tm'))!;
    addTearDown(desktop.close);
    final clicks = <String>[];
    desktop.activated.listen(clicks.add);
    // the bus clicks it as it answers: the reply and the signal in one
    // read
    bus.clickOnNotify = true;
    desktop.notify(const DesktopNotification('a'), id: 'a', report: true);
    await waitUntil(() => clicks.isNotEmpty, 'the click');
    expect(clicks, ['a']);
  });

  test('a click is told for one that asked for it, once', () async {
    final bus = await _Bus.start();
    final desktop = (await openDbusNotifications(bus.address, appName: 'tm'))!;
    addTearDown(desktop.close);
    final clicks = <String>[];
    desktop.activated.listen(clicks.add);
    desktop
      ..notify(const DesktopNotification('a'), id: 'a', report: true)
      ..notify(const DesktopNotification('b'), id: 'b', report: false);
    await waitUntil(() => bus.notified.length == 2, 'both shown');
    expect(bus.notified[0][5], ['default', 'Show']);
    bus
      ..signal('ActionInvoked', 'us', [1, 'default'])
      ..signal('ActionInvoked', 'us', [1, 'default'])
      ..signal('ActionInvoked', 'us', [2, 'default']);
    await waitUntil(() => clicks.isNotEmpty, 'the click');
    // a call after the signals: the bus sends them before its reply
    desktop.notify(const DesktopNotification('c'), id: 'c', report: false);
    await waitUntil(() => bus.notified.length == 3, 'a later one shown');
    expect(clicks, ['a']);
  });

  test('none without a notification service, nor where the bus is not '
      'there', () async {
    final bus = await _Bus.start(service: false);
    expect(await openDbusNotifications(bus.address, appName: 'tm'), isNull);
    expect(
      await openDbusNotifications(
        'unix:path=${Directory.systemTemp.path}/twk-no-bus-$pid',
        appName: 'tm',
      ),
      isNull,
    );
    expect(
      await openDbusNotifications('tcp:host=localhost,port=1', appName: 'tm'),
      isNull,
      reason: 'only Unix sockets',
    );
  });

  test("none for a remote session, whose bus is not the user's desktop's, "
      'or without a session bus', () async {
    final bus = await _Bus.start();
    final remote = {
      'DBUS_SESSION_BUS_ADDRESS': bus.address,
      'SSH_CONNECTION': '10.0.0.1 22 10.0.0.2 41000',
    };
    expect(await openDesktopNotifications(remote), isNull);
    expect(await openDesktopNotifications(const {}), isNull);
    final local = await waitFor(
      openDesktopNotifications({'DBUS_SESSION_BUS_ADDRESS': bus.address}),
      'the local one',
    );
    expect(local, isNotNull);
    await local!.close();
  });
}
