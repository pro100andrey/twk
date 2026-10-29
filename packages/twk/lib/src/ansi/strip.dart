/// Escape sequences taken out of text, the rest of it kept as it is:
/// [stripAnsi].
///
/// @docImport 'stream.dart';
library;

import 'escapes.dart';

/// [text] without its escape sequences: the sequences [AnsiStream] reads,
/// CSI, OSC, DCS, APC, PM, SOS and the other escapes, and the C1 controls
/// are taken out, and every other character is kept as it is, tabs, line
/// breaks, carriage returns and the other C0 controls among them, also
/// where they interrupt an escape or a CSI.
///
/// A sequence that is not ended takes the rest of [text] with it.
String stripAnsi(String text) {
  final out = StringBuffer();
  EscapeReader(text: out.write, control: out.writeCharCode).read(text);
  return out.toString();
}
