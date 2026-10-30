/// The transport layer of one connection, the server's end (RFC 4253):
/// the version exchange, the key exchanges, and the packets both ways.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'crypto.dart';
import 'keys.dart';
import 'packet.dart';
import 'wire.dart';

/// When the server starts a key exchange of its own (RFC 4253 §9): once
/// the keys in effect have carried [bytes] either way, or have been in
/// effect for [time].
///
/// RFC 4253 recommends a gigabyte or an hour, whichever comes first, and
/// those are the defaults. Both are checked as packets go (before one is
/// sent, after one is read), so a connection with no traffic keeps its
/// keys, which then protect nothing new; the first packet after the limit
/// starts the exchange and what the layers above send then goes under the
/// new keys. The server also rekeys before 2^31 packets either way, as
/// OpenSSH does, whatever the limits.
final class SshRekeyLimit {
  /// A rekey after [bytes] or [time], whichever comes first.
  const SshRekeyLimit({
    this.bytes = 1 << 30,
    this.time = const Duration(hours: 1),
  });

  /// The bytes in one direction, MACs included, after which the keys
  /// change.
  final int bytes;

  /// How long keys stay in effect, read on the transport's clock.
  final Duration time;
}

/// Starts a timer that calls [callback] once [duration] has passed:
/// `Timer.new`, or a test's on a fake clock.
typedef SshTimers = Timer Function(Duration duration, void Function() callback);

/// What the transport hands up: a message above it, from
/// SSH_MSG_SERVICE_REQUEST on. Returns false for one it doesn't know,
/// which is answered with SSH_MSG_UNIMPLEMENTED.
typedef MessageHandler = FutureOr<bool> Function(Uint8List payload);

