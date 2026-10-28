// The label of a ProgressBar: what a screen reader calls the bar, read
// once, in the bar's own line before how much is done; a bar without one
// reads as how much is done alone.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [children] one below another at their left edge.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

/// The lines the app reads as now.
List<String> read(TwkTester t) => t.binding.semantics.lines;

void main() {
  testTwk('a progress bar with a label reads as it once, before how much '
      'is done, and as the label alone while that is not known', (t) async {
    await t.pumpWidget(
      column(const [
        ProgressBar(value: 0.3, semanticsLabel: 'Upload'),
        ProgressBar(semanticsLabel: 'Sync'),
      ]),
      size: (20, 4),
    );
    expect(read(t), ['progressbar Upload: 30%', 'progressbar Sync']);
  });

  testTwk('a progress bar without a label, or with an empty one, reads as '
      'how much is done alone', (t) async {
    await t.pumpWidget(
      column(const [
        ProgressBar(value: 0.3),
        ProgressBar(value: 0.3, semanticsLabel: ''),
        ProgressBar(),
      ]),
      size: (20, 4),
    );
    expect(read(t), ['progressbar 30%', 'progressbar 30%', 'progressbar']);
  });
}
