# gallery

The twk gallery: every widget of `twk`, `twk_rich` (its
`package:twk_rich/image.dart` too) and `twk_term` on a page of its own, live, with its options and the Dart that
builds it, and a run of a program on twk's console as a terminal shows it. It is its own design: how it looks and why, and the rules a
page keeps, are in [doc/design.md](doc/design.md); how every page looks
is held by its golden screens (below).

| Dark, 120×36 | Light, 120×36 |
| --- | --- |
| ![The Table page in the dark theme](doc/shots/screens/table-dark.svg) | ![The Text page in the light theme](doc/shots/screens/text-light.svg) |

## Running it

```bash
dart run packages/gallery/bin/gallery.dart
# where a route says: a page, a theme, options, the Code tab
dart run packages/gallery/bin/gallery.dart --route='#/controls/button?theme=light'
dart run packages/gallery/bin/gallery.dart --route='#/text/text?o=wrap:none;width:40&tab=code'
```

In a browser, on xterm.js through twk_web (WebAssembly GC: Chrome and
Edge 137, Firefox 134, Safari 26.2 or later), the URL's hash its route:

```bash
cd packages/gallery
dart compile wasm web/main.dart -o web/main.wasm
python3 -m http.server -d web 8080   # http://localhost:8080/#/controls/button?theme=light
```

Every page works there but App › Cli, whose stage says that a console
program needs a terminal: the console reads and writes the process's stdio
through dart:io, so the page's stage is imported in its place on the web
(`lib/src/pages/cli_stage_web.dart` for `cli_stage.dart`). The Images
page's pictures are in the program
(`lib/src/pages/pictures.dart`, the files of `lib/src/pages/assets/` as
bytes, which `test/assets_test.dart` holds to them), the Terminal page's
shell is scripted, and nothing the build reads imports dart:io
(`dart run tool/web_check.dart gallery` from the root compiles it, looks,
and runs it through every page on a stand-in for xterm.js, failing where
one shows an error).

Ctrl+C quits. The keys:

| Where | Keys |
| --- | --- |
| the list | `up` `down` `home` `end` `pageup` `pagedown` choose a page; `enter`, `right`, `tab` into the page |
| the page | `tab`, `shift+tab` go through its widgets, then its options; `esc` back to the list |
| an option | `left` `right` choose or step; `space` flips a switch; `home` `end`; `up` `down` the option above or below |
| the code | `up` `down` `left` `right` `pageup` `pagedown` scroll; `y` copies (OSC 52) |
| the palette | `up` `down` go round; `enter` runs; `esc` closes |
| anywhere | `ctrl+p` the palette; `/` the filter; `c` Code or Preview; `t` the next theme (`T` back) |

A key the focused widget takes is the page's: the gallery's own act only
when no widget took them. The list's keys are bound in a hinted
`KeyBindings` layer around it, so that `FocusManager.activeKeys` lists
them, as a `KeyHintsBar` on the stage shows; the page's Tab, Shift+Tab and
Escape are not, so that Tab reaches the page's `InputListener`s first and a
page's own `KeyHintsBar` lists its keys alone.

## Routes

`--route` takes a route, a URL hash, with or without the `#`: `#/<group>/<page>?<parameters>`, group and page in
lower case with dashes.

| Parameter | |
| --- | --- |
| `theme=` | `dark` (the default), `light`, `nord`, `mocha`, `latte`, `terminal` (the terminal's own colors, `ThemeData.terminal` of its brightness) |
| `tab=code` | the Code tab |
| `o=key:value;…` | the options, each value as the inspector names it |
| `t=` | the clock stopped at this many milliseconds: the shell's motions at their end, toasts staying, a page that moves with time at that moment |
| `focus=` | `list`, `filter`, `page`, `code`, or `o:<key>` an option |
| `filter=` | the list's filter |
| `palette=` | the palette open with this query |
| `toast=`, `kind=` | a toast, of `info`, `success`, `warning` or `error` |
| `keys=` | keys pressed once it shows, comma-separated twk names (`comma` for a comma) |
| `type=` | characters typed after them |

`size=` and `bare=` are read and mean nothing: the terminal's size is the
grid.

For a headless run, as a test does:

```dart
import 'package:gallery/gallery.dart';
import 'package:twk_test/twk_test.dart';

testTwk('the Button page, light', (t) async {
  await t.pumpWidget(
    galleryApp(route: GalleryRoute.parse('#/controls/button?theme=light&t=2000')),
    size: (120, 36),
  );
  await t.pump();
  print(t.lines.join('\n'));
});
```

`galleryApp` is the whole screen, with its own theme and overlay. It
leaves a route's `keys=` and `type=` to whoever runs it (the tester's
`press` and `type`); `bin/gallery.dart` types them itself.

## Adding a page

A page is a `GalleryPage` in `lib/src/pages/<group>.dart`, its group and
title as `lib/src/catalog.dart` names them (a new page has its entry
there first); the group's list goes into `galleryPages` in
`lib/src/pages/pages.dart`. A page of the catalog that no `GalleryPage`
draws shows a placeholder.

