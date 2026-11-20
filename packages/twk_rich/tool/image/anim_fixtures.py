#!/usr/bin/env python3
"""Writes the animated fixtures of test/image/fixtures: .gif and .apng files
made by Pillow and, beside each, `<name>.frames`, what Pillow reads back
from it (the canvas at each frame): four little-endian uint32 (width,
height, plays, frame count; plays 0 for ever), then for each frame its delay
in milliseconds as a uint32 and width * height * 4 bytes of RGBA.

Run from packages/twk_rich: python3 tool/image/anim_fixtures.py
"""
import random
import struct
from pathlib import Path

from PIL import Image, ImageSequence

OUT = Path(__file__).resolve().parents[2] / 'test' / 'image' / 'fixtures'


def noise(width, height, seed):
    rnd = random.Random(seed)
    img = Image.new('RGB', (width, height))
    img.putdata([
        (x * 5 % 256, y * 7 % 256, rnd.randrange(256))
        for y in range(height) for x in range(width)
    ])
    return img


def solid(width, height, color, box=None, base=(0, 0, 0, 0)):
    img = Image.new('RGBA', (width, height), base)
    if box:
        img.paste(Image.new('RGBA', (box[2] - box[0], box[3] - box[1]), color),
                  box[:2])
    else:
        img.paste(color, (0, 0, width, height))
    return img


def write_frames(path, plays):
    with Image.open(path) as im:
        frames = []
        for frame in ImageSequence.Iterator(im):
            rgba = frame.convert('RGBA')
            frames.append((int(frame.info.get('duration', 0)), rgba.tobytes()))
        w, h = im.size
    data = struct.pack('<4I', w, h, plays, len(frames))
    for delay, pixels in frames:
        data += struct.pack('<I', delay) + pixels
    path.with_suffix('.frames').write_bytes(data)


def main():
    # full-colour noise: the LZW table grows to its 4096 codes and resets
    frames = [noise(64, 48, s).convert('P', palette=Image.ADAPTIVE)
              for s in range(3)]
    p = OUT / 'anim_noise.gif'
    frames[0].save(p, save_all=True, append_images=frames[1:],
                   duration=[40, 120, 250], loop=0, interlace=True)
    write_frames(p, 0)
    # not interlaced, two plays after the first, frames of rectangles
    t = [
        solid(8, 6, (255, 0, 0, 255)),
        solid(8, 6, (0, 255, 0, 255), (2, 1, 6, 5), (0, 0, 255, 255)),
        solid(8, 6, (255, 255, 0, 255), (0, 0, 4, 3), (0, 0, 0, 0)),
    ]
    p = OUT / 'anim_plain.gif'
    t[0].save(p, save_all=True, append_images=t[1:], duration=[100, 200, 300],
              loop=2, interlace=False, disposal=1)
    write_frames(p, 3)
    # APNG: blend over and source, disposal none and background (previous
    # is in the tests: Pillow disposes a first frame to the previous canvas
    # as to none, the specification as to the background)
    a = [
        solid(8, 6, (255, 0, 0, 255)),
        solid(8, 6, (0, 255, 0, 255), (2, 1, 6, 5), (0, 0, 0, 0)),
        solid(8, 6, (0, 0, 255, 255), (0, 0, 4, 3), (0, 0, 0, 0)),
        solid(8, 6, (255, 255, 0, 255), (4, 3, 8, 6), (0, 0, 0, 0)),
    ]
    for name, kw in [
        ('anim_over', dict(blend=1, disposal=0)),
        ('anim_background', dict(blend=0, disposal=1)),
    ]:
        p = OUT / f'{name}.apng'
        a[0].save(p, format='PNG', save_all=True, append_images=a[1:],
                  duration=[100, 200, 50, 400], loop=4, **kw)
        write_frames(p, 4)

    # the default image is no frame: the three after it are the animation
    p = OUT / 'anim_default.apng'
    a[0].save(p, format='PNG', save_all=True, default_image=True,
              append_images=a[1:], duration=[100, 200, 50, 400], loop=0,
              blend=1, disposal=0)
    write_frames(p, 0)


main()
