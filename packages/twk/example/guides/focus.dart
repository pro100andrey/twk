// The input and focus guide's app (doc/guides/input-and-focus.md): a form
// of two fields and a button that Tab goes through, Ctrl+S that saves from
// anywhere, and the keys hinted where the focus is; Ctrl+Q quits.
//
//   dart run example/guides/focus.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const SignIn());

final class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

final class _SignInState extends State<SignIn> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  var _status = '';

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() => setState(
    () => _status = _name.text.isEmpty ? 'a name, please' : 'hi, ${_name.text}',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      // not 'q' or 's': a focused field takes the characters typed
      {'ctrl+s': _save, 'ctrl+q': () => AppBinding.of(context).quit()},
      hints: const {'ctrl+s': 'save', 'ctrl+q': 'quit'},
      child: Box(
        style: theme.background.merge(theme.text),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Box(
              border: .all(type: .rounded, style: theme.border),
              titles: [BorderTitle(' Sign in ', style: theme.primary)],
              padding: const .all(1),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                gap: 1,
                children: [
                  _Labeled(
                    'Name',
                    child: TextField(
                      controller: _name,
                      placeholder: 'who you are',
                      autofocus: true,
                    ),
                  ),
                  _Labeled(
                    'Password',
                    child: TextField(
                      controller: _password,
                      obscureText: true,
                      semanticsLabel: 'Password',
                    ),
                  ),
                  _Labeled(
                    '',
                    child: Row(
                      gap: 2,
                      children: [
                        Button('Sign in', onPressed: _save),
                        Text(_status, style: theme.muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // the keys the focused widget and the bindings above it take
            const KeyHintsBar(),
          ],
        ),
      ),
    );
  }
}

/// [child] after [label], in a column of labels as wide as the longest.
final class _Labeled extends StatelessWidget {
  const _Labeled(this.label, {required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    gap: 1,
    children: [
      SizedBox(width: 8, child: Text(label)),
      Expanded(child: child),
    ],
  );
}
