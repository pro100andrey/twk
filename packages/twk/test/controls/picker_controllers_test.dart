// The controllers of the pickers: a PopupController opening and closing
// the list of a Select and a MultiSelect and the calendar of a
// DatePicker from outside, told of their own keys; a FilePickerController
// reading the directory, the entry highlighted and the files marked, going
// to a directory and listing it again.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pumpUntilIdle();
  }
}

/// Pumps, the futures of the file system answering meanwhile, until
/// [done].
Future<void> until(TwkTester t, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
    await t.pump();
  }
  expect(done(), isTrue, reason: 'nothing came:\n${t.lines.join('\n')}');
}

const List<Choice<String>> fruit = [
  Choice('a', 'Apple'),
  Choice('b', 'Banana'),
  Choice('d', 'Date'),
];

/// [child] above a node `next`, which has the focus at first, in an
/// overlay.
Widget app(Widget child) => Overlay(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      child,
      const Focus(debugLabel: 'next', autofocus: true, child: Text('next')),
    ],
  ),
);

PopupController popup() {
  final controller = PopupController();
  addTearDown(controller.dispose);
  return controller;
}

FocusNode node(String label) {
  final node = FocusNode(debugLabel: label);
  addTearDown(node.dispose);
  return node;
}

/// How many times [listenable] tells its listeners, from now on.
List<int> count(Listenable listenable) {
  final calls = [0];
  void listener() => calls[0]++;
  listenable.addListener(listener);
  addTearDown(() => listenable.removeListener(listener));
  return calls;
}

/// A file system whose tree [files] is, changed as the test goes; while
/// [hold] is given, a directory lists once it completes.
final class Changing implements PickerFileSystem {
  Changing(this.files);

  PickerFileSystem files;
  Completer<void>? hold;

  @override
  String get currentDirectory => files.currentDirectory;

  @override
  String? get homeDirectory => files.homeDirectory;

  @override
  Stream<DirectoryEntry> list(String directory) {
    final files = this.files;
    return switch (hold) {
      final hold? => Stream.fromFuture(
        hold.future,
      ).asyncExpand((_) => files.list(directory)),
      null => files.list(directory),
    };
  }

  @override
  FileKind kindOf(String path) => files.kindOf(path);

  @override
  Future<String> read(String file) => files.read(file);

  @override
  Future<int?> sizeOf(String file) => files.sizeOf(file);

  @override
  Stream<void> watch(String directory) => files.watch(directory);
}

