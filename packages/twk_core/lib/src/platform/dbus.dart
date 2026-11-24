/// As much of D-Bus as the desktop's notification service needs: a
/// connection to a bus over a Unix socket, its EXTERNAL authentication,
/// method calls and the signals of a match rule, the little-endian wire
/// format of the types they carry (`y b i u s o g v`, arrays, structs and
/// dict entries). From dart:io: `io.dart` only.
///
/// The specification: https://dbus.freedesktop.org/doc/dbus-specification.html
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'libc.dart' as c;

/// A D-Bus value whose type is written with it: a variant (`v`).
typedef DbusVariant = ({String signature, Object value});

/// An error a call was answered with: its name and its message.
final class DbusError implements Exception {
  /// The error [name] (`org.freedesktop.DBus.Error.ServiceUnknown`), with
  /// [message].
  const DbusError(this.name, this.message);

  /// The error's name.
  final String name;

  /// What it says.
  final String message;

  @override
  String toString() => 'DbusError: $name: $message';
}

/// A signal a bus passed on ([DbusConnection.signals]).
final class DbusSignal {
  /// A signal of [member] of [interface] at [path], carrying [values].
  const DbusSignal(this.path, this.interface, this.member, this.values);

  /// The object it came from.
  final String path;

  /// Its interface.
  final String interface;

  /// Its name.
  final String member;

  /// What it carries, as [DbusMessage.values] reads them.
  final List<Object?> values;
}

/// The message types of the wire.
abstract final class _Type {
  static const call = 1;
  static const reply = 2;
  static const error = 3;
  static const signal = 4;
}

/// A connection to a bus: [connect], then [call] and [signals].
final class DbusConnection {
  DbusConnection._(this._socket);

  final Socket _socket;
  final _pending = <int, Completer<List<Object?>>>{};
  // not sync: a signal is handed on after the replies before it, whose
  // calls' code then ran (a notification's id known before its click)
  final _signals = StreamController<DbusSignal>.broadcast();
  final _buffer = BytesBuilder();
  var _serial = 0;
  var _closed = false;

  /// A connection to the bus at [address] (`unix:path=...`, or
  /// `unix:abstract=...`; the first of several, `;` between them, that is
  /// one of these), authenticated as this process's user and introduced
  /// to the bus (`Hello`); null where none of them can be reached within
  /// [within].
  static Future<DbusConnection?> connect(
    String address, {
    Duration within = const Duration(seconds: 1),
  }) async {
    final socket = _socketOf(address);
    if (socket == null) {
      return null;
    }
    Socket? s;
    try {
      s = await Socket.connect(
        socket,
        0,
        timeout: within,
      );
      final connection = DbusConnection._(s);
      await connection._authenticate().timeout(within);
      await connection
          .call(
            destination: 'org.freedesktop.DBus',
            path: '/org/freedesktop/DBus',
            interface: 'org.freedesktop.DBus',
            member: 'Hello',
          )
          .timeout(within);
      return connection;
    } on Object {
      s?.destroy();
      return null;
    }
  }

  /// The socket of the first Unix address of [address], its values
  /// %-decoded; null for none.
  static InternetAddress? _socketOf(String address) {
    for (final one in address.split(';')) {
      if (!one.startsWith('unix:')) {
        continue;
      }
      final keys = {
        for (final kv in one.substring(5).split(','))
          if (kv.indexOf('=') case final eq when eq > 0)
            kv.substring(0, eq): Uri.decodeComponent(kv.substring(eq + 1)),
      };
      if (keys['path'] case final path?) {
        return InternetAddress(path, type: InternetAddressType.unix);
      }
      if (keys['abstract'] case final name?) {
        return InternetAddress('@$name', type: InternetAddressType.unix);
      }
    }
    return null;
  }

