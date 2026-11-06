---
title: "Performance"
about: "What a frame costs, what already costs nothing, and the few things worth doing when an app is slow."
order: 11
---
# Performance

Most apps need nothing on this page. A frame builds only what `setState`
marked, lays out only what changed, paints only what changed and writes
only the cells that differ from the screen. Measure before you change
anything: the sections below say what twk does by itself, what you can
narrow, and the one option that is a trade.

Where a figure is quoted it comes from the performance
survey unless it says otherwise: Dart AOT,
200 x 60 cells, the core's frame benchmark (`tool/bench.dart` in the
repository, run with `dart run tool/xtask.dart bench`). They are the
microseconds one frame costs, not what an app feels like; a 60 Hz frame is
16 600 of them.

## What costs nothing

- **A still app runs no frame.** A frame is requested by a `setState`, a
  notifying listenable, a ticker or an input event. When nothing asks,
  nothing runs; the benchmark's `idle` frame, when one does run, writes no
  bytes and takes 0.27 us.
- **At most `maxFps` frames a second, 60 by default.** Frames asked for
  sooner than that gap after the last one wait for it and are one frame;
  several `setState` calls between two frames make one build. `runApp`
  takes `maxFps` if you want fewer. Updating a state a thousand times a
  second therefore costs a thousand cheap state changes and sixty frames.
- **Tickers stop when idle.** An animation (`Spinner`, an `AnimationController`)
  has the app run frames while it moves and not after. A `Spinner` repaints
  its own cells and builds nothing.
- **Lazy lists are lazy.** A `ListView.builder` and a `Table` over a data
  source build the rows in view: a list of 100 000 items costs what the
  rows on the screen cost (the benchmark scrolls one at 8 us a frame). A
  `Column` of 10 000 children paints only those its clip shows, about 4 us
  a frame when it scrolls a row. A `Column` of children is still all
  built, so for a long list use the builder.
- **The terminal sees only what changed.** The presenter compares the frame
  with the screen and writes the difference; a typed character is about 17
  bytes. You do not need a repaint boundary, a double buffer or a dirty
  flag for that.

## Say what changed

A build runs when its state is marked, and rebuilds every widget it
returns that is not the same object as before. Two things keep that small.

A `const` widget is the same object each time, and an element whose widget
is identical to its new one is not updated at all
(`Element.updateChild` in `framework.dart` skips `update` for an identical
widget). So a `const Text('title')` among a screenful costs nothing in a
rebuild of its parent. This is the same as in Flutter, and so is putting
the state low: a `setState` high in the tree builds everything under it
that is not `const`.

The second is a listenable. A `ValueListenableBuilder` or
`ListenableBuilder` builds only what its builder returns, and its `child`
is built once and handed back:

<!-- file: packages/twk/example/guides/perf_listen.dart -->
```dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Dashboard());

final class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

final class _DashboardState extends State<Dashboard> {
  final ValueNotifier<int> _count = ValueNotifier(0);

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      '+': () => _count.value++,
      'q': () => AppBinding.of(context).quit(),
    },
    child: Focus(
      autofocus: true,
      child: ValueListenableBuilder<int>(
        valueListenable: _count,
        child: const Text('+ counts, q quits'),
        builder: (context, count, hint) => Column(
          children: [Text('count: $count'), hint!],
        ),
      ),
    ),
  );
}
```

Pressing `+` builds the `Column` and the `Text` of the count; `Dashboard`
is not built again. The [state guide](state.md) has the other ways to hold
state, and they build the same way: the widgets that read a value are the
ones that rebuild.

A build is cheap, though. The survey's `tree` scenario changes one text
among rows of six and a frame takes 2.1 us; most of the cost of a frame is
painting and writing, which only the rows that changed pay. Narrow a
rebuild when a profile shows builds, not by habit.

## A part that changes often

A `RepaintBoundary` makes its child repaint alone, over what was under it,
and keeps what is around it from being painted again with it. A clock, a
counter or a log under one does not repaint the screen with it. The
survey's `repaint-all` scenario, which repaints every object when the
spinner changes, takes 26.8 us a frame against 1.0 us for `spinner`.

A `Spinner` is one already. Before you add one, run with
`TWK_DEBUG=rainbow` (the [getting started](getting-started.md) page has
the debug aids): it tints what repaints, and a region that flashes when
it should not is where one goes.

## A long text edited one row at a time

A `Text` of eight rows or more, edited a few times without changing its
size (a checklist, a log you edit, a rendered document), keeps what it
painted by itself and from then on repaints only the rows that differ.
There is nothing to set, and a text that lies over another object's text
stays as it was, as does a short or a still one: it reads the cells under
it before it turns, and turns back if a glyph comes there.

It is a small gain. In the benchmark's mixed-script paragraph over most of
the screen, a word typed into it takes 56.8 us a frame plain and 20 us kept
(the `wrap` scenario, pinned, on an idle machine), against a frame budget
of 16 600 us. The bytes written are the same, 311.6 a frame
in both.

A render object of your own has `RenderParagraph.keepsPaint` to force it,
and its contract in the doc comment.

## Streams and logs

- `MarkdownView(data, appended: piece)` checks the length and the end of
  the text instead of comparing all of it (0.13 us at 50 KB), so a streamed
  answer costs the piece, not the answer. Without `appended` the whole text
  is compared. `MarkdownStream` keeps the blocks that are settled.
- A `LogView` holds at most `maxLines` of a `LogController` (10 000 by
  default). At its cap each new line moves every index, so the window
  repaints each frame: the survey's `log-append` allocates the most of the
  apps measured, 27 KB a line. A smaller cap is cheaper, and a log nobody
  reads past the last screen does not need 10 000.

## Measure

- `TWK_DEBUG=overlay` shows each frame's times and bytes in the app.
- For a change to twk itself, `dart run tool/xtask.dart bench` runs the
  frame benchmark against a commit and fails on more bytes or a slowdown;
  `tool/alloc` counts allocations. Both are in the repository, not in the
  package. A benchmark's times count only when the core it is pinned to
  has an idle sibling; a busy machine moves them by tens of percent, as the
  figures above did.

## Habits from Flutter that do not carry over

- **A deep widget tree is not the worry.** A build is a few microseconds,
  and the survey found no scenario where depth sorting of the dirty lists
  or the focus traversal showed in a sample.
- **`GC` is not where the time goes.** No benchmark scenario ran an
  old-space collection, and the longest scavenge was 4.8 ms. Allocation
  costs where it happens, which the profiles count.
- **There is no 60 fps to hit by hand.** The frame rate is a cap
  (`maxFps`), not a target: an app that changes nothing runs no frames.

[Coming from Flutter](coming-from-flutter.md) lists the rest of what
differs.