/// The server's end of a connection's transport.
///
/// The first key exchange starts as soon as the client's version line is
/// read, and nothing else is taken or sent until it is done: a message of
/// the layers above that arrives before the client's NEWKEYS ends the
/// connection, and so do the optional ones (IGNORE, DEBUG) under strict
/// key exchange, which the server offers and does when the client does
/// too (the Terrapin countermeasure: the client's KEXINIT must be its
/// first packet, and the sequence numbers start again from 0 after each
/// NEWKEYS). A key exchange the client starts later is taken the same way;
/// what the layers above send meanwhile waits until the server's NEWKEYS
/// ([holding], [onReleased]). A client that doesn't see a key exchange
/// through within [kexTimeout], or makes the server hold more than
/// [maxHeld] bytes meanwhile, is disconnected. Algorithms the client and
/// the server don't share end the connection with KEY_EXCHANGE_FAILED.
///
/// The server starts a key exchange itself after [SshRekeyLimit], read on
/// its clock.
///
/// Messages are handled one at a time, in order: while [onMessage] works
/// on one, the socket is paused.
final class SshTransport {
  /// The transport of a client's socket, proving itself with [hostKeys],
  /// its version line naming [version]; the messages above it go to
  /// [onMessage], and [onClose] is called once it ends. It rekeys after
  /// [rekeyLimit], its time read on [clock] (a new stopwatch by default;
  /// a test's runs on a fake clock), and gives up a key exchange the
  /// client doesn't finish by a deadline set on [timers] (`Timer.new` by
  /// default). [onReleased] is called when what was held is sent.
  SshTransport(
    this._socket, {
    required List<SshHostKey> hostKeys,
    required String version,
    required this.onMessage,
    this.onClose,
    this.onReleased,
    this.rekeyLimit = const SshRekeyLimit(),
    Stopwatch? clock,
    SshTimers? timers,
  }) : _hostKeys = {for (final k in hostKeys) k.algorithm: k},
       _serverVersion = 'SSH-2.0-$version',
       _clock = clock ?? (Stopwatch()..start()),
       _timers = timers ?? Timer.new {
    if (_hostKeys.isEmpty) {
      throw ArgumentError.value(hostKeys, 'hostKeys', 'no host key');
    }
    _sub = _socket.listen(
      _onData,
      onError: (Object _) => close(),
      onDone: close,
      cancelOnError: true,
    );
    _write(ascii.encode('$_serverVersion\r\n'));
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _sub;
  final Map<String, SshHostKey> _hostKeys;
  final String _serverVersion;

  /// Handles the messages of the layers above.
  final MessageHandler onMessage;

  /// Called once, when the connection ends.
  final void Function()? onClose;

  /// Called when the server's NEWKEYS is sent and what was held with it:
  /// what the layers above send goes out again ([holding]).
  final void Function()? onReleased;

  /// How long the client has for a key exchange after the first, from the
  /// server's KEXINIT to the client's NEWKEYS.
  static const kexTimeout = Duration(minutes: 1);

  /// The most bytes the server holds of what the layers above send while
  /// a key exchange is under way; a client that makes it hold more (by
  /// asking for answers and not finishing the exchange) is disconnected.
  @visibleForTesting
  static int maxHeld = 1 << 20;

  /// When the server starts a key exchange.
  final SshRekeyLimit rekeyLimit;

  final Stopwatch _clock;
  final SshTimers _timers;
  Timer? _kexTimer;

  /// When the keys in effect took effect, on [_clock].
  Duration _keyedAt = Duration.zero;

  /// The most packets one direction carries before the server rekeys, as
  /// OpenSSH's MAX_PACKETS: well before the sequence numbers wrap.
  @visibleForTesting
  static int maxPackets = 1 << 31;

  /// The client's version line, without its line break; null until read.
  String? get clientVersion => _clientVersion;
  String? _clientVersion;
  final _versionLine = BytesBuilder(copy: false);

  /// The exchange hash of the first key exchange; null until it is done.
  Uint8List? get sessionId => _sessionId;
  Uint8List? _sessionId;

  final _reader = PacketReader();
  final _writer = PacketWriter();

  /// Whether a key exchange is under way on the client's side: from its
  /// KEXINIT (from the start, for the first) to its NEWKEYS.
  var _inKex = true;

  /// Whether what the layers above send waits: from the server's KEXINIT
  /// to its NEWKEYS.
  var _holding = true;
  final _held = <Uint8List>[];
  var _heldBytes = 0;

  /// Whether what the layers above send is held, a key exchange under way
  /// on the server's side: what isn't needed now (a channel's data) is
  /// better kept until [onReleased].
  bool get holding => _holding;

  var _firstKex = true;
  var _strict = false;
  var _extInfo = false;
  Uint8List? _serverKexInit;
  Uint8List? _clientKexInit;
  _Negotiated? _negotiated;
  var _ignoreGuess = false;
  var _sentNewKeys = false;
  DirectionKeys? _nextIncoming;

  var _pumping = false;
  var _closed = false;
  final _done = Completer<void>();

  /// Whether the connection is closed.
  bool get isClosed => _closed;

  /// Completes once the connection is closed.
  Future<void> get done => _done.future;

  /// How many key exchanges are done, the first included.
  int get keyExchanges => _keyExchanges;
  var _keyExchanges = 0;

  /// How many key exchanges the server started.
  int get serverKeyExchanges => _serverKeyExchanges;
  var _serverKeyExchanges = 0;

  /// Whether the first key exchange was strict.
  bool get strictKex => _strict;

  /// The key exchange method of the last exchange; null until one is
  /// agreed on.
  String? get kexAlgorithm => _kexAlgorithm;
  String? _kexAlgorithm;

  /// Sends [payload], a message of the layers above; held while the
  /// server's side of a key exchange is under way.
  void send(Uint8List payload) {
    if (_closed) {
      return;
    }
    _rekeyIfDue();
    if (_holding) {
      _held.add(payload);
      _heldBytes += payload.length;
      if (_heldBytes > maxHeld) {
        disconnect(
          SshDisconnect.byApplication,
          'too much held during the key exchange',
        );
      }
    } else {
      _sendPacket(payload);
    }
  }

  /// Ends the connection with SSH_MSG_DISCONNECT, [reason] (an
  /// [SshDisconnect] code) and [description].
  void disconnect(int reason, String description) {
    if (_closed) {
      return;
    }
    _sendPacket(
      (SshWriter()
            ..byte(SshMsg.disconnect)
            ..uint32(reason)
            ..utf8String(description)
            ..utf8String(''))
          .takeBytes(),
    );
    close();
  }

  /// Closes the connection without a word.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _held.clear();
    _kexTimer?.cancel();
    unawaited(_sub.cancel());
    unawaited(_shutdown());
    _done.complete();
    onClose?.call();
  }

  /// Sends what is queued, then closes the socket; destroys it when that
  /// takes more than a few seconds (a client that doesn't read).
  Future<void> _shutdown() async {
    try {
      while (_flushing) {
        await (_idle ??= Completer<void>()).future.timeout(
          const Duration(seconds: 2),
        );
      }
      await _socket.close().timeout(const Duration(seconds: 2));
    } on Object {
      // gone, or not reading: destroyed below
    } finally {
      _socket.destroy();
    }
  }

  /// The most bytes queued for the socket before the client's messages
  /// are no longer read (they are what makes the server write).
  @visibleForTesting
  static int maxQueued = 1 << 20;

