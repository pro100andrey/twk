/// Fields that hold values, validate them and are submitted together, and
/// Enter moving from one to the next: [Form], [FormField] and
/// [TextFormField].
library;

import '../editing/input_decoration.dart';
import '../editing/text_editing.dart';
import '../editing/text_field.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../layout/flex.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'field_styles.dart';

/// When a [FormField] validates its value on its own, besides when its
/// [Form] validates ([FormState.validate], [FormState.submit]) or it is
/// told to ([FormFieldState.validate]). In every mode a field validated
/// once validates again at each change, until a reset: its error goes
/// once the value is right, and comes back when it is wrong again.
enum AutovalidateMode {
  /// Never on its own.
  disabled,

  /// At each build, before the user changed anything too.
  always,

  /// At each change of its value ([FormFieldState.didChange]).
  onUserInteraction,

  /// When the focus leaves it.
  onUnfocus,
}

/// Keeps the [FormField]s below [child] together, to validate, save, reset
/// and submit them as one.
///
/// Its state validates them ([FormState.validate]), saves
/// ([FormState.save]), resets ([FormState.reset]) and submits them
/// ([FormState.submit]): when one is not valid, the first such gets the
/// focus; when all are, they are saved and [onSubmitted] is called.
/// [Form.of] finds the state from below it, as a button that submits does.
///
/// While a field has the focus, Enter that what edits it leaves to the
/// nodes above (a [TextFormField] does) moves the focus to the next field
/// that takes it, the fields in the order of the tree, as a `Column`
/// shows them; from the last it submits the form. Enter is hinted `next`
/// and `submit`. A control that takes Enter itself (a `Checkbox`, a
/// `Select`) keeps it.
///
/// A sign-in of two fields, submitted from the second or by the button:
///
/// ```dart
/// Form(
///   onSubmitted: () => print('signing in'),
///   child: Column(
///     children: [
///       TextFormField(
///         placeholder: 'user',
///         autofocus: true,
///         validator: (v) => v!.isEmpty ? 'who are you?' : null,
///       ),
///       TextFormField(placeholder: 'password', obscureText: true),
///       Builder(
///         builder: (context) => Button(
///           'Sign in',
///           onPressed: () => Form.of(context).submit(),
///         ),
///       ),
///     ],
///   ),
/// )
/// ```
///
/// See also:
///
///  * [AutovalidateMode], when the fields validate on their own.
final class Form extends StatefulWidget {
  /// Keeps the fields below [child] together.
  const Form({
    required this.child,
    super.key,
    this.onSubmitted,
    this.onChanged,
    this.autovalidateMode = AutovalidateMode.disabled,
  });

  /// What holds the fields, anywhere below it.
  final Widget child;

  /// Called by a submit that found every field valid, once they are saved.
  final VoidCallback? onSubmitted;

  /// Called when the value of a field changed ([FormFieldState.didChange])
  /// and after a reset.
  final VoidCallback? onChanged;

  /// How the fields validate on their own, those that do not say.
  final AutovalidateMode autovalidateMode;

  /// The state of the nearest [Form] above [context], without depending on
  /// it; a [StateError] if there is none.
  static FormState of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError('no Form above ${context.widget.runtimeType}'));

  /// The state [of] finds, if there is one.
  static FormState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_FormScope>()?.form;

  @override
  State<Form> createState() => FormState();
}

/// What a [Form] does with its fields.
final class FormState extends State<Form> {
  final _fields = <FormFieldState<Object?>>{};

  /// Validates every field, each showing its error; returns whether all
  /// are valid.
  bool validate() {
    var valid = true;
    for (final f in _inOrder()) {
      valid = f.validate() && valid;
    }
    return valid;
  }

  /// Gives each field's value to its [FormField.onSaved].
  void save() {
    for (final f in _inOrder()) {
      f.save();
    }
  }

  /// Resets each field ([FormFieldState.reset]), then calls
  /// [Form.onChanged].
  void reset() {
    for (final f in _inOrder()) {
      f.reset();
    }
    _changed();
  }

  /// Validates every field: when one is not valid, focuses the first such
  /// that takes the focus and returns false; else saves them, calls
  /// [Form.onSubmitted] and returns true.
  bool submit() {
    final invalid = [
      for (final f in _inOrder())
        if (!f.validate()) f,
    ];
    if (invalid.isNotEmpty) {
      for (final f in invalid) {
        if (f.focus()) {
          break;
        }
      }
      return false;
    }
    save();
    widget.onSubmitted?.call();
    return true;
  }

