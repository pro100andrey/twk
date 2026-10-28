/// A wizard of steps, each refused or taken by its own validation:
/// [Stepper], its [Step]s and the [StepperController] that moves through
/// them.
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        Axis,
        CrossAxisAlignment,
        KeyEvent,
        MainAxisSize,
        Mod,
        TextSegmenter,
        TextWrap;

import '../animation/spinner.dart';
import '../binding/app_binding.dart';
import '../controls/button.dart';
import '../controls/pressable.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../foundation/controller_host.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/ignore_pointer.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/hit_row.dart';
import '../text/widgets.dart';

// Examples can assume:
// import 'dart:async';

/// Where a [Step] stands, as its header marks it: `○` [indexed], `●`
/// [editing], `✔` [complete], `✗` [error], and [disabled] muted; as
/// Flutter's.
enum StepState {
  /// Not reached yet: `○`, muted.
  indexed,

  /// The step being filled in: `●`, in the primary color.
  editing,

  /// Done: `✔`, in the theme's success.
  complete,

  /// Refused: `✗`, in the theme's error, its title too.
  error,

  /// Skipped: muted, neither clicked nor moved to.
  disabled,
}

/// A step of a [Stepper]: its [title], what it shows while it is the
/// current one ([content]), and what it takes to leave it forward
/// ([validate]).
///
/// One step of a wizard, refused while the name is empty:
///
/// ```dart
/// final name = TextEditingController();
/// final step = Step(
///   title: 'Project Info',
///   subtitle: 'The name of the package',
///   content: TextField(controller: name),
///   validate: () => name.text.isEmpty ? 'The project needs a name' : null,
/// );
/// ```
final class Step {
  /// A step called [title] that shows [content].
  const Step({
    required this.title,
    required this.content,
    this.subtitle,
    this.state,
    this.validate,
  });

  /// What its header calls it.
  final String title;

  /// What the stepper shows while it is the current step.
  final Widget content;

  /// A line more under its title, muted; none when null.
  final String? subtitle;

  /// Where it stands; null for where the stepper's position puts it: the
  /// steps before the current one [StepState.complete], the current one
  /// [StepState.editing], those after it [StepState.indexed]. A step the
  /// validation refused shows [StepState.error] over any of them but
  /// [StepState.disabled].
  final StepState? state;

  /// Says whether the step may be left forward: null to let it be left, a
  /// message to refuse it, which the stepper shows under its content. A
  /// future is waited for, the stepper ignoring its input meanwhile; null
  /// takes every step.
  final FutureOr<String?> Function()? validate;
}

/// Moves a [Stepper] through its steps: forward ([next], [goTo]) only
/// past the steps whose [Step.validate] takes them, back ([back]) at once.
///
/// The [current] step, from 0, and the refusal of the step that refused
/// last ([error]), are the controller's: a stepper built in place of
/// another with the same controller goes on where it was. It serves one
/// [Stepper] at a time, the last one built with it; while it serves none,
/// [next] and [goTo] return false and [back] does nothing. It notifies its
/// listeners when the current step, an error, or [validating] changes.
///
/// A wizard whose own key moves on:
///
/// ```dart
/// final controller = StepperController();
/// final wizard = KeyBindings(
///   {'ctrl+n': () => unawaited(controller.next())},
///   child: Stepper(
///     controller: controller,
///     steps: const [
///       Step(title: 'One', content: Text('first')),
///       Step(title: 'Two', content: Text('second')),
///     ],
///   ),
/// );
/// ```
final class StepperController extends ChangeNotifier {
  /// A controller at the step [initialStep], from 0.
  StepperController({int initialStep = 0})
    : _current = initialStep < 0 ? 0 : initialStep;

  final _hosts = ControllerHost<_StepperState>();

  int _current;
  final _errors = <int, String>{};
  var _validating = false;
  var _disposed = false;

  /// The step shown, from 0; the stepper shows the last one where it has
  /// fewer.
  int get current => _current;

  /// Why the current step was refused the last time it was validated;
  /// null where it was not, or was taken since.
  String? get error => _errors[_current];

  /// Whether a [Step.validate] is being waited for: [next], [back] and
  /// [goTo] do nothing meanwhile.
  bool get validating => _validating;

