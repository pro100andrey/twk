// Settings: a menu bar over tabs of switches, checkboxes and radio
// buttons, all of one form, and a status bar under them. F10 or a click
// opens a menu, Alt and its letter too; a right click on the settings, or
// Shift+F10 on one, opens a menu of what can be done with them. Tab moves
// from the tabs to the settings, Left and Right on the tabs switch them;
// Space, Enter or a click flips a switch or a box, the arrows choose a
// radio button. Ctrl+S saves the form, File ▸ Revert puts back what was
// saved. Clearing the cache asks first: confirmed, a spinner turns in the
// status bar while it is cleared, then a toast says it is done, and so
// does a desktop notification where the terminal shows them. Ctrl+Q
// quits.
//
//   dart run example/settings.dart
import 'dart:async';

import 'package:twk/twk.dart';

Future<void> main() => runApp(const SettingsApp());

/// What opens at startup.
enum Startup { lastFiles, emptyWindow, welcome }

/// What a level of indentation is.
enum Indent { twoSpaces, fourSpaces, tab }

/// The settings as saved last.
final class Settings {
  var autosave = true;
  var checkUpdates = true;
  Startup startup = .lastFiles;
  var wrapLines = false;
  var lineNumbers = true;
  var formatOnSave = false;
  Indent indent = .twoSpaces;
  var crashReports = true;
  var usageStatistics = false;
}

/// How long clearing the cache takes.
const clearingTime = Duration(seconds: 2);

/// The app, in an overlay for its menus, dialogs and toasts.
final class SettingsApp extends StatelessWidget {
  const SettingsApp({super.key});

  @override
  Widget build(BuildContext context) => const Overlay(child: _Settings());
}

final class _Settings extends StatefulWidget {
  const _Settings();

  @override
  State<_Settings> createState() => _SettingsState();
}

final class _SettingsState extends State<_Settings> {
  final _saved = Settings();
  final _form = GlobalKey<FormState>();
  late final _tabs = TabController(length: 3)
    ..addListener(() => setState(() {}));
  var _modified = false;

  /// The files in the cache.
  var _cached = 128;

  /// Ends the clearing of the cache while it runs.
  Timer? _clearing;

  bool get _canClear => _cached > 0 && _clearing == null;

