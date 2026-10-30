# twk reference: `animation`

[The reference](README.md) · `lib/src/animation/`, `test/animation/`

## `Ticker`

`Ticker(onTick, binding:)` calls `onTick` once a frame from `start` to
`stop`, with the time since its first tick: zero at the first, then each
frame's `frameTime` less the first's. Its ticks are the binding's frame
callbacks (`binding`), so the tickers of an app tick in the same frames, at
most `maxFps` a second, and a stopped one asks for no frame and starts no
timer; without a binding it never ticks.

## `TickerProviderStateMixin`

`TickerProviderStateMixin` makes a `State` a `TickerProvider`
(`createTicker`) whose tickers tick in the frames of its app
(`AppBinding.maybeOf`) and are disposed with it.

## `AnimationController`

`AnimationController(vsync:, value:, duration:, reverseDuration:,
lowerBound: 0, upperBound: 1)`, a `ChangeNotifier` and a
`ValueListenable<double>`, runs its `value` to the upper bound
(`forward(from:)`), back to the lower one (`reverse(from:)`), to any value
along a curve (`animateTo(target, duration:, curve: Curves.linear)`), or
round and round (`repeat(reverse:, period:)`), each run of part of the way
taking that share of `duration` (`reverseDuration` back), until `stop`;
`reset`, `isAnimating`; set, `value` stops the run and is clamped to the
bounds; a run with no duration is a `StateError`. Its listeners are told
each frame its value changes in, its status listeners (`addStatusListener`)
when its `status` (`AnimationStatus.dismissed`, `forward`, `reverse`,
`completed`) changes; at the frame whose time is the duration or past it a
run ends at its target and its ticker stops, so a controller that does not
run asks for no frame.

## `Animatable<T>`

`Animatable<T>` maps how far an animation is to a value (`transform(t)`,
`evaluate(animation)`, and `chain(curve)` to run along a curve):
`Tween(begin:, end:)` of doubles (other types override `lerp`), `IntTween`,
rounded, and `ColorTween`, each RGB channel between, or between colors that
are not RGB `begin` until halfway. A `Curve`, an `Animatable<double>`
exactly 0 and 1 at the ends (`flipped` backwards): `Curves.linear`, `ease`,
`easeIn`, `easeOut`, `easeInOut`, `fastOutSlowIn`, `decelerate`, `bounceOut`
and `elasticOut`, `Cubic(a, b, c, d)` as CSS's `cubic-bezier` and
`Interval(begin, end, curve:)`.

## `Spinner`

