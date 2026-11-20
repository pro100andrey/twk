part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _finders() => const [SizedBox(height: 1, child: _Found())];
}

/// A line that says whether a finder found a text in the tree above it,
/// and how many cells of the screen the render object of the first shows.
final class _Found extends StatelessWidget {
  const _Found();

  @override
  Widget build(BuildContext context) {
    final found = const ElementFinder.text('sample').evaluate(
      context as Element,
    );
    final cells = found.isEmpty ? null : shown(found.first.renderObject!);
    return Text('found ${found.length} ${_width(cells)}');
  }

  static int _width(ShownRect? cells) => cells?.width ?? 0;
}
