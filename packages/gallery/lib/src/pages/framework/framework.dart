// The Framework group of the gallery.

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';

part 'layoutbuilder.dart';
part 'notificationlistener.dart';
part 'slot_slotscope.dart';

/// The group of the catalog these pages are in.
const _group = 'Framework';

/// The pages of the Framework group that draw.
final List<GalleryPage> frameworkPages = [_layout, _notifications, _slots];
