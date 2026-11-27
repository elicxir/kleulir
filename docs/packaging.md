# Packaging kleulir

How the folder that is handed to other people is made, and what has to be in it.

## Build the folder

```powershell
$env:VCPKG_ROOT = "C:\path\to\vcpkg"
cmake --preset msvc
cmake --build build --config Release
cmake --install build --config Release --prefix dist/kleulir-win64
```

`dist/kleulir-win64` then holds `kleulir.exe`, the Qt libraries with their plugins
and QML modules, the other DLLs, `LICENSE`, `README.md` and a `licenses` folder.
It runs from anywhere; zip it to distribute it.

## Bundle mpv

kleulir plays through mpv. Without a bundled copy it looks for an installed one
and, failing that, falls back to the Windows media player (inexact seeking). To
ship mpv with kleulir, put these in `third_party/mpv/` (the folder is not in Git):

| File | What |
| --- | --- |
| `mpv.exe` | The player. A plain `x86_64` build, not `x86_64-v3` (that one needs a recent CPU). |
| `LICENSE.GPL` | mpv's licence text, from the build's archive or from mpv's repository. |
| `LICENSE.GPLv3` | The GPLv3 text, when the build's FFmpeg was configured with `--enable-version3` (the usual Windows builds are): the binary as a whole is then GPLv3-or-later. |
| `SOURCE.txt` | Which build this is and where its source is: the archive's file name, the URL it came from, its SHA-256, the mpv version (`mpv --version`), and the URL of the build scripts and their revision. |

Then configure again (the check for `mpv.exe` happens at configure time) and
install:

```powershell
cmake --preset msvc
cmake --install build --config Release --prefix dist/kleulir-win64
```

`mpv.exe` lands next to `kleulir.exe`, where kleulir looks first; the other files
go to `licenses/mpv/`.

Windows builds of mpv are listed at <https://mpv.io/installation/>. Check that the
build is redistributable: an FFmpeg configured with `--enable-nonfree` may not be
passed on. `mpv --version` prints the FFmpeg configuration.

## What the licences ask for

kleulir is GPL-3.0-or-later; the folder as a whole is distributed under the GPL.

- **kleulir**: `LICENSE` is included and the source is public. A release should
  name the commit it was built from.
- **mpv** (GPL-2.0-or-later, a separate program): its licence text and
  `SOURCE.txt`, so a recipient can get the source of exactly that build.
- **Qt** (LGPL-3.0): shipped as separate DLLs, with the licence texts in
  `licenses/`.
- **Everything else**: one licence file each in `licenses/`, taken from the vcpkg
  packages the build used. `licenses/THIRD-PARTY.txt` lists them.

The Visual C++ runtime is not included: a PC without it needs the "Visual C++
Redistributable" from Microsoft.

This is a working description, not legal advice. Have it checked before a public
release.
