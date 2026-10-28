// The Foundation, Framework, App, Screen readers and Debugging pages: each
// builds at both sizes, its options apply and its keys do what the
// design's do.
import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] in a terminal of [size], a frame for the
/// route's focus after the first.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
}) async {
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(route)), size: size);
  await t.pump();
}

/// Presses [keys] (apart by commas), a frame after each.
Future<void> keys(TwkTester t, String keys) async {
  for (final k in keys.split(',')) {
    await t.press(k);
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 500));
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// Each page's route and a text its stage shows.
const _pages = {
  'foundation/listenablebuilder': 'ValueListenableBuilder: 2',
  'foundation/futurebuilder-streambuilder': 'future: not started',
  'framework/layoutbuilder': '40×8: wide',
  'framework/notificationlistener': 'nothing yet',
  'framework/slot-slotscope': 'git main',
  'screen-readers/semantics': 'A screen reader reads:',
  'app/inputlistener': 'Press a key nothing takes, such as x',
  'app/errorwidget': 'Bad state: the',
  'app/static': '✓ resolved 42 packages',
  'app/terminalprogress': 'In the tab: normal, 33%',
  'app/viewport': 'testing…',
  'app/window-title': 'In the title bar: twk gallery',
  'app/notifications': 'notified: nothing',
  'debugging/console': 'The app, under its console.',
  'debugging/frameoverlay': 'cells compared',
  'debugging/repaint-rainbow': 'syncing',
};

/// What a page logs by design: the ErrorWidget page's weather throws.
bool _expected(String page, String problem) =>
    page == 'app/errorwidget' && problem.contains('_Weather failed to build');

