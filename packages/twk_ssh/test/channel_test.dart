import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_ssh/src/session.dart';
import 'package:twk_ssh/src/wire.dart';
import 'package:twk_test/twk_test.dart';

/// What a session sends, decoded far enough to check.
final class FakeTransport implements SessionTransport {
  final sent = <Uint8List>[];
  var closed = 0;

  @override
  void send(Uint8List payload) => sent.add(payload);

  @override
  void channelClosed() => closed++;

  @override
  var holding = false;

  /// The data of the CHANNEL_DATA messages sent, each.
  List<int> get dataLengths => [
    for (final p in sent)
      if (p[0] == SshMsg.channelData)
        (SshReader(p)
              ..byte()
              ..uint32())
            .string()
            .length,
  ];

  List<int> get ids => [for (final p in sent) p[0]];
}

SshSession session(
  FakeTransport t, {
  int window = 1 << 20,
  int maxPacket = 1 << 15,
}) => SshSession(
  user: 'u',
  publicKey: null,
  remoteAddress: InternetAddress.loopbackIPv4,
  remotePort: 1,
  transport: t,
  remoteId: 7,
  remoteWindow: window,
  remoteMaxPacket: maxPacket,
);

Matcher throwsProtocol() => throwsA(isA<SshProtocolException>());

