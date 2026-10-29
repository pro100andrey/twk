# twk reference: `foundation`

[The reference](README.md) · `lib/src/foundation/`, `test/foundation/`

## `Listenable`

`Listenable` (and `Listenable.merge`), `ValueListenable`, `ChangeNotifier`,
`ValueNotifier`;

## `ListenableBuilder`

`ListenableBuilder` and `ValueListenableBuilder`, which rebuild what they
build when their listenable notifies;

## `FutureBuilder`

`FutureBuilder` and `StreamBuilder` (on `StreamBuilderBase`), which build
from the latest `AsyncSnapshot` (data or error, and a `ConnectionState`) of
a future or a stream;

## `ControllerHost`

`ControllerHost`, which a controller given to one widget at a time keeps its
widget in, handed over to one built in that one's place (a key changed) with
what the controller holds, and what is to happen when none takes it over run
after the build; `formatTook(time)`, the time something took as a
`ProgressList` and a `TaskList` write it, to the tenth of a second, cut,
under a minute (`3.1 s`), else a clock (`01:05`, `1:02:03`)
