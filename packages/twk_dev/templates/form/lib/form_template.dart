import 'package:twk/twk.dart';

/// What the form asks for.
final class Signup {
  var name = '';
  var email = '';
  var age = 30.0;
  var newsletter = false;
}

/// The error of [name], null for none.
String? validateName(String? name) =>
    name!.trim().isEmpty ? 'a name, please' : null;

/// The error of [email], null for none.
String? validateEmail(String? email) =>
    RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(email!) ? null : 'an email: a@b';

/// The error of [age], null for none.
String? validateAge(double? age) => age! < 18 ? '18 or older' : null;

/// A sign-up form: a name, an email, an age and the newsletter, each field
/// said what is wrong with it below it. Enter goes to the next field and
/// from the last submits, as Ctrl+S and the button do; once every field is
/// right, who signed up shows under the form. Ctrl+Q quits.
final class SignupForm extends StatefulWidget {
  const SignupForm({super.key});

  @override
  State<SignupForm> createState() => _SignupFormState();
}

final class _SignupFormState extends State<SignupForm> {
  final _form = GlobalKey<FormState>();
  final _signup = Signup();

  /// Who signed up, once the form was submitted.
  String? _done;

  void _submit() => _form.currentState!.submit();

  void _submitted() => setState(
    () => _done =
        '${_signup.name} <${_signup.email}>, ${_signup.age.round()}, '
        '${_signup.newsletter ? 'with' : 'without'} the newsletter',
  );

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'ctrl+s': _submit, 'ctrl+q': () => AppBinding.of(context).quit()},
    hints: const {'ctrl+s': 'submit', 'ctrl+q': 'quit'},
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Box(
          border: .all(type: .rounded, style: Theme.of(context).border),
          titles: const [BorderTitle(' Sign up ')],
          padding: const .x(1),
          child: Form(
            key: _form,
            onSubmitted: _submitted,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                _Labeled(
                  'name',
                  TextFormField(
                    placeholder: 'Ann Lee',
                    validator: validateName,
                    onSaved: (name) => _signup.name = name!.trim(),
                    autofocus: true,
                  ),
                ),
                _Labeled(
                  'email',
                  TextFormField(
                    placeholder: 'ann@example.com',
                    validator: validateEmail,
                    onSaved: (email) => _signup.email = email!,
                  ),
                ),
                _Labeled(
                  'age',
                  FormField<double>(
                    initialValue: _signup.age,
                    validator: validateAge,
                    onSaved: (age) => _signup.age = age!,
                    builder: (field) => NumberInput(
                      value: field.value!,
                      onChanged: field.didChange,
                      min: 0,
                      max: 130,
                    ),
                  ),
                ),
                _Labeled(
                  '',
                  FormField<bool>(
                    initialValue: _signup.newsletter,
                    onSaved: (newsletter) => _signup.newsletter = newsletter!,
                    builder: (field) => Checkbox(
                      value: field.value!,
                      onChanged: field.didChange,
                      label: 'send me the newsletter',
                    ),
                  ),
                ),
                // under the fields, past their labels
                Padding(
                  padding: const .only(left: 6),
                  child: Button('Sign up', onPressed: _submit),
                ),
              ],
            ),
          ),
        ),
        if (_done case final done?)
          StatusMessage('Signed up: $done', kind: .success),
        const Spacer(),
        // the keys where the focus is: Enter next or submit, Ctrl+S, Ctrl+Q
        const KeyHintsBar(),
      ],
    ),
  );
}

/// [field] after [label], the labels of the fields one above another.
final class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.field);

  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      SizedBox(width: 6, child: Text(label)),
      Expanded(child: field),
    ],
  );
}
