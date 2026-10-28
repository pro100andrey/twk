// TuiApp imported by a show combinator (before 6d4f947).
//
// The combinator is left as it is: dart fix renames the uses, and the name
// in `show` (undefined_shown_name) is changed by hand, after which the
// renamed uses resolve.
import 'package:twk_core/twk_core.dart' show Terminal, TuiApp;

Future<TuiApp> open() async => TuiApp(await Terminal.open());
