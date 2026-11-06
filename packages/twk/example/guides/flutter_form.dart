// A Flutter form as twk writes it: the Coming from Flutter guide.
import 'package:twk/twk.dart';

Future<void> main() => runApp(const App(child: Profile()));

final class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<Profile> createState() => _ProfileState();
}

final class _ProfileState extends State<Profile> {
  final _name = TextEditingController();
  var _news = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const .all(1),
      child: Column(
        crossAxisAlignment: .start,
        gap: 1,
        children: [
          Text('Profile', style: theme.primary),
          SizedBox(width: 30, child: TextField(controller: _name)),
          Checkbox(
            value: _news,
            label: 'Send me the news',
            onChanged: (value) => setState(() => _news = value),
          ),
          Row(
            gap: 2,
            children: [
              Button.filled(
                'Save',
                onPressed: () => showToast(context, 'saved'),
              ),
              Button.outlined(
                'Delete',
                onPressed: () => showDialog<void>(
                  context,
                  (context) => const Dialog(
                    title: 'Delete?',
                    child: Text('This cannot be undone.'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
