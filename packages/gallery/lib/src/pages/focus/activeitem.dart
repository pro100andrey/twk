// The ActiveItem page.
part of 'focus.dart';

final _activeitemPage = GalleryPage(
  group: 'Focus and keys',
  title: 'ActiveItem',
  about:
      "The item a focused list's keys act on: the terminal's hidden cursor "
      "rests on it, which iTerm2's cursor guide marks and macOS zoom, a "
      'screen reader or a braille display follows.',
  build: (context, o) => const _Active(),
  code: (o) => _activeCode,
);

/// A list Up and Down move a cursor in, the hidden cursor on its row.
final class _Active extends StatefulWidget {
  const _Active();

  @override
  State<_Active> createState() => _ActiveState();
}

final class _ActiveState extends State<_Active> {
  static const _fruits = ['apple', 'banana', 'cherry', 'damson', 'elder'];

  var _cursor = 0;

  void _move(int by) =>
      setState(() => _cursor = (_cursor + by).clamp(0, _fruits.length - 1));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      {'up': () => _move(-1), 'down': () => _move(1)},
      child: Focus(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _fruits.length; i++)
              ActiveItem(
                active: i == _cursor,
                child: Text(
                  i == _cursor ? '› ${_fruits[i]}' : '  ${_fruits[i]}',
                  style: i == _cursor ? theme.selection : const Style(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _activeCode = r'''
static const _fruits = ['apple', 'banana', 'cherry', 'damson', 'elder'];

var _cursor = 0;

void _move(int by) =>
    setState(() => _cursor = (_cursor + by).clamp(0, _fruits.length - 1));

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return KeyBindings(
    {'up': () => _move(-1), 'down': () => _move(1)},
    child: Focus(
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          for (var i = 0; i < _fruits.length; i++)
            // the hidden cursor on the cursor's row
            ActiveItem(
              active: i == _cursor,
              child: Text(
                i == _cursor ? '› ${_fruits[i]}' : '  ${_fruits[i]}',
                style: i == _cursor ? theme.selection : const Style(),
              ),
            ),
        ],
      ),
    ),
  );
}''';
