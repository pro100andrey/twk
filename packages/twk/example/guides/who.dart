// The input guide's focus and mouse app (doc/guides/input-and-focus.md):
// F2 tells which node has the focus, and a card inside a card each
// has a tap of its own.
//
//   dart run example/guides/who.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Who());

final class Who extends StatefulWidget {
  const Who({super.key});

  @override
  State<Who> createState() => _WhoState();
}

final class _WhoState extends State<Who> {
  final _search = FocusNode(debugLabel: 'search');
  var _said = 'nothing yet';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      // the node that has the focus now, none if no widget does
      'f2': () => setState(() {
        final focus = AppBinding.of(context).focusManager.primaryFocus;
        _said = 'focus: ${focus == _search ? 'search' : 'elsewhere'}';
      }),
      'ctrl+q': () => AppBinding.of(context).quit(),
    },
    child: Column(
      crossAxisAlignment: .start,
      children: [
        Text(_said),
        GestureDetector(
          onTap: (_) => setState(() => _said = 'outer'),
          child: Box(
            border: const .all(type: .rounded),
            padding: const .all(1),
            child: GestureDetector(
              // the deepest detector with an onTap takes the tap
              onTap: (_) => setState(() => _said = 'inner'),
              child: const Box(
                border: .all(type: .single),
                child: Text('inner'),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 20,
          child: TextField(
            focusNode: _search,
            autofocus: true,
            placeholder: 'search',
          ),
        ),
      ],
    ),
  );
}
