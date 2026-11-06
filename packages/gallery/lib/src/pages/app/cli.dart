// The Cli page.
part of 'app.dart';

/// The terminal's frame in [room]: all of it, a terminal of at most
/// 74 × 20 inside its border; 76 × 22 before the stage was laid out.
(int, int) _cliBox(StageRoom room) => room == StageRoom.unbounded
    ? (76, 22)
    : (
        math.max(30, math.min(76, room.width)),
        math.max(8, math.min(22, room.height)),
      );

/// The Cli page's `program` option.
const _cliProgram = ChoiceOption<String>(
  'program',
  'program',
  values: ['create', 'install', 'check'],
);

final _cli = GalleryPage(
  terminalAround: true,
  group: _group,
  title: 'Cli',
  options: const [
    _cliProgram,
  ],
  build: (context, o) => LayoutBuilder(
    builder: (context, c) {
      const most = 1 << 20;
      final (w, h) = _cliBox(
        StageRoom(
          c.maxWidth < BoxConstraints.unbounded ? c.maxWidth : most,
          c.maxHeight < BoxConstraints.unbounded ? c.maxHeight : most,
        ),
      );
      return cliStage(context, o.nameOf(_cliProgram), width: w, height: h);
    },
  ),
  heightIn: (o, room) => _cliBox(room).$2,
  code: (o) => cliCode[o.nameOf(_cliProgram)]!,
);