  /// The fields, in the order of the tree.
  List<FormFieldState<Object?>> _inOrder() {
    final byElement = {for (final f in _fields) f.context: f};
    final fields = <FormFieldState<Object?>>[];
    void visit(Element e) {
      if (fields.length < byElement.length) {
        if (byElement[e] case final f?) {
          fields.add(f);
        }
        e.visitChildren(visit);
      }
    }

    (context as Element).visitChildren(visit);
    return fields;
  }

  /// The fields after [field] that take the focus.
  Iterable<FormFieldState<Object?>> _after(FormFieldState<Object?> field) {
    final fields = _inOrder();
    return fields
        .skip(fields.indexOf(field) + 1)
        .where((f) => f._focusable != null);
  }

  /// Enter in [field]: the focus to the next field, or a submit.
  void _next(FormFieldState<Object?> field) {
    if (!_after(field).any((f) => f.focus())) {
      submit();
    }
  }

  void _changed() => widget.onChanged?.call();

  @override
  Widget build(BuildContext context) =>
      _FormScope(this, widget.autovalidateMode, child: widget.child);
}

/// What the fields find their [Form] by.
final class _FormScope extends InheritedWidget {
  const _FormScope(this.form, this.mode, {required super.child});

  final FormState form;
  final AutovalidateMode mode;

  @override
  bool updateShouldNotify(_FormScope oldWidget) => mode != oldWidget.mode;
}

/// A field of the nearest [Form] above it, which holds a value that
/// [builder] shows and edits.
///
/// [builder] builds what shows and edits the value from the field's
/// state, and what edits it tells a change with
/// [FormFieldState.didChange]. A control that takes a value and a callback
/// plugs in so:
///
/// ```dart
/// FormField<bool>(
///   initialValue: false,
///   validator: (v) => v! ? null : 'accept the terms',
///   builder: (field) => Checkbox(
///     value: field.value!,
///     onChanged: field.didChange,
///     label: 'I accept',
///   ),
/// )
/// ```
///
/// [validator] says what is wrong with a value, null for a valid one; the
/// error shows below what [builder] built, in [errorStyle] over the
/// theme's text ([ThemeData.error] when null), and wraps. The field
/// validates when the form does, or as [autovalidateMode] says, the form's
/// when null. [onSaved] gets the value when the form saves. The value
/// starts as [initialValue] and goes back to it at a reset.
///
/// The field has the focus while what [builder] built has it: a node of
/// the focus tree that does not take the focus itself is around it
/// ([FormFieldState.focus]).
final class FormField<T> extends StatefulWidget {
  /// A field of the value [builder] shows, [initialValue] at first.
  const FormField({
    required this.builder,
    super.key,
    this.initialValue,
    this.validator,
    this.onSaved,
    this.autovalidateMode,
    this.errorStyle,
  });

  /// Builds what shows and edits the value of the field.
  // ignore: unsafe_variance
  final Widget Function(FormFieldState<T> field) builder;

  /// The value the field starts with and a reset gives it back.
  final T? initialValue;

  /// The error for a value, null for a valid one; null takes every value.
  // ignore: unsafe_variance
  final String? Function(T? value)? validator;

  /// Gets the value when the form saves.
  // ignore: unsafe_variance
  final void Function(T? value)? onSaved;

  /// When the field validates on its own; the form's when null.
  final AutovalidateMode? autovalidateMode;

  /// The error; [ThemeData.error] when null.
  final Style? errorStyle;

  /// Whether what [builder] builds shows the error itself, which the
  /// field then does not show under it.
  bool get _showsError => false;

  @override
  FormFieldState<T> createState() => FormFieldState<T>();
}

/// The value of a [FormField], its error, and what its [Form] does with
/// it.
final class FormFieldState<T> extends State<FormField<T>> {
  T? _value;
  String? _error;
  _FormScope? _scope;

  // validated since the start or the last reset
  var _validated = false;

  // around what the builder built: it has the focus while that has it
  final _node = FocusNode(debugLabel: 'FormField', canRequestFocus: false);

  /// The value the field holds.
  T? get value => _value;

  /// The error it shows; null while it shows none.
  String? get errorText => _error;

