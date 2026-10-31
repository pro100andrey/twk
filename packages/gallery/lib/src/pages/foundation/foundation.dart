// The Foundation group of the gallery.
//
// Time is the gallery's clock alone: a timer's ticks, a future's two
// seconds and a stream's events are worked out from when they started, so
// a route's `t=` shows that moment (the page opened at 0).

import 'dart:async';

import 'package:twk/twk.dart';

import '../../motion.dart';
import '../../page.dart';
import '../kit/kit.dart';

part '_shared.dart';
part 'futurebuilder_streambuilder.dart';
part 'listenablebuilder.dart';

/// The group of the catalog these pages are in.
const _group = 'Foundation';

/// The pages of the Foundation group that draw.
final List<GalleryPage> foundationPages = [_listenable, _async];
