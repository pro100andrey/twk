// A form filled through the tester: text fields and the choice controls
// plugged in by a builder, Enter moving to the next field and submitting
// from the last, errors under the fields, the first invalid field focused
// on submit; the validation modes; save and reset; the order of the tree
// for fields that come and go; a text field's controller.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pump();
}

/// A node named [label], disposed after the test.
FocusNode node(String label) {
  final n = FocusNode(debugLabel: label);
  addTearDown(n.dispose);
  return n;
}

String? required(String? v) => v == null || v.isEmpty ? 'required' : null;

/// [fields] one below another.
Widget column(List<Widget> fields) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: fields);

/// A button that submits the form above it, [submitted] told whether all
/// its fields were valid.
final class SubmitButton extends StatelessWidget {
  const SubmitButton({required this.focusNode, this.submitted, super.key});

  final FocusNode focusNode;
  final void Function(bool valid)? submitted;

  @override
  Widget build(BuildContext context) => Button(
    'Submit',
    focusNode: focusNode,
    onPressed: () => submitted?.call(Form.of(context).submit()),
  );
}

void main() {
  testTwk('Enter moves from a text field to the next and submits from the '
      'last, hinted next and submit; all valid, the fields are saved, then '
      'onSubmitted is called', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Form(
          onSubmitted: () => log.add('submitted'),
          child: column([
            TextFormField(
              focusNode: node('name'),
              autofocus: true,
              placeholder: 'name',
              onSaved: (v) => log.add('name $v'),
            ),
            TextFormField(
              focusNode: node('email'),
              placeholder: 'email',
              onSaved: (v) => log.add('email $v'),
            ),
          ]),
        ),
      ),
      size: (20, 3),
    );
    await t.pump();
    expect(t.lines, ['name', 'email', '']);
    expect(focused(t), 'name');
    expect(hints(t), ['enter next']);
    await type(t, 'Ada');
    await press(t, 'enter');
    expect(focused(t), 'email');
    expect(hints(t), ['enter submit']);
    expect(log, isEmpty);
    await type(t, 'ada@x');
    await press(t, 'enter');
    expect(log, ['name Ada', 'email ada@x', 'submitted']);
    expect(t.lines, ['Ada', 'ada@x', '']);
    expect(focused(t), 'email');
  });

  testTwk('a field takes Enter from the moment the focus is in it: Enter '
      'typed right after the Tab that focuses it, in one read', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Form(
          onSubmitted: () => log.add('submitted'),
          child: column([
            for (final name in ['name', 'email', 'city'])
              TextFormField(
                focusNode: node(name),
                autofocus: name == 'name',
                onSaved: (v) => log.add('$name $v'),
              ),
          ]),
        ),
      ),
      size: (20, 3),
    );
    await t.pump();
    await t.type('Ada\t\r');
    await t.pump();
    expect(focused(t), 'city');
    await t.type('\x1b[Zada@x\r');
    await t.pump();
    expect(focused(t), 'city');
    await t.type('\x1b[Z\tLondon\r');
    await t.pump();
    expect(log, ['name Ada', 'email ada@x', 'city London', 'submitted']);
  });

  testTwk('a submit validates every field: each error under its field in '
      "the theme's error color, the first invalid field focused, nothing "
      'saved; a field that shows an error validates again as it '
      'changes', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Form(
          onSubmitted: () => log.add('submitted'),
          child: column([
            TextFormField(
              focusNode: node('name'),
              placeholder: 'name',
              validator: required,
              onSaved: (v) => log.add('name $v'),
            ),
            TextFormField(
              focusNode: node('age'),
              placeholder: 'age',
              validator: (v) => int.tryParse(v!) == null ? 'a number' : null,
              onSaved: (v) => log.add('age $v'),
            ),
            TextFormField(
              focusNode: node('email'),
              autofocus: true,
              placeholder: 'email',
              validator: required,
            ),
          ]),
        ),
      ),
      size: (20, 6),
    );
    await type(t, 'x');
    expect(t.lines, ['name', 'age', 'x', '', '', '']);
    await press(t, 'enter');
    expect(t.lines, ['name', 'required', 'age', 'a number', 'x', '']);
    expect(t, styleAt(0, 1, hasFg(Color.red)));
    expect(t, styleAt(0, 3, hasFg(Color.red)));
    expect(t, styleAt(0, 0, isNot(hasFg(Color.red))));
    expect(focused(t), 'name');
    expect(log, isEmpty);
    await type(t, 'A');
    expect(t.lines, ['A', 'age', 'a number', 'x', '', '']);
    await press(t, 'backspace');
    expect(t.lines, ['name', 'required', 'age', 'a number', 'x', '']);
    await type(t, 'Al');
    await press(t, 'enter');
    expect(focused(t), 'age');
    await type(t, '4');
    expect(t.lines, ['Al', '4', 'x', '', '', '']);
    await press(t, 'enter enter');
    expect(log, ['name Al', 'age 4', 'submitted']);
  });

  testTwk('each field validates on its own as its autovalidateMode says: '
      'always from the start, onUserInteraction at each change, onUnfocus '
      'as the focus leaves it, disabled never', (t) async {
    TextFormField field(String label, AutovalidateMode mode) => TextFormField(
      focusNode: node(label),
      placeholder: label,
      validator: (v) => v!.length < 2 ? '$label short' : null,
      autovalidateMode: mode,
    );
    await t.pumpWidget(
      Theme.terminal(
        child: Form(
          child: column([
            field('always', AutovalidateMode.always),
            field('change', AutovalidateMode.onUserInteraction),
            field('blur', AutovalidateMode.onUnfocus),
            field('off', AutovalidateMode.disabled),
          ]),
        ),
      ),
      size: (20, 6),
    );
    expect(t.lines, ['always', 'always short', 'change', 'blur', 'off', '']);
    await press(t, 'tab');
    expect(focused(t), 'always');
    await type(t, 'ab');
    expect(t.lines, ['ab', 'change', 'blur', 'off', '', '']);
    await press(t, 'tab');
    await type(t, 'a');
    expect(t.lines, ['ab', 'a', 'change short', 'blur', 'off', '']);
    await type(t, 'b');
    expect(t.lines, ['ab', 'ab', 'blur', 'off', '', '']);
    await press(t, 'tab');
    expect(focused(t), 'blur');
    await type(t, 'a');
    expect(t.lines, ['ab', 'ab', 'a', 'off', '', '']);
    await press(t, 'tab');
    expect(focused(t), 'off');
    expect(t.lines, ['ab', 'ab', 'a', 'blur short', 'off', '']);
    await type(t, 'a');
    await press(t, 'shift+tab');
    expect(t.lines, ['ab', 'ab', 'a', 'blur short', 'a', '']);
    await type(t, 'b');
    expect(t.lines, ['ab', 'ab', 'ab', 'a', '', '']);
  });

  testTwk("a field without a mode of its own takes the form's, and a form "
      'built with another mode rebuilds its fields', (t) async {
    final mode = ValueNotifier(AutovalidateMode.disabled);
    addTearDown(mode.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: ValueListenableBuilder<AutovalidateMode>(
          valueListenable: mode,
          builder: (context, m, fields) =>
              Form(autovalidateMode: m, child: fields!),
          child: column([
            TextFormField(
              focusNode: node('a'),
              autofocus: true,
              placeholder: 'a',
              validator: required,
            ),
            TextFormField(placeholder: 'b', validator: required),
            TextFormField(
              placeholder: 'c',
              validator: required,
              autovalidateMode: AutovalidateMode.disabled,
            ),
          ]),
        ),
      ),
      size: (20, 5),
    );
    await type(t, 'x');
    await press(t, 'backspace');
    expect(t.lines, ['a', 'b', 'c', '', '']);
    mode.value = AutovalidateMode.onUserInteraction;
    await t.pump();
    await type(t, 'x');
    expect(t.lines, ['x', 'b', 'c', '', '']);
    await press(t, 'backspace');
    expect(t.lines, ['a', 'required', 'b', 'c', '']);
    mode.value = AutovalidateMode.always;
    await t.pump();
    expect(t.lines, ['a', 'required', 'b', 'required', 'c']);
  });

  testTwk('the choice controls plug in by the builder: validated, saved '
      'and reset with a text field; a control that takes Enter keeps it; '
      'a button below finds the form by Form.of and submits it', (t) async {
    final log = <String>[];
    final form = GlobalKey<FormState>();
    var changes = 0;
    await t.pumpWidget(
      Theme.terminal(
        child: Overlay(
          child: Form(
            key: form,
            onSubmitted: () => log.add('submitted'),
            onChanged: () => changes++,
            child: column([
              TextFormField(
                focusNode: node('name'),
                initialValue: 'Ada',
                validator: required,
                onSaved: (v) => log.add('name $v'),
              ),
              FormField<bool>(
                initialValue: false,
                validator: (v) => v! ? null : 'accept',
                onSaved: (v) => log.add('terms $v'),
                builder: (field) => Checkbox(
                  value: field.value!,
                  onChanged: field.didChange,
                  label: 'terms',
                  focusNode: node('terms'),
                ),
              ),
              FormField<int>(
                validator: (v) => v == null ? 'pick a size' : null,
                onSaved: (v) => log.add('size $v'),
                builder: (field) => RadioGroup<int>(
                  choices: const [Choice(1, 'S'), Choice(2, 'M')],
                  value: field.value,
                  onChanged: field.didChange,
                  direction: Axis.horizontal,
                  focusNode: node('size'),
                ),
              ),
              FormField<String>(
                validator: required,
                onSaved: (v) => log.add('fruit $v'),
                builder: (field) => Select<String>(
                  choices: const [Choice('a', 'Apple'), Choice('b', 'Banana')],
                  value: field.value,
                  onChanged: field.didChange,
                  hint: 'fruit',
                  focusNode: node('fruit'),
                ),
              ),
              SubmitButton(
                focusNode: node('submit'),
                submitted: (valid) => log.add('valid $valid'),
              ),
            ]),
          ),
        ),
      ),
      size: (20, 9),
    );
    final start = [
      'Ada',
      '[ ] terms',
      '( ) S  ( ) M',
      ' fruit  ▾',
      ' Submit',
      '',
      '',
      '',
      '',
    ];
    expect(t.lines, start);
    await press(t, 'tab');
    expect(focused(t), 'name');
    await type(t, ' L.');
    await press(t, 'tab tab tab tab');
    expect(focused(t), 'submit');
    await press(t, 'enter');
    expect(log, ['valid false']);
    expect(t.lines, [
      'Ada L.',
      '[ ] terms',
      'accept',
      '( ) S  ( ) M',
      'pick a size',
      ' fruit  ▾',
      'required',
      ' Submit',
      '',
    ]);
    expect(focused(t), 'terms');
    await press(t, 'enter');
    expect(focused(t), 'terms');
    expect(t.lines.take(3), ['Ada L.', '[x] terms', '( ) S  ( ) M']);
    await press(t, 'tab space right');
    expect(t.lines.skip(2).take(2), ['( ) S  (●) M', ' fruit  ▾']);
    await press(t, 'tab enter down enter');
    expect(t.lines, [
      'Ada L.',
      '[x] terms',
      '( ) S  (●) M',
      ' Banana ▾',
      ' Submit',
      '',
      '',
      '',
      '',
    ]);
    expect(changes, 7);
    await press(t, 'tab enter');
    expect(log, [
      'valid false',
      'name Ada L.',
      'terms true',
      'size 2',
      'fruit b',
      'submitted',
      'valid true',
    ]);
    form.currentState!.reset();
    await t.pump();
    expect(t.lines, start);
    expect(changes, 8);
    await press(t, 'tab ctrl+u');
    expect(focused(t), 'name');
    expect(t.lines.take(2), ['', '[ ] terms']);
    form.currentState!.reset();
    await t.pump();
    log.clear();
    form.currentState!.save();
    expect(log, ['name Ada', 'terms false', 'size null', 'fruit null']);
    expect(form.currentState!.validate(), isFalse);
    await t.pump();
    expect(t.lines.take(5), [
      'Ada',
      '[ ] terms',
      'accept',
      '( ) S  ( ) M',
      'pick a size',
    ]);
    expect(focused(t), 'name');
  });

  testTwk('Enter passes the fields that cannot take the focus; fields '
      'built later are in the order of the tree, and a field gone is '
      'neither validated nor saved', (t) async {
    final log = <String>[];
    final middle = ValueNotifier(false);
    addTearDown(middle.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: ValueListenableBuilder<bool>(
          valueListenable: middle,
          builder: (context, on, _) => Form(
            onSubmitted: () => log.add('submitted'),
            child: column([
              FormField<bool>(
                initialValue: false,
                validator: (v) => on ? 'top' : null,
                builder: (field) => Checkbox(
                  value: field.value!,
                  onChanged: null,
                  label: 'top',
                ),
              ),
              TextFormField(
                focusNode: node('first'),
                autofocus: true,
                onSaved: (v) => log.add('first'),
              ),
              if (on)
                TextFormField(
                  focusNode: node('middle'),
                  validator: required,
                  onSaved: (v) => log.add('middle'),
                ),
              FormField<bool>(
                initialValue: false,
                onSaved: (v) => log.add('off'),
                builder: (field) => Checkbox(
                  value: field.value!,
                  onChanged: null,
                  label: 'off',
                ),
              ),
              TextFormField(
                focusNode: node('last'),
                onSaved: (v) => log.add('last'),
              ),
              FormField<bool>(
                initialValue: false,
                builder: (field) => Checkbox(
                  value: field.value!,
                  onChanged: null,
                  label: 'end',
                ),
              ),
            ]),
          ),
        ),
      ),
      size: (20, 8),
    );
    await t.pump();
    expect(hints(t), ['enter next']);
    await press(t, 'enter');
    expect(focused(t), 'last');
    expect(hints(t), ['enter submit']);
    middle.value = true;
    await t.pump();
    await press(t, 'shift+tab');
    expect(focused(t), 'middle');
    await press(t, 'shift+tab');
    expect(focused(t), 'first');
    await press(t, 'enter');
    expect(focused(t), 'middle');
    await press(t, 'enter');
    expect(focused(t), 'last');
    await press(t, 'enter');
    expect(log, isEmpty);
    expect(focused(t), 'middle');
    expect(t.lines, [
      '[ ] top',
      'top',
      '',
      '',
      'required',
      '[ ] off',
      '',
      '[ ] end',
    ]);
    middle.value = false;
    await t.pump();
    await press(t, 'tab');
    expect(focused(t), 'first');
    await press(t, 'enter');
    expect(focused(t), 'last');
    await press(t, 'enter');
    expect(log, ['first', 'off', 'last', 'submitted']);
  });

  testTwk("a text field's controller: the value follows its text, the "
      "app's changes too; a reset gives back the text it had first; "
      'another controller takes its place', (t) async {
    final a = TextEditingController(text: 'one');
    final b = TextEditingController(text: 'two');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final controller = ValueNotifier<TextEditingController?>(a);
    addTearDown(controller.dispose);
    final field = GlobalKey<FormFieldState<String>>();
    var changes = 0;
    await t.pumpWidget(
      Theme.terminal(
        child: ValueListenableBuilder<TextEditingController?>(
          valueListenable: controller,
          builder: (context, c, _) => Form(
            onChanged: () => changes++,
            child: TextFormField(
              key: field,
              controller: c,
              focusNode: node('field'),
              autofocus: true,
              validator: required,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
          ),
        ),
      ),
      size: (20, 2),
    );
    expect(field.currentState!.value, 'one');
    await type(t, '!');
    expect(field.currentState!.value, 'one!');
    a.text = '';
    await t.pump();
    expect(field.currentState!.value, '');
    expect(t.lines, ['', 'required']);
    expect(changes, 2);
    a.selection = const TextSelection.collapsed(offset: 0);
    expect(changes, 2);
    field.currentState!.reset();
    await t.pump();
    expect(a.text, 'one');
    expect(t.lines, ['one', '']);
    expect(changes, 2);
    expect(a.canUndo, isFalse, reason: 'a reset is no step to undo');
    controller.value = b;
    await t.pump();
    expect(field.currentState!.value, 'two');
    expect(t.lines, ['two', '']);
    a.text = 'gone';
    await t.pump();
    expect(field.currentState!.value, 'two');
    await type(t, '2');
    expect(field.currentState!.value, 'two2');
    expect(b.text, 'two2');
    field.currentState!.reset();
    expect(b.text, 'two');
    controller.value = null;
    await t.pump();
    expect(t.lines, ['two', '']);
    await type(t, '3');
    expect(field.currentState!.value, 'two3');
    expect(b.text, 'two');
    controller.value = a;
    await t.pump();
    expect(t.lines, ['gone', '']);
    expect(field.currentState!.value, 'gone');
  });

  testTwk('a TextFormField hands the parameters of its TextField on', (
    t,
  ) async {
    final changed = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Form(
          child: column([
            TextFormField(
              focusNode: node('secret'),
              autofocus: true,
              obscureText: true,
              obscuringCharacter: '*',
              maxLength: 3,
              onChanged: changed.add,
              style: const Style(fg: Color.green),
              selectionStyle: const Style(fg: Color.magenta),
            ),
            TextFormField(
              placeholder: 'off',
              placeholderStyle: const Style(fg: Color.yellow),
              canRequestFocus: false,
            ),
          ]),
        ),
      ),
      size: (10, 2),
    );
    await type(t, 'abcd');
    expect(t.lines, ['***', 'off']);
    expect(changed, ['a', 'ab', 'abc']);
    expect(t, styleAt(0, 0, hasFg(Color.green)));
    expect(t, styleAt(0, 1, hasFg(Color.yellow)));
    await press(t, 'shift+left tab');
    expect(focused(t), 'secret');
    expect(t, styleAt(1, 0, hasFg(Color.green)));
    expect(t, styleAt(2, 0, hasFg(Color.magenta)));
  });

  testTwk('a TextFormField reads as a textbox of its semanticsLabel, else '
      'of its placeholder', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: Form(
          child: column([
            TextFormField(semanticsLabel: 'Email', placeholder: 'you@x.org'),
            TextFormField(placeholder: 'City'),
            TextFormField(),
          ]),
        ),
      ),
      size: (12, 3),
    );
    expect(t.binding.semantics.lines, [
      'textbox Email',
      'textbox City',
      'textbox',
    ]);
  });

  testTwk("a field's state: its value, error and focus; focus() moves the "
      'focus to the first node in it that Tab stops at, false where there '
      'is none', (t) async {
    final text = GlobalKey<FormFieldState<String>>();
    final box = GlobalKey<FormFieldState<bool>>();
    final wrapped = GlobalKey<FormFieldState<String>>();
    await t.pumpWidget(
      Theme.terminal(
        child: Form(
          child: column([
            TextFormField(
              key: text,
              focusNode: node('text'),
              initialValue: 'x',
              validator: (v) => v!.length < 2 ? 'short' : null,
              errorStyle: const Style(fg: Color.yellow),
            ),
            FormField<bool>(
              key: box,
              initialValue: true,
              builder: (field) =>
                  Checkbox(value: field.value!, onChanged: null, label: 'off'),
            ),
            FormField<String>(
              key: wrapped,
              builder: (field) => Focus(
                debugLabel: 'wrapper',
                skipTraversal: true,
                child: TextField(focusNode: node('inner')),
              ),
            ),
          ]),
        ),
      ),
      size: (20, 4),
    );
    final s = text.currentState!;
    expect(
      (s.value, s.errorText, s.hasError, s.isValid, s.hasFocus),
      ('x', null, false, false, false),
    );
    expect(s.focus(), isTrue);
    expect(s.hasFocus, isTrue);
    expect(s.validate(), isFalse);
    await t.pump();
    expect((s.errorText, s.hasError), ('short', true));
    expect(t.lines, ['x', 'short', '[x] off', '']);
    expect(t, styleAt(0, 1, hasFg(Color.yellow)));
    s.didChange('xy');
    await t.pump();
    expect((s.value, s.errorText, s.isValid), ('xy', null, true));
    expect(box.currentState!.focus(), isFalse);
    expect(focused(t), 'text');
    expect(box.currentState!.validate(), isTrue);
    expect(wrapped.currentState!.focus(), isTrue);
    expect(focused(t), 'inner');
  });

  testTwk('Enter does nothing to a form while none of its fields has the '
      'focus', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Form(
          onSubmitted: () => log.add('submitted'),
          child: TextFormField(focusNode: node('only')),
        ),
      ),
      size: (20, 2),
    );
    await press(t, 'enter');
    expect(focused(t), isNot('only'));
    expect(log, isEmpty);
    expect(hints(t), isEmpty);
  });

  testTwk('outside a Form a field validates alone and leaves Enter to the '
      'nodes above, unhinted; Form.of finds none', (t) async {
    final entered = <String>[];
    final field = GlobalKey<FormFieldState<String>>();
    late BuildContext inside;
    await t.pumpWidget(
      Theme.terminal(
        child: KeyBindings(
          {'enter': () => entered.add('enter')},
          child: TextFormField(
            key: field,
            focusNode: node('field'),
            autofocus: true,
            validator: required,
            autovalidateMode: AutovalidateMode.onUnfocus,
          ),
        ),
      ),
      size: (20, 2),
    );
    await t.pump();
    inside = field.currentContext!;
    expect(hints(t), isEmpty);
    await press(t, 'enter');
    expect(entered, ['enter']);
    expect(field.currentState!.validate(), isFalse);
    await t.pump();
    expect(t.lines, ['', 'required']);
    expect(Form.maybeOf(inside), isNull);
    expect(() => Form.of(inside), throwsStateError);
  });

  testTwk('a TextFormField shows the focus on the selection color, its '
      'selection a step towards the primary; focusedStyle gives a '
      'plain look', (t) async {
    const dark = ThemeData.dark;
    await t.pumpWidget(
      Theme.terminal(
        child: Theme(
          data: dark,
          child: Form(
            child: Column(
              children: [
                TextFormField(initialValue: 'ab', autofocus: true),
                TextFormField(initialValue: 'cd', focusedStyle: const Style()),
              ],
            ),
          ),
        ),
      ),
      size: (10, 2),
    );
    expect(t.cell(5, 0).bg, dark.selection.bg);
    expect(t.cell(5, 1).bg, dark.well.bg);
    await t.press('shift+left');
    await t.pump();
    expect(t.cell(1, 0).bg, const Color.rgb(0x40, 0x6d, 0xa3));
    await t.press('tab');
    await t.pump();
    expect(t.cell(5, 0).bg, dark.well.bg);
    expect(t.cell(5, 1).bg, dark.well.bg);
  });
}