  /// Validates the current step and moves to the next one that is not
  /// [StepState.disabled]; returns whether it moved.
  ///
  /// A refusal stays on the step, marking it [StepState.error] with the
  /// message as [error]. On the last step it finishes instead: once the
  /// step is taken, and on a stepper that is not [Stepper.linear] every
  /// step before it too (it moves to the first refused), it calls
  /// [Stepper.onFinished] and returns true. False while [validating],
  /// and while it serves no stepper. An error [Step.validate] throws is
  /// thrown here.
  Future<bool> next() async {
    final host = _hosts.host;
    if (host == null || _validating) {
      return false;
    }
    final steps = host.widget.steps;
    if (steps.isEmpty) {
      return false;
    }
    final from = _clamped(steps.length);
    final to = _after(steps, from, 1);
    if (to >= 0) {
      if (!await _check(steps, from)) {
        return false;
      }
      _move(to);
      return true;
    }
    final taken = host.widget.linear
        ? await _check(steps, from)
        : await _checkUpTo(steps, steps.length);
    if (taken && _hosts.isHost(host) && host.mounted) {
      host.widget.onFinished?.call();
    }
    return taken;
  }

  /// Moves to the step before the current one that is not
  /// [StepState.disabled], validating nothing; does nothing on the first
  /// and while [validating].
  void back() {
    final host = _hosts.host;
    if (host == null || _validating) {
      return;
    }
    final steps = host.widget.steps;
    if (steps.isEmpty) {
      return;
    }
    final to = _after(steps, _clamped(steps.length), -1);
    if (to >= 0) {
      _move(to);
    }
  }

  /// Moves to [step], from 0; returns whether it is there.
  ///
  /// Back at once; forward on a [Stepper.linear] stepper only past every
  /// step on the way, validated in turn: it stops at the first refused,
  /// moving there. False for a step it does not have or that is
  /// [StepState.disabled], while [validating], and while it serves no
  /// stepper.
  Future<bool> goTo(int step) async {
    final host = _hosts.host;
    if (host == null || _validating) {
      return false;
    }
    final steps = host.widget.steps;
    if (step < 0 ||
        step >= steps.length ||
        steps[step].state == StepState.disabled) {
      return false;
    }
    final from = _clamped(steps.length);
    if (step > from && host.widget.linear) {
      if (!await _checkUpTo(steps, step, from: from)) {
        return false;
      }
    }
    _move(step);
    return true;
  }

  /// Validates the steps from [from] up to [end], in turn; at the first
  /// refused, moves there and returns false.
  Future<bool> _checkUpTo(List<Step> steps, int end, {int from = 0}) async {
    for (var i = from; i < end; i++) {
      if (!await _check(steps, i)) {
        _move(i);
        return false;
      }
    }
    return true;
  }

  /// Validates the step [i] of [steps], keeping its refusal; returns
  /// whether it was taken.
  Future<bool> _check(List<Step> steps, int i) async {
    final step = steps[i];
    final validate = step.validate;
    if (validate == null || step.state == StepState.disabled) {
      _refuse(i, null);
      return true;
    }
    final result = validate();
    String? message;
    if (result is Future<String?>) {
      _validating = true;
      notifyListeners();
      try {
        message = await result;
      } catch (_) {
        _validating = false;
        if (!_disposed) {
          notifyListeners();
        }
        rethrow;
      }
      _validating = false;
      if (_disposed) {
        return false;
      }
      _refuse(i, message, notify: true);
    } else {
      message = result;
      _refuse(i, message);
    }
    return message == null;
  }

  /// Keeps [message] as the refusal of the step [i], none when null;
  /// notifies when that changes, or with [notify].
  void _refuse(int i, String? message, {bool notify = false}) {
    final before = _errors[i];
    if (message == null) {
      _errors.remove(i);
    } else {
      _errors[i] = message;
    }
    if (notify || before != message) {
      notifyListeners();
    }
  }

  void _move(int to) {
    if (to != _current && !_disposed) {
      _current = to;
      notifyListeners();
    }
  }

  int _clamped(int count) => _current < count ? _current : count - 1;

  /// The step [dir] steps on from [from] that is not disabled; -1 for
  /// none.
  static int _after(List<Step> steps, int from, int dir) {
    for (var i = from + dir; i >= 0 && i < steps.length; i += dir) {
      if (steps[i].state != StepState.disabled) {
        return i;
      }
    }
    return -1;
  }

  @override
  void dispose() {
    _disposed = true;
    _hosts.dispose();
    super.dispose();
  }
}