void main() {
  group('each page builds', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final MapEntry(key: page, value: shows) in _pages.entries) {
        testTwk('$page at ${size.$1}x${size.$2}', (t) async {
          await open(t, '#/$page?t=2000', size: size);
          expect(screen(t), contains(shows));
          expect(screen(t), isNot(contains('drawn in the next part')));
          expect([
            for (final p in problems(t))
              if (!_expected(page, p)) p,
          ], isEmpty);
        });
      }
    }
  });

  group('the options apply', () {
    testTwk('ListenableBuilder without the timer', (t) async {
      await open(t, '#/foundation/listenablebuilder?t=2000&o=timer:false');
      expect(screen(t), contains('ListenableBuilder: 0'));
    });

    testTwk('FutureBuilder with take(5), done', (t) async {
      await open(
        t,
        '#/foundation/futurebuilder-streambuilder?t=7000&o=take:take(5)',
      );
      await t.pump();
      expect(screen(t), contains('stream: 5 s'));
      expect(screen(t), contains('done'));
    });

    testTwk('LayoutBuilder narrow', (t) async {
      await open(t, '#/framework/layoutbuilder?t=2000&o=width:20');
      expect(screen(t), contains('20×8: narrow'));
    });

    testTwk('NotificationListener hearing overscrolls', (t) async {
      await open(
        t,
        '#/framework/notificationlistener?t=2000&o=outer:Overscroll',
      );
      expect(screen(t), contains('outer OverscrollNotification'));
    });

    testTwk('Slot without a placeholder, lint last', (t) async {
      await open(
        t,
        '#/framework/slot-slotscope?t=2000&o=placeholder:false;lint:3, last',
      );
      expect(screen(t), contains('git main  words 120'));
    });

    testTwk('ErrorWidget: the weather that does not fail', (t) async {
      await open(t, '#/app/errorwidget?t=2000&o=fails:false');
      expect(screen(t), contains('12°C'));
      expect(screen(t), isNot(contains('Bad state')));
      expect(problems(t), isEmpty);
    });

    testTwk('Static on the alternate screen', (t) async {
      await open(t, '#/app/static?t=2000&o=mode:fullscreen');
      expect(screen(t), contains('alternate screen'));
      expect(screen(t), isNot(contains('git pull')));
    });

    testTwk('TerminalProgress where the terminal shows none', (t) async {
      await open(t, '#/app/terminalprogress?t=2000&o=shows:false');
      expect(screen(t), contains('wrote: nothing'));
    });

    testTwk('Viewport on the alternate screen', (t) async {
      await open(t, '#/app/viewport?t=2000&o=mode:fullscreen');
      expect(screen(t), contains('alternate screen'));
      expect(screen(t), isNot(contains('67bc09f')));
    });

    testTwk('Window title once the app ended', (t) async {
      await open(t, '#/app/window-title?t=2000&o=running:false');
      expect(screen(t), contains('user@twk: ~/twk'));
      expect(screen(t), isNot(contains('In the title bar')));
    });

    testTwk('Console from warnings up, 4 rows', (t) async {
      await open(t, '#/debugging/console?t=2000&o=level:warning;rows:4');
      expect(screen(t), contains('warning+'));
      expect(screen(t), isNot(contains('GET /api')));
    });

    testTwk('FrameOverlay off', (t) async {
      await open(t, '#/debugging/frameoverlay?t=2000&o=overlay:false');
      expect(screen(t), contains('syncing'));
      expect(screen(t), isNot(contains('cells compared')));
    });

    testTwk('Semantics read out', (t) async {
      await open(
        t,
        '#/screen-readers/semantics?t=2000&o=view:TWK_SCREEN_READER=1',
      );
      await t.pump();
      expect(screen(t), contains('checkbox Remember me, not checked'));
      expect(screen(t), isNot(contains('A screen reader reads:')));
    });
  });

  group('the keys do what the design says', () {
    testTwk('Count counts, Reset resets', (t) async {
      await open(t, '#/foundation/listenablebuilder?t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('ListenableBuilder: 3'));
      await keys(t, 'tab,enter');
      expect(screen(t), contains('ListenableBuilder: 0'));
    });

    testTwk('Load fails with an error', (t) async {
      await open(
        t,
        '#/foundation/futurebuilder-streambuilder?t=2000&o=outcome:error',
      );
      await keys(t, 'tab,enter');
      expect(screen(t), contains('future: Exception: offline'));
    });

    testTwk('the list scrolls, the outer listener hears it', (t) async {
      await open(t, '#/framework/notificationlistener?t=2000');
      await keys(t, 'tab,down,down');
      expect(screen(t), contains('scrolled 1 to 2 of 94'));
    });

    testTwk('the inner listener stops them', (t) async {
      await open(
        t,
        '#/framework/notificationlistener?t=2000&o=stops:true',
      );
      await keys(t, 'tab,down');
      expect(screen(t), contains('heard: nothing'));
      expect(screen(t), contains('stops'));
    });

    testTwk('a plugin turned on shows in the slot', (t) async {
      await open(t, '#/framework/slot-slotscope?t=2000');
      await keys(t, 'tab,tab,space');
      expect(screen(t), contains('git main  lint 0 problems  words 120'));
    });

    testTwk('the InputListener hears what no widget took', (t) async {
      await open(t, '#/app/inputlistener?t=2000');
      await keys(t, 'tab,x,ctrl+a,pagedown');
      expect(screen(t), contains('key    x'));
      expect(screen(t), contains('key    ctrl+a'));
      expect(screen(t), contains('key    pageDown'));
    });

    testTwk('Clear clears what the InputListener heard', (t) async {
      await open(t, '#/app/inputlistener?t=2000');
      await keys(t, 'tab,x,enter');
      expect(screen(t), contains('nothing yet'));
    });

    testTwk('Notify notifies, the desktop shows it', (t) async {
      await open(t, '#/app/notifications?t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('notified: 1'));
      expect(screen(t), contains('Build finished'));
    });

    testTwk('xterm shows no notification', (t) async {
      await open(t, '#/app/notifications?t=2000&o=terminal:xterm');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('notified: 1'));
      expect(screen(t), isNot(contains('Build finished')));
    });

    testTwk('Info logs to the console', (t) async {
      await open(t, '#/debugging/console?t=2000&o=live:false');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('all is well'));
    });

    testTwk('Ctrl+G shows the commands, o hides the overlay', (t) async {
      await open(t, '#/debugging/frameoverlay?t=2000');
      await keys(t, 'tab,ctrl+g');
      expect(screen(t), contains('ctrl+g'));
      expect(screen(t), contains('o overlay'));
      await keys(t, 'o');
      expect(screen(t), isNot(contains('cells compared')));
    });

    testTwk('space pauses the Sync', (t) async {
      await open(t, '#/debugging/repaint-rainbow?t=2000');
      await keys(t, 'tab,space');
      expect(screen(t), contains('paused'));
    });

    testTwk('More moves the upload, read out', (t) async {
      await open(t, '#/screen-readers/semantics?t=2000');
      await keys(t, 'tab,tab,tab,enter');
      expect(screen(t), contains('progressbar Upload: 50%'));
    });
  });
}