  /// Whether it shows an error.
  bool get hasError => _error != null;

  /// Whether [FormField.validator] takes the value: a validation that
  /// shows nothing.
  bool get isValid => _check() == null;

  /// Whether what the builder built has the focus.
  bool get hasFocus => _node.hasFocus;

  /// The value it starts with and goes back to at a reset.
  T? get _initial => widget.initialValue;

  AutovalidateMode get _mode =>
      widget.autovalidateMode ?? _scope?.mode ?? AutovalidateMode.disabled;

  String? _check() => widget.validator?.call(_value);

  @override
  void initState() {
    super.initState();
    _value = _initial;
    _node.addListener(_focusChanged);
  }

  @override
  void deactivate() {
    _scope?.form._fields.remove(this);
    super.deactivate();
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// Takes [value] as the field's new value: validates it under
  /// [AutovalidateMode.onUserInteraction] or once validated, rebuilds the
  /// field and calls [Form.onChanged].
  void didChange(T? value) {
    setState(() {
      _value = value;
      if (_validated || _mode == AutovalidateMode.onUserInteraction) {
        _validate();
      }
    });
    _scope?.form._changed();
  }

  /// Validates the value, showing the error; returns whether it is valid.
  bool validate() {
    setState(_validate);
    return _error == null;
  }

  void _validate() {
    _error = _check();
    _validated = true;
  }

  /// Gives the value to [FormField.onSaved].
  void save() => widget.onSaved?.call(_value);

  /// Puts back the value the field started with, without an error, as
  /// one not validated since.
  void reset() => setState(() {
    _value = _initial;
    _error = null;
    _validated = false;
  });

  /// Focuses the first node below the field that Tab stops at, what edits
  /// the value; returns whether there is one.
  bool focus() {
    final node = _focusable;
    node?.requestFocus();
    return node != null && node.hasFocus;
  }

  /// The first node below the field that Tab stops at.
  FocusNode? get _focusable {
    FocusNode? first(FocusNode node) {
      for (final child in node.children) {
        if (child.canRequestFocus && !child.skipTraversal) {
          return child;
        }
        if (first(child) case final below?) {
          return below;
        }
      }
      return null;
    }

    return first(_node);
  }

  void _focusChanged() => setState(() {
    if (!_node.hasFocus && _mode == AutovalidateMode.onUnfocus) {
      _validate();
    }
  });

  void _enter() => _scope?.form._next(this);

  late final _enterAction = _EnterAction(this);

  @override
  Widget build(BuildContext context) {
    final scope = _scope = context
        .dependOnInheritedWidgetOfExactType<_FormScope>();
    scope?.form._fields.add(this);
    if (_mode == AutovalidateMode.always) {
      _error = _check();
    }
    // hinted for the focus it is built with: _after walks the form
    final entered = scope != null && _node.hasFocus;
    final error = _error;
    final theme = Theme.of(context);
    return Focus(
      focusNode: _node,
      child: Shortcuts(
        scope != null ? const {'enter': _Enter()} : const {},
        hints: !entered
            ? const {}
            : scope.form._after(this).isEmpty
            ? const {'enter': 'submit'}
            : const {'enter': 'next'},
        child: Actions(
          {_Enter: _enterAction},
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.builder(this),
              if (error != null && !widget._showsError)
                Text(
                  error,
                  style: theme.text.merge(widget.errorStyle ?? theme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Enter in a field of a [Form].
final class _Enter extends Intent {
  const _Enter();
}

/// Moves on from [field] ([FormState._next]) while the focus is in it
/// as the key comes; a key that reaches the field's layer with the focus
/// above it, as one with no node focused does, passes on.
final class _EnterAction extends Action<_Enter> {
  _EnterAction(this.field);

  final FormFieldState<Object?> field;

  @override
  bool isEnabled(_Enter intent) => field.hasFocus;

  @override
  void invoke(_Enter intent) => field._enter();
}

/// A [FormField] of the text a [TextField] edits.
///
/// The text is held by [controller], one of its own when null, starting
/// with [initialValue]. With a [controller], the field starts with its
/// text, and a reset gives that back; another controller, its text then.
/// The value follows the text, the app's changes of it too; the other
/// parameters go to the [TextField], which leaves Enter to the [Form]. A
/// field without a box around it, it shows the focus in
/// [TextField.focusedStyle], [ThemeData.selection] when null, and then its
/// selection, when no selectionStyle is given either, a step towards
/// [ThemeData.primary]; `focusedStyle: const Style()` gives a plain look,
/// the field without a fill.
///
/// With a [decoration], the field is drawn in it ([TextField.decoration])
/// and its error is the decoration's `errorText`, under the field in
/// place of its helper, the border and the label in [ThemeData.error];
/// the field then has no well or selection of its own, only the styles
/// given.
///
/// A screen reader reads it as its [TextField]: a textbox of
/// `semanticsLabel`, or of `placeholder` without one
/// ([TextField.semanticsLabel]).
///
/// A field of an email address, checked as the focus leaves it:
///
/// ```dart
/// TextFormField(
///   placeholder: 'you@example.com',
///   autovalidateMode: AutovalidateMode.onUnfocus,
///   validator: (v) => v!.contains('@') ? null : 'not an email address',
///   onSaved: (v) => print('email: $v'),
/// )
/// ```
final class TextFormField extends FormField<String> {
  /// A field of the text of [controller], or of one of its own starting
  /// with [initialValue]; not both, which it asserts.
  TextFormField({
    super.key,
    this.controller,
    String? initialValue,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.errorStyle,
    String? placeholder,
    String? semanticsLabel,
    bool obscureText = false,
    String obscuringCharacter = '•',
    int? maxLength,
    void Function(String text)? onChanged,
    FocusNode? focusNode,
    bool autofocus = false,
    bool? canRequestFocus,
    Style? style,
    Style? focusedStyle,
    Style? placeholderStyle,
    Style? selectionStyle,
    this.decoration,
  }) : assert(
         controller == null || initialValue == null,
         'the text of the controller is the initial value',
       ),
       super(
         initialValue: initialValue ?? '',
         // the styles given as they are in a decoration, in the well
         // without one
         builder: (field) {
           final plain = decoration == null;
           return TextField(
             controller: (field as _TextFormFieldState)._controller,
             placeholder: placeholder,
             semanticsLabel: semanticsLabel,
             obscureText: obscureText,
             obscuringCharacter: obscuringCharacter,
             maxLength: maxLength,
             onChanged: onChanged,
             focusNode: focusNode,
             autofocus: autofocus,
             canRequestFocus: canRequestFocus,
             style: plain
                 ? fieldRest(
                     Theme.of(field.context),
                   ).merge(style ?? const Style())
                 : style,
             focusedStyle: plain
                 ? focusedStyle ?? fieldFocused(Theme.of(field.context))
                 : focusedStyle,
             placeholderStyle: placeholderStyle,
             selectionStyle: plain
                 ? selectionStyle ??
                       (focusedStyle == null
                           ? fieldSelection(Theme.of(field.context))
                           : null)
                 : selectionStyle,
             decoration: switch (field.errorText) {
               final error? => decoration?.copyWith(errorText: error),
               null => decoration,
             },
           );
         },
       );

  /// What holds the text; null for one of the field's own.
  final TextEditingController? controller;

  /// What is drawn around the field, its error in it; null for the field
  /// in the well, the error on a line under it.
  final InputDecoration? decoration;

  @override
  bool get _showsError => decoration != null;

  @override
  FormFieldState<String> createState() => _TextFormFieldState();
}

final class _TextFormFieldState extends FormFieldState<String> {
  TextEditingController? _own;

  // the text of the controller given when the field started
  String? _start;

  TextEditingController? get _given => (widget as TextFormField).controller;

  TextEditingController get _controller =>
      _given ?? (_own ??= TextEditingController(text: _value ?? ''));

  @override
  String? get _initial =>
      _given == null ? widget.initialValue : _start ??= _given!.text;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(FormField<String> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = (oldWidget as TextFormField).controller;
    if (identical(old, _given)) {
      return;
    }
    (old ?? _own!).removeListener(_textChanged);
    if (old == null) {
      _own!.dispose();
      _own = null;
    }
    _controller.addListener(_textChanged);
    _start = _given?.text;
    _value = _controller.text;
  }

  @override
  void dispose() {
    _controller.removeListener(_textChanged);
    _own?.dispose();
    super.dispose();
  }

  void _textChanged() {
    final text = _controller.text;
    if (text != _value) {
      didChange(text);
    }
  }

  @override
  void reset() {
    super.reset();
    _controller.text = _value ?? '';
  }
}