/// A wizard of [steps], one shown at a time under the headers of all of
/// them, with Back and Next under it: installers, `init`-style setups,
/// deploy flows.
///
/// ```text
/// ✔ 1. Project Info ── ● 2. Dependencies ── ○ 3. Confirmation
/// Select packages to install: …
///  Back                                    Next
/// ```
///
/// Each header is the [Step.title] after its number and its mark, as its
/// [StepState] says: `✔` the steps done, `●` the current one, its title in
/// bold, `○` those after it, `✗` and the theme's error a step its
/// [Step.validate] refused, muted one [StepState.disabled]. The header
/// row of a [direction] of [Axis.horizontal] that does not fit gives way
/// to the current step alone, `Step 2 of 3 · Dependencies`; the current
/// step's [Step.subtitle] is under it, muted. With [Axis.vertical], the
/// headers are in a column, each subtitle under its own, and the current
/// step's content and controls under its header, two columns in.
///
/// Next, or PageDown, which comes up from the content, so a field keeps
/// Enter, validates the step and moves on, or shows the refusal under the
/// content in the theme's error; on the last step it is [finishLabel] and
/// finishes: [onFinished] once the step is taken
/// ([StepperController.next]). Back, or PageUp, goes to the step before.
/// PageDown and PageUp are hinted. While a validation is waited for, a
/// [Spinner] is in the Next button, and the stepper ignores the keys,
/// Ctrl+C aside, and the mouse: the focus, where it was in the stepper,
/// waits on it, and comes back where it was if the step is refused. A
/// click on a header goes to that step: on a [linear] stepper only to
/// one before the current one, on one that is not to any but a disabled
/// one, validating nothing. Once the step changes, a focus that was in the
/// stepper, or nowhere, goes to the first control of the new step's
/// content that Tab stops at, Next where it has none; [onStepChanged]
/// gets the step, from 0. Only the current step's content is built, so
/// what it holds is held by the app (a `TextEditingController`).
///
/// The [controller], one of its own when null, holds the step shown and
/// moves it from the app; [showControls] false leaves Back and Next out
/// for the app's own, the keys still there.
///
/// A screen reader reads the headers as a [SemanticsRole.list] of
/// [SemanticsRole.listItem]s, `2. Dependencies`, the current one
/// `selected`, a done one hinted `complete` and a refused one with its
/// message; then the content, and the buttons.
///
/// A project's setup, the name checked at once and the packages by a
/// server:
///
/// ```dart
/// final name = TextEditingController();
/// final wizard = Stepper(
///   steps: [
///     Step(
///       title: 'Project Info',
///       content: TextField(controller: name),
///       validate: () => name.text.isEmpty ? 'The project needs a name' : null,
///     ),
///     Step(
///       title: 'Dependencies',
///       content: const Text('Select packages to install: …'),
///       validate: () async {
///         await Future<void>.delayed(const Duration(seconds: 1));
///         return null;
///       },
///     ),
///     const Step(title: 'Confirmation', content: Text('Create it?')),
///   ],
///   onFinished: () => print('created'),
/// );
/// ```
///
/// See also:
///
///  * `TabBar`, views side by side that need no order.
///  * `Form`, the fields of one step validated together.
final class Stepper extends StatefulWidget {
  /// A wizard of [steps], the first shown unless [controller] says.
  const Stepper({
    required this.steps,
    super.key,
    this.controller,
    this.direction = Axis.horizontal,
    this.linear = true,
    this.onFinished,
    this.onStepChanged,
    this.backLabel = 'Back',
    this.nextLabel = 'Next',
    this.finishLabel = 'Finish',
    this.showControls = true,
  });

  /// The steps, in order.
  final List<Step> steps;

  /// Holds the step shown and moves it; one of the stepper's own when
  /// null.
  final StepperController? controller;

  /// [Axis.horizontal] for the headers on a row over the content,
  /// [Axis.vertical] for a column of them with the content under the
  /// current one.
  final Axis direction;

  /// Whether a step is reached only past those before it: a click goes
  /// back only, and [StepperController.goTo] validates the way. False
  /// lets any header be clicked, and validates every step on Finish.
  final bool linear;

  /// Called once the last step is taken by Next.
  final VoidCallback? onFinished;

  /// Called with the step the stepper moved to, from 0.
  final void Function(int step)? onStepChanged;

  /// The text of the button that goes back.
  final String backLabel;

  /// The text of the button that goes on.
  final String nextLabel;

  /// The text of the button that goes on from the last step.
  final String finishLabel;

  /// Whether Back and Next are shown.
  final bool showControls;

  @override
  State<Stepper> createState() => _StepperState();
}

/// Where the focus goes after a frame: into the content, back where it
/// was before the validation, or into the content when nothing has it.
enum _Refocus { content, resume, initial }