  final _queue = <List<int>>[];
  var _queued = 0;
  var _flushing = false;
  var _readingPaused = false;
  Completer<void>? _idle;

  /// The most bytes that were queued at once.
  @visibleForTesting
  int get maxQueuedSeen => _maxQueuedSeen;
  var _maxQueuedSeen = 0;

  /// Writes [bytes] to the socket: at once while no flush runs, queued
  /// while one does. Over [maxQueued] the socket is no longer read until
  /// the queue goes out: a client that doesn't read what the server sends
  /// can't make it hold more.
  void _write(List<int> bytes) {
    if (_flushing) {
      _queue.add(bytes);
      _queued += bytes.length;
      if (_queued > _maxQueuedSeen) {
        _maxQueuedSeen = _queued;
      }
      if (_queued > maxQueued && !_readingPaused && !_closed) {
        _readingPaused = true;
        _sub.pause();
      }
      return;
    }
    try {
      _socket.add(bytes);
    } on Object {
      return close();
    }
    _flushing = true;
    unawaited(
      _socket.flush().then(
        _flushed,
        onError: (Object _) {
          _flushing = false;
          _wakeIdle();
          close();
        },
      ),
    );
  }

  void _flushed(Object? _) {
    _flushing = false;
    if (_queue.isEmpty) {
      return _wakeIdle();
    }
    final queued = BytesBuilder(copy: false);
    _queue
      ..forEach(queued.add)
      ..clear();
    _queued = 0;
    _write(queued.takeBytes());
    if (_readingPaused) {
      _readingPaused = false;
      if (!_closed) {
        _sub.resume();
        unawaited(_pump());
      }
    }
  }

  void _wakeIdle() {
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }

  void _sendPacket(List<int> payload) {
    if (!_closed) {
      _write(_writer.encode(payload));
    }
  }

  /// Whether the socket is not read now: the queue went over [maxQueued],
  /// or a message is still being handled.
  @visibleForTesting
  bool get readingPaused => _sub.isPaused;

  /// Bytes queued for the socket now.
  @visibleForTesting
  int get queued => _queued;

  void _onData(Uint8List bytes) {
    if (_closed) {
      return;
    }
    if (_clientVersion == null) {
      final rest = _readVersion(bytes);
      if (rest == null) {
        return;
      }
      _reader.add(rest);
      _sendKexInit();
    } else {
      _reader.add(bytes);
    }
    unawaited(_pump());
  }

  /// Takes [bytes] into the version line; what follows it once it is
  /// complete, null until then.
  Uint8List? _readVersion(Uint8List bytes) {
    final lf = bytes.indexOf(0x0A);
    _versionLine.add(lf < 0 ? bytes : Uint8List.sublistView(bytes, 0, lf));
    // 255 bytes with the line break (RFC 4253 §4.2)
    if (_versionLine.length > 254) {
      close();
      return null;
    }
    if (lf < 0) {
      return null;
    }
    var line = latin1.decode(_versionLine.takeBytes());
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    if (!line.startsWith('SSH-2.0-') && !line.startsWith('SSH-1.99-')) {
      _write(ascii.encode('Protocol mismatch.\r\n'));
      close();
      return null;
    }
    _clientVersion = line;
    return Uint8List.sublistView(bytes, lf + 1);
  }

  Future<void> _pump() async {
    if (_pumping) {
      return;
    }
    _pumping = true;
    try {
      while (!_closed && !_readingPaused) {
        final payload = _reader.next();
        if (payload == null) {
          break;
        }
        _rekeyIfDue();
        final pending = _handle(payload);
        if (pending != null) {
          _sub.pause();
          try {
            await pending;
          } finally {
            if (!_closed) {
              _sub.resume();
            }
          }
        }
      }
    } on SshProtocolException catch (e) {
      disconnect(e.reason, e.message);
    } on Object {
      disconnect(SshDisconnect.byApplication, 'internal error');
    } finally {
      _pumping = false;
    }
  }

