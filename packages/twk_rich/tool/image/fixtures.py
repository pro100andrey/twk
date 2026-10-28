#!/usr/bin/env python3
"""Writes the test fixtures of package:twk_rich/image.dart into
test/image/fixtures.

Each image `<name>.png` or `<name>.jpg` comes with `<name>.rgba`, the pixels
it decodes to: 8-bit RGBA, row by row, straight alpha.

The PNGs are written here with zlib and struct alone, every colour type at
every bit depth it allows, interlaced or not, the rows filtered with each of
the five filters in turn; their pixels are known from how they were made.
The JPEGs are made by libjpeg-turbo's cjpeg from a picture drawn here, their
pixels those djpeg decodes them to (`-dct int -nosmooth`: the integer IDCT
and chroma replicated, not interpolated); the CMYK one is made by Pillow and the YCCK
one by ImageMagick, their pixels what ImageMagick converts them to in sRGB.

Run from anywhere: python3 tool/image/fixtures.py
"""

import os
import struct
import subprocess
import tempfile
import zlib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'test', 'image', 'fixtures')

# PNG ------------------------------------------------------------------------

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}

ADAM7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4),
         (1, 0, 2, 2), (0, 1, 1, 2)]


def sample(x, y, c, depth):
    """The raw sample of channel c at (x, y)."""
    if depth < 8:
        return (x + 3 * y + c) % (1 << depth)
    if depth == 8:
        return (x * 37 + y * 91 + c * 53) % 256
    return (x * 7919 + y * 10007 + c * 1237) % 65536


def to8(v, depth):
    if depth < 8:
        return v * 255 // ((1 << depth) - 1)
    return v if depth == 8 else v >> 8


def palette(depth):
    count = 1 << depth if depth < 8 else 200
    return [((i * 67) % 256, (i * 131) % 256, (i * 29 + 7) % 256)
            for i in range(count)]


def index(x, y, depth, count):
    if depth < 8:
        return (x + 3 * y) % (1 << depth)
    return (x * 7 + y * 13) % count