final class _StepperState extends State<Stepper> {
  StepperController? _own;
  late StepperController _controller;

  /// The stepper's node: the focus waits on it while a validation is.
  late final _root = FocusNode(
    debugLabel: 'Stepper',
    onKeyEvent: _swallow,
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// Above the content: the first stop after it is the content's.
  final _content = FocusNode(
    debugLabel: 'Stepper content',
    canRequestFocus: false,
    skipTraversal: true,
  );

  final _next = FocusNode(debugLabel: 'Stepper next');
  final _back = FocusNode(debugLabel: 'Stepper back');

  /// The step shown at the last change.
  var _shown = 0;
  var _wasValidating = false;

  /// Where the focus was before the validation took it.
  FocusNode? _resume;
  _Refocus? _refocus;
  var _asked = false;

  /// Counts the changes the focus follows: each builds an [_Arrival].
  var _arrivals = 0;

  /// Where the header of each step is along the row as last laid out.
  final _headers = HitRow();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? (_own = StepperController());
    _controller._hosts.attach(this);
    _controller.addListener(_changed);
    _shown = _step;
    _refocus = _Refocus.initial;
  }

  @override
  void didUpdateWidget(Stepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _controller
        ..removeListener(_changed)
        .._hosts.detach(this);
      _own?.dispose();
      _own = null;
      _controller = widget.controller ?? (_own = StepperController());
      _controller._hosts.attach(this);
      _controller.addListener(_changed);
    }
    _shown = _step;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      .._hosts.detach(this);
    _own?.dispose();
    _root.dispose();
    _content.dispose();
    _next.dispose();
    _back.dispose();
    super.dispose();
  }

  /// The step shown: the controller's, within the steps; -1 for none.
  int get _step {
    final n = widget.steps.length;
    final current = _controller.current;
    return n == 0 ? -1 : (current < n ? current : n - 1);
  }

  /// Whether the focus is in the stepper, or nowhere.
  bool get _focusHere {
    final manager = _root.manager;
    return _root.hasFocus || manager == null || manager.primaryFocus == null;
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    final validating = _controller.validating;
    if (validating != _wasValidating) {
      _wasValidating = validating;
      if (validating && _focusHere) {
        _resume = _root.manager?.primaryFocus;
        _root
          ..canRequestFocus = true
          ..requestFocus();
      } else if (!validating && _root.canRequestFocus) {
        _refocus = _Refocus.resume;
        _arrivals++;
      }
    }
    final step = _step;
    if (step != _shown) {
      _shown = step;
      if (_focusHere) {
        _refocus = _Refocus.content;
        _arrivals++;
      }
      widget.onStepChanged?.call(step);
    }
    setState(() {});
  }

  /// Every key but Ctrl+C, while a validation is waited for.
  KeyEventResult _swallow(FocusNode node, KeyEvent event) =>
      _controller.validating &&
          !(event.char == 'c' && event.modifiers == Mod.ctrl)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;

  /// After the first frame, which settled the autofocus: into the
  /// content where nothing has the focus.
  void _focusFirst(Duration _) {
    if (!mounted || _refocus != _Refocus.initial) {
      return;
    }
    _refocus = null;
    final manager = _root.manager;
    if (manager != null && manager.needsFlush) {
      manager.flush();
    }
    if (manager?.primaryFocus == null) {
      _enterContent();
    }
  }

  /// Once the build of a change has mounted the step and the controls
  /// ([_Arrival]): the focus where [_refocus] says, in the same frame.
  void _arrive() {
    final refocus = _refocus;
    if (refocus != _Refocus.content && refocus != _Refocus.resume) {
      return;
    }
    _refocus = null;
    final resume = _resume;
    _resume = null;
    final manager = _root.manager;
    if (refocus == _Refocus.resume &&
        resume != null &&
        resume.context != null &&
        resume.canRequestFocus) {
      resume.requestFocus();
    } else if (_root.hasFocus || manager?.primaryFocus == null) {
      _enterContent();
    }
    _root.canRequestFocus = false;
  }

  /// Focuses the first stop of the content, else Next.
  void _enterContent() {
    _content.nextFocus();
    if (!_content.hasFocus && _next.context != null) {
      _next.requestFocus();
    }
  }

  void _goNext() => unawaited(_controller.next());

  void _click(int step) => unawaited(_controller.goTo(step));

  /// The state of the step [i], [current] being shown.
  StepState _stateOf(int i, int current) {
    final given = widget.steps[i].state;
    if (given == StepState.disabled) {
      return given!;
    }
    if (_controller._errors.containsKey(i)) {
      return StepState.error;
    }
    return given ??
        (i < current
            ? StepState.complete
            : i == current
            ? StepState.editing
            : StepState.indexed);
  }

  /// Whether a click on the header of [i] goes there.
  bool _clickable(int i, int current) =>
      i != current &&
      widget.steps[i].state != StepState.disabled &&
      (!widget.linear || i < current);

  @override
  Widget build(BuildContext context) {
    if (_refocus == _Refocus.initial && !_asked) {
      _asked = true;
      AppBinding.maybeOf(context)?.scheduleFrameCallback(_focusFirst);
    }
    final steps = widget.steps;
    final current = _step;
    final validating = _controller.validating;
    final theme = Theme.of(context);
    final last =
        current >= 0 && StepperController._after(steps, current, 1) < 0;
    final canBack =
        current >= 0 && StepperController._after(steps, current, -1) >= 0;
    final Widget body;
    if (current < 0) {
      body = const SizedBox();
    } else if (widget.direction == Axis.vertical) {
      body = _vertical(theme, current, last: last, canBack: canBack);
    } else {
      body = _horizontal(theme, current, last: last, canBack: canBack);
    }
    return Focus(
      focusNode: _root,
      child: KeyBindings(
        {
          if (current >= 0) 'pagedown': _goNext,
          if (canBack) 'pageup': _controller.back,
        },
        hints: {
          if (current >= 0) 'pagedown': last ? 'finish' : 'next step',
          if (canBack) 'pageup': 'previous step',
        },
        child: AbsorbPointer(
          absorbing: validating,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(child: body),
              _Arrival(key: ValueKey(_arrivals), onArrive: _arrive),
            ],
          ),
        ),
      ),
    );
  }

  Widget _horizontal(
    ThemeData theme,
    int current, {
    required bool last,
    required bool canBack,
  }) {
    final subtitle = widget.steps[current].subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          role: SemanticsRole.list,
          nodes: [
            for (var i = 0; i < widget.steps.length; i++)
              _semantics(i, current),
          ],
          child: GestureDetector(
            onTap: (event) {
              final step = _headers.at(event.x);
              // the step shown now: a click may come before the build
              if (step >= 0 && _clickable(step, _step)) {
                _click(step);
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) => _row(
                theme,
                segmenterOf(context),
                current,
                constraints.maxW,
              ),
            ),
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: theme.text.merge(theme.muted),
            wrap: TextWrap.none,
            maxLines: 1,
          ),
        ..._body(theme, current, last: last, canBack: canBack),
      ],
    );
  }

  Widget _vertical(
    ThemeData theme,
    int current, {
    required bool last,
    required bool canBack,
  }) {
    final steps = widget.steps;
    // Keyed, as the body moves under the header of the new step: its
    // element, and the nodes of the content, Back and Next that it
    // attaches, go with it. Unkeyed, a new element would attach them while
    // the old one still held them, and the old one, removed at the end of
    // the frame, would take them out of the focus tree, the focus moved
    // off the new step's first stop to the next one.
    return Semantics(
      role: SemanticsRole.list,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Semantics(
              key: ValueKey(('header', i)),
              nodes: [_semantics(i, current)],
              child: GestureDetector(
                onTap: (_) {
                  if (_clickable(i, _step)) {
                    _click(i);
                  }
                },
                child: Text.rich(
                  _header(theme, i, current),
                  style: theme.text,
                  wrap: TextWrap.none,
                  maxLines: 1,
                ),
              ),
            ),
            if (steps[i].subtitle case final subtitle?)
              Padding(
                key: ValueKey(('subtitle', i)),
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  subtitle,
                  style: theme.text.merge(theme.muted),
                  wrap: TextWrap.none,
                  maxLines: 1,
                ),
              ),
            if (i == current)
              Flexible(
                key: const ValueKey('body'),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _body(
                      theme,
                      current,
                      last: last,
                      canBack: canBack,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// The content of the step [current], its refusal and the controls.
  List<Widget> _body(
    ThemeData theme,
    int current, {
    required bool last,
    required bool canBack,
  }) {
    final error = _controller._errors[current];
    return [
      Flexible(
        child: Focus(
          focusNode: _content,
          child: _Keyed(
            key: ValueKey(current),
            child: widget.steps[current].content,
          ),
        ),
      ),
      if (error != null) Text(error, style: theme.text.merge(theme.error)),
      if (widget.showControls)
        Row(
          children: [
            Button(
              widget.backLabel,
              focusNode: _back,
              onPressed: canBack ? _controller.back : null,
            ),
            const Spacer(),
            if (_controller.validating)
              _busy(theme, last ? widget.finishLabel : widget.nextLabel)
            else
              Button(
                last ? widget.finishLabel : widget.nextLabel,
                focusNode: _next,
                onPressed: _goNext,
              ),
          ],
        ),
    ];
  }

  /// The Next button while a validation is waited for: a [Spinner] in its
  /// chip, before [label].
  Widget _busy(ThemeData theme, String label) {
    final chip = theme.text.merge(buttonStyle(theme));
    return Semantics(
      role: SemanticsRole.button,
      label: label,
      state: const SemanticsState(disabled: true),
      hint: 'validating',
      child: Box(
        style: Style(bg: chip.bg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(' ', style: chip),
            Spinner(style: Style(fg: chip.fg)),
            Text(' $label ', style: chip, wrap: TextWrap.none, maxLines: 1),
          ],
        ),
      ),
    );
  }

  SemanticsNode _semantics(int i, int current) {
    final step = widget.steps[i];
    final state = _stateOf(i, current);
    return SemanticsNode(
      role: SemanticsRole.listItem,
      label: '${i + 1}. ${step.title}',
      state: SemanticsState(
        selected: i == current,
        disabled: state == StepState.disabled,
      ),
      hint: switch (state) {
        StepState.complete => 'complete',
        StepState.error => _controller._errors[i] ?? 'error',
        _ => null,
      },
    );
  }

  /// The spans of the header of the step [i]: its mark, its number and its
  /// title.
  List<Span> _header(ThemeData theme, int i, int current) {
    final state = _stateOf(i, current);
    final text = theme.text;
    final (mark, markStyled) = switch (state) {
      StepState.complete => ('✔', text.merge(theme.success)),
      StepState.editing => ('●', text.merge(markStyle(theme))),
      StepState.error => ('✗', text.merge(theme.error)),
      StepState.indexed || StepState.disabled => ('○', text.merge(theme.muted)),
    };
    return [
      Span(mark, markStyled),
      Span(' ${i + 1}. ${widget.steps[i].title}', _titleStyle(theme, i, state)),
    ];
  }

  Style _titleStyle(ThemeData theme, int i, StepState state) {
    final text = theme.text;
    return switch (state) {
      StepState.error => text.merge(theme.error),
      StepState.disabled => text.merge(theme.muted),
      _ when i == _step => text.merge(const Style(attrs: Attr.bold)),
      _ => text,
    };
  }

  /// The headers on one row, [width] columns at most as [segmenter]
  /// measures them, each a target of [_headers]; the current step alone
  /// where they do not fit.
  Widget _row(
    ThemeData theme,
    TextSegmenter segmenter,
    int current,
    int width,
  ) {
    const sep = ' ── ';
    final steps = widget.steps;
    final spans = <HitSpan>[];
    var x = 0;
    for (var i = 0; i < steps.length; i++) {
      if (i > 0) {
        spans.add((span: Span(sep, theme.text.merge(theme.muted)), target: -1));
        x += segmenter.width(sep);
      }
      for (final part in _header(theme, i, current)) {
        spans.add((span: part, target: i));
        x += segmenter.width(part.text);
      }
    }
    if (x > width) {
      final state = _stateOf(current, current);
      return _headers.row(
        [
          (
            span: Span(
              'Step ${current + 1} of ${steps.length} · ',
              theme.text.merge(theme.muted),
            ),
            target: -1,
          ),
          (
            span: Span(
              steps[current].title,
              _titleStyle(theme, current, state),
            ),
            target: -1,
          ),
        ],
        segmenter,
        style: theme.text,
      );
    }
    return _headers.row(spans, segmenter, style: theme.text);
  }
}

/// [child] under a key of its own: the content of one step is not
/// another's, its state not kept from one to the next.
final class _Keyed extends StatelessWidget {
  const _Keyed({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Calls [onArrive] as it is mounted: after what is before it in the
/// tree, built in the same pass. Nothing to show.
final class _Arrival extends StatefulWidget {
  const _Arrival({required this.onArrive, super.key});

  final VoidCallback onArrive;

  @override
  State<_Arrival> createState() => _ArrivalState();
}

final class _ArrivalState extends State<_Arrival> {
  @override
  void initState() {
    super.initState();
    widget.onArrive();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
