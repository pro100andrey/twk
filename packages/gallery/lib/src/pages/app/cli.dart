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

final _cli = GalleryPage(
  terminalAround: true,
  group: 'App',
  title: 'Cli',
  options: const [
    ChoiceOption('program', 'program', values: ['create', 'install', 'check']),
  ],
  build: (context, o) => LayoutBuilder(
    builder: (context, c) {
      const most = 1 << 20;
      final (w, h) = _cliBox(
        StageRoom(
          c.maxW < BoxConstraints.unbounded ? c.maxW : most,
          c.maxH < BoxConstraints.unbounded ? c.maxH : most,
        ),
      );
      return cliStage(context, o.label('program'), width: w, height: h);
    },
  ),
  heightIn: (o, room) => _cliBox(room).$2,
  code: (o) => cliCode[o.label('program')]!,
);
