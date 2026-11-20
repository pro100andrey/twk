/// The most pixels an image the decoders make may have: a gigabyte of RGBA.
const int maxImagePixels = 1 << 28;

/// The most pixels the screen of an animation (GIF, APNG) may have: 32 MB of
/// RGBA, the default window of its composed frames. The composing keeps a
/// canvas and gives each frame a copy of it, so an animation's memory is a
/// few times this, where a still image's is its own.
const int maxAnimationPixels = 1 << 23;
