---
title: "Debugging"
about: "The log console, the frame overlay, the repaint rainbow and repaint boundaries."
pages: 4
---
# Debugging

The log console, the frame overlay, the repaint rainbow and repaint boundaries.

[All groups](README.md)

| | |
| --- | --- |
| [![Console](../../packages/gallery/doc/shots/debugging/console.dark.svg)](debugging/console.md)<br>**[Console](debugging/console.md)**<br>Log records listed over the app, newest last; the app has one of its own, which Ctrl+G then c opens. | [![FrameOverlay](../../packages/gallery/doc/shots/debugging/frameoverlay.dark.svg)](debugging/frameoverlay.md)<br>**[FrameOverlay](debugging/frameoverlay.md)**<br>Each frame's numbers over the app: the time its build, layout, paint and write took and the bytes it wrote; Ctrl+G then o. |
| [![Repaint rainbow](../../packages/gallery/doc/shots/debugging/repaint-rainbow.dark.svg)](debugging/repaint-rainbow.md)<br>**[Repaint rainbow](debugging/repaint-rainbow.md)**<br>Each repaint boundary tinted a new colour when it paints, and relayouts marked, to see what a change redraws; Ctrl+G then r, and l. | [![RepaintBoundary](../../packages/gallery/doc/shots/debugging/repaintboundary.dark.svg)](debugging/repaintboundary.md)<br>**[RepaintBoundary](debugging/repaintboundary.md)**<br>A subtree painted on its own layer: what changes in it is painted again without what is around it, and the other way round. |

