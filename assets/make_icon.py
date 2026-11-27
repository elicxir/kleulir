"""Builds assets/kleulir.ico, the icon embedded in kleulir.exe.

Two drawings go into it:

    kleulir-named.svg   gramophone with the name under it, for 48 px and larger
    kleulir.svg         gramophone alone, for 32 px and smaller, where the name
                        would be unreadable (also the window and tray icon)

The SVGs are rendered with ImageMagick (`magick` on PATH) and packed into the
.ico here:

    python assets/make_icon.py
"""
import os
import struct
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SIZES = [(16, "kleulir.svg"), (24, "kleulir.svg"), (32, "kleulir.svg"),
         (48, "kleulir-named.svg"), (64, "kleulir-named.svg"), (256, "kleulir-named.svg")]


def png(size, svg):
    """The SVG as PNG bytes, size x size, with a transparent background."""
    return subprocess.run(
        ["magick", "-background", "none", "-density", "384", os.path.join(HERE, svg),
         "-resize", f"{size}x{size}", "-strip", "png32:-"],
        check=True, capture_output=True).stdout


def main():
    images = [png(size, svg) for size, svg in SIZES]
    out = struct.pack("<HHH", 0, 1, len(SIZES))
    offset = 6 + 16 * len(SIZES)
    for (size, _), data in zip(SIZES, images):
        edge = 0 if size == 256 else size  # 0 stands for 256 in an icon directory
        out += struct.pack("<BBBBHHII", edge, edge, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    out += b"".join(images)
    path = os.path.join(HERE, "kleulir.ico")
    with open(path, "wb") as f:
        f.write(out)
    print("wrote", path, len(out), "bytes")


if __name__ == "__main__":
    main()
