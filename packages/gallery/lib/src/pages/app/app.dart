// The App group of the gallery.

import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../../page.dart';
import '../../paint.dart';
import '../../view/tokens.dart';
import '../cli_code.dart';
import '../cli_stage.dart' if (dart.library.js_interop) '../cli_stage_web.dart';
import '../kit/kit.dart' show TimedState, codeLine;

part '_shared.dart';
part 'cli.dart';
part 'errorwidget.dart';
part 'inputlistener.dart';
part 'notifications.dart';
part 'static.dart';
part 'terminalprogress.dart';
part 'viewport.dart';
part 'window_title.dart';

/// The group of the catalog these pages are in.
const _group = 'App';

/// The pages of the App group that draw.
final List<GalleryPage> appPages = [
  _input,
  _error,
  _static,
  _progress,
  _viewport,
  _windowTitle,
  _notifications,
  _cli,
];
