// The Controls group of the gallery.
import 'dart:async';

import 'package:twk/twk.dart';

import '../page.dart';
import 'common.dart';

/// The pages of the Controls group that draw.
final List<GalleryPage> controlsPages = [
  GalleryPage(
    group: 'Controls',
    title: 'Button',
    options: const [
      ColorOption('color', 'style', values: pageColors, initial: 'primary'),
      ChoiceOption('look', 'look', values: ['chip', 'outlined', 'filled']),
      SwitchOption('tall', 'tall'),
    ],
    build: (context, o) => _Buttons(
      color: o.color('color'),
      look: o.choice('look'),
      tall: o.flag('tall'),
    ),
    code: (o) {
      final c = o.color('color');
      final styled = c != 'primary';
      final look = o.choice<String>('look');
      final chip = look == 'chip';
      final button = chip ? 'Button' : 'Button.$look';
      final args = [
        if (styled && chip) ...['style: style', 'focusedStyle: focused'],
        if (styled && !chip) 'style: theme.$c',
        if (!chip && o.flag('tall')) 'tall: true',
      ];
      return [
        'var _saved = 0;',
        'var _sent = 0;',
        '',
        '// Button, as each control here, stands on',
        '// Pressable: a node that Tab stops at unless it',
        '// is disabled, the keys it binds while it has',
        '// the focus (Enter, Space), a press that focuses',
        '// it and a click.',
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        if (styled && chip) ...[
          '  final style = theme.$c.merge(const .new(attrs: Attr.bold));',
          '  final focused = style.merge(const .new(attrs: Attr.reverse));',
        ],
        '  return Column(',
        '    mainAxisSize: .min,',
        '    crossAxisAlignment: .start,',
        '    gap: 1,',
        '    children: [',
        '      Row(',
        '        mainAxisSize: .min,',
        '        gap: 2,',
        '        children: [',
        ...call(10, button, [
          "'Save'",
          ...args,
          'onPressed: () => setState(() => _saved++)',
        ], ','),
        ...call(10, button, [
          "'Send'",
          ...args,
          'onPressed: () => setState(() => _sent++)',
        ], ','),
        ...call(10, '${styled ? '' : 'const '}$button', [
          "'Disabled'",
          ...args,
          'onPressed: null',
        ], ','),
        '        ],',
        '      ),',
        '      Text.rich([',
        "        Span('saved: ', theme.muted),",
        r"        Span('$_saved'),",
        "        Span('  sent: ', theme.muted),",
        r"        Span('$_sent'),",
        '      ]),',
        '    ],',
        '  );',
        '}',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Controls',
    title: 'Pressable',
    options: const [
      ColorOption('color', 'style', values: pageColors, initial: 'primary'),
    ],
    build: (context, o) => _Stars(color: o.color('color')),
    code: (o) => [
      "final _starred = {'twk'};",
      '',
      'void _toggle(String name) => setState(() {',
      '  if (!_starred.remove(name)) {',
      '    _starred.add(name);',
      '  }',
      '});',
      '',
      '// A row that stars [name], made of a Pressable: Tab',
      '// stops at it unless it is disabled, its bindings',
      '// are the keys it takes while it has the focus, a',
      '// press focuses it and a tap calls onTap; it',
      '// builds its look by whether it has the focus.',
      'Widget _star(String name, {bool enabled = true}) => Pressable(',
      '  enabled: enabled,',
      "  bindings: {'space': () => _toggle(name)},",
      "  hints: const {'space': 'star'},",
      '  onTap: enabled ? (_) => _toggle(name) : null,',
      '  builder: (context, focused) {',
      '    final theme = Theme.of(context);',
      '    final on = _starred.contains(name);',
      '    return Text.rich(',
      '      [',
      '        Span(',
      "          on ? '★' : '☆',",
      '          on ? ${_markOf(o)} : theme.muted,',
      '        ),',
      r"        Span(' $name'),",
      '      ],',
      '      style: !enabled',
      '          ? theme.muted',
      '          : focused',
      '          ? theme.selection',
      '          : const .new(),',
      '    );',
      '  },',
      ');',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      Column(',
      '        mainAxisSize: .min,',
      '        crossAxisAlignment: .start,',
      '        children: [',
      "          _star('twk'),",
      "          _star('gallery'),",
      "          _star('archive', enabled: false),",
      '        ],',
      '      ),',
      '      Text.rich([',
      "        Span('starred: ', theme.muted),",
      '        if (_starred.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      "          Span(_starred.join(', ')),",
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Controls',
    title: 'Checkbox, Switch',
    options: const [
      ChoiceOption('switch', 'switch', values: ['pill', 'brackets']),
    ],
    build: (context, o) => _Toggles(pill: o.choice<String>('switch') == 'pill'),
    code: (o) => [
      'var _wrap = true;',
      'var _dark = false;',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Checkbox(',
      '      value: _wrap,',
      "      label: 'wrap lines',",
      '      onChanged: (value) => setState(() => _wrap = value),',
      '    ),',
      '    Switch(',
      '      value: _dark,',
      "      label: 'dark mode',",
      if (o.choice<String>('switch') == 'brackets') '      pill: false,',
      '      onChanged: (value) => setState(() => _dark = value),',
      '    ),',
      "    const Checkbox(value: true, label: 'disabled', onChanged: null),",
      '  ],',
      ');',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Controls',
    title: 'RadioGroup',
    options: const [
      ChoiceOption(
        'direction',
        'direction',
        values: ['vertical', 'horizontal'],
      ),
    ],
    build: (context, o) =>
        _Radios(direction: Axis.values.byName(o.choice('direction'))),
    code: (o) => [
      'const _fruit = [',
      "  Choice('apple', 'apple'),",
      "  Choice('banana', 'banana'),",
      "  Choice('cherry', 'cherry'),",
      "  Choice('durian', 'durian', enabled: false),",
      '];',
      '',
      'String? _chosen;',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      RadioGroup<String>(',
      '        choices: _fruit,',
      '        value: _chosen,',
      '        direction: .${o.label('direction')},',
      '        onChanged: (value) => setState(() => _chosen = value),',
      '      ),',
      '      Text.rich([',
      "        Span('chosen: ', theme.muted),",
      '        if (_chosen case final chosen?)',
      '          Span(chosen)',
      '        else',
      "          Span('nothing', theme.muted),",
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n'),
  ),
  _segmented,
  GalleryPage(
    group: 'Controls',
    title: 'SelectionList',
    options: const [
      SwitchOption('multiple', 'multiple'),
      SwitchOption('bar', 'cursor bar', initial: true),
    ],
    build: (context, o) =>
        _Planets(multiple: o.flag('multiple'), bar: o.flag('bar')),
    code: (o) => [
      'static const _planets = [',
      for (final p in _planets) "  '$p',",
      '];',
      '',
      if (o.flag('multiple')) ...[
        'late final _selection = SelectionController<String>(',
        '  multiple: true,',
        "  selected: ['Earth'],",
        ')..addListener(() => setState(() {}));',
      ] else ...[
        _selectionLine,
        '  ..addListener(() => setState(() {}));',
      ],
      '',
      '@override',
      'void dispose() {',
      '  _selection.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  final selected = _selection.selected;',
      '  return SizedBox(',
      '    width: 29,',
      '    height: 8,',
      '    child: Row(',
      '      crossAxisAlignment: .start,',
      '      gap: 2,',
      '      children: [',
      '        SizedBox(',
      '          width: 18,',
      '          // the border primary while the list has the focus',
      '          child: FocusBuilder(',
      '            builder: (context, hasFocus, list) => Box(',
      '              border: .all(',
      '                type: .rounded,',
      '                style: hasFocus ? theme.primary : theme.border,',
      '              ),',
      '              child: list,',
      '            ),',
      '            child: SelectionList<String>(',
      '              itemCount: _planets.length,',
      '              keyOf: (i) => _planets[i],',
      '              itemBuilder: (context, i) => Text(_planets[i]),',
      "              itemEnabled: (i) => _planets[i] != 'Venus',",
      if (!o.flag('bar')) '              bar: false,',
      '              controller: _selection,',
      '            ),',
      '          ),',
      '        ),',
      '        Expanded(',
      '          child: Text.rich([',
      r"            Span('selected\n', theme.muted),",
      '            if (selected.isEmpty)',
      "              Span('nothing', theme.muted)",
      '            else',
      r"              Span(selected.join('\n')),",
      '          ]),',
      '        ),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Controls',
    title: 'Select, MultiSelect',
    options: [
      const SwitchOption('inline', 'inline'),
      const ChoiceOption('rows', 'rows', values: [4, 8], initial: 4),
      // an inline list shows no popup
      popupLookOption(disabled: (o) => o.flag('inline')),
    ],
    build: (context, o) => _Selects(
      inline: o.flag('inline'),
      rows: o.choice('rows'),
      popupLook: popupLookOf(o),
    ),
    code: (o) {
      final extra = [
        if (o.flag('inline')) 'inline: true,',
        'rows: ${o.label('rows')},',
        if (!o.flag('inline')) ...popupLookArg(o, ''),
      ];
      return [
        'const _fruit = [',
        for (final c in _fruits) _choiceLine(c),
        '];',
        '',
        'final _popup = PopupController();',
        'String? _one;',
        'var _some = <String>{};',
        '',
        '@override',
        'void dispose() {',
        '  _popup.dispose();',
        '  super.dispose();',
        '}',
        '',
        '// Open, each shows its choices in an OptionList,',
        '// as Autocomplete and CommandPalette do: the',
        '// letters typed lit, the highlighted one on the',
        '// selection.',
        '@override',
        'Widget build(BuildContext context) => Column(',
        '  mainAxisSize: .min,',
        '  crossAxisAlignment: .start,',
        '  gap: 1,',
        '  children: [',
        '    Row(',
        '      mainAxisSize: .min,',
        '      crossAxisAlignment: .start,',
        '      gap: 4,',
        '      children: [',
        '        Select<String>(',
        '          choices: _fruit,',
        '          value: _one,',
        "          hint: 'a fruit',",
        for (final l in extra) '          $l',
        '          controller: _popup,',
        '          onChanged: (value) => setState(() => _one = value),',
        '        ),',
        '        MultiSelect<String>(',
        '          choices: _fruit,',
        '          values: _some,',
        "          hint: 'some fruit',",
        for (final l in extra) '          $l',
        '          onChanged: (values) => setState(() => _some = values),',
        '        ),',
        '      ],',
        '    ),',
        "    // opens the fruit's list, the focus in its field",
        "    Button('Choose a fruit', onPressed: _popup.open),",
        '  ],',
        ');',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Controls',
    title: 'ConfirmInput',
    options: const [
      ChoiceOption(
        'default',
        'default',
        values: [true, false],
        labels: ['yes', 'no'],
      ),
      ChoiceOption('labels', 'answers', values: ['Yes, No', 'Delete, Keep']),
    ],
    build: (context, o) => _Confirm(
      defaultValue: o.choice('default'),
      answers: _answers[o.choice<String>('labels')]!,
    ),
    code: (o) {
      final (yes, no) = _answers[o.choice<String>('labels')]!;
      return [
        'bool? _answer;',
        '',
        '@override',
        'Widget build(BuildContext context) => Column(',
        '  mainAxisSize: .min,',
        '  crossAxisAlignment: .start,',
        '  gap: 1,',
        '  children: [',
        '    ConfirmInput(',
        "      'Delete 3 files?',",
        '      // it reads defaultValue once: another is a new input',
        '      key: const ValueKey(${o['default']}),',
        '      defaultValue: ${o['default']},',
        if (yes != 'Yes') ...["      yes: '$yes',", "      no: '$no',"],
        '      onConfirmed: (yes) => setState(() => _answer = yes),',
        '    ),',
        '    Text.rich([',
        "      Span('answer: ', Theme.of(context).muted),",
        '      switch (_answer) {',
        "        null => Span('nothing', Theme.of(context).muted),",
        "        true => const Span('yes'),",
        "        false => const Span('no'),",
        '      },',
        '    ]),',
        '  ],',
        ');',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Controls',
    title: 'Slider',
    options: [
      const ChoiceOption(
        'divisions',
        'divisions',
        values: [null, 10, 4],
        labels: ['none', '10', '4'],
      ),
      SliderOption(
        'width',
        'width',
        min: 10,
        max: 40,
        initial: 30,
        format: (v) => '$v cells',
      ),
    ],
    build: (context, o) => _Volume(
      width: o.number('width').toInt(),
      divisions: o.choice('divisions'),
    ),
    code: (o) => [
      'var _volume = 0.5;',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    SizedBox(',
      '      width: ${o.label('width')},',
      '      child: Slider(',
      '        value: _volume,',
      "        semanticsLabel: 'Volume',",
      if (o['divisions'] != null) '        divisions: ${o.label('divisions')},',
      '        onChanged: (value) => setState(() => _volume = value),',
      '      ),',
      '    ),',
      '    Text.rich([',
      "      Span('volume: ', Theme.of(context).muted),",
      r"      Span('${(_volume * 100).round()}%'),",
      '    ]),',
      '  ],',
      ');',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Controls',
    title: 'NumberInput',
    build: (context, o) => const _Numbers(),
    code: (o) => [
      'var _copies = 1.0;',
      'var _price = 9.5;',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    Row(',
      '      mainAxisSize: .min,',
      '      children: [',
      "        const SizedBox(width: 16, child: Text('copies, 1 to 99')),",
      '        SizedBox(',
      '          width: 10,',
      '          child: NumberInput(',
      '            value: _copies,',
      '            min: 1,',
      '            max: 99,',
      '            onChanged: (value) => setState(() => _copies = value),',
      '          ),',
      '        ),',
      '      ],',
      '    ),',
      '    Row(',
      '      mainAxisSize: .min,',
      '      children: [',
      "        const SizedBox(width: 16, child: Text('price, by 0.25')),",
      '        SizedBox(',
      '          width: 10,',
      '          child: NumberInput(',
      '            value: _price,',
      '            min: 0,',
      '            step: 0.25,',
      '            decimals: 2,',
      '            onChanged: (value) => setState(() => _price = value),',
      '          ),',
      '        ),',
      '      ],',
      '    ),',
      '    Text(',
      r"      '${_copies.round()} × ${_price.toStringAsFixed(2)} = '",
      r"      '${(_copies * _price).toStringAsFixed(2)}',",
      '    ),',
      '  ],',
      ');',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Controls',
    title: 'DatePicker',
    // Tab stays in the open calendar's FocusScope
    modalTab: false,
    options: [
      const SwitchOption('time', 'time of day'),
      const ChoiceOption(
        'week',
        'weeks start',
        values: [1, 7],
        labels: ['monday', 'sunday'],
      ),
      popupLookOption(),
    ],
    build: (context, o) => _Date(
      time: o.flag('time'),
      firstWeekday: o.choice('week'),
      popupLook: popupLookOf(o),
    ),
    code: (o) {
      final time = o.flag('time');
      return [
        'final _calendar = PopupController();',
        'DateTime? _date;',
        '',
        'static const _days = [',
        for (final d in _days) "  '$d',",
        '];',
        '',
        '@override',
        'void dispose() {',
        '  _calendar.dispose();',
        '  super.dispose();',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) => Column(',
        '  mainAxisSize: .min,',
        '  crossAxisAlignment: .start,',
        '  gap: 1,',
        '  children: [',
        '    Row(',
        '      mainAxisSize: .min,',
        '      gap: 2,',
        '      children: [',
        '        SizedBox(',
        '          width: 22,',
        '          child: DatePicker(',
        '            value: _date,',
        if (time) '            showTime: true,',
        '            firstDate: DateTime(2026),',
        '            lastDate: DateTime(2026, 12, 31),',
        '            today: DateTime(2026, 10, 19),',
        if (o['week'] == 7) '            firstWeekday: DateTime.sunday,',
        ...popupLookArg(o, '            '),
        '            controller: _calendar,',
        '            onChanged: (date) => setState(() => _date = date),',
        '          ),',
        '        ),',
        '        // opens the calendar, the focus in it',
        "        Button('Calendar', onPressed: _calendar.open),",
        '      ],',
        '    ),',
        '    Text.rich([',
        "      Span('picked: ', Theme.of(context).muted),",
        '      switch (_date) {',
        "        null => Span('nothing', Theme.of(context).muted),",
        '        final date => Span(',
        r"          '${_days[date.weekday - 1]}, ${date.day} '",
        if (time)
          r"          '${Calendar.englishMonthNames[date.month - 1]}, '"
        else
          r"          '${Calendar.englishMonthNames[date.month - 1]}',",
        if (time) ...[
          r"          '${'${date.hour}'.padLeft(2, '0')}:'",
          r"          '${'${date.minute}'.padLeft(2, '0')}',",
        ],
        '        ),',
        '      },',
        '    ]),',
        '  ],',
        ');',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Controls',
    title: 'FilePicker',
    options: const [
      ChoiceOption(
        'mode',
        'mode',
        values: ['open', 'several', 'save', 'directory'],
        labels: ['open', 'open several', 'save', 'directory'],
      ),
      SwitchOption('hidden', 'show hidden'),
    ],
    // a picker for each mode and showHidden, which it reads once, and its
    // controller with it
    build: (context, o) => _Files(
      key: ValueKey((o.choice<String>('mode'), o.flag('hidden'))),
      mode: o.choice('mode'),
      showHidden: o.flag('hidden'),
    ),
    code: (o) {
      final (mode, multiple) = _modes[o.choice<String>('mode')]!;
      final args = [
        if (mode != FilePickerMode.open) 'mode: .${mode.name}',
        if (multiple) 'multiple: true',
        if (o.flag('hidden')) 'showHidden: true',
      ];
      final key = "key: const ValueKey('${o.choice<String>('mode')}')";
      return [
        'final _files = FilePickerController();',
        'String? _picked;',
        '',
        '@override',
        'void dispose() {',
        '  _files.dispose();',
        '  super.dispose();',
        '}',
        '',
        'static const _filters = [',
        "  FileFilter('Dart', ['dart']),",
        "  FileFilter('All files'),",
        '];',
        '',
        'void _show(List<String>? paths) {',
        '  if (mounted && paths != null) {',
        "    setState(() => _picked = paths.join(', '));",
        '  }',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  final theme = Theme.of(context);',
        '  return SizedBox(',
        '    width: 50,',
        '    child: Column(',
        '      mainAxisSize: .min,',
        '      crossAxisAlignment: .stretch,',
        '      gap: 1,',
        '      children: [',
        '        SizedBox(',
        '          height: 8,',
        '          // a picker for each mode: it reads its mode once',
        ...call(10, 'child: FilePicker', [
          key,
          ...args,
          'controller: _files',
          'filters: _filters',
          'onPicked: _show',
        ], ','),
        '        ),',
        '        Row(',
        '          crossAxisAlignment: .start,',
        '          gap: 2,',
        '          children: [',
        '            Button(',
        "              'In a dialog',",
        '              onPressed: () => unawaited(',
        ...call(16, 'showFilePicker', [
          'context',
          ...args,
          'filters: _filters',
        ], '.then(_show),'),
        '              ),',
        '            ),',
        '            // the picker above gone there, the name typed kept',
        "            Button('lib/src', onPressed: () => _files.goTo('~/twk/lib/src')),",
        '            Expanded(',
        '              child: Text.rich(',
        '                [',
        "                  Span('picked: ', theme.muted),",
        '                  if (_picked case final picked?)',
        '                    Span(picked)',
        '                  else',
        "                    Span('nothing', theme.muted),",
        '                ],',
        '                maxLines: 2,',
        '                overflow: .ellipsis,',
        '              ),',
        '            ),',
        '          ],',
        '        ),',
        '      ],',
        '    ),',
        '  );',
        '}',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Controls',
    title: 'Form, FormField',
    options: const [
      ChoiceOption(
        'validate',
        'validate',
        values: ['disabled', 'always', 'onUserInteraction', 'onUnfocus'],
      ),
    ],
    build: (context, o) => _Signup(
      validate: AutovalidateMode.values.byName(o.choice('validate')),
    ),
    code: (o) => [
      'final _form = GlobalKey<FormState>();',
      'String? _submitted;',
      "var _name = '';",
      '',
      '@override',
      'Widget build(BuildContext context) => Form(',
      '  key: _form,',
      if (o.choice<String>('validate') != 'disabled')
        '  autovalidateMode: .${o.label('validate')},',
      '  onSubmitted: () => setState(() => _submitted = _name),',
      '  child: SizedBox(',
      '    width: 40,',
      '    child: Column(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .stretch,',
      '      gap: 1,',
      '      children: [',
      '        TextFormField(',
      "          placeholder: 'name',",
      "          validator: (name) => name!.isEmpty ? 'a name, please' : null,",
      '          onSaved: (name) => _name = name!,',
      '        ),',
      '        TextFormField(',
      "          placeholder: 'email',",
      '          validator: (email) =>',
      "              email!.contains('@') ? null : 'an email has an @ in it',",
      '        ),',
      '        FormField<bool>(',
      '          initialValue: false,',
      '          validator: (accepted) =>',
      "              accepted! ? null : 'the terms are to be accepted',",
      '          builder: (field) => Checkbox(',
      '            value: field.value!,',
      '            onChanged: field.didChange,',
      "            label: 'I accept the terms',",
      '          ),',
      '        ),',
      '        Row(',
      '          gap: 2,',
      '          children: [',
      _submitLine,
      _resetLine,
      '            Expanded(',
      '              child: Text.rich(',
      '                [',
      "                  Span(' submitted: ', Theme.of(context).muted),",
      '                  if (_submitted case final submitted?)',
      '                    Span(submitted)',
      '                  else',
      "                    Span('nothing', Theme.of(context).muted),",
      '                ],',
      '                wrap: .none,',
      '                overflow: .ellipsis,',
      '              ),',
      '            ),',
      '          ],',
      '        ),',
      '      ],',
      '    ),',
      '  ),',
      ');',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Controls',
    title: 'TabBar, TabView',
    options: const [
      ChoiceOption('tabs', 'tabs', values: [3, 7], initial: 3),
      ChoiceOption('look', 'look', values: ['plain', 'strip']),
    ],
    build: (context, o) => _Tabs(
      count: o.choice('tabs'),
      strip: o.choice<String>('look') == 'strip',
    ),
    code: (o) {
      final tabs = _tabNames.take(o.choice<int>('tabs')).toList();
      final made = o.choice<String>('look') == 'strip'
          ? 'TabBar.strip'
          : 'TabBar';
      final bar =
          '      $made(controller: _tabs, tabs: const '
          '[${tabs.map((t) => "'$t'").join(', ')}]),';
      return [
        'final _tabs = TabController(length: ${tabs.length});',
        'var _wrap = true;',
        'var _hidden = false;',
        "var _indent = 'spaces';",
        '',
        '@override',
        'void dispose() {',
        '  _tabs.dispose();',
        '  super.dispose();',
        '}',
        '',
        '@override',
        'Widget build(BuildContext context) => SizedBox(',
        '  width: 40,',
        '  height: 7,',
        '  child: Column(',
        '    crossAxisAlignment: .stretch,',
        '    children: [',
        if (bar.length <= 80)
          bar
        else ...[
          '      $made(',
          '        controller: _tabs,',
          '        tabs: const [',
          for (final t in tabs) "          '$t',",
          '        ],',
          '      ),',
        ],
        '      Expanded(',
        '        // the view, its border primary while the focus is in it',
        '        child: FocusBuilder(',
        '          builder: (context, hasFocus, view) => Box(',
        '            border: .all(',
        '              type: .rounded,',
        '              style: hasFocus',
        '                  ? Theme.of(context).primary',
        '                  : Theme.of(context).border,',
        '            ),',
        '            padding: const .x(1),',
        '            child: view,',
        '          ),',
        '          child: TabView(',
        '            controller: _tabs,',
        '            children: [',
        '              Column(',
        '                crossAxisAlignment: .start,',
        '                children: [',
        '                  Checkbox(',
        '                    value: _wrap,',
        "                    label: 'wrap lines',",
        '                    onChanged: (on) => setState(() => _wrap = on),',
        '                  ),',
        '                  Checkbox(',
        '                    value: _hidden,',
        "                    label: 'show hidden files',",
        '                    onChanged: (on) => setState(() => _hidden = on),',
        '                  ),',
        '                ],',
        '              ),',
        '              Column(',
        '                crossAxisAlignment: .start,',
        '                children: [',
        "                  const Text('Indent with'),",
        '                  RadioGroup<String>(',
        '                    choices: const [',
        "                      Choice('spaces', 'spaces'),",
        "                      Choice('tabs', 'tabs'),",
        '                    ],',
        '                    value: _indent,',
        '                    direction: .horizontal,',
        _indentLine,
        '                  ),',
        '                ],',
        '              ),',
        for (final t in tabs.skip(2)) _tabTextLine(t),
        '            ],',
        '          ),',
        '        ),',
        '      ),',
        '    ],',
        '  ),',
        ');',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Controls',
    title: 'KeyHintsBar',
    options: const [
      SwitchOption('unhinted', 'unhinted keys'),
      SwitchOption('join', 'join keys', initial: true),
      ChoiceOption('keys', 'keys named by', values: ['signs', 'names']),
      ChoiceOption(
        'separator',
        'separator',
        values: _separators,
        labels: ['blanks', 'dot', 'line'],
      ),
    ],
    build: (context, o) => _Hinted(
      unhinted: o.flag('unhinted'),
      joinKeys: o.flag('join'),
      names: o.choice<String>('keys') == 'names',
      separator: o.choice('separator'),
    ),
    code: (o) => [
      'String? _did;',
      'var _autosave = false;',
      '',
      if (o.choice<String>('keys') == 'names') ...[
        '// a key by its name, as KeyCombo writes it: left, escape',
        r"static String _named(KeyCombo combo) => '$combo';",
        '',
      ],
      'void _do(String what) => setState(() => _did = what);',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return KeyBindings(',
      '    {',
      "      'ctrl+s': () => _do('save'),",
      "      'ctrl+x ctrl+o': () => _do('open'),",
      "      'f2': () => _do('rename'),",
      '    },',
      "    hints: const {'ctrl+s': 'save', 'ctrl+x ctrl+o': 'open'},",
      '    child: SizedBox(',
      '      width: 44,',
      '      child: Column(',
      '        mainAxisSize: .min,',
      '        crossAxisAlignment: .stretch,',
      '        gap: 1,',
      '        children: [',
      '          Row(',
      '            gap: 2,',
      '            children: [',
      '              // a field without a box shows the focus on the selection',
      '              Expanded(',
      '                child: TextField(',
      "                  placeholder: 'a field',",
      '                  focusedStyle: theme.selection,',
      '                ),',
      '              ),',
      '              Checkbox(',
      '                value: _autosave,',
      "                label: 'autosave',",
      '                onChanged: (on) => setState(() => _autosave = on),',
      '              ),',
      '            ],',
      '          ),',
      '          Text.rich([',
      "            Span('did: ', theme.muted),",
      '            if (_did case final did?)',
      '              Span(did)',
      '            else',
      "              Span('nothing', theme.muted),",
      '          ]),',
      '          Box(',
      '            border: .all(type: .rounded, style: theme.border),',
      '            padding: const .x(1),',
      ...call(12, 'child: const KeyHintsBar', [
        if (o.flag('unhinted')) 'showUnhinted: true',
        if (o.choice<String>('keys') == 'names') 'keyLabel: _named',
        if (!o.flag('join')) 'joinKeys: false',
        if (o.choice<String>('separator') != _separators.first)
          "separator: '${o.choice<String>('separator')}'",
      ], ','),
      '          ),',
      '        ],',
      '      ),',
      '    ),',
      '  );',
      '}',
    ].join('\n'),
  ),
  GalleryPage(
    group: 'Controls',
    title: 'StatusMessage, Badge',
    options: const [
      ChoiceOption(
        'kind',
        'kind',
        values: ['info', 'success', 'warning', 'error'],
      ),
    ],
    build: (context, o) {
      final kind = StatusKind.values.byName(o.choice('kind'));
      final (said, disk) = _says[kind]!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          StatusMessage(said, kind: kind),
          StatusMessage(disk, kind: kind, title: 'Disk'),
          Row(
            mainAxisSize: MainAxisSize.min,
            gap: 1,
            children: [
              for (final kind in StatusKind.values)
                Badge(kind.name, kind: kind),
              const Badge('3'),
            ],
          ),
        ],
      );
    },
    code: (o) {
      final k = o.label('kind');
      final (said, disk) = _says[StatusKind.values.byName(k)]!;
      return [
        'return Column(',
        '  mainAxisSize: .min,',
        '  crossAxisAlignment: .start,',
        '  gap: 1,',
        '  children: [',
        "    const StatusMessage('$said', kind: .$k),",
        '    const StatusMessage(',
        "      '$disk',",
        '      kind: .$k,',
        "      title: 'Disk',",
        '    ),',
        '    Row(',
        '      mainAxisSize: .min,',
        '      gap: 1,',
        '      children: [',
        _badgesLine,
        "        const Badge('3'),",
        '      ],',
        '    ),',
        '  ],',
        ');',
      ].join('\n');
    },
  ),
  _callout,
  GalleryPage(
    group: 'Controls',
    title: 'Link',
    options: const [
      ColorOption(
        'color',
        'style',
        values: ['primary', 'accent', 'info'],
        initial: 'primary',
      ),
      ChoiceOption(
        'text',
        'shows',
        values: ['label', 'url'],
        labels: ['text', 'url'],
      ),
    ],
    build: (context, o) {
      final c = o.color('color');
      final labelled = o.choice<String>('text') == 'label';
      final style = c == 'primary'
          ? null
          : o
                .colorStyle(context, 'color')
                .merge(const Style(attrs: Attr.underline));
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [
          Link(
            'https://dart.dev',
            style: style,
            text: labelled ? 'The Dart language' : null,
          ),
          Link('https://pub.dev', style: style),
          Link(
            'file:///home/user/twk/README.md',
            style: style,
            text: labelled ? 'the README' : null,
          ),
        ],
      );
    },
    code: (o) {
      final c = o.color('color');
      final primary = c == 'primary';
      final labelled = o.choice<String>('text') == 'label';
      // a link, its text where the page labels it
      List<String> link(String url, String? text) => [
        "'$url'",
        if (!primary) 'style: style',
        if (labelled && text != null) "text: '$text'",
      ];
      return [
        if (!primary) ...[
          'final theme = Theme.of(context);',
          'final style = theme.$c.merge(const .new(attrs: Attr.underline));',
        ],
        'return ${primary ? 'const ' : ''}Column(',
        '  mainAxisSize: .min,',
        '  crossAxisAlignment: .start,',
        '  gap: 1,',
        '  children: [',
        ...call(4, 'Link', link('https://dart.dev', 'The Dart language'), ','),
        ...call(4, 'Link', link('https://pub.dev', null), ','),
        ...call(4, 'Link', link(_readme, 'the README'), ','),
        '  ],',
        ');',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Controls',
    title: 'ListTile',
    options: const [
      SwitchOption('leading', 'leading', initial: true),
      SwitchOption('subtitle', 'subtitle', initial: true),
      SwitchOption('trailing', 'trailing', initial: true),
    ],
    build: (context, o) => _Tiles(
      leading: o.flag('leading'),
      subtitle: o.flag('subtitle'),
      trailing: o.flag('trailing'),
    ),
    code: (o) {
      final leading = o.flag('leading');
      final subtitle = o.flag('subtitle');
      final trailing = o.flag('trailing');
      return [
        'var _open = 0;',
        '',
        '@override',
        'Widget build(BuildContext context) {',
        '  const files = [',
        for (final (name, about) in _tileFiles) "    ('$name', '$about'),",
        '  ];',
        '  return Column(',
        '    mainAxisSize: .min,',
        '    children: [',
        '      for (final (i, (name, about)) in files.indexed)',
        '        ListTile(',
        if (leading) "          leading: const Text('▤'),",
        '          title: Text(name),',
        if (subtitle) '          subtitle: Text(about),',
        if (trailing) "          trailing: const Text('›'),",
        '          selected: i == _open,',
        '          enabled: i != 3,',
        '          onTap: () => setState(() => _open = i),',
        '        ),',
        '    ],',
        '  );',
        '}',
      ].join('\n');
    },
  ),
  GalleryPage(
    group: 'Controls',
    title: 'StatusBar',
    options: [
      SliderOption(
        'width',
        'width',
        min: 12,
        max: 50,
        initial: 50,
        format: (v) => '$v cells',
      ),
      const ChoiceOption('gap', 'gap', values: [0, 1, 3], initial: 1),
    ],
    build: (context, o) => SizedBox(
      width: o.number('width').toInt(),
      child: StatusBar(
        gap: o.choice('gap'),
        left: const Badge('NORMAL'),
        center: const Text(
          'example/widgets/main.dart',
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
        ),
        right: Text('Ln 12, Col 4', style: Theme.of(context).muted),
      ),
    ),
    code: (o) => [
      'return SizedBox(',
      '  width: ${o.label('width')},',
      '  child: StatusBar(',
      if (o.choice<int>('gap') != 1) '    gap: ${o.label('gap')},',
      "    left: const Badge('NORMAL'),",
      '    center: const Text(',
      "      'example/widgets/main.dart',",
      '      wrap: .none,',
      '      overflow: .ellipsis,',
      '    ),',
      "    right: Text('Ln 12, Col 4', style: Theme.of(context).muted),",
      '  ),',
      ');',
    ].join('\n'),
  ),
];

/// Save, Send and a disabled button, and how often each was pressed.
final class _Buttons extends StatefulWidget {
  const _Buttons({required this.color, this.look = 'chip', this.tall = false});

  final String color;

  /// `chip`, `outlined` or `filled`: Button, Button.outlined, Button.filled.
  final String look;

  /// Whether an outlined or a filled one is three rows.
  final bool tall;

  @override
  State<_Buttons> createState() => _ButtonsState();
}

final class _ButtonsState extends State<_Buttons> {
  // kept in the page's state while the gallery runs
  late final Map<String, Object?> _kept = PageControl.of(context).state;
  int get _saved => _kept['saved'] as int? ?? 0;
  set _saved(int n) => _kept['saved'] = n;
  int get _sent => _kept['sent'] as int? ?? 0;
  set _sent(int n) => _kept['sent'] = n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styled = widget.color != 'primary';
    final style = styled
        ? themeColor(theme, widget.color).merge(const Style(attrs: Attr.bold))
        : null;
    final focused = style?.merge(const Style(attrs: Attr.reverse));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 2,
          children: [
            for (final (label, onPressed) in [
              ('Save', () => setState(() => _saved++)),
              ('Send', () => setState(() => _sent++)),
              ('Disabled', null),
            ])
              switch (widget.look) {
                'outlined' => Button.outlined(
                  label,
                  tall: widget.tall,
                  style: styled ? themeColor(theme, widget.color) : null,
                  onPressed: onPressed,
                ),
                'filled' => Button.filled(
                  label,
                  tall: widget.tall,
                  style: styled ? themeColor(theme, widget.color) : null,
                  onPressed: onPressed,
                ),
                _ => Button(
                  label,
                  style: style,
                  focusedStyle: focused,
                  onPressed: onPressed,
                ),
              },
          ],
        ),
        LitLine([
          ('saved: ', true),
          ('$_saved', false),
          ('  sent: ', true),
          ('$_sent', false),
        ], serial: _saved + _sent),
      ],
    );
  }
}

/// The style of a star that is on, as the Pressable page's Code writes it.
String _markOf(Options o) =>
    'theme.${o.color('color')}.merge(const .new(attrs: Attr.bold))';

/// The rows of the Pressable page, each a Pressable that stars a name,
/// and the line that says which are starred.
final class _Stars extends StatefulWidget {
  const _Stars({required this.color});

  final String color;

  @override
  State<_Stars> createState() => _StarsState();
}

final class _StarsState extends State<_Stars> {
  // kept in the page's state while the gallery runs, in the order starred
  late final Map<String, Object?> _kept = PageControl.of(context).state;
  List<String> get _starred =>
      (_kept['starred'] as List<String>?) ?? const ['twk'];
  int get _serial => _kept['serial'] as int? ?? 0;

  void _toggle(String name) => setState(() {
    final starred = _starred;
    _kept['starred'] = starred.contains(name)
        ? [
            for (final n in starred)
              if (n != name) n,
          ]
        : [...starred, name];
    _kept['serial'] = _serial + 1;
  });

  Widget _star(String name, {bool enabled = true}) => Pressable(
    enabled: enabled,
    bindings: {'space': () => _toggle(name)},
    hints: const {'space': 'star'},
    onTap: enabled ? (_) => _toggle(name) : null,
    builder: (context, focused) {
      final theme = Theme.of(context);
      final on = _starred.contains(name);
      final mark = themeColor(
        theme,
        widget.color,
      ).merge(const Style(attrs: Attr.bold));
      return Text.rich(
        [
          Span(on ? '★' : '☆', on ? mark : theme.muted),
          Span(' $name'),
        ],
        style: !enabled
            ? theme.muted
            : focused
            ? theme.selection
            : const Style(),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final starred = _starred;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _star('twk'),
            _star('gallery'),
            _star('archive', enabled: false),
          ],
        ),
        LitLine([
          ('starred: ', true),
          if (starred.isEmpty)
            ('nothing', true)
          else
            (starred.join(', '), false),
        ], serial: _serial),
      ],
    );
  }
}

const _planets = [
  'Mercury',
  'Venus',
  'Earth',
  'Mars',
  'Jupiter',
  'Saturn',
  'Uranus',
  'Neptune',
];

const _selectionLine =
    "late final _selection = SelectionController<String>(selected: ['Earth'])";

const List<Choice<String>> _fruit = [
  Choice('apple', 'apple'),
  Choice('banana', 'banana'),
  Choice('cherry', 'cherry'),
  Choice('durian', 'durian', enabled: false),
];

const List<Choice<String>> _fruits = [
  Choice('apple', 'apple'),
  Choice('apricot', 'apricot'),
  Choice('banana', 'banana'),
  Choice('blueberry', 'blueberry'),
  Choice('cherry', 'cherry'),
  Choice('durian', 'durian', enabled: false),
  Choice('fig', 'fig'),
  Choice('grape', 'grape'),
  Choice('lemon', 'lemon'),
];

/// The Code's line of [c].
String _choiceLine(Choice<String> c) {
  final enabled = c.enabled ? '' : ', enabled: false';
  return "  Choice('${c.value}', '${c.label}'$enabled),";
}

/// The look of a control's popup, raised or bordered, [disabled] as
/// [PageOption.disabled] says: one option of the pages of Select,
/// DatePicker and Autocomplete.
ChoiceOption popupLookOption({bool Function(Options options)? disabled}) =>
    ChoiceOption(
      'popup',
      'popup look',
      values: const ['raised', 'bordered'],
      disabled: disabled,
    );

/// The [PanelLook] of [popupLookOption] in [o].
PanelLook popupLookOf(Options o) => PanelLook.values.byName(o.choice('popup'));

/// The Code's `popupLook:` line of [popupLookOption] in [o], [pad] columns
/// in, where it is not the default.
List<String> popupLookArg(Options o, String pad) => [
  if (popupLookOf(o) != PanelLook.raised)
    '${pad}popupLook: .${popupLookOf(o).name},',
];

/// The answers of the ConfirmInput page, yes and no, by the option's value.
const _answers = {
  'Yes, No': ('Yes', 'No'),
  'Delete, Keep': ('Delete', 'Keep'),
};

/// The page's own state, which outlives a visit to another page.
mixin _Kept<T extends StatefulWidget> on State<T> {
  late final Map<String, Object?> kept = PageControl.of(context).state;

  /// [key] of the kept state, [or] while it has none.
  V keptOr<V>(String key, V or) => kept[key] as V? ?? or;

  /// Sets [key] of the kept state to [value], and counts the change.
  void keep(String key, Object? value) => setState(() {
    kept[key] = value;
    kept['serial'] = serial + 1;
  });

  /// How often the kept state changed.
  int get serial => keptOr('serial', 0);
}

/// A checkbox, a switch and a disabled checkbox.
final class _Toggles extends StatefulWidget {
  const _Toggles({required this.pill});

  /// Whether the switch is the pill, not `[on ]` and `[off]`.
  final bool pill;

  @override
  State<_Toggles> createState() => _TogglesState();
}

final class _TogglesState extends State<_Toggles> with _Kept {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Checkbox(
        value: keptOr('wrap', true),
        label: 'wrap lines',
        onChanged: (value) => keep('wrap', value),
      ),
      Switch(
        value: keptOr('dark', false),
        label: 'dark mode',
        pill: widget.pill,
        onChanged: (value) => keep('dark', value),
      ),
      const Checkbox(value: true, label: 'disabled', onChanged: null),
    ],
  );
}

/// A fruit chosen in a radio group.
final class _Radios extends StatefulWidget {
  const _Radios({required this.direction});

  final Axis direction;

  @override
  State<_Radios> createState() => _RadiosState();
}

final class _RadiosState extends State<_Radios> with _Kept {
  @override
  Widget build(BuildContext context) {
    final chosen = keptOr<String?>('chosen', null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        RadioGroup<String>(
          choices: _fruit,
          value: chosen,
          direction: widget.direction,
          onChanged: (value) => keep('chosen', value),
        ),
        LitLine([
          ('chosen: ', true),
          if (chosen == null) ('nothing', true) else (chosen, false),
        ], serial: serial),
      ],
    );
  }
}

/// Planets selected in a list, one or several.
final class _Planets extends StatefulWidget {
  const _Planets({required this.multiple, required this.bar});

  final bool multiple;

  /// Whether the list shows its bar on the cursor's row.
  final bool bar;

  @override
  State<_Planets> createState() => _PlanetsState();
}

final class _PlanetsState extends State<_Planets> with _Kept {
  /// The selection, kept with the page: a new one with Earth selected when
  /// [_Planets.multiple] changes.
  SelectionController<String> get _selection {
    final c = kept['selection'] as SelectionController<String>?;
    if (c != null && c.multiple == widget.multiple) {
      return c;
    }
    return kept['selection'] = SelectionController<String>(
      multiple: widget.multiple,
      selected: ['Earth'],
    );
  }

  SelectionController<String>? _listening;
  var _said = '';

  void _changed() {
    final said = _listening?.selected.join(',') ?? '';
    setState(() {
      if (said != _said) {
        kept['serial'] = serial + 1;
      }
      _said = said;
    });
  }

  @override
  void dispose() {
    _listening?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = _selection;
    if (!identical(selection, _listening)) {
      _listening?.removeListener(_changed);
      _listening = selection..addListener(_changed);
      _said = selection.selected.join(',');
    }
    final selected = selection.selected;
    return SizedBox(
      width: 29,
      height: 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 2,
        children: [
          SizedBox(
            width: 18,
            child: FocusBuilder(
              builder: (context, hasFocus, list) => Box(
                border: Border.all(
                  type: BorderType.rounded,
                  style: hasFocus ? theme.primary : theme.border,
                ),
                child: list,
              ),
              child: SelectionList<String>(
                itemCount: _planets.length,
                keyOf: (i) => _planets[i],
                itemBuilder: (context, i) => Text(_planets[i]),
                itemEnabled: (i) => _planets[i] != 'Venus',
                bar: widget.bar,
                controller: selection,
              ),
            ),
          ),
          Expanded(
            child: LitLine([
              ('selected\n', true),
              if (selected.isEmpty)
                ('nothing', true)
              else
                (selected.join('\n'), false),
            ], serial: serial),
          ),
        ],
      ),
    );
  }
}

/// A fruit chosen in a Select, some in a MultiSelect.
final class _Selects extends StatefulWidget {
  const _Selects({
    required this.inline,
    required this.rows,
    required this.popupLook,
  });

  final bool inline;
  final int rows;
  final PanelLook popupLook;

  @override
  State<_Selects> createState() => _SelectsState();
}

final class _SelectsState extends State<_Selects> with _Kept {
  final _popup = PopupController();

  @override
  void dispose() {
    _popup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 4,
        children: [
          Select<String>(
            choices: _fruits,
            value: keptOr<String?>('one', null),
            hint: 'a fruit',
            inline: widget.inline,
            rows: widget.rows,
            popupLook: widget.popupLook,
            controller: _popup,
            onChanged: (value) => keep('one', value),
          ),
          MultiSelect<String>(
            choices: _fruits,
            values: keptOr('some', const <String>{}),
            hint: 'some fruit',
            inline: widget.inline,
            rows: widget.rows,
            popupLook: widget.popupLook,
            onChanged: (values) => keep('some', values),
          ),
        ],
      ),
      Button('Choose a fruit', onPressed: _popup.open),
    ],
  );
}

/// A question answered yes or no, and the answer.
final class _Confirm extends StatefulWidget {
  const _Confirm({required this.defaultValue, required this.answers});

  final bool defaultValue;
  final (String, String) answers;

  @override
  State<_Confirm> createState() => _ConfirmState();
}

final class _ConfirmState extends State<_Confirm> with _Kept {
  @override
  Widget build(BuildContext context) {
    final answer = keptOr<bool?>('answer', null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        ConfirmInput(
          'Delete 3 files?',
          // it reads defaultValue once: another is a new input
          key: ValueKey(widget.defaultValue),
          defaultValue: widget.defaultValue,
          yes: widget.answers.$1,
          no: widget.answers.$2,
          onConfirmed: (yes) => keep('answer', yes),
        ),
        LitLine([
          ('answer: ', true),
          switch (answer) {
            null => ('nothing', true),
            true => ('yes', false),
            false => ('no', false),
          },
        ], serial: serial),
      ],
    );
  }
}

/// A volume on a slider.
final class _Volume extends StatefulWidget {
  const _Volume({required this.width, required this.divisions});

  final int width;
  final int? divisions;

  @override
  State<_Volume> createState() => _VolumeState();
}

final class _VolumeState extends State<_Volume> with _Kept {
  @override
  Widget build(BuildContext context) {
    final volume = keptOr('volume', 0.5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SizedBox(
          width: widget.width,
          child: Slider(
            value: volume,
            semanticsLabel: 'Volume',
            divisions: widget.divisions,
            onChanged: (value) => keep('volume', value),
          ),
        ),
        LitLine([
          ('volume: ', true),
          ('${(volume * 100).round()}%', false),
        ], serial: serial),
      ],
    );
  }
}

/// Copies and a price, typed or stepped, and what they come to.
final class _Numbers extends StatefulWidget {
  const _Numbers();

  @override
  State<_Numbers> createState() => _NumbersState();
}

final class _NumbersState extends State<_Numbers> with _Kept {
  @override
  Widget build(BuildContext context) {
    final copies = keptOr<double>('copies', 1);
    final price = keptOr('price', 9.5);
    Widget row(String label, Widget input) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 16, child: Text(label)),
        SizedBox(width: 10, child: input),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        row(
          'copies, 1 to 99',
          NumberInput(
            value: copies,
            min: 1,
            max: 99,
            onChanged: (value) => keep('copies', value),
          ),
        ),
        row(
          'price, by 0.25',
          NumberInput(
            value: price,
            min: 0,
            step: 0.25,
            decimals: 2,
            onChanged: (value) => keep('price', value),
          ),
        ),
        LitLine([
          (
            '${copies.round()} × ${price.toStringAsFixed(2)} = '
                '${(copies * price).toStringAsFixed(2)}',
            false,
          ),
        ], serial: serial),
      ],
    );
  }
}

const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// A day of 2026 picked, typed or stepped, with its time of day or not.
final class _Date extends StatefulWidget {
  const _Date({
    required this.time,
    required this.firstWeekday,
    required this.popupLook,
  });

  final bool time;
  final int firstWeekday;
  final PanelLook popupLook;

  @override
  State<_Date> createState() => _DateState();
}

final class _DateState extends State<_Date> with _Kept {
  final _calendar = PopupController();

  @override
  void dispose() {
    _calendar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = keptOr<DateTime?>('date', null);
    String two(int n) => '$n'.padLeft(2, '0');
    final at = date == null || !widget.time
        ? ''
        : ', ${two(date.hour)}:${two(date.minute)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 2,
          children: [
            SizedBox(
              width: 22,
              child: DatePicker(
                value: date,
                showTime: widget.time,
                firstDate: DateTime(2026),
                lastDate: DateTime(2026, 12, 31),
                today: DateTime(2026, 10, 19),
                firstWeekday: widget.firstWeekday,
                popupLook: widget.popupLook,
                controller: _calendar,
                onChanged: (date) => keep('date', date),
              ),
            ),
            Button('Calendar', onPressed: _calendar.open),
          ],
        ),
        LitLine([
          ('picked: ', true),
          if (date == null)
            ('nothing', true)
          else
            (
              '${_days[date.weekday - 1]}, ${date.day} '
                  '${Calendar.englishMonthNames[date.month - 1]}$at',
              false,
            ),
        ], serial: serial),
      ],
    );
  }
}

/// The FilePicker page's modes: what the picker picks, and whether
/// several.
const Map<String, (FilePickerMode, bool)> _modes = {
  'open': (FilePickerMode.open, false),
  'several': (FilePickerMode.open, true),
  'save': (FilePickerMode.save, false),
  'directory': (FilePickerMode.directory, false),
};

const _filters = [
  FileFilter('Dart', ['dart']),
  FileFilter('All files'),
];

/// The gallery's file system of its own, which the pickers list in
/// place of the machine's: the same on every machine, and nothing of it
/// shown.
final _files = PickerFileSystem.memory(
  [
    '/home/user/.cache/dart/',
    '/home/user/.bashrc',
    '/home/user/notes.md',
    '/home/user/todo.txt',
    for (final name in [
      '.dart_tool/package_config.json',
      for (final f in ['chat_demo', 'counter', 'hello']) 'example/$f.dart',
      for (final f in ['controls', 'data', 'main', 'page', 'text'])
        'example/widgets/$f.dart',
      'lib/twk.dart',
      'lib/src/app.dart',
      'lib/src/theme.dart',
      for (final f in [
        'button',
        'choice',
        'select',
        'slider',
        'tabs',
        'toggle',
      ])
        'lib/src/controls/$f.dart',
      'lib/src/editing/text_area.dart',
      'lib/src/editing/text_field.dart',
      for (final f in ['box', 'flex', 'grid']) 'lib/src/layout/$f.dart',
      for (final f in ['app', 'button', 'select', 'slider'])
        'test/${f}_test.dart',
      '.gitignore',
      'analysis_options.yaml',
      'CHANGELOG.md',
      'pubspec.yaml',
      'README.md',
    ])
      '/home/user/twk/$name',
    '/tmp/build.log',
  ],
  currentDirectory: '/home/user/twk',
  homeDirectory: '/home/user',
);

/// A file picker, the same in a dialog, and what was picked.
final class _Files extends StatefulWidget {
  const _Files({required this.mode, required this.showHidden, super.key});

  final String mode;

  /// Whether the pickers show the files whose names start with a dot at
  /// first.
  final bool showHidden;

  @override
  State<_Files> createState() => _FilesState();
}

final class _FilesState extends State<_Files> with _Kept {
  final _picker = FilePickerController();

  @override
  void dispose() {
    _picker.dispose();
    super.dispose();
  }

  void _show(List<String>? paths) {
    if (mounted && paths != null) {
      keep('picked', paths.join(', '));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (mode, multiple) = _modes[widget.mode]!;
    final picked = keptOr<String?>('picked', null);
    return SizedBox(
      width: 50,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        gap: 1,
        children: [
          SizedBox(
            height: 8,
            // a picker for each mode: it reads its mode once
            child: FilePicker(
              key: ValueKey(widget.mode),
              fileSystem: _files,
              mode: mode,
              multiple: multiple,
              showHidden: widget.showHidden,
              controller: _picker,
              filters: _filters,
              onPicked: _show,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            gap: 2,
            children: [
              Button(
                'In a dialog',
                onPressed: () => unawaited(
                  showFilePicker(
                    context,
                    fileSystem: _files,
                    mode: mode,
                    multiple: multiple,
                    showHidden: widget.showHidden,
                    filters: _filters,
                  ).then(_show),
                ),
              ),
              Button(
                'lib/src',
                onPressed: () => _picker.goTo('~/twk/lib/src'),
              ),
              Expanded(
                child: LitLine(
                  [
                    ('picked: ', true),
                    if (picked == null) ('nothing', true) else (picked, false),
                  ],
                  serial: serial,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _submitLine =
    "            Button('Submit', onPressed: () => "
    '_form.currentState!.submit()),';
const _resetLine =
    "            Button('Reset', onPressed: () => "
    '_form.currentState!.reset()),';

/// A form of a name, an email and the terms, submitted or reset together.
final class _Signup extends StatefulWidget {
  const _Signup({required this.validate});

  final AutovalidateMode validate;

  @override
  State<_Signup> createState() => _SignupState();
}

final class _SignupState extends State<_Signup> with _Kept {
  final _form = GlobalKey<FormState>();
  var _name = '';

  @override
  Widget build(BuildContext context) {
    final submitted = keptOr<String?>('submitted', null);
    return Form(
      key: _form,
      autovalidateMode: widget.validate,
      onSubmitted: () => keep('submitted', _name),
      child: SizedBox(
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          gap: 1,
          children: [
            TextFormField(
              placeholder: 'name',
              validator: (name) => name!.isEmpty ? 'a name, please' : null,
              onSaved: (name) => _name = name!,
            ),
            TextFormField(
              placeholder: 'email',
              validator: (email) =>
                  email!.contains('@') ? null : 'an email has an @ in it',
            ),
            FormField<bool>(
              initialValue: false,
              validator: (accepted) =>
                  accepted! ? null : 'the terms are to be accepted',
              builder: (field) => Checkbox(
                value: field.value!,
                onChanged: field.didChange,
                label: 'I accept the terms',
              ),
            ),
            Row(
              gap: 2,
              children: [
                Button(
                  'Submit',
                  onPressed: () => _form.currentState!.submit(),
                ),
                Button('Reset', onPressed: () => _form.currentState!.reset()),
                Expanded(
                  child: LitLine(
                    [
                      (' submitted: ', true),
                      if (submitted == null)
                        ('nothing', true)
                      else
                        (submitted, false),
                    ],
                    serial: serial,
                    wrap: TextWrap.none,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _tabNames = [
  'General',
  'Editor',
  'Keys',
  'Themes',
  'Plugins',
  'Terminal',
  'About',
];

const _indentLine =
    '                    onChanged: (value) => '
    'setState(() => _indent = value),';

/// The Code's line of the Text of tab [t].
String _tabTextLine(String t) {
  final text = _tabText[t]!.replaceAll('\n', r'\n');
  return "              const Text('$text'),";
}

/// What the tabs after General and Editor show.
const _tabText = {
  'Keys': 'ctrl+s saves the file.\nctrl+q quits.',
  'Themes': 'How the colours look.',
  'Plugins': 'What else is loaded.',
  'Terminal': 'The terminal it runs in.',
  'About': 'What this is.',
};

/// Tabs of settings, [count] of them, and the view of the one picked.
final class _Tabs extends StatefulWidget {
  const _Tabs({required this.count, required this.strip});

  final int count;

  /// Whether the bar is on a strip ([TabBar.strip]).
  final bool strip;

  @override
  State<_Tabs> createState() => _TabsState();
}

final class _TabsState extends State<_Tabs> with _Kept {
  /// The tabs, kept with the page: new ones, at the first, when their
  /// count changes.
  TabController get _tabs {
    final c = kept['tabs'] as TabController?;
    if (c != null && c.length == widget.count) {
      return c;
    }
    return kept['tabs'] = TabController(length: widget.count);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final names = _tabNames.take(widget.count).toList();
    return SizedBox(
      width: 40,
      height: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.strip)
            TabBar.strip(controller: tabs, tabs: names)
          else
            TabBar(controller: tabs, tabs: names),
          Expanded(
            // the view, its border primary while the focus is in it
            child: FocusBuilder(
              builder: (context, hasFocus, view) => Box(
                border: Border.all(
                  type: BorderType.rounded,
                  style: hasFocus
                      ? Theme.of(context).primary
                      : Theme.of(context).border,
                ),
                padding: const EdgeInsets.x(1),
                child: view,
              ),
              child: TabView(
                controller: tabs,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: keptOr('wrap', true),
                        label: 'wrap lines',
                        onChanged: (on) => keep('wrap', on),
                      ),
                      Checkbox(
                        value: keptOr('hidden', false),
                        label: 'show hidden files',
                        onChanged: (on) => keep('hidden', on),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Indent with'),
                      RadioGroup<String>(
                        choices: const [
                          Choice('spaces', 'spaces'),
                          Choice('tabs', 'tabs'),
                        ],
                        value: keptOr('indent', 'spaces'),
                        direction: Axis.horizontal,
                        onChanged: (value) => keep('indent', value),
                      ),
                    ],
                  ),
                  for (final t in names.skip(2)) Text(_tabText[t]!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A field and a checkbox under keys of their own, and the bar of the keys
/// that can be pressed now.
final class _Hinted extends StatefulWidget {
  const _Hinted({
    required this.unhinted,
    required this.joinKeys,
    required this.names,
    required this.separator,
  });

  final bool unhinted;
  final bool joinKeys;

  /// Whether the bar names the keys as [KeyCombo.toString] does, not by
  /// their signs.
  final bool names;
  final String separator;

  @override
  State<_Hinted> createState() => _HintedState();
}

final class _HintedState extends State<_Hinted> with _Kept {
  void _do(String what) => keep('did', what);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final did = keptOr<String?>('did', null);
    return KeyBindings(
      {
        'ctrl+s': () => _do('save'),
        'ctrl+x ctrl+o': () => _do('open'),
        'f2': () => _do('rename'),
      },
      hints: const {'ctrl+s': 'save', 'ctrl+x ctrl+o': 'open'},
      child: SizedBox(
        width: 44,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          gap: 1,
          children: [
            Row(
              gap: 2,
              children: [
                // a field without a box shows the focus on the selection
                Expanded(
                  child: TextField(
                    placeholder: 'a field',
                    focusedStyle: theme.selection,
                  ),
                ),
                Checkbox(
                  value: keptOr('autosave', false),
                  label: 'autosave',
                  onChanged: (on) => keep('autosave', on),
                ),
              ],
            ),
            LitLine([
              ('did: ', true),
              if (did == null) ('nothing', true) else (did, false),
            ], serial: serial),
            Box(
              border: Border.all(type: BorderType.rounded, style: theme.border),
              padding: const EdgeInsets.x(1),
              child: KeyHintsBar(
                showUnhinted: widget.unhinted,
                keyLabel: widget.names ? _named : null,
                joinKeys: widget.joinKeys,
                separator: widget.separator,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _readme = 'file:///home/user/twk/README.md';

/// What the KeyHintsBar page offers between two keys.
const _separators = ['   ', ' · ', ' │ '];

/// [combo] by its name, as [KeyCombo.toString] writes it.
String _named(KeyCombo combo) => '$combo';

/// What each kind of StatusMessage says: a message, and one under the
/// title Disk.
const Map<StatusKind, (String, String)> _says = {
  StatusKind.info: (
    'Saving runs in the background.',
    'The disk has 120 GB free.',
  ),
  StatusKind.success: ('Saved 3 files to disk.', 'Backed up: 3 files, 12 MB.'),
  StatusKind.warning: (
    'Saved 3 files; 1 was skipped.',
    'The disk is nearly full: 95% of it is used.',
  ),
  StatusKind.error: (
    'Could not save 3 files.',
    'The disk is full: nothing more can be written.',
  ),
};

const _badgesLine =
    '        for (final kind in StatusKind.values) '
    'Badge(kind.name, kind: kind),';

// ------------------------------------------------------------ SegmentedButton

/// The segments of the SegmentedButton page: a log's records by kind.
const List<Choice<String>> _kinds = [
  Choice('all', 'All'),
  Choice('errors', 'Errors (3)'),
  Choice('warnings', 'Warnings (12)'),
  Choice('info', 'Info', enabled: false),
];

/// What is on at first, one of them or several.
Set<String> _firstShown({required bool multiple}) =>
    multiple ? {'errors', 'warnings'} : {'all'};

final _segmented = GalleryPage(
  group: 'Controls',
  title: 'SegmentedButton',
  options: const [
    SwitchOption('multiple', 'multiple'),
    SwitchOption('empty', 'allow none'),
    SwitchOption('icon', 'selected icon'),
    ChoiceOption('caps', 'caps', values: ['square', 'round']),
  ],
  build: (context, o) => _Segments(
    key: ValueKey(o.flag('multiple')),
    multiple: o.flag('multiple'),
    empty: o.flag('empty'),
    icon: o.flag('icon'),
    round: o.choice<String>('caps') == 'round',
  ),
  code: (o) {
    final multiple = o.flag('multiple');
    final shown = _firstShown(multiple: multiple).map((v) => "'$v'");
    return [
      'var _shown = {${shown.join(', ')}};',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      SegmentedButton<String>(',
      '        segments: const [',
      for (final c in _kinds)
        if (c.enabled)
          "          Choice('${c.value}', '${c.label}'),"
        else
          "          Choice('${c.value}', '${c.label}', enabled: false),",
      '        ],',
      '        selected: _shown,',
      if (multiple) '        multiSelectionEnabled: true,',
      if (o.flag('empty')) '        emptySelectionAllowed: true,',
      if (o.flag('icon')) '        showSelectedIcon: true,',
      if (o.choice<String>('caps') == 'round') "        caps: ('(', ')'),",
      '        onSelectionChanged: (shown) => setState(() => _shown = shown),',
      '      ),',
      '      Text.rich([',
      "        Span('shown: ', theme.muted),",
      '        if (_shown.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      "          Span(_shown.join(', ')),",
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// A log's filter, one kind of record or several, and what it shows.
final class _Segments extends StatefulWidget {
  const _Segments({
    required this.multiple,
    required this.empty,
    required this.icon,
    required this.round,
    super.key,
  });

  final bool multiple;
  final bool empty;
  final bool icon;
  final bool round;

  @override
  State<_Segments> createState() => _SegmentsState();
}

final class _SegmentsState extends State<_Segments> with _Kept {
  @override
  Widget build(BuildContext context) {
    final name = 'shown:${widget.multiple}';
    final shown = keptOr(name, _firstShown(multiple: widget.multiple));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        SegmentedButton<String>(
          segments: _kinds,
          selected: shown,
          multiSelectionEnabled: widget.multiple,
          emptySelectionAllowed: widget.empty,
          showSelectedIcon: widget.icon,
          caps: widget.round ? ('(', ')') : ('[', ']'),
          onSelectionChanged: (shown) => keep(name, shown),
        ),
        LitLine([
          ('shown: ', true),
          if (shown.isEmpty) ('nothing', true) else (shown.join(', '), false),
        ], serial: serial),
      ],
    );
  }
}

// ------------------------------------------------------------ Callout

/// What a callout of each kind says, the button that acts on it, and its
/// own title.
const Map<StatusKind, (String, String, String)> _notices = {
  StatusKind.info: ('A newer version of twk is out: 0.2.0.', 'Update', 'twk'),
  StatusKind.success: ('The build finished in 4.2 s.', 'Open it', 'Build'),
  StatusKind.warning: (
    'The disk is 95 % full: 2.1 GB are left.',
    'Clean up',
    'Disk',
  ),
  StatusKind.error: ('3 of the 214 tests failed.', 'Show them', 'Tests'),
};

/// The Callout page's own icon, in place of the kind's.
const _ownIcon = '★';

final _callout = GalleryPage(
  group: 'Controls',
  title: 'Callout',
  options: [
    const ChoiceOption(
      'kind',
      'kind',
      values: ['info', 'success', 'warning', 'error'],
    ),
    const SwitchOption('dismiss', 'dismissible', initial: true),
    const SwitchOption('actions', 'actions', initial: true),
    const ChoiceOption(
      'title',
      'title',
      values: ['kind', 'own'],
    ),
    const ChoiceOption(
      'icon',
      'icon',
      values: ['kind', 'own', 'none'],
    ),
    SliderOption(
      'width',
      'width',
      min: 24,
      max: 60,
      initial: 44,
      format: (v) => '$v cells',
    ),
  ],
  build: (context, o) => _Notice(
    kind: StatusKind.values.byName(o.choice('kind')),
    dismiss: o.flag('dismiss'),
    actions: o.flag('actions'),
    width: o.number('width').toInt(),
    ownTitle: o.choice<String>('title') == 'own',
    icon: _iconOf(o),
  ),
  code: (o) {
    final kind = StatusKind.values.byName(o.choice('kind'));
    final (says, act, title) = _notices[kind]!;
    final icon = _iconOf(o);
    final dismiss = o.flag('dismiss');
    final actions = o.flag('actions');
    final did = act.toLowerCase();
    return [
      'var _shown = true;',
      "var _did = '';",
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  return Column(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 1,',
      '    children: [',
      '      if (_shown)',
      '        SizedBox(',
      '          width: ${o.label('width')},',
      '          child: Callout.text(',
      "            '$says',",
      if (kind != StatusKind.info) '            kind: .${kind.name},',
      if (o.choice<String>('title') == 'own') "            title: '$title',",
      if (icon != null) "            icon: '$icon',",
      if (dismiss) ...[
        '            onDismissed: () => setState(() {',
        '              _shown = false;',
        "              _did = 'dismissed';",
        '            }),',
      ],
      if (actions) ...[
        '            actions: [',
        '              Button(',
        "                '$act',",
        "                onPressed: () => setState(() => _did = '$did'),",
        '              ),',
        '            ],',
      ],
      '          ),',
      '        )',
      '      else',
      '        Button(',
      "          'Show it again',",
      '          onPressed: () => setState(() {',
      '            _shown = true;',
      "            _did = 'shown again';",
      '          }),',
      '        ),',
      '      Text.rich([',
      "        Span('did: ', theme.muted),",
      '        if (_did.isEmpty)',
      "          Span('nothing', theme.muted)",
      '        else',
      '          Span(_did),',
      '      ]),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The Callout page's icon in [o]: null for the kind's, `''` for none.
String? _iconOf(Options o) => switch (o.choice<String>('icon')) {
  'own' => _ownIcon,
  'none' => '',
  _ => null,
};

/// A callout of [kind], dismissed and shown again, and what was done.
final class _Notice extends StatefulWidget {
  const _Notice({
    required this.kind,
    required this.dismiss,
    required this.actions,
    required this.width,
    required this.ownTitle,
    required this.icon,
  });

  final StatusKind kind;
  final bool dismiss;
  final bool actions;
  final int width;

  /// Whether it has its own title, not the kind's name.
  final bool ownTitle;

  /// Its icon: null for the kind's, `''` for none.
  final String? icon;

  @override
  State<_Notice> createState() => _NoticeState();
}

final class _NoticeState extends State<_Notice> with _Kept {
  void _did(String what, {bool? shown}) => setState(() {
    if (shown != null) {
      kept['shown'] = shown;
    }
    kept['did'] = what;
    kept['serial'] = serial + 1;
  });

  @override
  Widget build(BuildContext context) {
    final (says, act, title) = _notices[widget.kind]!;
    final did = keptOr('did', '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        if (keptOr('shown', true))
          SizedBox(
            width: widget.width,
            child: Callout.text(
              says,
              kind: widget.kind,
              title: widget.ownTitle ? title : null,
              icon: widget.icon,
              onDismissed: widget.dismiss
                  ? () => _did('dismissed', shown: false)
                  : null,
              actions: [
                if (widget.actions)
                  Button(act, onPressed: () => _did(act.toLowerCase())),
              ],
            ),
          )
        else
          Button(
            'Show it again',
            onPressed: () => _did('shown again', shown: true),
          ),
        LitLine([
          ('did: ', true),
          if (did.isEmpty) ('nothing', true) else (did, false),
        ], serial: serial),
      ],
    );
  }
}

/// The files of the ListTile page, each with what it is; the last is the
/// disabled one.
const _tileFiles = [
  ('notes.md', '2 KB, an hour ago'),
  ('todo.md', '640 B, today'),
  ('photo.png', '1.2 MB, last week'),
  ('locked.txt', 'no access'),
];

/// The ListTile page: the files, the one tapped open (selected), its parts
/// as the options say.
final class _Tiles extends StatefulWidget {
  const _Tiles({
    required this.leading,
    required this.subtitle,
    required this.trailing,
  });

  final bool leading;
  final bool subtitle;
  final bool trailing;

  @override
  State<_Tiles> createState() => _TilesState();
}

final class _TilesState extends State<_Tiles> {
  // kept in the page's state while the gallery runs
  late final Map<String, Object?> _kept = PageControl.of(context).state;
  int get _open => _kept['open'] as int? ?? 0;
  set _open(int i) => _kept['open'] = i;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, (name, about)) in _tileFiles.indexed)
        ListTile(
          leading: widget.leading ? const Text('▤') : null,
          title: Text(name),
          subtitle: widget.subtitle ? Text(about) : null,
          trailing: widget.trailing ? const Text('›') : null,
          selected: i == _open,
          enabled: i != 3,
          onTap: () => setState(() => _open = i),
        ),
    ],
  );
}