  /// EXTERNAL: the user's id, which the bus checks against the socket's
  /// credentials, in hex of its decimal digits; then the binary protocol.
  Future<void> _authenticate() async {
    final lines = StreamController<String>();
    final pending = <int>[];
    _socket.listen(
      (bytes) {
        if (lines.isClosed) {
          _receive(bytes);
          return;
        }
        pending.addAll(bytes);
        final end = pending.indexOf(0x0A);
        if (end >= 0) {
          lines.add(ascii.decode(pending.sublist(0, end)).trim());
          _receive(pending.sublist(end + 1));
          pending.clear();
        }
      },
      onError: _fail,
      onDone: () => _fail(const SocketException('the bus closed')),
      cancelOnError: true,
    );
    final uid = ascii.encode('${c.getuid()}');
    final hex = [
      for (final b in uid) b.toRadixString(16).padLeft(2, '0'),
    ].join();
    _socket
      ..add(const [0])
      ..add(ascii.encode('AUTH EXTERNAL $hex\r\n'));
    final answer = await lines.stream.first;
    await lines.close();
    if (!answer.startsWith('OK ')) {
      throw DbusError('auth', answer);
    }
    _socket.add(ascii.encode('BEGIN\r\n'));
  }

  /// Calls [member] of [interface] on [path] of [destination] with
  /// [values] of [signature], and completes with what it answers; with a
  /// [DbusError] where it answers one, or the connection ends first.
  Future<List<Object?>> call({
    required String destination,
    required String path,
    required String interface,
    required String member,
    String signature = '',
    List<Object> values = const [],
  }) {
    if (_closed) {
      return Future.error(const DbusError('closed', 'the connection'));
    }
    final serial = ++_serial;
    final done = Completer<List<Object?>>();
    _pending[serial] = done;
    _socket.add(
      DbusMessage.encode(
        type: _Type.call,
        serial: serial,
        path: path,
        interface: interface,
        member: member,
        destination: destination,
        signature: signature,
        values: values,
      ),
    );
    return done.future;
  }

  /// The signals the bus passes on: those of the match rules added
  /// (`org.freedesktop.DBus.AddMatch`).
  Stream<DbusSignal> get signals => _signals.stream;

  void _receive(List<int> bytes) {
    _buffer.add(bytes);
    while (true) {
      final all = _buffer.toBytes();
      final length = DbusMessage.lengthOf(all);
      if (length == null || all.length < length) {
        return;
      }
      _buffer
        ..clear()
        ..add(Uint8List.sublistView(all, length));
      final DbusMessage m;
      try {
        m = DbusMessage.decode(Uint8List.sublistView(all, 0, length));
      } on Object catch (e) {
        _fail(e);
        return;
      }
      switch (m.type) {
        case _Type.reply:
          _pending.remove(m.replySerial)?.complete(m.values);
        case _Type.error:
          _pending
              .remove(m.replySerial)
              ?.completeError(
                DbusError(m.errorName ?? '', switch (m.values.firstOrNull) {
                  final String message => message,
                  _ => '',
                }),
              );
        case _Type.signal:
          _signals.add(
            DbusSignal(
              m.path ?? '',
              m.interface ?? '',
              m.member ?? '',
              m.values,
            ),
          );
      }
    }
  }

  void _fail(Object e) {
    for (final p in _pending.values) {
      p.completeError(e);
    }
    _pending.clear();
    unawaited(close());
  }

  /// Ends the connection; what is still to be answered fails.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final p in _pending.values) {
      p.completeError(const DbusError('closed', 'the connection'));
    }
    _pending.clear();
    _socket.destroy();
    await _signals.close();
  }
}

/// A message of the wire, as [decode] reads it or [encode] writes one.
final class DbusMessage {
  /// A message of [type] whose header said what the arguments say.
  const DbusMessage({
    required this.type,
    required this.serial,
    required this.values,
    this.path,
    this.interface,
    this.member,
    this.errorName,
    this.replySerial,
    this.destination,
    this.signature = '',
  });

  /// 1 a method call, 2 its reply, 3 an error, 4 a signal.
  final int type;

  /// Its serial, which a reply names as its [replySerial].
  final int serial;

  /// Its body, by [signature]: `y b i u` as an int (`b` as a bool), `s o
  /// g` as a String, an array as a List, of dict entries as a Map, a struct
  /// as a List, a variant as what it holds.
  final List<Object?> values;

  /// The object it is of.
  final String? path;

  /// Its interface.
  final String? interface;

  /// Its method or signal.
  final String? member;

  /// An error's name.
  final String? errorName;

