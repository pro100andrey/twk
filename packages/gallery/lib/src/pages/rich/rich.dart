// The Rich group of the gallery.

import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Pen, RenderParagraph;
import 'package:twk_rich/twk_rich.dart';

import '../../page.dart';
import '../kit/kit.dart';

part 'bigtext.dart';
part 'codeview.dart';
part 'diffview.dart';
part 'jsonview.dart';
part 'markdownview.dart';
part 'qrcode.dart';
part 'syntaxthemescope.dart';

/// The pages of the Rich group that draw.
final richPages = <GalleryPage>[
  _markdownView,
  _codeView,
  _syntaxThemeScope,
  _diffView,
  _jsonView,
  _bigText,
  _qrCode,
];
