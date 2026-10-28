import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cipherlib/cipherlib.dart' show MLKEM;
import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:test/test.dart';
import 'package:twk_ssh/src/crypto.dart';
import 'package:twk_ssh/src/packet.dart';
import 'package:twk_ssh/src/wire.dart';
import 'package:twk_ssh/twk_ssh.dart';
import 'package:twk_test/twk_test.dart';

/// A host key made once for all the tests: generating one is quick, but
/// the client checks it is the same across connections only by type.
final hostKey = SshHostKey.generate();

/// A client key pair, and its public key as the server sees it.
final class ClientKey {
  ClientKey._(this.pair);

  factory ClientKey.ed25519() {
    final key = ed25519.SigningKey.generate();
    return ClientKey._(
      OpenSSHEd25519KeyPair(
        Uint8List.fromList(key.verifyKey.asTypedList),
        Uint8List.fromList(key.asTypedList),
        'test',
      ),
    );
  }

  /// A key ssh-keygen makes, of [type] (`rsa`, `ecdsa`) and [bits], in
  /// [dir]; null without ssh-keygen.
  static Future<ClientKey?> keygen(Directory dir, String type, int bits) async {
    final path = '${dir.path}/id_$type$bits';
    final r = await sshKeygen([
      '-q', '-t', type, '-b', '$bits', '-N', '', '-f', path, //
    ]);
    if (r == null || r.exitCode != 0) {
      return null;
    }
    return ClientKey._(
      SSHKeyPair.fromPem(File(path).readAsStringSync()).single,
    );
  }

  final SSHKeyPair pair;
  late final publicKey = SshPublicKey.decode(pair.toPublicKey().encode());
}