  /// Handles one message; a future while it is still at work on it.
  Future<void>? _handle(Uint8List payload) {
    final id = payload[0];
    if (id == SshMsg.kexInit) {
      _onKexInit(payload);
      return null;
    }
    if (_inKex) {
      switch (id) {
        case SshMsg.kexEcdhInit:
          _onEcdhInit(payload);
        case SshMsg.newKeys:
          _onNewKeys(payload);
        case SshMsg.disconnect:
          close();
        case SshMsg.ignore || SshMsg.debug || SshMsg.unimplemented
            when !(_strict && _firstKex):
          break;
        default:
          throw SshProtocolException('message $id during the key exchange');
      }
      return null;
    }
    switch (id) {
      case SshMsg.disconnect:
        close();
        return null;
      case SshMsg.ignore || SshMsg.debug || SshMsg.unimplemented:
        return null;
    }
    if (id >= 20 && id < 50) {
      throw SshProtocolException('message $id outside a key exchange');
    }
    final sequence = (_reader.sequence - 1) & 0xFFFFFFFF;
    final handled = onMessage(payload);
    if (handled is Future<bool>) {
      return handled.then((known) {
        if (!known) {
          _unimplemented(sequence);
        }
      });
    }
    if (!handled) {
      _unimplemented(sequence);
    }
    return null;
  }

  void _unimplemented(int sequence) => send(
    (SshWriter()
          ..byte(SshMsg.unimplemented)
          ..uint32(sequence))
        .takeBytes(),
  );

  // ------------------------------------------------------- key exchange --

  /// Starts a key exchange when the keys in effect are past
  /// [rekeyLimit] or [maxPackets], and none is under way.
  void _rekeyIfDue() {
    if (_closed || _holding || _inKex) {
      return;
    }
    final limit = rekeyLimit;
    if (_writer.bytes >= limit.bytes ||
        _reader.bytes >= limit.bytes ||
        _writer.packets >= maxPackets ||
        _reader.packets >= maxPackets ||
        _clock.elapsed - _keyedAt >= limit.time) {
      _serverKeyExchanges++;
      _sendKexInit();
    }
  }

  void _sendKexInit() {
    final w = SshWriter()
      ..byte(SshMsg.kexInit)
      ..raw(randomBytes(16))
      ..nameList([...kexAlgorithms, if (_firstKex) strictKexServer])
      ..nameList(_hostKeys.keys.toList())
      ..nameList([for (final c in CipherSpec.all) c.name])
      ..nameList([for (final c in CipherSpec.all) c.name])
      ..nameList([for (final m in MacSpec.all) m.name])
      ..nameList([for (final m in MacSpec.all) m.name])
      ..nameList(const ['none'])
      ..nameList(const ['none'])
      ..nameList(const [])
      ..nameList(const [])
      ..boolean(false)
      ..uint32(0);
    final payload = w.takeBytes();
    _serverKexInit = payload;
    _holding = true;
    if (!_firstKex) {
      // the first is the login's to time
      _kexTimer = _timers(
        kexTimeout,
        () => disconnect(
          SshDisconnect.keyExchangeFailed,
          'the key exchange timed out',
        ),
      );
    }
    _sendPacket(payload);
  }

  void _onKexInit(Uint8List payload) {
    if (_clientKexInit != null) {
      throw const SshProtocolException('a second KEXINIT');
    }
    final r = SshReader(payload)
      ..byte()
      ..raw(16);
    final kex = r.nameList();
    final hostKeys = r.nameList();
    final ciphersIn = r.nameList();
    final ciphersOut = r.nameList();
    final macsIn = r.nameList();
    final macsOut = r.nameList();
    final compressionIn = r.nameList();
    final compressionOut = r.nameList();
    r
      ..nameList()
      ..nameList();
    final guessFollows = r.boolean();
    r.uint32();
    if (_firstKex) {
      _strict = kex.contains(strictKexClient);
      _extInfo = kex.contains(extInfoClient);
      // the KEXINIT must have been the first packet: none slipped in
      if (_strict && _reader.sequence != 1) {
        throw const SshProtocolException('KEXINIT was not the first packet');
      }
    }
    _inKex = true;
    _clientKexInit = Uint8List.fromList(payload);
    if (_serverKexInit == null) {
      _sendKexInit();
    }
    String pick(List<String> client, Iterable<String> server, String what) {
      for (final name in client) {
        if (server.contains(name)) {
          return name;
        }
      }
      throw SshProtocolException(
        'no $what in common',
        SshDisconnect.keyExchangeFailed,
      );
    }

    final kexName = pick(kex, kexAlgorithms, 'key exchange');
    final hostKey = pick(hostKeys, _hostKeys.keys, 'host key algorithm');
    final cipherNames = [for (final c in CipherSpec.all) c.name];
    final macNames = [for (final m in MacSpec.all) m.name];
    final cipherIn = pick(ciphersIn, cipherNames, 'cipher');
    final cipherOut = pick(ciphersOut, cipherNames, 'cipher');
    final macIn = pick(macsIn, macNames, 'MAC');
    final macOut = pick(macsOut, macNames, 'MAC');
    pick(compressionIn, const ['none'], 'compression');
    pick(compressionOut, const ['none'], 'compression');
    _kexAlgorithm = kexName;
    _negotiated = _Negotiated(
      _hostKeys[hostKey]!,
      CipherSpec.all.firstWhere((c) => c.name == cipherIn),
      CipherSpec.all.firstWhere((c) => c.name == cipherOut),
      MacSpec.all.firstWhere((m) => m.name == macIn),
      MacSpec.all.firstWhere((m) => m.name == macOut),
    );
    // a guessed first exchange packet that guessed wrong is skipped
    _ignoreGuess =
        guessFollows && (kex.first != kexName || hostKeys.first != hostKey);
  }