def chunk(kind, data):
    crc = zlib.crc32(kind + data) & 0xffffffff
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', crc)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def filtered(rows, bpp):
    """The rows of one (sub)image, row y filtered with filter y % 5."""
    out = bytearray()
    prev = bytes(len(rows[0])) if rows else b''
    for y, row in enumerate(rows):
        kind = y % 5
        out.append(kind)
        for i, v in enumerate(row):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            p = [0, a, b, (a + b) // 2, paeth(a, b, c)][kind]
            out.append((v - p) & 255)
        prev = row
    return bytes(out)


def scanline(samples, depth):
    if depth == 8:
        return bytes(samples)
    if depth == 16:
        return b''.join(struct.pack('>H', s) for s in samples)
    out = bytearray()
    acc = bits = 0
    for s in samples:
        acc = (acc << depth) | s
        bits += depth
        if bits == 8:
            out.append(acc)
            acc = bits = 0
    if bits:
        out.append(acc << (8 - bits))
    return bytes(out)


def png(name, color, depth, width=13, height=11, interlaced=False, trns=False,
        split=False, extra=False):
    channels = CHANNELS[color]
    pal = palette(depth) if color == 3 else None
    alphas = None
    if color == 3 and trns:
        alphas = [(i * 41) % 256 for i in range(len(pal) // 2 + 1)]
    key = None
    if trns and color == 0:
        key = (sample(1, 0, 0, depth),)
    if trns and color == 2:
        key = tuple(sample(2, 1, c, depth) for c in range(3))

    def raw(x, y):
        if color == 3:
            return (index(x, y, depth, len(pal)),)
        return tuple(sample(x, y, c, depth) for c in range(channels))

    def rgba(x, y):
        s = raw(x, y)
        if color == 3:
            r, g, b = pal[s[0]]
            a = alphas[s[0]] if alphas and s[0] < len(alphas) else 255
            return (r, g, b, a)
        v = [to8(c, depth) for c in s]
        a = 255
        if key is not None and s == key:
            a = 0
        if color == 0:
            return (v[0], v[0], v[0], a)
        if color == 2:
            return (v[0], v[1], v[2], a)
        if color == 4:
            return (v[0], v[0], v[0], v[1])
        return tuple(v)

    bpp = max(1, channels * depth // 8)

    def image(xs, ys):
        rows = [scanline([s for x in xs for s in raw(x, y)], depth) for y in ys]
        return filtered(rows, bpp) if xs and ys else b''

    if interlaced:
        data = b''.join(
            image(range(x0, width, dx), range(y0, height, dy))
            for x0, y0, dx, dy in ADAM7)
    else:
        data = image(range(width), range(height))
    compressed = zlib.compress(data, 9)
    out = b'\x89PNG\r\n\x1a\n'
    out += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, depth, color,
                                      0, 0, 1 if interlaced else 0))
    if extra:
        out += chunk(b'gAMA', struct.pack('>I', 45455))
        out += chunk(b'tEXt', b'Comment\x00made by tool/fixtures.py')
    if pal:
        out += chunk(b'PLTE', bytes(c for entry in pal for c in entry))
    if alphas:
        out += chunk(b'tRNS', bytes(alphas))
    elif key is not None:
        out += chunk(b'tRNS', b''.join(struct.pack('>H', k) for k in key))
    step = 50 if split else len(compressed)
    for i in range(0, len(compressed), step):
        out += chunk(b'IDAT', compressed[i:i + step])
    out += chunk(b'IEND', b'')
    write(name + '.png', out)
    write(name + '.rgba',
          bytes(c for y in range(height) for x in range(width)
                for c in rgba(x, y)))


def pngs():
    for depth in (1, 2, 4, 8, 16):
        png(f'gray{depth}', 0, depth, split=depth == 4)
    png('gray4_trns', 0, 4, trns=True)
    png('gray16_trns', 0, 16, trns=True)
    png('rgb8', 2, 8, extra=True)
    png('rgb16', 2, 16, split=True)
    png('rgb8_trns', 2, 8, trns=True)
    png('rgb16_trns', 2, 16, trns=True)
    for depth in (1, 2, 4, 8):
        png(f'palette{depth}', 3, depth)
    png('palette2_trns', 3, 2, trns=True)
    png('palette8_trns', 3, 8, trns=True, split=True)
    png('graya8', 4, 8)
    png('graya16', 4, 16)
    png('rgba8', 6, 8, split=True, extra=True)
    png('rgba16', 6, 16)
    png('gray1_adam7', 0, 1, interlaced=True)
    png('gray2_adam7', 0, 2, interlaced=True)
    png('rgb8_adam7', 2, 8, interlaced=True)
    png('palette4_trns_adam7', 3, 4, interlaced=True, trns=True)
    png('graya8_adam7', 4, 8, interlaced=True)
    png('rgba16_adam7', 6, 16, interlaced=True, split=True)
    png('rgba8_adam7_1x1', 6, 8, width=1, height=1, interlaced=True)
    png('rgb8_adam7_2x3', 2, 8, width=2, height=3, interlaced=True)
    png('gray1_1x1', 0, 1, width=1, height=1)


# JPEG -----------------------------------------------------------------------

JPEG_WIDTH, JPEG_HEIGHT = 37, 23


def picture():
    """Gradients with a white and a red square on them, as a PPM."""
    out = bytearray(b'P6 %d %d 255\n' % (JPEG_WIDTH, JPEG_HEIGHT))
    for y in range(JPEG_HEIGHT):
        for x in range(JPEG_WIDTH):
            r = x * 255 // (JPEG_WIDTH - 1)
            g = y * 255 // (JPEG_HEIGHT - 1)
            b = (x * 5 + y * 9) % 256
            if 4 <= x < 12 and 4 <= y < 12:
                r = g = b = 255
            if 20 <= x < 31 and 9 <= y < 18:
                r, g, b = 200, 16, 32
            out += bytes((r, g, b))
    return bytes(out)


def noise():
    """Pseudo-random pixels, whose coefficients take Huffman codes of up to
    16 bits, as a PPM."""
    width, height = 48, 32
    out = bytearray(b'P6 %d %d 255\n' % (width, height))
    state = 12345
    for _ in range(width * height * 3):
        state = (state * 1103515245 + 12345) % (1 << 31)
        out.append(state >> 23)
    return bytes(out)


def ppm_to_rgba(data):
    """The pixels of a binary PPM or PGM as RGBA."""
    fields = []
    pos = 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    pos += 1
    kind, width, height = fields[0], int(fields[1]), int(fields[2])
    pixels = data[pos:]
    out = bytearray()
    for i in range(width * height):
        if kind == b'P5':
            v = pixels[i]
            out += bytes((v, v, v, 255))
        else:
            out += pixels[i * 3:i * 3 + 3] + b'\xff'
    return bytes(out)


def jpegs():
    jpeg_options = {
        'jpeg444': ['-sample', '1x1'],
        'jpeg422': ['-sample', '2x1'],
        'jpeg420': ['-sample', '2x2'],
        'jpeg440': ['-sample', '1x2'],
        'jpeg_gray': ['-grayscale'],
        'jpeg_rgb': ['-rgb'],
        'jpeg_q1': ['-quality', '1'],
        'jpeg_restart': ['-sample', '2x2', '-restart', '3B'],
        'jpeg_optimized': ['-quality', '75', '-optimize'],
        'jpeg_progressive420': ['-progressive', '-sample', '2x2'],
        'jpeg_progressive444': ['-progressive', '-sample', '1x1'],
        'jpeg_progressive_gray': ['-progressive', '-grayscale'],
        'jpeg_progressive_restart': ['-progressive', '-sample', '2x2',
                                     '-restart', '2B'],
    }
    with tempfile.TemporaryDirectory() as tmp:
        source = os.path.join(tmp, 'picture.ppm')
        with open(source, 'wb') as f:
            f.write(picture())
        with open(os.path.join(tmp, 'noise.ppm'), 'wb') as f:
            f.write(noise())
        jpeg_options['jpeg_noise'] = ['-quality', '100', '-sample', '2x2',
                                      os.path.join(tmp, 'noise.ppm')]
        for name, options in jpeg_options.items():
            if '-quality' not in options:
                options = ['-quality', '90'] + options
            path = os.path.join(OUT, name + '.jpg')
            if not options[-1].endswith('.ppm'):
                options = options + [source]
            subprocess.run(['cjpeg', *options[:-1], '-outfile', path,
                            options[-1]], check=True)
            decoded = subprocess.run(
                ['djpeg', '-dct', 'int', '-nosmooth', '-pnm', path],
                check=True, capture_output=True).stdout
            write(name + '.rgba', ppm_to_rgba(decoded))
        # ImageMagick writes CMYK as YCCK (Adobe transform 2), Pillow as
        # CMYK (transform 0); both store the inks inverted, as Adobe does.
        from PIL import Image
        cmyk = os.path.join(OUT, 'jpeg_cmyk.jpg')
        Image.open(source).convert('CMYK').save(cmyk, quality=90)
        ycck = os.path.join(OUT, 'jpeg_ycck.jpg')
        subprocess.run(['magick', source, '-colorspace', 'CMYK', '-quality',
                        '90', '-strip', ycck], check=True)
        for name, path in (('jpeg_cmyk', cmyk), ('jpeg_ycck', ycck)):
            decoded = subprocess.run(
                ['magick', path, '-colorspace', 'sRGB', '-depth', '8',
                 'ppm:-'], check=True, capture_output=True).stdout
            write(name + '.rgba', ppm_to_rgba(decoded))


def write(name, data):
    with open(os.path.join(OUT, name), 'wb') as f:
        f.write(data)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    pngs()
    jpegs()