void main() {
  group('output', () {
    test('is sent up to the window, in packets of the maximum size', () async {
      final t = FakeTransport();
      final s = session(t, window: 100000, maxPacket: 30000)
        ..add(Uint8List(150000));
      expect(t.dataLengths, [30000, 30000, 30000, 10000]);
      expect(s.pendingOutput, 50000);
      var flushed = false;
      unawaited(s.flush().then((_) => flushed = true));
      await Future<void>.delayed(Duration.zero);
      expect(flushed, isFalse);
      s.receiveWindowAdjust(20000);
      expect(t.dataLengths.skip(4), [20000]);
      await Future<void>.delayed(Duration.zero);
      expect(flushed, isFalse);
      s.receiveWindowAdjust(1 << 20);
      expect(t.dataLengths.skip(5), [30000]);
      await Future<void>.delayed(Duration.zero);
      expect(flushed, isTrue);
      expect(s.pendingOutput, 0);
    });

    test('past maxPendingOutput waiting for a client that grants none, the '
        'session is closed and holds none of it', () {
      final t = FakeTransport();
      final s = session(t, window: 0)
        ..add(Uint8List(SshSession.maxPendingOutput));
      expect(s.pendingOutput, SshSession.maxPendingOutput);
      expect(t.ids, isEmpty, reason: 'up to the limit it waits');
      s.add(Uint8List(1));
      expect(s.pendingOutput, 0);
      expect(t.ids, [SshMsg.channelEof, SshMsg.channelClose]);
      s.add(Uint8List(10));
      expect(s.pendingOutput, 0, reason: 'dropped once closed');
    });

    test('a window grown past 2^32 - 1 is a protocol error', () {
      final s = session(FakeTransport(), window: 0xFFFFFFF0);
      expect(() => s.receiveWindowAdjust(0x10), throwsProtocol());
    });

    test(
      'exit sends what is pending, then the status, EOF and close',
      () async {
        final t = FakeTransport();
        final s = session(t, window: 10)..add(Uint8List(15));
        final exited = s.exit(4);
        await Future<void>.delayed(Duration.zero);
        expect(t.ids, [SshMsg.channelData]);
        s.receiveWindowAdjust(10);
        await Future<void>.delayed(Duration.zero);
        expect(t.ids, [
          SshMsg.channelData,
          SshMsg.channelData,
          SshMsg.channelRequest,
          SshMsg.channelEof,
          SshMsg.channelClose,
        ]);
        final status = SshReader(t.sent[2])
          ..byte()
          ..uint32();
        expect(
          [status.utf8String(), status.boolean(), status.uint32()],
          ['exit-status', false, 4],
        );
        expect(s.isDone, isFalse); // until the client closes too
        s.receiveClose();
        await exited;
        expect(t.closed, 1);
      },
    );

    test('exit gives up on output the client never grants', () async {
      final t = FakeTransport();
      final s = session(t, window: 0)..add(Uint8List(5));
      final clock = FakeClock()
        ..run(() => unawaited(s.exit(0, const Duration(milliseconds: 20))));
      await clock.elapse(const Duration(milliseconds: 19));
      expect(t.ids, isEmpty);
      await clock.elapse(const Duration(milliseconds: 1));
      expect(t.ids, [
        SshMsg.channelRequest,
        SshMsg.channelEof,
        SshMsg.channelClose,
      ]);
    });
  });

  group('input', () {
    test('beyond the window is a protocol error', () {
      final s = session(FakeTransport());
      for (var i = 0; i < SshSession.window ~/ SshSession.maxPacket; i++) {
        s.receiveData(Uint8List(SshSession.maxPacket));
      }
      expect(() => s.receiveData(Uint8List(1)), throwsProtocol());
    });

    test('longer than the maximum packet is a protocol error', () {
      final s = session(FakeTransport());
      expect(
        () => s.receiveData(Uint8List(SshSession.maxPacket + 1)),
        throwsProtocol(),
      );
    });

    test('extended data is dropped, and its window granted again', () {
      final t = FakeTransport();
      final s = session(t);
      expect(
        () => s.receiveExtendedData(SshSession.maxPacket + 1),
        throwsProtocol(),
      );
      for (var i = 0; i < 2 * SshSession.window ~/ SshSession.maxPacket; i++) {
        s.receiveExtendedData(SshSession.maxPacket);
      }
      expect(
        t.ids.where((id) => id == SshMsg.channelWindowAdjust),
        hasLength(4),
      );
      expect(s.heldInput, 0);
    });

    test('is granted again once half the window is read', () async {
      final t = FakeTransport();
      final s = session(t);
      final read = <int>[];
      s.input.listen((b) => read.add(b.length));
      for (var i = 0; i < SshSession.window ~/ SshSession.maxPacket; i++) {
        s.receiveData(Uint8List(SshSession.maxPacket));
      }
      await Future<void>.delayed(Duration.zero);
      final adjusts = [
        for (final p in t.sent)
          if (p[0] == SshMsg.channelWindowAdjust)
            (SshReader(p)
                  ..byte()
                  ..uint32())
                .uint32(),
      ];
      expect(adjusts, [SshSession.window ~/ 2, SshSession.window ~/ 2]);
      // granted again: the next window's worth is taken
      s.receiveData(Uint8List(SshSession.maxPacket));
    });
  });

  group('requests', () {
    Uint8List body(void Function(SshWriter w) write) {
      final w = SshWriter();
      write(w);
      return w.takeBytes();
    }

    test('pty-req: the terminal, its size and modes', () {
      final s = session(FakeTransport());
      final modes = body(
        (w) => w
          ..byte(SshPty.verase)
          ..uint32(0x08)
          ..byte(53) // ECHO
          ..uint32(1)
          ..byte(0),
      );
      final ok = s.request(
        'pty-req',
        SshReader(
          body(
            (w) => w
              ..utf8String('xterm-256color')
              ..uint32(120)
              ..uint32(40)
              ..uint32(0)
              ..uint32(0)
              ..string(modes),
          ),
        ),
      );
      expect(ok, isTrue);
      expect(s.pty!.term, 'xterm-256color');
      expect(s.pty!.modes, {SshPty.verase: 0x08, 53: 1});
      expect(s.pty!.eraseChar, 0x08);
    });

    test('pty-req and window-change: a size past the most is cut to it', () {
      final s = session(FakeTransport());
      Uint8List size(int columns, int rows) => body(
        (w) => w
          ..uint32(columns)
          ..uint32(rows)
          ..uint32(0)
          ..uint32(0),
      );
      expect(
        s.request(
          'pty-req',
          SshReader(
            Uint8List.fromList([
              ...body((w) => w.utf8String('xterm')),
              ...size(0xFFFFFFFF, 0xFFFFFFFF),
              ...body((w) => w.string(Uint8List.fromList([0]))),
            ]),
          ),
        ),
        isTrue,
      );
      expect(
        (s.pty!.columns, s.pty!.rows),
        (SshPty.maxColumns, SshPty.maxRows),
      );
      expect(s.request('window-change', SshReader(size(100, 1 << 20))), isTrue);
      expect((s.pty!.columns, s.pty!.rows), (100, SshPty.maxRows));
      expect(s.request('window-change', SshReader(size(80, 24))), isTrue);
      expect((s.pty!.columns, s.pty!.rows), (80, 24));
    });

    test('env is bounded in count and size', () {
      final s = session(FakeTransport());
      bool env(String name, String value) => s.request(
        'env',
        SshReader(
          body(
            (w) => w
              ..utf8String(name)
              ..utf8String(value),
          ),
        ),
      );
      expect(env('BIG', 'x' * 5000), isFalse);
      for (var i = 0; i < 64; i++) {
        expect(env('V$i', '$i'), isTrue);
      }
      expect(env('ONE_TOO_MANY', '1'), isFalse);
      expect(s.environment, hasLength(64));
    });

    test('one shell or command; the others are refused', () {
      final s = session(FakeTransport());
      expect(
        s.request('subsystem', SshReader(body((w) => w.utf8String('sftp')))),
        isFalse,
      );
      expect(s.request('x11-req', SshReader(Uint8List(0))), isFalse);
      expect(s.request('shell', SshReader(Uint8List(0))), isTrue);
      expect(s.started, isTrue);
      expect(
        s.request('exec', SshReader(body((w) => w.utf8String('ls')))),
        isFalse,
      );
      expect(s.request('shell', SshReader(Uint8List(0))), isFalse);
      expect(s.command, isNull);
    });

    test('a malformed request is a protocol error', () {
      final s = session(FakeTransport());
      expect(
        () => s.request('pty-req', SshReader(body((w) => w.uint32(3)))),
        throwsProtocol(),
      );
    });
  });
}