  /// The serial of the call it answers.
  final int? replySerial;

  /// Whom it is for.
  final String? destination;

  /// The signature of its body.
  final String signature;

  /// How long the message at the start of [bytes] is, from its fixed
  /// header and its fields' length; null where they have not all come.
  static int? lengthOf(Uint8List bytes) {
    if (bytes.length < 16) {
      return null;
    }
    final d = ByteData.sublistView(bytes);
    final body = d.getUint32(4, Endian.little);
    final fields = d.getUint32(12, Endian.little);
    return _align(16 + fields, 8) + body;
  }

  /// A message of [type] as the wire carries it, little-endian.
  static Uint8List encode({
    required int type,
    required int serial,
    String? path,
    String? interface,
    String? member,
    String? destination,
    String? errorName,
    int? replySerial,
    String signature = '',
    List<Object> values = const [],
  }) {
    final body = _Writer();
    final types = _types(signature);
    for (var i = 0; i < types.length; i++) {
      body.value(types[i], values[i]);
    }
    final fields = <List<Object>>[
      if (path != null) [1, (signature: 'o', value: path)],
      if (interface != null) [2, (signature: 's', value: interface)],
      if (member != null) [3, (signature: 's', value: member)],
      if (errorName != null) [4, (signature: 's', value: errorName)],
      if (replySerial != null) [5, (signature: 'u', value: replySerial)],
      if (destination != null) [6, (signature: 's', value: destination)],
      if (signature.isNotEmpty) [8, (signature: 'g', value: signature)],
    ];
    final header = _Writer()
      ..byte(0x6C) // 'l', little-endian
      ..byte(type)
      ..byte(0)
      ..byte(1)
      ..u32(body.length)
      ..u32(serial)
      ..value('a(yv)', fields)
      ..pad(8);
    return Uint8List.fromList([...header.bytes, ...body.bytes]);
  }

  /// The message [bytes] are, a whole one; throws [FormatException] for
  /// one that is not little-endian or reads past its end.
  // ignore: prefer_constructors_over_static_methods, reads, as encode writes
  static DbusMessage decode(Uint8List bytes) {
    if (bytes[0] != 0x6C) {
      throw const FormatException('not little-endian');
    }
    final r = _Reader(bytes)..at = 12;
    final fields = {
      for (final f
          in (r.value('a(yv)')! as List<Object?>).cast<List<Object?>>())
        f[0]! as int: f[1],
    };
    r.align(8);
    final signature = (fields[8] as String?) ?? '';
    final values = [for (final t in _types(signature)) r.value(t)];
    return DbusMessage(
      type: bytes[1],
      serial: ByteData.sublistView(bytes).getUint32(8, Endian.little),
      values: values,
      path: fields[1] as String?,
      interface: fields[2] as String?,
      member: fields[3] as String?,
      errorName: fields[4] as String?,
      replySerial: fields[5] as int?,
      destination: fields[6] as String?,
      signature: signature,
    );
  }
}

int _align(int n, int to) => (n + to - 1) ~/ to * to;

/// The complete types of [signature], in turn.
List<String> _types(String signature) {
  final out = <String>[];
  for (var i = 0; i < signature.length;) {
    final end = _typeEnd(signature, i);
    out.add(signature.substring(i, end));
    i = end;
  }
  return out;
}

/// Where the complete type at [i] of [s] ends.
int _typeEnd(String s, int i) {
  switch (s[i]) {
    case 'a':
      return _typeEnd(s, i + 1);
    case '(' || '{':
      final close = s[i] == '(' ? ')' : '}';
      var j = i + 1;
      while (s[j] != close) {
        j = _typeEnd(s, j);
      }
      return j + 1;
    default:
      return i + 1;
  }
}

/// How the type starting [type] is aligned.
int _alignment(String type) => switch (type[0]) {
  'y' || 'g' || 'v' => 1,
  'n' || 'q' => 2,
  'b' || 'i' || 'u' || 's' || 'o' || 'a' => 4,
  _ => 8, // x t d, ( {
};

final class _Writer {
  final bytes = <int>[];

  int get length => bytes.length;

  void pad(int to) {
    while (bytes.length % to != 0) {
      bytes.add(0);
    }
  }

