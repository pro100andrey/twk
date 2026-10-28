/// The project a command works for: [projectOf].
library;

import 'package:path/path.dart' as p;
import 'package:twk_core/twk_core.dart';

/// The directory of the project [directory] is in, the current one when
/// not given: [LocalAddress.projectOf] of [directory] made absolute and
/// normalised, so that `..` goes up and the path it gives has no `.` or
/// `..` in it.
String projectOf(String? directory) =>
    LocalAddress.projectOf(p.normalize(p.absolute(directory ?? '.')));
