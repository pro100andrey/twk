// Opens the terminal, sends one notification, copies a text to the
// clipboard and closes it, for notify_test.dart.
import 'package:twk_core/terminal.dart';

Future<void> main() async {
  final term = await Terminal.open();
  term
    ..notify('Build', 'done; 3 tests')
    ..copyToClipboard('copied 🧪');
  await term.close();
}
