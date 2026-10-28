/// The SSH binary encoding (RFC 4251 §5) and the numbers of the messages
/// and disconnect reasons the server uses.
library;

import 'dart:convert';
import 'dart:typed_data';

/// What the client sent breaks the protocol: the connection ends with
/// [reason] (an [SshDisconnect] code) and [message].
final class SshProtocolException implements Exception {
  /// A breach described by [message], ending the connection with
  /// [reason].
  const SshProtocolException(
    this.message, [
    this.reason = SshDisconnect.protocolError,
  ]);

  /// What was wrong.
  final String message;

  /// The reason the DISCONNECT gives.
  final int reason;

  @override
  String toString() => 'SshProtocolException($reason): $message';
}

/// Message numbers (RFC 4250 §4.1, RFC 8308, OpenSSH's PROTOCOL).
abstract final class SshMsg {
  /// SSH_MSG_DISCONNECT: the connection ends.
  static const disconnect = 1;

  /// SSH_MSG_IGNORE: nothing, to be skipped.
  static const ignore = 2;

  /// SSH_MSG_UNIMPLEMENTED: a message of that sequence number is not known.
  static const unimplemented = 3;

  /// SSH_MSG_DEBUG: a message to show, or not.
  static const debug = 4;

  /// SSH_MSG_SERVICE_REQUEST: the client asks for a service.
  static const serviceRequest = 5;

  /// SSH_MSG_SERVICE_ACCEPT: the service is granted.
  static const serviceAccept = 6;

  /// SSH_MSG_EXT_INFO: the extensions spoken (RFC 8308).
  static const extInfo = 7;

  /// SSH_MSG_KEXINIT: a key exchange starts, and the algorithms offered.
  static const kexInit = 20;

  /// SSH_MSG_NEWKEYS: what follows is under the new keys.
  static const newKeys = 21;

  /// SSH_MSG_KEX_ECDH_INIT: the client's ephemeral key.
  static const kexEcdhInit = 30;

  /// SSH_MSG_KEX_ECDH_REPLY: the server's host key, ephemeral key and
  /// signature.
  static const kexEcdhReply = 31;

  /// SSH_MSG_USERAUTH_REQUEST: a login attempt.
  static const userauthRequest = 50;

  /// SSH_MSG_USERAUTH_FAILURE: refused, and the methods that can go on.
  static const userauthFailure = 51;

  /// SSH_MSG_USERAUTH_SUCCESS: logged in.
  static const userauthSuccess = 52;

  /// SSH_MSG_USERAUTH_BANNER: text to show before the login.
  static const userauthBanner = 53;

  /// SSH_MSG_USERAUTH_PK_OK: the key would be taken, signed.
  static const userauthPkOk = 60;

  /// SSH_MSG_GLOBAL_REQUEST: a request for the connection.
  static const globalRequest = 80;

  /// SSH_MSG_REQUEST_SUCCESS: the global request is granted.
  static const requestSuccess = 81;

  /// SSH_MSG_REQUEST_FAILURE: the global request is refused.
  static const requestFailure = 82;

  /// SSH_MSG_CHANNEL_OPEN: the client opens a channel.
  static const channelOpen = 90;

  /// SSH_MSG_CHANNEL_OPEN_CONFIRMATION: the channel is open.
  static const channelOpenConfirmation = 91;

  /// SSH_MSG_CHANNEL_OPEN_FAILURE: the channel is refused.
  static const channelOpenFailure = 92;

  /// SSH_MSG_CHANNEL_WINDOW_ADJUST: more of the window is granted.
  static const channelWindowAdjust = 93;

  /// SSH_MSG_CHANNEL_DATA: data on a channel.
  static const channelData = 94;

  /// SSH_MSG_CHANNEL_EXTENDED_DATA: data of another stream (stderr).
  static const channelExtendedData = 95;

  /// SSH_MSG_CHANNEL_EOF: no more data that way.
  static const channelEof = 96;

  /// SSH_MSG_CHANNEL_CLOSE: the channel is closed that way.
  static const channelClose = 97;

  /// SSH_MSG_CHANNEL_REQUEST: a request on a channel.
  static const channelRequest = 98;

  /// SSH_MSG_CHANNEL_SUCCESS: the channel request is granted.
  static const channelSuccess = 99;

  /// SSH_MSG_CHANNEL_FAILURE: the channel request is refused.
  static const channelFailure = 100;
}

/// Disconnect reason codes (RFC 4250 §4.2.2).
abstract final class SshDisconnect {
  /// SSH_DISCONNECT_PROTOCOL_ERROR.
  static const protocolError = 2;

  /// SSH_DISCONNECT_KEY_EXCHANGE_FAILED: no algorithms in common.
  static const keyExchangeFailed = 3;

  /// SSH_DISCONNECT_MAC_ERROR: a packet failed its MAC.
  static const macError = 5;

  /// SSH_DISCONNECT_SERVICE_NOT_AVAILABLE.
  static const serviceNotAvailable = 7;

