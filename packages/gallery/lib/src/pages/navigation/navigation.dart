// The Navigation group of the gallery.

import 'dart:async';

import 'package:twk/twk.dart';

import '../../motion.dart';
import '../../page.dart';
import '../kit/kit.dart';

part 'breadcrumbs.dart';
part 'navigator.dart';
part 'pagination.dart';
part 'popscope_navigatorobserver.dart';
part 'stepper.dart';

/// The pages of the Navigation group that draw.
final List<GalleryPage> navigationPages = [
  _navigatorPage,
  _popscopeNavigatorobserverPage,
  _breadcrumbs,
  _pagination,
  _stepper,
];