  void _onEcdhInit(Uint8List payload) {
    final negotiated = _negotiated;
    if (negotiated == null || _sentNewKeys) {
      throw const SshProtocolException('an unexpected KEX_ECDH_INIT');
    }
    if (_ignoreGuess) {
      _ignoreGuess = false;
      return;
    }
    // KEX_ECDH_INIT, or KEX_HYBRID_INIT: the same number and shape
    final r = SshReader(payload)..byte();
    final clientKey = r.string();
    final (:reply, secret: k) = agree(_kexAlgorithm!, clientKey);
    final hostKey = negotiated.hostKey;
    final hostKeyBlob = hostKey.publicKey;
    final h = sha256(
      (SshWriter()
            ..utf8String(_clientVersion!)
            ..utf8String(_serverVersion)
            ..string(_clientKexInit!)
            ..string(_serverKexInit!)
            ..string(hostKeyBlob)
            ..string(clientKey)
            ..string(reply)
            ..raw(k))
          .takeBytes(),
    );
    final sessionId = _sessionId ??= h;
    _sendPacket(
      (SshWriter()
            ..byte(SshMsg.kexEcdhReply)
            ..string(hostKeyBlob)
            ..string(reply)
            ..string(hostKey.sign(h)))
          .takeBytes(),
    );
    _sendPacket(const [SshMsg.newKeys]);

    Uint8List derive(int letter, int length) {
      var out = sha256([...k, ...h, letter, ...sessionId]);
      while (out.length < length) {
        out = Uint8List.fromList([
          ...out,
          ...sha256([...k, ...h, ...out]),
        ]);
      }
      return Uint8List.sublistView(out, 0, length);
    }

    DirectionKeys keys(
      CipherSpec cipher,
      MacSpec mac,
      int iv,
      int key,
      int m,
    ) => DirectionKeys(
      cipher.create(
        derive(key, cipher.keyLength),
        derive(iv, cipher.ivLength),
      ),
      mac.create(derive(m, mac.keyLength)),
      etm: mac.etm,
    );

    // A to F (RFC 4253 §7.2): the IVs, the keys and the MAC keys, client
    // to server first
    _writer.rekey(
      keys(negotiated.cipherOut, negotiated.macOut, 0x42, 0x44, 0x46),
    );
    if (_strict) {
      _writer.resetSequence();
    }
    _nextIncoming = keys(
      negotiated.cipherIn,
      negotiated.macIn,
      0x41,
      0x43,
      0x45,
    );
    _sentNewKeys = true;
    if (_firstKex && _extInfo) {
      _sendPacket(
        (SshWriter()
              ..byte(SshMsg.extInfo)
              ..uint32(1)
              ..utf8String('server-sig-algs')
              ..nameList(SshPublicKey.signatureAlgorithms))
            .takeBytes(),
      );
    }
    _holding = false;
    final held = List.of(_held);
    _held.clear();
    _heldBytes = 0;
    held.forEach(_sendPacket);
    onReleased?.call();
  }

  void _onNewKeys(Uint8List payload) {
    if (!_sentNewKeys || payload.length != 1) {
      throw const SshProtocolException('an unexpected NEWKEYS');
    }
    _reader.rekey(_nextIncoming!);
    if (_strict) {
      _reader.resetSequence();
    }
    _nextIncoming = null;
    _negotiated = null;
    _clientKexInit = null;
    _serverKexInit = null;
    _sentNewKeys = false;
    _inKex = false;
    _firstKex = false;
    _kexTimer?.cancel();
    _kexTimer = null;
    _keyExchanges++;
    _keyedAt = _clock.elapsed;
  }
}

final class _Negotiated {
  _Negotiated(
    this.hostKey,
    this.cipherIn,
    this.cipherOut,
    this.macIn,
    this.macOut,
  );

  final SshHostKey hostKey;
  final CipherSpec cipherIn;
  final CipherSpec cipherOut;
  final MacSpec macIn;
  final MacSpec macOut;
}