void main() {
  group('PopupController', () {
    testTwk('opens and closes a Select from outside, the field focused; '
        'told of the list its keys open and close', (t) async {
      final controller = popup();
      final calls = count(controller);
      String? chosen;
      await t.pumpWidget(
        app(
          Select<String>(
            choices: fruit,
            value: null,
            onChanged: (v) => chosen = v,
            controller: controller,
            focusNode: node('select'),
          ),
        ),
        size: (20, 8),
      );
      expect(controller.isOpen, isFalse);
      expect(focused(t), 'next');
      controller.open();
      await t.pumpUntilIdle();
      expect(controller.isOpen, isTrue);
      expect(focused(t), 'select');
      expect(t.lines.sublist(1, 4), ['▎Apple', ' Banana', ' Date']);
      controller.close();
      await t.pumpUntilIdle();
      expect(controller.isOpen, isFalse);
      expect(t.lines[1], 'next');
      expect(calls[0], 2);
      // its own keys: Enter opens, Down and Enter choose and close
      await press(t, 'enter');
      expect(controller.isOpen, isTrue);
      await press(t, 'down enter');
      expect(chosen, 'b');
      expect(controller.isOpen, isFalse);
      await press(t, 'enter escape');
      expect(controller.isOpen, isFalse);
      expect(calls[0], 6);
    });

    testTwk('opens a MultiSelect; a disabled Select stays closed', (t) async {
      final multi = popup();
      final disabled = popup();
      await t.pumpWidget(
        app(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MultiSelect<String>(
                choices: fruit,
                values: const {'a'},
                onChanged: (_) {},
                controller: multi,
              ),
              Select<String>(
                choices: fruit,
                value: null,
                onChanged: null,
                controller: disabled,
                focusNode: node('disabled'),
              ),
            ],
          ),
        ),
        size: (24, 8),
      );
      disabled.open();
      await t.pumpUntilIdle();
      expect(disabled.isOpen, isFalse);
      expect(focused(t), 'next');
      multi.open();
      await t.pumpUntilIdle();
      expect(t.lines[1], contains('[x] Apple'));
      await press(t, 'escape');
      expect(multi.isOpen, isFalse);
    });

    testTwk('built open, a Select opens', (t) async {
      final controller = popup()..open();
      await t.pumpWidget(
        app(
          Select<String>(
            choices: fruit,
            value: null,
            onChanged: (_) {},
            controller: controller,
          ),
        ),
        size: (20, 8),
      );
      await t.pumpUntilIdle();
      expect(t.lines[1], '▎Apple');
    });

    testTwk('opens and closes the calendar of a DatePicker from outside, '
        'the calendar focused, the field after; told of Escape closing it', (
      t,
    ) async {
      final controller = popup();
      final calls = count(controller);
      DateTime? picked;
      await t.pumpWidget(
        app(
          SizedBox(
            width: 16,
            child: DatePicker(
              value: DateTime(2026, 10, 19),
              onChanged: (d) => picked = d,
              controller: controller,
              focusNode: node('date'),
            ),
          ),
        ),
        size: (30, 12),
      );
      controller.open();
      await t.pumpUntilIdle();
      expect(t.lines.join('\n'), contains('October 2026'));
      expect(focused(t), isNot(anyOf('next', 'date')));
      controller.close();
      await t.pumpUntilIdle();
      expect(t.lines.join('\n'), isNot(contains('October 2026')));
      expect(focused(t), 'date');
      expect(calls[0], 2);
      // its own keys: Alt+Down opens, Escape closes, Enter picks
      await press(t, 'alt+down');
      expect(controller.isOpen, isTrue);
      await press(t, 'escape');
      expect(controller.isOpen, isFalse);
      controller.open();
      await t.pumpUntilIdle();
      await press(t, 'right enter');
      expect(picked, DateTime(2026, 10, 20));
      expect(controller.isOpen, isFalse);
      expect(calls[0], 6);
    });

    testTwk('a DatePicker given a controller that is open opens its '
        'calendar on the month of its date', (t) async {
      final controller = popup()..open();
      Widget picker(PopupController? c) => app(
        SizedBox(
          width: 16,
          child: DatePicker(
            value: DateTime(2020, 3, 9),
            today: DateTime(2026, 10, 19),
            onChanged: (_) {},
            controller: c,
          ),
        ),
      );
      await t.pumpWidget(picker(null), size: (30, 12));
      await t.pumpUntilIdle();
      expect(t.lines.join('\n'), isNot(contains('March 2020')));
      await t.pumpWidget(picker(controller));
      await t.pumpUntilIdle();
      expect(t.lines.join('\n'), contains('March 2020'));
    });

    testTwk('a disabled DatePicker stays closed', (t) async {
      final controller = popup();
      await t.pumpWidget(
        app(
          SizedBox(
            width: 16,
            child: DatePicker(
              value: null,
              onChanged: null,
              controller: controller,
            ),
          ),
        ),
        size: (30, 12),
      );
      controller.open();
      await t.pumpUntilIdle();
      expect(controller.isOpen, isFalse);
      expect(t.lines.join('\n'), isNot(contains('2026')));
    });
  });

  group('FilePickerController', () {
    final files = PickerFileSystem.memory(
      [
        '/home/docs/b.md',
        '/home/docs/c.md',
        '/home/a.txt',
        '/home/z.txt',
        '/srv/',
      ],
      currentDirectory: '/home',
      homeDirectory: '/home',
    );

    FilePickerController controller() {
      final controller = FilePickerController();
      addTearDown(controller.dispose);
      return controller;
    }

    Widget picker(
      FilePickerController controller, {
      bool multiple = false,
      PickerFileSystem? fileSystem,
    }) => Overlay(
      child: FilePicker(
        onPicked: (_) {},
        controller: controller,
        fileSystem: fileSystem ?? files,
        multiple: multiple,
        name: 'new',
      ),
    );

    testTwk('reads the directory and the entry highlighted, told as the '
        'keys move them; goTo goes to a directory, or to a file in one', (
      t,
    ) async {
      final c = controller();
      final calls = count(c);
      expect(c.directory, isNull);
      await t.pumpWidget(picker(c), size: (30, 10));
      await until(t, () => c.highlighted != null);
      expect(c.directory, '/home');
      expect(c.highlighted, '/home/docs');
      expect(calls[0], greaterThan(0));
      final before = calls[0];
      t.binding.focusManager.primaryFocus?.unfocus();
      await press(t, 'tab tab down');
      expect(c.highlighted, '/home/a.txt');
      expect(calls[0], greaterThan(before));
      c.goTo('docs');
      await until(t, () => c.highlighted != null);
      expect(c.directory, '/home/docs');
      expect(c.highlighted, '/home/docs/b.md');
      // the name typed is kept
      expect(t.lines.first, startsWith('/home/docs/new'));
      c.goTo('~/z.txt');
      await until(t, () => c.highlighted != null);
      expect(c.directory, '/home');
      expect(c.highlighted, '/home/z.txt');
      c.goTo('/nowhere');
      await until(t, () => t.lines.any((l) => l.contains('cannot list')));
      expect(c.directory, '/nowhere');
    });

    testTwk('goTo before the picker has it is where the picker starts', (
      t,
    ) async {
      final c = controller()..goTo('/srv');
      await t.pumpWidget(picker(c), size: (30, 10));
      expect(c.directory, '/srv');
      expect(t.lines.first, startsWith('/srv/new'));
    });

    testTwk('goTo a file before the picker has it starts in its directory, '
        'the cursor on it', (t) async {
      final c = controller()..goTo('~/z.txt');
      await t.pumpWidget(picker(c), size: (30, 10));
      await until(t, () => c.highlighted != null);
      expect(c.directory, '/home');
      expect(c.highlighted, '/home/z.txt');
    });

    testTwk('a picker built in place of the one that had it takes it over, '
        'the new one starting before the old one is gone', (t) async {
      final c = controller();
      Widget keyed(FilePickerMode mode) => Overlay(
        child: FilePicker(
          key: ValueKey(mode),
          onPicked: (_) {},
          controller: c,
          fileSystem: files,
          mode: mode,
        ),
      );
      await t.pumpWidget(keyed(FilePickerMode.open), size: (30, 10));
      await until(t, () => c.highlighted != null);
      c.goTo('docs');
      await until(t, () => c.highlighted != null);
      expect(c.directory, '/home/docs');
      await t.pumpWidget(keyed(FilePickerMode.save), size: (30, 10));
      await until(t, () => c.highlighted != null);
      expect(c.directory, '/home', reason: 'the new picker, where it starts');
      c.goTo('/srv');
      await t.pump();
      expect(c.directory, '/srv');
      expect(t.lines.first, startsWith('/srv/'));
    });

    testTwk('selected: the files marked, in order; refresh lists the '
        'directory again, keeping the cursor', (t) async {
      final c = controller();
      final changing = Changing(files);
      await t.pumpWidget(
        picker(c, multiple: true, fileSystem: changing),
        size: (30, 10),
      );
      await until(t, () => c.highlighted != null);
      expect(c.selected, isEmpty);
      t.binding.focusManager.primaryFocus?.unfocus();
      await press(t, 'tab tab end space up space');
      expect(c.selected, ['/home/z.txt', '/home/a.txt']);
      expect(() => c.selected.add('x'), throwsUnsupportedError);
      changing.files = PickerFileSystem.memory(
        ['/home/a.txt', '/home/b.txt', '/home/z.txt'],
        currentDirectory: '/home',
      );
      await t.pump();
      expect(t.lines.any((l) => l.contains('b.txt')), isFalse);
      final hold = changing.hold = Completer<void>();
      c.refresh();
      await Future<void>.delayed(Duration.zero);
      await t.pump();
      // what it listed shows meanwhile
      expect(t.lines.any((l) => l.contains('listing')), isFalse);
      expect(t.lines.any((l) => l.contains('docs')), isTrue);
      hold.complete();
      await until(t, () => t.lines.any((l) => l.contains('b.txt')));
      expect(t.lines.any((l) => l.contains('docs')), isFalse);
      expect(c.highlighted, '/home/a.txt');
      expect(c.directory, '/home');
    });
  });
}
