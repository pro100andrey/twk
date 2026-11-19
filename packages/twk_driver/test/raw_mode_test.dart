import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_driver/src/session.dart';

/// A `struct termios` of the platform's layout with `c_lflag` [lflag], in the
/// host's byte order.
Uint8List _termios(int lflag, {required bool macos}) {
  final bytes = Uint8List(macos ? 72 : 60);
  final data = ByteData.sublistView(bytes);
  if (macos) {
    data.setUint64(24, lflag, Endian.host);
  } else {
    data.setUint32(12, lflag, Endian.host);
  }
  return bytes;
}

void main() {
  group('rawModeProblem', () {
    test('a macOS tty in cooked mode (ICANON 0x100, ECHO 0x8, ISIG 0x80)', () {
      expect(
        rawModeProblem(_termios(0x100 | 0x8 | 0x80, macos: true), macos: true),
        isNull,
      );
    });

    test('a macOS tty with ISIG off is raw, with ECHOKE (0x1) set or not', () {
      for (final lflag in [0x100 | 0x8, 0x100 | 0x8 | 0x1]) {
        expect(
          rawModeProblem(_termios(lflag, macos: true), macos: true),
          contains('raw mode'),
        );
      }
    });

    test('a macOS tty without ICANON or ECHO is raw', () {
      expect(
        rawModeProblem(_termios(0x8 | 0x80, macos: true), macos: true),
        contains('raw mode'),
      );
      expect(
        rawModeProblem(_termios(0x100 | 0x80, macos: true), macos: true),
        contains('raw mode'),
      );
    });

    test('a Linux tty in cooked mode (ISIG 0x1, ICANON 0x2, ECHO 0x8)', () {
      expect(
        rawModeProblem(_termios(0x1 | 0x2 | 0x8, macos: false), macos: false),
        isNull,
      );
      expect(
        rawModeProblem(_termios(0x1 | 0x8, macos: false), macos: false),
        contains('0x9'),
      );
    });
  });

  test('the ports follow the platform unless told', () {
    expect(SessionPorts().macos, Platform.isMacOS);
    expect(SessionPorts(macos: true).macos, isTrue);
  });
}
