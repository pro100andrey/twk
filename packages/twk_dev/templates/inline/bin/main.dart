import 'package:inline_template/inline_template.dart';
import 'package:twk/twk.dart';

// inline: in rows below the shell's prompt, left on the screen at the end
Future<void> main() => runApp(const Chat(), mode: .inline);
