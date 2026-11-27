"""Draws assets/kleulir.ico, the icon embedded in kleulir.exe.

The same picture as assets/kleulir.svg (dark tile, jade bar, light play triangle),
drawn here with nothing but the standard library so the icon can be regenerated
without extra tools:

    python assets/make_icon.py
"""
import os
import struct
import zlib

BACKGROUND = (0x21, 0x21, 0x21, 255)
BAR = (0x38, 0xB4, 0x8B, 255)
TRIANGLE = (0xED, 0xED, 0xED, 255)
SUPERSAMPLE = 4  # samples per pixel edge, for smooth triangle edges


def colour_at(x, y):
    """Colour of the 64x64 design at (x, y)."""
    if 10 <= x < 18 and 12 <= y < 52:
        return BAR
    # Triangle (26,12) (54,32) (26,52): right of x = 26, between the two slanted edges.
    if x >= 26:
        half_height = 20.0 * (54.0 - x) / 28.0
        if x <= 54 and abs(y - 32.0) <= half_height:
            return TRIANGLE
    return BACKGROUND


def render(size):
    rows = []
    scale = 64.0 / size
    n = SUPERSAMPLE
    for py in range(size):
        row = bytearray([0])  # PNG filter type: none
        for px in range(size):
            total = [0, 0, 0, 0]
            for sy in range(n):
                for sx in range(n):
                    c = colour_at((px + (sx + 0.5) / n) * scale, (py + (sy + 0.5) / n) * scale)
                    for i in range(4):
                        total[i] += c[i]
            row.extend(v // (n * n) for v in total)
        rows.append(bytes(row))
    return b"".join(rows)


def png(size):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(render(size), 9)) + chunk(b"IEND", b""))


def main():
    sizes = [16, 24, 32, 48, 64, 256]
    images = [png(s) for s in sizes]
    out = struct.pack("<HHH", 0, 1, len(sizes))
    offset = 6 + 16 * len(sizes)
    for size, data in zip(sizes, images):
        edge = 0 if size == 256 else size  # 0 stands for 256 in an icon directory
        out += struct.pack("<BBBBHHII", edge, edge, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    out += b"".join(images)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kleulir.ico")
    with open(path, "wb") as f:
        f.write(out)
    print("wrote", path, len(out), "bytes")


if __name__ == "__main__":
    main()