```dart
GalleryPage(
  group: 'Controls',
  title: 'Slider',
  // the inspector's options: keys, labels, values and first values
  options: [
    const ChoiceOption('divisions', 'divisions', values: [null, 10, 4], labels: ['none', '10', '4']),
    const SwitchOption('live', 'live', initial: true),
    SliderOption('width', 'width', min: 10, max: 60, initial: 30, format: (v) => '$v cells'),
    const ColorOption('color', 'style', values: ['primary', 'accent', 'success'], initial: 'primary'),
    // an option may say when it does not apply: disabled: (o) => …
  ],
  // the widget on the stage, with the options as they are
  build: (context, o) => SizedBox(
    width: o.number('width').toInt(),
    child: Slider(style: o.colorStyle(context, 'color'), /* … */),
  ),
  // the Dart of the Code tab, which builds what build: does
  code: (o) => ['return SizedBox(', '  width: ${o.label('width')},', /* … */].join('\n'),
  // StageSize.room for a view that takes the stage's room (MarkdownView)
);
```

A Code that writes a size from the stage's room (a chart as tall as the
stage lets it be) is `codeIn: (o,
room) => …` instead of `code:`; `room` is a `StageRoom`, the cells the
stage gives the widget, `room.height` rows. A widget that fits itself to
its room (a scrolling view, BigText) says how tall it is in a room with
`heightIn: (o, room) => rows`, so that the
options under a narrow stage take what it leaves; the stage keeps the
rows its widget asks for, and the options scroll. A widget that needs its
columns (a terminal of 80) says so with `minWidth:`, so that the options
go under the stage where beside it they would leave fewer. `modalTab: false` says
that what the page opens over the gallery takes Tab itself (a menu, a
command palette), so the hint bar leaves `tab next` out while it is open.
`hintLabel` names a key as the gallery's hint bar does (`alt+↓`, `esc`,
`pgdn`), for a page's own `KeyHintsBar(keyLabel: hintLabel)`. The hint bar
lists the hinted keys of the layers above the focus; hints that are no
key a layer binds (`type take over`, `wheel scroll back`) come from `PageHints(hints: [...], child:
…)` around the focusable widget, listed first while the focus is in it.

`Options` gives each option's value (`o['key']`, `o.choice<T>`,
`o.flag`, `o.number`, `o.color`), its name as the inspector and a route
write it (`o.label`), and the theme's style of a colour option
(`o.colorStyle`).

A page's widget reaches the gallery through `PageControl.of(context)`:
`state`, a map of its own that outlives a visit to another page;
`setOption(key, value)`, an option set as its control would (for a
`cycle` switch); `toast`.

The rules a page keeps (and those of [doc/design.md](doc/design.md),
"What every page keeps"):

- It builds what its Code writes, with real twk API: `tool/code_check.dart`
  holds the one to the other (below).
- Its widget behaves as its Dart doc says: keys, clicks, callbacks.
- What happened shows in a line under the widget, `label: value`, the
  value lit for a moment when it changes: `LitLine` (`pages/common.dart`).
- What moves with time reads the gallery's clock (`Clock.of(context)`,
  or a `Motion`, `lib/src/motion.dart`), so that a route's `t=` stills
  it.
- A Column or Row the stage sizes says `mainAxisSize: .min`: the stage's
  room is loose and bounded.
- Its golden screens are written (`TWK_UPDATE_GOLDENS=1 dart test
  test/goldens_test.dart`) and looked at, dark and light, at 120×36 and
  80×24, drawn as its pictures (`dart run tool/shots.dart`,
  "Pictures") and written into the catalog (`dart run tool/catalog.dart`,
  "The widget catalog").

## Checks

```bash
cd packages/gallery
dart pub get
dart analyze --fatal-infos
dart test
dart format --output=none --set-exit-if-changed lib test bin
```

The tests read the routes, check that every page that draws has its place
in the catalog, open every page at 80×24 and 120×36 without an overflow
or an error, and go through the list, the filter, the palette, the
inspector, a dialog and the theme with the keys.

## The Code against the stage

