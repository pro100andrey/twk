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
under a minute (`3.1 s`), else a clock (`01:05`, `1:02:03`); `formatBytes(bytes,
units: ByteUnits.decimal)`, a size as a `DirectoryTree` and a `ProgressList`
write it, whole from 100 of a unit and to the tenth below (`512 B`, `4.1 kB`,
`620 kB`, `1.2 MB`), or with `ByteUnits.binary` counted by 1024 as `ls -h`
does and named as the IEC does (`1023 B`, `1.0 KiB`, `1.5 MiB`)
