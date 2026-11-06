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
after the build; `formatTook(time)` (with `formatBytes` and `ByteUnits` in
`package:twk/format.dart`, not in `twk.dart`), the time something took as a
`ProgressList` and a `TaskList` write it, to the tenth of a second, cut,
under a minute (`3.1 s`), else a clock (`01:05`, `1:02:03`); `formatBytes(bytes,
byteUnits: ByteUnits.decimal)`, a size as a `DirectoryTree` and a `ProgressList`
write it, whole from 100 of a unit and to the tenth below (`512 B`, `4.1 kB`,
`620 kB`, `1.2 MB`), or with `ByteUnits.binary` counted by 1024 as `ls -h`
does and named as the IEC does (`1023 B`, `1.0 KiB`, `1.5 MiB`)

## `TwkStrings`

`TwkStrings`, the words twk's widgets and `Cli` write themselves (`ETA`,
`+3 more`, `Y/n`, what a refused answer says), plain data with English
defaults, and `Localizations(strings:, child:)`, which gives them to the
widgets below; `TwkStrings.of(context)` reads the nearest, English without
one, and a widget that reads them is built again when they change.

`TwkStrings.decimalSeparator` (`.` by default) is the point of the sizes and
times twk writes: with `,` a `ProgressList`, a `TaskList` and `Cli` write
`4,5 GB` and `3,1 s`. `formatBytes` and `formatTook` take it as
`decimalSeparator:`, the point by default. An interactive yes or no answers to
the first letters of the `yes` and `no` of the strings too (`д`, `н`), besides
`y` and `n`.