  void byte(int v) => bytes.add(v & 0xFF);

  void u32(int v) {
    pad(4);
    bytes.addAll(
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little),
    );
  }

  void i32(int v) {
    pad(4);
    bytes.addAll(
      Uint8List(4)..buffer.asByteData().setInt32(0, v, Endian.little),
    );
  }

  void string(String s) {
    final b = utf8.encode(s);
    u32(b.length);
    bytes
      ..addAll(b)
      ..add(0);
  }

  void signature(String s) {
    byte(s.length);
    bytes
      ..addAll(ascii.encode(s))
      ..add(0);
  }

  void value(String type, Object v) {
    switch (type[0]) {
      case 'y':
        byte(v as int);
      case 'b':
        u32((v as bool) ? 1 : 0);
      case 'i':
        i32(v as int);
      case 'u':
        u32(v as int);
      case 's' || 'o':
        string(v as String);
      case 'g':
        signature(v as String);
      case 'v':
        final variant = v as DbusVariant;
        signature(variant.signature);
        value(variant.signature, variant.value);
      case '(':
        pad(8);
        final types = _types(type.substring(1, type.length - 1));
        final items = v as List<Object>;
        for (var i = 0; i < types.length; i++) {
          value(types[i], items[i]);
        }
      case 'a':
        final element = type.substring(1);
        u32(0);
        final lengthAt = bytes.length - 4;
        pad(_alignment(element));
        final start = bytes.length;
        if (element.startsWith('{')) {
          final types = _types(element.substring(1, element.length - 1));
          final entries = (v as Map<Object, Object>).entries;
          for (final MapEntry(:key, :value) in entries) {
            pad(8);
            this.value(types[0], key);
            this.value(types[1], value);
          }
        } else {
          for (final item in v as List<Object>) {
            value(element, item);
          }
        }
        final n = bytes.length - start;
        bytes.setRange(
          lengthAt,
          lengthAt + 4,
          Uint8List(4)..buffer.asByteData().setUint32(0, n, Endian.little),
        );
      default:
        throw ArgumentError.value(type, 'type', 'not written');
    }
  }
}

final class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  var at = 0;

  void align(int to) => at = _align(at, to);

  int u32() {
    align(4);
    final v = data.getUint32(at, Endian.little);
    at += 4;
    return v;
  }

  String string() {
    final n = u32();
    final s = utf8.decode(Uint8List.sublistView(bytes, at, at + n));
    at += n + 1;
    return s;
  }

  String signature() {
    final n = bytes[at];
    final s = ascii.decode(Uint8List.sublistView(bytes, at + 1, at + 1 + n));
    at += n + 2;
    return s;
  }

  Object? value(String type) {
    switch (type[0]) {
      case 'y':
        return bytes[at++];
      case 'b':
        return u32() != 0;
      case 'n' || 'q':
        align(2);
        final v = type == 'n'
            ? data.getInt16(at, Endian.little)
            : data.getUint16(at, Endian.little);
        at += 2;
        return v;
      case 'i':
        align(4);
        final v = data.getInt32(at, Endian.little);
        at += 4;
        return v;
      case 'u':
        return u32();
      case 'x' || 't':
        align(8);
        final v = data.getInt64(at, Endian.little);
        at += 8;
        return v;
      case 'd':
        align(8);
        final v = data.getFloat64(at, Endian.little);
        at += 8;
        return v;
      case 's' || 'o':
        return string();
      case 'g':
        return signature();
      case 'v':
        return value(signature());
      case '(':
        align(8);
        return [
          for (final t in _types(type.substring(1, type.length - 1))) value(t),
        ];
      case 'a':
        final n = u32();
        final element = type.substring(1);
        align(_alignment(element));
        final end = at + n;
        if (element.startsWith('{')) {
          final types = _types(element.substring(1, element.length - 1));
          final map = <Object?, Object?>{};
          while (at < end) {
            align(8);
            final key = value(types[0]);
            map[key] = value(types[1]);
          }
          return map;
        }
        final list = <Object?>[];
        while (at < end) {
          list.add(value(element));
        }
        return list;
    }
    throw FormatException('type $type not read');
  }
}
