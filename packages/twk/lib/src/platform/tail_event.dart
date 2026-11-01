/// What a followed file tells: [FileBytes] written to it, or a [FileReset].
library;

/// One thing a followed file told, in the stream of `tailFile`.
sealed class TailEvent {
  const TailEvent();
}

/// Bytes written to the file, in the order they were.
final class FileBytes extends TailEvent {
  /// Bytes [bytes].
  const FileBytes(this.bytes);

  /// What was read.
  final List<int> bytes;
}

/// The file was cut short or replaced and is read from its start again: the
/// bytes before it are of the old file, and a line they left unended is not
/// the start of the next one.
final class FileReset extends TailEvent {
  /// A reset.
  const FileReset();
}