/// Whether [executable] is a file in a directory of the `PATH`.
bool onPath(String executable) {
  final path = Platform.environment['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  return path
      .split(separator)
      .where((dir) => dir.isNotEmpty)
      .any((dir) => File('$dir/$executable').existsSync());
}

/// A run of ssh-keygen with [arguments], ended with the test if it still
/// runs then; null where ssh-keygen is not installed.
Future<ProcessResult?> sshKeygen(List<String> arguments) async =>
    onPath('ssh-keygen') ? runProcess('ssh-keygen', arguments) : null;

/// A server on the loopback interface, at a port the system picks, closed
/// when the test ends.
Future<SshServer> serve({
  required SshAuth auth,
  required SessionHandler onSession,
  List<SshHostKey>? hostKeys,
  Duration loginTimeout = const Duration(seconds: 10),
  int maxUnauthenticated = 10,
  SshRekeyLimit rekeyLimit = const SshRekeyLimit(),
  Stopwatch? clock,
  SshTimers? timers,
}) async {
  final server = await SshServer.bind(
    InternetAddress.loopbackIPv4,
    0,
    hostKeys: hostKeys ?? [hostKey],
    auth: auth,
    onSession: onSession,
    loginTimeout: loginTimeout,
    maxUnauthenticated: maxUnauthenticated,
    rekeyLimit: rekeyLimit,
    clock: clock,
    timers: timers,
  );
  addTearDown(server.close);
  return server;
}

/// A dartssh2 client of [server], closed when the test ends.
Future<SSHClient> connect(
  SshServer server, {
  String user = 'alice',
  List<SSHKeyPair>? identities,
  FutureOr<String?> Function()? password,
  SSHAlgorithms algorithms = const SSHAlgorithms(),
}) async {
  final client = SSHClient(
    await SSHSocket.connect(server.address.address, server.port),
    username: user,
    identities: identities,
    onPasswordRequest: password,
    algorithms: algorithms,
    onVerifyHostKey: (_, _) => true,
  );
  addTearDown(client.close);
  return client;
}

/// Accepts the keys [keys] for any user.
SshAuth acceptKeys(List<ClientKey> keys) =>
    SshAuth(publicKey: (_, key) => keys.any((k) => k.publicKey == key));

/// What [stream] gives until [done] holds for what came so far.
Future<String> readUntil(
  Stream<Uint8List> stream,
  bool Function(String text) done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final text = StringBuffer();
  final finished = Completer<String>();
  late final StreamSubscription<Uint8List> sub;
  sub = stream.listen(
    (bytes) {
      text.write(utf8.decode(bytes, allowMalformed: true));
      if (!finished.isCompleted && done('$text')) {
        finished.complete('$text');
      }
    },
    onDone: () {
      if (!finished.isCompleted) {
        finished.complete('$text');
      }
    },
  );
  try {
    return await finished.future.timeout(timeout);
  } finally {
    await sub.cancel();
  }
}

/// A client that speaks the protocol by hand: for what a real client never
/// sends, and for watching what the server sends in what order.
final class RawClient {
  RawClient._(this.socket) {
    _sub = socket.listen(
      _onData,
      onDone: _onDone,
      onError: (Object _) => _onDone(),
    );
  }

  /// A client of [server]; with [receiveBuffer], the socket's receive
  /// buffer is that small (SO_RCVBUF, Linux), so a client that doesn't
  /// read stalls the server soon.
  static Future<RawClient> connect(
    SshServer server, {
    int? receiveBuffer,
  }) async {
    final socket = await Socket.connect(server.address, server.port);
    final client = RawClient._(socket);
    if (receiveBuffer != null) {
      client.setReceiveBuffer(receiveBuffer);
    }
    addTearDown(socket.destroy);
    return client;
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _sub;
  final _reader = PacketReader();
  final _writer = PacketWriter();
  final _line = <int>[];

  static const clientVersion = 'SSH-2.0-raw';

  /// The server's version line, once read.
  String? serverVersion;

  /// The first bytes the server sent.
  String get rawText => latin1.decode(_first);
  final _first = <int>[];
  var _garbled = false;

  /// A NEWKEYS was read: what follows waits for the keys.
  var _waitingForKeys = false;

  final _payloads = Queue<Uint8List>();
  Completer<void>? _waiting;
  var closed = false;

  Uint8List? sessionId;

  /// The size of the socket's receive buffer (SO_RCVBUF, Linux): how much
  /// the kernel takes in for the client before the server's writes wait.
  /// Small, it holds back all that comes after too: through a 4 KiB
  /// buffer the server's answers come at some 40 KB/s.
  void setReceiveBuffer(int bytes) => socket.setRawOption(
    RawSocketOption.fromInt(RawSocketOption.levelSocket, 8, bytes),
  );

  /// Stops reading what the server sends, and starts again.
  void pause() => _sub.pause();
  void resume() => _sub.resume();

  void _onData(Uint8List bytes) {
    if (_first.length < 4096) {
      _first.addAll(bytes);
    }
    var rest = bytes;
    if (serverVersion == null) {
      final lf = bytes.indexOf(0x0A);
      _line.addAll(lf < 0 ? bytes : bytes.sublist(0, lf));
      if (lf < 0) {
        return;
      }
      serverVersion = latin1.decode(_line).trimRight();
      rest = Uint8List.sublistView(bytes, lf + 1);
    }
    _reader.add(rest);
    _decode();
  }

  void _decode() {
    if (_garbled) {
      return;
    }
    try {
      while (!_waitingForKeys) {
        final p = _reader.next();
        if (p == null) {
          break;
        }
        _payloads.add(Uint8List.fromList(p));
        _waitingForKeys = p[0] == SshMsg.newKeys;
      }
    } on SshProtocolException {
      _garbled = true; // not packets: text after the version line
    }
    _wake();
  }

  void _onDone() {
    closed = true;
    _wake();
  }

  void _wake() {
    final w = _waiting;
    _waiting = null;
    w?.complete();
  }

  void version([String line = clientVersion]) =>
      socket.add(ascii.encode('$line\r\n'));

  void send(List<int> payload) => socket.add(_writer.encode(payload));

  void sendMessage(void Function(SshWriter w) write) {
    final w = SshWriter();
    write(w);
    send(w.takeBytes());
  }

  /// The next payload from the server; null once it closed.
  Future<Uint8List?> next({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    while (_payloads.isEmpty && !closed) {
      await (_waiting ??= Completer<void>()).future.timeout(timeout);
    }
    return _payloads.isEmpty ? null : _payloads.removeFirst();
  }

  /// The next message [id], skipping those of [skip] before it.
  Future<Uint8List> expectNext(
    int id, {
    Set<int> skip = const {SshMsg.extInfo, SshMsg.ignore, SshMsg.debug},
  }) async {
    for (;;) {
      final p = await next();
      if (p == null) {
        fail('closed while waiting for message $id');
      }
      if (p[0] == id) {
        return p;
      }
      if (!skip.contains(p[0])) {
        fail('message ${p[0]} while waiting for $id');
      }
    }
  }

  /// The reason of the DISCONNECT the server ends with, skipping what comes
  /// before it; null when it closes without one.
  Future<int?> disconnectReason() async {
    for (var p = await next(); p != null; p = await next()) {
      if (p[0] == SshMsg.disconnect) {
        return (SshReader(p)..byte()).uint32();
      }
    }
    return null;
  }

  /// Whether the server closes within [within].
  Future<bool> closes(Duration within) async {
    try {
      while (!closed) {
        await (_waiting ??= Completer<void>()).future.timeout(within);
      }
      return true;
    } on TimeoutException {
      return false;
    }
  }

  /// The client's side of a key exchange of [kex], strict, in aes128-ctr
  /// with hmac-sha2-256: the [first], after the version line, or one it
  /// starts later (or answers, when the server's KEXINIT came first).
  /// [serverKexInit] is the server's KEXINIT when it was read already.
  /// Returns the messages the server sent between its KEXINIT and its
  /// NEWKEYS, the reply left out.
  Future<List<int>> exchangeKeys({
    bool first = true,
    String kex = 'curve25519-sha256',
    Uint8List? serverKexInit,
  }) async {
    var theirs = serverKexInit;
    if (first) {
      version();
    }
    final kexInit = clientKexInit(kex: [kex], strict: first);
    send(kexInit);
    // what comes before the server's KEXINIT it sent before it saw ours
    while (theirs == null) {
      final p = await next();
      if (p == null) {
        fail('closed during the key exchange');
      }
      if (p[0] == SshMsg.kexInit) {
        theirs = p;
      }
    }
    final between = <int>[];
    final ephemeral = X25519();
    final hybrid = kex == mlkem768x25519;
    // the client's ML-KEM-768 key pair, for the hybrid
    final pq = MLKEM.kem768().keygen();
    // KEX_ECDH_INIT, or KEX_HYBRID_INIT: C_INIT = C_PK2 || C_PK1
    final init = hybrid
        ? Uint8List.fromList([...pq.encapsulationKey, ...ephemeral.publicKey])
        : ephemeral.publicKey;
    sendMessage(
      (w) => w
        ..byte(SshMsg.kexEcdhInit)
        ..string(init),
    );
    Future<Uint8List> until(int id) async {
      for (;;) {
        final p = (await next())!;
        if (p[0] == id) {
          return p;
        }
        between.add(p[0]);
      }
    }

    final r = SshReader(await until(SshMsg.kexEcdhReply))..byte();
    final hostKey = r.string();
    final serverKey = r.string();
    final signature = r.string();
    final Uint8List k;
    if (hybrid) {
      // S_REPLY = S_CT2 || S_PK1; K = SHA-256(K_PQ || K_CL), a string
      expect(serverKey, hasLength(1088 + 32));
      final pqSecret = MLKEM.kem768().decaps(
        pq.decapsulationKey,
        Uint8List.sublistView(serverKey, 0, 1088),
      );
      final classical = ephemeral.agree(Uint8List.sublistView(serverKey, 1088));
      k = (SshWriter()..string(sha256([...pqSecret.bytes, ...classical])))
          .takeBytes();
    } else {
      k = (SshWriter()..mpint(ephemeral.agree(serverKey))).takeBytes();
    }
    final h = sha256(
      (SshWriter()
            ..utf8String(clientVersion)
            ..utf8String(serverVersion!)
            ..string(kexInit)
            ..string(theirs)
            ..string(hostKey)
            ..string(init)
            ..string(serverKey)
            ..raw(k))
          .takeBytes(),
    );
    expect(
      SshPublicKey.decode(hostKey).verify('ssh-ed25519', h, signature),
      isTrue,
    );
    final id = sessionId ??= h;
    Uint8List derive(int letter, int length) => Uint8List.sublistView(
      sha256([...k, ...h, letter, ...id]),
      0,
      length,
    );
    final cipher = CipherSpec.all.first;
    final mac = MacSpec.all[2];
    await until(SshMsg.newKeys);
    send(const [SshMsg.newKeys]);
    _writer
      ..rekey(
        DirectionKeys(
          cipher.create(derive(0x43, 16), derive(0x41, 16)),
          mac.create(derive(0x45, 32)),
          etm: false,
        ),
      )
      ..resetSequence();
    _reader
      ..rekey(
        DirectionKeys(
          cipher.create(derive(0x44, 16), derive(0x42, 16)),
          mac.create(derive(0x46, 32)),
          etm: false,
        ),
      )
      ..resetSequence();
    _waitingForKeys = false;
    _decode();
    return between;
  }

  /// Logs in as [user] with [key].
  Future<void> logIn(String user, SSHKeyPair key) async {
    sendMessage(
      (w) => w
        ..byte(SshMsg.serviceRequest)
        ..utf8String('ssh-userauth'),
    );
    await expectNext(SshMsg.serviceAccept);
    final blob = key.toPublicKey().encode();
    void request(SshWriter w) => w
      ..byte(SshMsg.userauthRequest)
      ..utf8String(user)
      ..utf8String('ssh-connection')
      ..utf8String('publickey')
      ..boolean(true)
      ..utf8String(key.type)
      ..string(blob);
    final signed = SshWriter()..string(sessionId!);
    request(signed);
    final signature = key.sign(signed.takeBytes()).encode();
    sendMessage((w) {
      request(w);
      w.string(signature);
    });
    await expectNext(SshMsg.userauthSuccess);
  }

  /// Opens a session channel granting [window] and asks for a shell;
  /// returns the server's number for the channel.
  Future<int> openShell({int window = 1 << 20}) async {
    sendMessage(
      (w) => w
        ..byte(SshMsg.channelOpen)
        ..utf8String('session')
        ..uint32(0)
        ..uint32(window)
        ..uint32(1 << 15),
    );
    final confirmation =
        SshReader(
            await expectNext(SshMsg.channelOpenConfirmation),
          )
          ..byte()
          ..uint32();
    final channel = confirmation.uint32();
    sendMessage(
      (w) => w
        ..byte(SshMsg.channelRequest)
        ..uint32(channel)
        ..utf8String('shell')
        ..boolean(true),
    );
    await expectNext(SshMsg.channelSuccess);
    return channel;
  }
}

/// A KEXINIT as a client sends it.
Uint8List clientKexInit({
  List<String> kex = const ['curve25519-sha256'],
  List<String> hostKeys = const ['ssh-ed25519'],
  List<String> ciphers = const ['aes128-ctr'],
  List<String> macs = const ['hmac-sha2-256'],
  List<String> compression = const ['none'],
  bool strict = false,
}) =>
    (SshWriter()
          ..byte(SshMsg.kexInit)
          ..raw(Uint8List(16))
          ..nameList([...kex, if (strict) 'kex-strict-c-v00@openssh.com'])
          ..nameList(hostKeys)
          ..nameList(ciphers)
          ..nameList(ciphers)
          ..nameList(macs)
          ..nameList(macs)
          ..nameList(compression)
          ..nameList(compression)
          ..nameList(const [])
          ..nameList(const [])
          ..boolean(false)
          ..uint32(0))
        .takeBytes();
