// The Focus and keys group of the gallery.

import 'package:twk/twk.dart';

import '../../page.dart';
import '../kit/kit.dart';
import '../snippets.g.dart';

part '_shared.dart';
part 'activeitem.dart';
part 'excludefocus.dart';
part 'focus_focusscope.dart';
part 'keybindings_leaderkey.dart';
part 'shortcuts_actions.dart';

/// The group of the catalog these pages are in.
const _group = 'Focus and keys';

/// The pages of the Focus and keys group that draw.
final focusPages = <GalleryPage>[
  _focusFocusscopePage,
  _activeitemPage,
  _excludefocusPage,
  _keybindingsLeaderkeyPage,
  _shortcutsActionsPage,
];
