# kleulir

A music player for Windows that plays from an
[eos](https://github.com/elicxir/extended-opensubsonic-server) server (an
OpenSubsonic-compatible server with extensions for soundtrack collections).
Written in C++ with Qt 6 (QML); audio is played by [mpv](https://mpv.io/).

Requirements for the client are in [docs/requirements.md](docs/requirements.md)
(Japanese).

## Building

Windows 11, Visual Studio 2022, CMake 3.25 or later, and a recent
[vcpkg](https://github.com/microsoft/vcpkg) checkout. The dependencies (Qt, libcurl,
nlohmann/json) are built by vcpkg from `vcpkg.json`; the first build takes a long
time because Qt is built from source.

```powershell
git clone --recurse-submodules https://github.com/elicxir/kleulir.git
cd kleulir
$env:VCPKG_ROOT = "C:\path\to\vcpkg"
cmake --preset msvc
cmake --build build --config Release
cmake --install build --config Release --prefix dist/kleulir-win64
```

`dist/kleulir-win64/kleulir.exe` then runs on its own.

kleulir plays through mpv when it finds `mpv.exe` (in `KLEULIR_MPV`, next to
`kleulir.exe`, on `PATH`, or in the usual install folders) and through the Windows
media player otherwise. mpv is recommended: seeking is exact and ReplayGain is
applied from the files' tags.

## Licence

Copyright (C) 2026 iselir (elicxir)

kleulir is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.

kleulir is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE. See the GNU General Public License for more details.

The full text is in [LICENSE](LICENSE).

kleulir uses Qt under the LGPL, and starts mpv, a separate program under the GPL.

## Contributions

This project does not take outside contributions; see
[CONTRIBUTING.md](CONTRIBUTING.md).