  /// SSH_DISCONNECT_BY_APPLICATION: the server ends it.
  static const byApplication = 11;

  /// SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE: too many failures.
  static const noMoreAuthMethods = 14;
}

/// Channel open failure codes (RFC 4254 §5.1).
abstract final class SshOpenFailure {
  /// SSH_OPEN_ADMINISTRATIVELY_PROHIBITED: not a channel served.
  static const administrativelyProhibited = 1;

  /// SSH_OPEN_UNKNOWN_CHANNEL_TYPE.
  static const unknownChannelType = 3;

  /// SSH_OPEN_RESOURCE_SHORTAGE: no room for another channel.
  static const resourceShortage = 4;
}

/// Builds a message in the SSH encoding.
final class SshWriter {
  var _bytes = Uint8List(64);
  var _length = 0;

  /// The bytes written so far.
  int get length => _length;

  void _reserve(int n) {
    if (_length + n <= _bytes.length) {
      return;
    }
    var size = _bytes.length * 2;
    while (size < _length + n) {
      size *= 2;
    }
    _bytes = Uint8List(size)..setRange(0, _length, _bytes);
  }

  /// A byte, [value].
  void byte(int value) {
    _reserve(1);
    _bytes[_length++] = value;
  }

  /// A boolean, [value], as a byte of 1 or 0.
  void boolean(bool value) => byte(value ? 1 : 0);

  /// A uint32, [value], big-endian.
  void uint32(int value) {
    _reserve(4);
    _bytes.buffer.asByteData().setUint32(_length, value);
    _length += 4;
  }

  /// [bytes] as they are, without a length.
  void raw(List<int> bytes) {
    _reserve(bytes.length);
    _bytes.setRange(_length, _length + bytes.length, bytes);
    _length += bytes.length;
  }

  /// A string: [bytes] after their length.
  void string(List<int> bytes) {
    uint32(bytes.length);
    raw(bytes);
  }

  /// A string: [value] in UTF-8.
  void utf8String(String value) => string(utf8.encode(value));

  /// A name-list: [names] joined by commas.
  void nameList(List<String> names) => utf8String(names.join(','));

  /// [magnitude], an unsigned big-endian number, as an mpint: without
  /// leading zeros, with a zero byte before a first byte whose top bit is
  /// set.
  void mpint(List<int> magnitude) {
    var start = 0;
    while (start < magnitude.length && magnitude[start] == 0) {
      start++;
    }
    final digits = magnitude.sublist(start);
    if (digits.isNotEmpty && digits[0] & 0x80 != 0) {
      uint32(digits.length + 1);
      byte(0);
    } else {
      uint32(digits.length);
    }
    raw(digits);
  }

  /// What was written; the writer starts over.
  Uint8List takeBytes() {
    final out = Uint8List.sublistView(_bytes, 0, _length);
    _bytes = Uint8List(64);
    _length = 0;
    return out;
  }
}

/// Reads a message in the SSH encoding; reading past its end is an
/// [SshProtocolException].
final class SshReader {
  /// A reader of a message's bytes, from the first.
  SshReader(this._bytes);

  final Uint8List _bytes;
  var _at = 0;

  /// Whether everything is read.
  bool get atEnd => _at >= _bytes.length;

  /// What is left unread.
  Uint8List rest() {
    final out = Uint8List.sublistView(_bytes, _at);
    _at = _bytes.length;
    return out;
  }

  void _need(int n) {
    if (n < 0 || _bytes.length - _at < n) {
      throw const SshProtocolException('truncated message');
    }
  }

  /// The next byte.
  int byte() {
    _need(1);
    return _bytes[_at++];
  }

  /// The next [n] bytes, without a length.
  Uint8List raw(int n) {
    _need(n);
    final out = Uint8List.sublistView(_bytes, _at, _at + n);
    _at += n;
    return out;
  }

  /// The next boolean: a byte other than 0 is true.
  bool boolean() => byte() != 0;

  /// The next uint32.
  int uint32() {
    _need(4);
    final value = _bytes.buffer.asByteData(_bytes.offsetInBytes).getUint32(_at);
    _at += 4;
    return value;
  }

  /// The next string, its bytes.
  Uint8List string() {
    final n = uint32();
    _need(n);
    final out = Uint8List.sublistView(_bytes, _at, _at + n);
    _at += n;
    return out;
  }

  /// The next string, in UTF-8.
  String utf8String() {
    try {
      return utf8.decode(string());
    } on FormatException {
      throw const SshProtocolException('malformed UTF-8');
    }
  }

  /// The next name-list, its names.
  List<String> nameList() {
    final s = utf8String();
    return s.isEmpty ? const [] : s.split(',');
  }

  /// An mpint that must not be negative, as its big-endian magnitude.
  Uint8List mpint() {
    final bytes = string();
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      throw const SshProtocolException('negative mpint');
    }
    var start = 0;
    while (start < bytes.length && bytes[start] == 0) {
      start++;
    }
    return Uint8List.sublistView(bytes, start);
  }
}