`tool/code_check.dart` holds each page's Code tab to what its stage
shows: the Code at the start (a page that sets its own options as time
goes on has another by the route's time), made into a program
(`tool/code_check/wrap.dart`: a `main`, a `State`, a State's members or a
`build()`'s body), run in twk's tester on a terminal the size of the
stage's room, in the page's theme, to the route's time; then its cells
against those of the widget on the stage, the glyph, the colours (the
default ones as the theme's) and the attributes, a blank by its
background.

```bash
dart run tool/code_check.dart                    # every page: dark, 120x36, 2 s
dart run tool/code_check.dart '#/controls/button?o=style:danger&keys=tab'
```

It writes `.dart_tool/code_check/`: what the stages showed
(`stages.json`), the package the Codes were made into (`gen/`) and
`report.md`, a row a page and the first differing cells of each that
differs. It fails where a Code does not compile, ends in an error or an
`ErrorWidget` it does not build, or differs from its stage, unless
`tool/code_check/known.dart` says why it cannot agree (a Code that lists
the directory it runs in, a run without the gallery's focus); a page of
that list that matches is named, so that its entry goes. In `xtask`'s
handover as `gallery-code`.

Where the widget draws a terminal around the app the Code is (App ›
Static, TerminalProgress, Viewport, Window title, Notifications), the
page says so (`GalleryPage.terminalAround`) and puts the app in a
`CodeApp`: only its cells are compared, and its size is the Code's
terminal. App › Cli's Code is a console program of `lib/cli/` (`create.dart`,
`install.dart`, `check.dart`, as `lib/src/pages/cli_code.dart` has them
for the Code tab, which `test/pages/cli_test.dart` holds to the files):
its stage runs the program on twk_test's fake terminal in
`lib/cli/run.dart`'s `CliRun`, typing what that file's `cliScripts` say
somebody at the terminal types, on a clock moved to the gallery's time,
and draws the fake terminal's screen. A Code whose `main` is
`Cli.runWithArgs(args, f)` is written as it is to `lib/cli/f.dart` of
the package the Codes are made into, beside a copy of `run.dart`, and
run in `CliRun` as the stage runs it, so that its traceback names the
same file and lines; the routes of its other programs are checked with
every page's own (`tool/code_check/stages.dart`, `_more`).

Where the stage is the app's terminal in the terminal's own
colours, as `runApp` gives them (Debugging › FrameOverlay, Repaint
rainbow: `codeInTerminalColors`), the Code runs under
`ThemeData.terminal` on a terminal the widget's size.

## Golden screens

`test/goldens_test.dart` holds the gallery's look screen by screen: every
page in the dark and the light theme at 120×36 and in the dark at 80×24,
and the routes that go past a page's first frame (other themes and
sizes, the palette, the Code tab, the filter, keys pressed and text
typed), each against its file in `test/goldens/`
(`<group>/<page>.<variant>.txt`), as twk_test's `matchesScreenFile` reads
it: the text of each row, a style character a cell, and a legend. A
route is shown on a terminal of its size whose
background is its theme's, the clock stopped at its `t=` (2 s), its keys
pressed after the first frame.

The files were first written at 405 routes when the gallery matched
its design, then a prototype in design/gallery (since retired:
doc/design.md), cell for cell there (by that prototype's comparison,
`design/tools/compare/compare.mjs --screen`), but for one: after `y`
copies the code, the design in headless Chrome toasts that it has no
clipboard, where the gallery writes OSC 52 and toasts what it copied.

A change to how a page looks shows as the diff of its files. When the
change is the one meant, write them again and commit them with it:

```bash
TWK_UPDATE_GOLDENS=1 dart test test/goldens_test.dart
git diff --stat test/goldens
```

A style keeps the character its file gave it, so the diff is what
changed. A new page has its files written by the same run.

## Pictures

`tool/shots.dart` draws the golden screens as SVGs into `doc/shots/`:
each page's widget, cut from the stage to its corner marks and its size
with a margin, in the dark and the light theme
(`doc/shots/<group>/<page>.<theme>.svg`), and a few whole screens for the
READMEs (`doc/shots/screens/`). The cells' backgrounds are rectangles,
their text a `<text>` a character, each at its cell's column, and the
box-drawing and block characters shapes, so that lines meet whatever
font draws the text. They keep to what flutter_svg reads (its parser,
vector_graphics_compiler, takes one `x` a `<text>`): no lists of
positions, no `textLength`, no `currentColor` (`test/shots_test.dart`
holds them to it), and one font family, `monospace`, which a Flutter app
can give a font of its own under that name. It reads the goldens alone: after they changed,

```bash
dart run tool/shots.dart
```

and commit `doc/shots/` with them; `gallery-shots`, in `handover`, runs
it and fails where that changed a file. `--png <directory>` also makes a
PNG of each whole screen with `rsvg-convert`, for pub.dev, which takes no
SVG as a screenshot (twk's, in `packages/twk/doc/screenshots/`):

```bash
dart run tool/shots.dart --png ../twk/doc/screenshots
```

## The widget catalog

`tool/catalog.dart` writes the widget catalog, `doc/widgets/` at the
repository's root, from the catalog's groups and pages, each page's Code
with its options as they start (a Code that reads its room in the room of
a stage at 120×36, 56×26), its options, and the pictures above: an index
of the groups, a page a group, and a page a widget, each with front
matter (`title`, `group`, `package`, `about`, `image`, `image_light`,
`route`) for a site to read. The one line a group gets is
`groupAbout` there. After a page or its pictures changed:

```bash
dart run tool/catalog.dart
```

and commit `doc/widgets/`; `catalog`, in `handover`, runs it after
`gallery-shots` and fails where that changed a file.
