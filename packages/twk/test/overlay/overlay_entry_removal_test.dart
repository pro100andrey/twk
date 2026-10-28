// An Overlay over a Row as small as its children lays it out as the
// screen does without it; an entry inserted outside a build and removed in
// the next build, before its host was built, is not shown, with or
// without a fade.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Removes [entry] in didUpdateWidget once [keep] turns false.
final class Remover extends StatefulWidget {
  const Remover(this.entry, {required this.keep, super.key});

  final OverlayEntry entry;
  final bool keep;

  @override
  State<Remover> createState() => _RemoverState();
}

final class _RemoverState extends State<Remover> {
  @override
  void didUpdateWidget(Remover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.keep) {
      widget.entry.remove();
    }
  }

  @override
  Widget build(BuildContext context) => const Text('under');
}

void main() {
  testTwk('a Row as small as its children under an Overlay is laid out as '
      'without it: as tall as the screen, its child in the middle', (t) async {
    // the screen's constraints are tight, so the Row is 10 rows tall and
    // centres the button on its cross axis, row 4, with or without the
    // Overlay
    Widget row() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [Button('Help', onPressed: () {})],
    );
    await t.pumpWidget(
      Theme(data: ThemeData.dark, child: row()),
      size: (40, 10),
    );
    final without = t.lines;
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: Overlay(child: row()),
      ),
    );
    expect(t.lines, without);
    expect(t.lines[4].trim(), 'Help');
    expect(t.lines.first, isEmpty);
  });

  testTwk('an entry inserted outside a build and removed in the next one '
      'before its host was built is not shown', (t) async {
    final overlay = GlobalKey<OverlayState>();
    final entry = OverlayEntry(
      builder: (_) => const Positioned(left: 0, top: 1, child: Text('TIP')),
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );
    Widget app({required bool keep}) => Overlay(
      key: overlay,
      child: Remover(entry, keep: keep),
    );
    await t.pumpWidget(app(keep: true), size: (10, 3));
    overlay.currentState!.insert(entry);
    await t.pumpWidget(app(keep: false));
    expect(entry.mounted, isFalse);
    expect(t.lines[1].trim(), isEmpty);
    await t.pump();
    expect(t.lines[1].trim(), isEmpty);
    expect(overlay.currentState!.entries, isEmpty);

    // inserted again, it shows
    overlay.currentState!.insert(entry);
    await t.pump();
    expect(t.lines[1].trim(), 'TIP');
  });

  testTwk('so is one that fades out', (t) async {
    final overlay = GlobalKey<OverlayState>();
    final entry = OverlayEntry(
      builder: (_) => const Positioned(left: 0, top: 1, child: Text('TIP')),
    );
    Widget app({required bool keep}) => Overlay(
      key: overlay,
      child: Remover(entry, keep: keep),
    );
    await t.pumpWidget(app(keep: true), size: (10, 3));
    overlay.currentState!.insert(entry);
    await t.pumpWidget(app(keep: false));
    expect(entry.mounted, isFalse);
    await t.pump(const Duration(milliseconds: 500));
    expect(t.lines[1].trim(), isEmpty);
  });
}