`Spinner(frames:, style:)` shows the frames of its `SpinnerFrames` in turn
(`dots`, braille, 80 ms each, the default; `line`, ASCII, 130 ms; `arc`, 100
ms; or frames and an `interval` of one's own): the frame of the step of the
app's clock the frame is in, so spinners of the same frames show the same
one and step in the same frames, on one timer, building nothing; as wide as
its widest frame and a row tall.

## `ProgressBar`

`ProgressBar(value:, style:)` is filled from the left as far as `value`,
from 0 to 1, says, in eighths of a cell; while the value is null, a block a
quarter of its width goes from one end to the other and back, a cell each
`ProgressBar.step` (50 ms) of the app's clock, so such bars move together;
as wide as it may be and a row tall; braille stands in for the block
elements where the canvas draws those two columns wide. Both are repaint
boundaries, a step or a new value repainting nothing else, in `style` or the
theme's `primary`, a spinner's merged over the theme's background and text;
outside an app a spinner shows its first frame and a block stays where it
starts. Implicit animations, each with a `duration`, a `curve`
(`Curves.linear`) and `onEnd`, run from the value shown to a new one when
built with it, on the app's clock, and ask for no frame once there:
`AnimatedPadding(padding:)`, `AnimatedAlign(alignment:)` (at the nearest
cell, a half towards the start, so that at rest it is where `Align` puts
it), `AnimatedPositioned(left:, top:, right:, bottom:, width:, height:)` in
a `Stack`, `AnimatedOpacity(opacity:)`, `AnimatedDefaultTextStyle(style:)`,
`AnimatedBox(style:, border:, titles:, padding:, width:, height:)` (the
border's type switching halfway), `AnimatedSize(duration:, curve:,
alignment:)`, from the size shown to its child's, the child cut off
meanwhile, and `TweenAnimationBuilder<T>(value:, from:, tween:, builder:)`,
whose `tween` is a constructor (`EdgeInsetsTween.new`), since a `Tween` here
is immutable. One of an app's own extends `ImplicitlyAnimatedWidget`, its
state `ImplicitlyAnimatedWidgetState`, whose `forEachTween(visitor)` gives
each of its tweens (a `TweenVisitor` of `TweenConstructor`s), started again
from the value shown on a new target, and whose `progress` is how far the
run is along its curve.

## `EdgeInsetsTween`

`EdgeInsetsTween`;

## `StyleTween`

`StyleTween`, the colors mixed as by `ColorTween` and their alpha between, a
color set on one side only fading in or out through alpha, the attributes
switching halfway.

## `AnimatedSwitcher`

`AnimatedSwitcher(duration:, reverseDuration:, switchInCurve:,
switchOutCurve:, transition: SwitcherTransition.fade, alignment:
Alignment.topLeft, child:)` shows a child that does not update the one
before (of another type, or with another key) come in over it as the old one
goes out: `SwitcherTransition.fade`, `slide(from: Alignment.centerRight)`,
`dissolve`, or one of an app's own (`build(child, shown, entering:)`); the
first child shows at once. Under them, `Opacity(opacity:)` mixes its child
with what is under it cell by cell (the backgrounds blended, the child's
text over the other's from half on, text in a default color not known yet
faint; what a repaint boundary inside repaints on its own mixed again; at 0
the child is not painted), `Dissolve(shown:, inverse:)` shows a scattered
share of the child's cells (`inverse` exactly the others) and
`FractionalTranslation(x:, y:)` moves its child by fractions of its size. In
a test, the first frame after a change builds with it, the old value shown,
and the run starts at the next.

## `Effect`

`Effect(effect:, onEnd:, child:)` shows its child through a `CellEffect`, a
function over the cells of the child's rectangle of what the child painted
in each and what was under it, run from its start to its end in its
`duration` on the app's clock when first built and again when given an
effect not equal to the one it had (or a new key), `onEnd` as a run ends; it
asks for frames only while it runs, the effect staying as it is at its end
(one of no duration shown at once). The child repaints normally underneath;
a frame of the effect paints neither the child nor what is under it (the
core's `RenderEffect`). Effects, each with a `duration` and a `curve`:
`CellEffect.grade(map, amount:)`, `tint(color, amount:)`, `dim(amount:)`,
`desaturate(amount:)` and `scanlines(amount:)`, run from none of their
amount to all; `sweep(from:, edge:)`, `dissolve()` and
`typewriter(cursor:)`, showing more of the child as they run;
`glitch(amount:, seed:)`, fewer cells scattered until none. They compose:
`CellEffect.sequence([…])`, one after another, `CellEffect.parallel([…])`,
at once, `reversed` (a dissolve out) and `delayed(delay)`; an app's own
extends `CellEffect`, whose `at(elapsed)` gives a `CellFilter` that sets the
`glyph` and the `style` of each `EffectCell` (`childGlyph`, `childStyle`,
`underGlyph`, `underStyle`, `showUnder()`).

## `AnimatedBuilder`

`AnimatedBuilder(animation:, builder:, child:)` is Flutter's name for a
`ListenableBuilder` (`foundation`) over an animation, so Flutter code that
builds on one ports as it is. `example/files.dart` copies a slice of a file
a frame on a `Ticker`, so frames and keys keep coming while it works.

## `Skeletonize`

`Skeletonize(enabled:, child:, shimmer: true)` shows its child as a skeleton
while `enabled`, laid out as it is, so the layout is the real one: each cell
that shows something becomes the `SkeletonTheme`'s glyph in its muted color,
the blanks left as they are; meanwhile the mouse passes the child by, its
focus nodes take no focus and a screen reader reads `loading`. Turned off,
the child shows, its state kept.

## `Skeleton`

`Skeleton(width:, height: 1, style:)` is a block of such cells where content
will be (as wide as it may be when `width` is null), `Skeleton.text(lines:
1, lastLine: 0.6, style:)` lines of text, the last shorter. With `shimmer`,
a band of brighter cells sweeps over them from left to right, stepped by
`Skeletonize.step` (50 ms) on the app's clock, every skeleton on the screen
in the same frames on one timer; there is none on plain output, in the
screen-reader mode or where the theme's colors are not RGB
(`ThemeData.terminal`), and the app asks for no frame while nothing
shimmers.

## `SkeletonTheme`

`SkeletonTheme(period: 1500 ms, glyph: '░', style:, highlight:, band: 8,
child:)` says how they look below it.

## `ProgressTracker`

`ProgressTracker(rateWindow: 5 s, clock:)` holds tasks going on at once,
added and removed as they come, each a `ProgressTask`: `add(label, total:,
unit: ProgressUnit.count)` adds one, pending (of an amount not known while
`total` is null), and `run(label, body, total:, unit:)` adds one, sets it
going and runs `body(task)`, the task done when it returns and failed with
what it throws, which is thrown again. A task is set going by `start`,
`advance([by])` or `update(completed)` and finished once by `done([label])`,
`fail([error])` or `skip()`; it gives its `fraction`, `rate` (over the last
`rateWindow`), `eta`, `elapsed` and a line of text, `summary` (`✓
Downloading assets.zip • 3.4/3.4 MB • 2.1 s`). The tracker's listeners are
told when a task comes, goes, starts or ends, or its label or total changes,
not at each `advance`; `onTaskFinished` streams each task as it ends; its
times are read on the `clock` it is constructed with, else on a stopwatch of
its own, for its whole life, nothing replacing it: an app hands it the
app's, `ProgressTracker(clock: AppBinding.of(context).twkApp.clock)`, so a
test's fake clock moves them.

## `ProgressList`

`ProgressList(tracker:, columns: ProgressList.defaultColumns, hideFinished:
false, maxVisible:, spinner: SpinnerFrames.dots)` shows the tasks a row each
in the `ProgressColumn`s given (`mark`, `label`, `bar`, `percent`, `count`,
`rate`, `eta`, `elapsed`; all but `count` and `elapsed` by default): the
mark of the task's `TaskStatus` as a `TaskList` shows it, its label, a bar
as a `ProgressBar` draws it, sweeping while the task runs without a total,
then `62%`, `1.2 MB/s` (`ProgressUnit.bytes` in their units) and `ETA
00:04`. The columns line up across the rows, each as wide as its widest
cell, the amounts right-aligned, and one empty in every row takes no room;
where a row is short the labels are cut off first, then, at 8 cells of
label, the bar narrows and goes, then the columns after it from the last.
`hideFinished` leaves out the tasks done or skipped, the failed ones still
shown; `maxVisible` shows at most that many rows, the running ones first,
and `+3 more` for the rest. It is built again when the tracker tells its
listeners, and repaints at the steps of `spinner` while a task it shows
runs, so a million `advance` calls a second cost a frame a step; a repaint
boundary, read by a screen reader as a list of progress bars (`progressbar
Downloading assets.zip: 62%`)
