/// Which file a path names, where the platform tells it: `tailFile`'s test
/// of a file put in the place of the one it follows.
///
/// On macOS the directory watch tells a write to a file made shortly
/// before it began as that file's making too (FSEvents keeps the item's
/// created flag), so a create event there says nothing about whether the
/// name holds another file; its device and inode do. Elsewhere the watch's
/// create events are the file's own, and nothing is asked.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/libc.dart' as c;

/// The file a path names: `stat`'s `st_dev` and `st_ino`.
typedef FileIdentity = ({int device, int inode});

/// Whether [fileIdentity] tells files apart here: on macOS, where libc can
/// be reached.
bool get knowsFileIdentity => _stat != null;

/// The file [path] names now, or null where there is none or
/// [knowsFileIdentity] is false.
FileIdentity? fileIdentity(String path) => _stat?.of(path);

final _Stat? _stat = Platform.isMacOS ? _Stat.open() : null;

typedef _StatD = int Function(Pointer<Uint8>, Pointer<Uint8>);

/// macOS's `stat` with 64-bit inodes, the memory it writes into taken from
/// the core's libc.
final class _Stat {
  _Stat._(DynamicLibrary libc, String symbol)
    : _call = libc
          .lookupFunction<
            Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
            _StatD
          >(symbol);

  /// libc's, or null where it has none. x86_64 names the `stat` of 64-bit
  /// inodes `stat$INODE64`; arm64 has that one alone, as `stat`: a symbol
  /// of its own, so looked up here rather than bound by the core.
  static _Stat? open() {
    final libc = DynamicLibrary.process();
    for (final symbol in [r'stat$INODE64', 'stat']) {
      if (libc.providesSymbol(symbol)) {
        return _Stat._(libc, symbol);
      }
    }
    return null;
  }

  final _StatD _call;

  /// The room for `struct stat`, 144 bytes on macOS, with some to spare;
  /// the path follows it, so the struct is at the aligned start.
  static const _room = 256;

  FileIdentity? of(String path) {
    final name = utf8.encode(path);
    final memory = c.calloc(1, _room + name.length + 1).cast<Uint8>();
    if (memory == nullptr) {
      return null;
    }
    try {
      (memory + _room).asTypedList(name.length + 1)
        ..setAll(0, name)
        ..[name.length] = 0;
      if (_call(memory + _room, memory) != 0) {
        return null;
      }
      // dev_t (32 bits) first, then mode_t and nlink_t (16 bits each), then
      // the 64-bit ino_t at 8
      final bytes = ByteData.sublistView(memory.asTypedList(16));
      return (
        device: bytes.getInt32(0, Endian.host),
        inode: bytes.getUint64(8, Endian.host),
      );
    } finally {
      c.free(memory.cast());
    }
  }
}
