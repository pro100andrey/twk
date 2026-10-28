// An image viewer: the PNG or JPEG file named on the command line, below
// its name and above the keys, shown with the terminal's graphics protocol
// or, where it has none, in half blocks. The protocol is the one the probe
// finds when the app starts, or the one TWK_GRAPHICS names (kitty, sixel,
// iterm2 or none), and stays for the whole run. f cycles the fit (contain,
// cover, fill, scale down); p what the image is drawn with: the
// terminal's protocol, half blocks, quadrants; q quits.
//
//   dart run example/image/viewer.dart photo.jpg
//   TWK_GRAPHICS=sixel dart run example/image/viewer.dart photo.png
import 'dart:io';
import 'dart:typed_data';

import 'package:twk/twk.dart';
import 'package:twk_rich/image.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run example/image/viewer.dart FILE');
    exitCode = 64;
    return;
  }
  final Uint8List bytes;
  final ({int width, int height}) size;
  try {
    bytes = File(args.single).readAsBytesSync();
    size = imageSize(bytes);
  } on FileSystemException catch (e) {
    stderr.writeln('${args.single}: ${e.osError?.message ?? e.message}');
    exitCode = 66;
    return;
  } on FormatException catch (e) {
    stderr.writeln('${args.single}: ${e.message}');
    exitCode = 65;
    return;
  }
  await runApp(Theme.adaptive(child: Viewer(args.single, bytes, size)));
}

/// The image file [name] of [bytes], [size] pixels.
final class Viewer extends StatefulWidget {
  const Viewer(this.name, this.bytes, this.size, {super.key});

  final String name;
  final Uint8List bytes;
  final ({int width, int height}) size;

  @override
  State<Viewer> createState() => _ViewerState();
}

/// What the image is drawn with: the terminal's protocol, or blocks.
enum _Drawing { protocol, half, quadrant }

final class _ViewerState extends State<Viewer> {
  ImageFit _fit = .contain;
  _Drawing _drawing = .protocol;

  void _nextFit() => setState(
    () => _fit = ImageFit.values[(_fit.index + 1) % ImageFit.values.length],
  );

  void _nextDrawing() => setState(
    () => _drawing =
        _Drawing.values[(_drawing.index + 1) % _Drawing.values.length],
  );

  @override
  Widget build(BuildContext context) {
    final caps = AppBinding.of(context).twkApp.terminal.info.caps;
    final protocol = caps.graphics;
    final drawnWith = switch (_drawing) {
      _Drawing.protocol when protocol != GraphicsProtocol.none => protocol.name,
      _Drawing.protocol || _Drawing.half => 'half blocks',
      _Drawing.quadrant => 'quadrants',
    };
    final cell = caps.cellPixelWidth == 0
        ? 'cell size not reported'
        : 'cells of ${caps.cellPixelWidth} × ${caps.cellPixelHeight}';
    final theme = Theme.of(context);
    return KeyBindings(
      {
        'q': () => AppBinding.of(context).quit(),
        'f': _nextFit,
        'p': _nextDrawing,
      },
      hints: {
        'q': 'quit',
        'f': 'fit: ${_fit.name}',
        'p': 'drawn with $drawnWith',
      },
      child: Box(
        style: theme.background.merge(theme.text),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Text.rich([
              Span(' ${widget.name}  ', theme.primary).bold,
              Span(
                '${widget.size.width} × ${widget.size.height} pixels, '
                '$cell, the terminal shows ${protocol.name}',
                theme.muted,
              ),
            ], wrap: .none),
            Expanded(
              child: Image.memory(
                widget.bytes,
                fit: _fit,
                blockMode: _drawing == _Drawing.quadrant
                    ? BlockMode.quadrant
                    : BlockMode.half,
                forceBlocks: _drawing != _Drawing.protocol,
              ),
            ),
            const KeyHintsBar(),
          ],
        ),
      ),
    );
  }
}
