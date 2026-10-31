part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _controls() => const [
    SizedBox(
      height: 3,
      child: Row(
        gap: 1,
        children: [
          SizedBox(width: 16, child: _Tabs()),
          Badge('3', kind: StatusKind.success),
          StatusMessage('saved', kind: StatusKind.success),
          Link('https://dart.dev', text: 'dart'),
          SizedBox(width: 4, child: ListTile(title: Text('tile'))),
          SizedBox(
            width: 16,
            child: StatusBar(left: Text('mode'), right: Text('Ln 1')),
          ),
          Overlay(child: _Choices()),
          Expanded(child: KeyHintsBar(showUnhinted: true)),
        ],
      ),
    ),
    SizedBox(
      // the file picker's field, a row of its list and its buttons
      height: 3,
      child: Row(
        gap: 2,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _SignUp()),
          Overlay(child: _Inputs()),
          SizedBox(width: 30, child: Overlay(child: _Files())),
        ],
      ),
    ),
    SizedBox(height: 3, child: _Notices()),
  ];
}

/// A notice to dismiss and two segments to choose one of.
final class _Notices extends StatefulWidget {
  const _Notices();

  @override
  State<_Notices> createState() => _NoticesState();
}

final class _NoticesState extends State<_Notices> {
  var _shown = true;
  var _view = {1};

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      if (_shown)
        Callout.text('new', onDismissed: () => setState(() => _shown = false)),
      SegmentedButton<int>(
        segments: const [Choice(1, 'a'), Choice(2, 'b')],
        selected: _view,
        onSelectionChanged: (v) => setState(() => _view = v),
      ),
    ],
  );
}

/// Two tabs and the view of the selected one.
final class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

final class _TabsState extends State<_Tabs> {
  final _tabs = TabController(length: 2);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TabBar(controller: _tabs, tabs: const ['one', 'two']),
      Expanded(
        child: TabView(
          controller: _tabs,
          children: const [Text('first'), Text('second')],
        ),
      ),
    ],
  );
}

/// A control of each kind, and the values they choose.
final class _Choices extends StatefulWidget {
  const _Choices();

  @override
  State<_Choices> createState() => _ChoicesState();
}

final class _ChoicesState extends State<_Choices> {
  final SelectionController<int> _selection = SelectionController(
    multiple: true,
  );
  var _checked = false;
  var _on = true;
  int? _radio = 1;
  int? _select;
  Set<int> _multi = {};
  bool? _sure;

  static const List<Choice<int>> _numbers = [
    Choice(1, 'one'),
    Choice(2, 'two'),
  ];

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    gap: 1,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Button('Clear', onPressed: () => setState(_selection.clear)),
          Checkbox(
            value: _checked,
            onChanged: (v) => setState(() => _checked = v),
            label: 'check',
          ),
          Switch(
            value: _on,
            onChanged: (v) => setState(() => _on = v),
            label: 'switch',
          ),
        ],
      ),
      Pressable(
        bindings: {'enter': () => setState(() => _on = !_on)},
        builder: (context, focused) => Text(focused ? '>' : ' '),
      ),
      RadioGroup<int>(
        choices: _numbers,
        value: _radio,
        onChanged: (v) => setState(() => _radio = v),
      ),
      SizedBox(
        width: 5,
        child: SelectionList<int>(
          itemCount: 3,
          keyOf: (i) => i,
          itemBuilder: (context, i) => Text('$i'),
          controller: _selection,
        ),
      ),
      Select<int>(
        choices: _numbers,
        value: _select,
        onChanged: (v) => setState(() => _select = v),
        hint: 'pick',
      ),
      MultiSelect<int>(
        choices: _numbers,
        values: _multi,
        onChanged: (v) => setState(() => _multi = v),
        hint: 'pick',
      ),
      ConfirmInput(
        _sure == null ? 'ok?' : '$_sure',
        onConfirmed: (v) => setState(() => _sure = v),
      ),
    ],
  );
}

/// A form of a name and a box to check side by side, which say what is
/// missing below them as they change.
final class _SignUp extends StatelessWidget {
  const _SignUp();

  @override
  Widget build(BuildContext context) => Form(
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: Row(
      gap: 1,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 10,
          child: TextFormField(
            placeholder: 'name',
            validator: (v) => v!.isEmpty ? 'name?' : null,
          ),
        ),
        FormField<bool>(
          initialValue: false,
          validator: (v) => v! ? null : 'agree?',
          builder: (field) => Checkbox(
            value: field.value!,
            onChanged: field.didChange,
            label: 'ok',
          ),
        ),
      ],
    ),
  );
}

/// A level on a slider, a count and a date, which they change.
final class _Inputs extends StatefulWidget {
  const _Inputs();

  @override
  State<_Inputs> createState() => _InputsState();
}

final class _InputsState extends State<_Inputs> {
  var _level = 0.5;
  var _count = 3.0;
  DateTime? _date;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    gap: 1,
    children: [
      SizedBox(
        width: 12,
        child: Slider(
          value: _level,
          divisions: 10,
          onChanged: (v) => setState(() => _level = v),
        ),
      ),
      SizedBox(
        width: 8,
        child: NumberInput(
          value: _count,
          min: 0,
          max: 99,
          onChanged: (v) => setState(() => _count = v),
        ),
      ),
      SizedBox(
        width: 14,
        child: DatePicker(
          value: _date,
          onChanged: (v) => setState(() => _date = v),
        ),
      ),
    ],
  );
}

/// A picker of the Dart files of the current directory.
final class _Files extends StatelessWidget {
  const _Files();

  @override
  Widget build(BuildContext context) => FilePicker(
    filters: const [
      FileFilter('Dart', ['dart']),
    ],
    onPicked: (_) {},
  );
}