  @override
  void dispose() {
    _clearing?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _save() => _form.currentState!.submit();

  void _submitted() {
    setState(() => _modified = false);
    showToast(context, 'The settings are saved.');
  }

  void _revert() {
    _form.currentState!.reset();
    setState(() => _modified = false);
  }

  void _quit() => AppBinding.of(context).quit();

  /// Asks before the cache is cleared, then clears it.
  Future<void> _clearCache() async {
    final clear = await showDialog<bool>(
      context,
      (context) => _ClearCacheDialog(files: _cached),
    );
    if ((clear ?? false) && mounted) {
      setState(() => _clearing = Timer(clearingTime, _cleared));
    }
  }

  void _cleared() {
    final done = 'The cache is cleared: $_cached files deleted.';
    setState(() {
      _clearing = null;
      _cached = 0;
    });
    showToast(context, done);
    AppBinding.of(context).notify('Settings', done);
  }

  void _askToClear() => unawaited(_clearCache());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      {'ctrl+s': _save, 'ctrl+q': _quit},
      // the theme's background and text under all of it
      child: Box(
        style: theme.background.merge(theme.text),
        child: MenuBar(
          menus: [
            Menu(
              '&File',
              items: [
                MenuItem('&Save', onSelected: _save),
                MenuItem('&Revert', onSelected: _modified ? _revert : null),
                const MenuDivider(),
                MenuItem('&Quit', onSelected: _quit),
              ],
            ),
            Menu(
              '&View',
              items: [
                for (final (i, tab) in _tabNames.indexed)
                  MenuItem(
                    '&$tab',
                    checked: _tabs.index == i,
                    onSelected: () => _tabs.index = i,
                  ),
              ],
            ),
            Menu(
              '&Tools',
              items: [
                MenuItem(
                  '&Clear the cache…',
                  onSelected: _canClear ? _askToClear : null,
                ),
              ],
            ),
          ],
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              TabBar(
                controller: _tabs,
                tabs: _tabNames,
                autofocus: true,
              ),
              Expanded(
                child: ContextMenu(
                  items: [
                    MenuItem('&Save', onSelected: _save),
                    MenuItem('&Revert', onSelected: _modified ? _revert : null),
                    const MenuDivider(),
                    MenuItem(
                      '&Clear the cache…',
                      onSelected: _canClear ? _askToClear : null,
                    ),
                  ],
                  child: Box(
                    border: .all(type: .rounded, style: theme.border),
                    padding: const .x(1),
                    child: Form(
                      key: _form,
                      onChanged: () => setState(() => _modified = true),
                      onSubmitted: _submitted,
                      child: TabView(
                        controller: _tabs,
                        children: [
                          _GeneralTab(saved: _saved),
                          _EditorTab(saved: _saved),
                          _PrivacyTab(
                            saved: _saved,
                            cached: _cached,
                            onClear: _canClear ? _askToClear : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              StatusBar(
                left: _modified
                    ? Text(' modified ', style: theme.warning)
                    : Text(' saved ', style: theme.muted),
                center: _clearing == null
                    ? null
                    : Row(
                        mainAxisSize: .min,
                        gap: 1,
                        children: [
                          Spinner(style: theme.primary),
                          const Text('clearing the cache…'),
                        ],
                      ),
                right: const Text('f10 menu  ctrl+s save  ctrl+q quit '),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _tabNames = ['General', 'Editor', 'Privacy'];
}

/// Asks whether the [files] of the cache are deleted; closes with true
/// when they are to be. Cancel has the focus: what cannot be undone takes
/// a Tab first.
final class _ClearCacheDialog extends StatelessWidget {
  const _ClearCacheDialog({required this.files});

  final int files;

  @override
  Widget build(BuildContext context) => Dialog(
    title: 'Clear the cache',
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      gap: 1,
      children: [
        Text('Delete the $files files of the cache?\nThis cannot be undone.'),
        Row(
          mainAxisSize: .min,
          gap: 2,
          children: [
            Button(
              'Cancel',
              autofocus: true,
              onPressed: () => closeDialog(context, false),
            ),
            Button(
              'Delete',
              style: Theme.of(context).error.merge(
                const Style(attrs: Attr.bold),
              ),
              onPressed: () => closeDialog(context, true),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The General tab: saving, updates and what opens at startup.
final class _GeneralTab extends StatelessWidget {
  const _GeneralTab({required this.saved});

  final Settings saved;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    children: [
      _SwitchField(
        'save automatically',
        saved: saved.autosave,
        onSaved: (v) => saved.autosave = v,
      ),
      _CheckboxField(
        'check for updates',
        saved: saved.checkUpdates,
        onSaved: (v) => saved.checkUpdates = v,
      ),
      const SizedBox(height: 1),
      const Text('On startup, open'),
      _RadioField(
        const [
          Choice(Startup.lastFiles, 'the files open last'),
          Choice(Startup.emptyWindow, 'an empty window'),
          Choice(Startup.welcome, 'the welcome page'),
        ],
        saved: saved.startup,
        onSaved: (v) => saved.startup = v,
      ),
    ],
  );
}

/// The Editor tab: lines, formatting and indentation.
final class _EditorTab extends StatelessWidget {
  const _EditorTab({required this.saved});

  final Settings saved;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    children: [
      _CheckboxField(
        'wrap lines',
        saved: saved.wrapLines,
        onSaved: (v) => saved.wrapLines = v,
      ),
      _CheckboxField(
        'show line numbers',
        saved: saved.lineNumbers,
        onSaved: (v) => saved.lineNumbers = v,
      ),
      _SwitchField(
        'format on save',
        saved: saved.formatOnSave,
        onSaved: (v) => saved.formatOnSave = v,
      ),
      const SizedBox(height: 1),
      const Text('Indent with'),
      _RadioField(
        const [
          Choice(Indent.twoSpaces, '2 spaces'),
          Choice(Indent.fourSpaces, '4 spaces'),
          Choice(Indent.tab, 'a tab'),
        ],
        saved: saved.indent,
        onSaved: (v) => saved.indent = v,
        direction: .horizontal,
      ),
    ],
  );
}

/// The Privacy tab: what is sent, and the cache, [cached] files of it,
/// with a button that asks to clear it, [onClear], disabled when null.
final class _PrivacyTab extends StatelessWidget {
  const _PrivacyTab({
    required this.saved,
    required this.cached,
    required this.onClear,
  });

  final Settings saved;
  final int cached;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    children: [
      _SwitchField(
        'send crash reports',
        saved: saved.crashReports,
        onSaved: (v) => saved.crashReports = v,
      ),
      _CheckboxField(
        'share usage statistics',
        saved: saved.usageStatistics,
        onSaved: (v) => saved.usageStatistics = v,
      ),
      const SizedBox(height: 1),
      Text(
        cached == 0 ? 'The cache is empty.' : 'The cache holds $cached files.',
      ),
      Button('Clear the cache…', onPressed: onClear),
    ],
  );
}

/// A field of the form: a checkbox of [label], checked as [saved] says
/// until the form saves its value with [onSaved].
final class _CheckboxField extends StatelessWidget {
  const _CheckboxField(
    this.label, {
    required this.saved,
    required this.onSaved,
  });

  final String label;
  final bool saved;
  final void Function(bool value) onSaved;

  @override
  Widget build(BuildContext context) => FormField<bool>(
    initialValue: saved,
    onSaved: (value) => onSaved(value!),
    builder: (field) =>
        Checkbox(value: field.value!, label: label, onChanged: field.didChange),
  );
}

/// A field of the form: a switch of [label], as [_CheckboxField] is.
final class _SwitchField extends StatelessWidget {
  const _SwitchField(this.label, {required this.saved, required this.onSaved});

  final String label;
  final bool saved;
  final void Function(bool value) onSaved;

  @override
  Widget build(BuildContext context) => FormField<bool>(
    initialValue: saved,
    onSaved: (value) => onSaved(value!),
    builder: (field) =>
        Switch(value: field.value!, label: label, onChanged: field.didChange),
  );
}

/// A field of the form: radio buttons of [choices] along [direction], the
/// one of [saved] chosen until the form saves the value with [onSaved].
final class _RadioField<T> extends StatelessWidget {
  const _RadioField(
    this.choices, {
    required this.saved,
    required this.onSaved,
    this.direction = .vertical,
  });

  final List<Choice<T>> choices;
  final T saved;

  // called with the field's values, whose T is the widget's own
  // ignore: unsafe_variance
  final void Function(T value) onSaved;
  final Axis direction;

  @override
  Widget build(BuildContext context) => FormField<T>(
    initialValue: saved,
    onSaved: (value) => onSaved(value as T),
    builder: (field) => RadioGroup<T>(
      choices: choices,
      value: field.value,
      direction: direction,
      onChanged: field.didChange,
    ),
  );
}
