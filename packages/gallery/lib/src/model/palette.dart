// The palette's model (doc/design.md, "The palette"): what it lists, how
// it ranks what matches, and where it stands while it is open.
import 'package:twk/twk.dart';

/// What the palette lists: [title], [detail] at its right, and what it
/// runs.
final class PaletteItem {
  const PaletteItem(this.title, this.detail, this.run);

  final String title;
  final String detail;
  final void Function() run;
}

/// The palette while it is open: its [query], when it [opened], the row
/// [selected] and how far its list [scroll]s.
final class PaletteState {
  PaletteState(this.query, this.opened);

  String query;
  final Duration opened;
  var selected = 0;
  var scroll = 0;
}

/// The items of [items] that match [query], as twk's CommandPalette ranks
/// them: by score, then by when each was last run ([recent], the titles
/// run, the last first), then in their order; all of them, the ones run
/// before first, while [query] is empty.
List<(PaletteItem, FuzzyMatch?)> rankPalette(
  List<PaletteItem> items,
  String query,
  List<String> recent,
) {
  int lastRun(PaletteItem it) {
    final i = recent.indexOf(it.title);
    return i < 0 ? recent.length : i;
  }

  final out = <(PaletteItem, FuzzyMatch?, int, int)>[];
  for (final (i, it) in items.indexed) {
    if (query.isEmpty) {
      out.add((it, null, lastRun(it), i));
    } else if (fuzzyMatch(query, it.title) case final m?) {
      out.add((it, m, lastRun(it), i));
    }
  }
  out.sort((a, b) {
    final s = (b.$2?.score ?? 0).compareTo(a.$2?.score ?? 0);
    if (s != 0) {
      return s;
    }
    final r = a.$3.compareTo(b.$3);
    return r != 0 ? r : a.$4.compareTo(b.$4);
  });
  return [for (final (it, m, _, _) in out) (it, m)];
}

/// [recent] with [title] run last: first, and nowhere else.
void ranLast(List<String> recent, String title) => recent
  ..remove(title)
  ..insert(0, title);
