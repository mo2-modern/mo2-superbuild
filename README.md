# MO2 — open, build, run

```
git clone --recursive https://github.com/mo2-modern/mo2-superbuild
```

Open the folder in **Visual Studio 2026** or **Rider**, pick the `vs2026` preset, build.
No `env.ps1`, no mob, no environment variables.

The 33 MO2 repositories are submodules under `repos/`, so `--recursive` gets them. If you already
have a checkout from mob, skip `--recursive`: the build falls back to a sibling `mo2-modern` tree
rather than making you clone several GB twice. Either way, `MO2_SOURCE_ROOT` overrides it.

## What this is

A superbuild: a single CMake project that configures every MO2 repository at once, so there
is one solution to open and one button to press. It replaces the mob-driven cycle where each
repository had to be built *and installed* before the next could even configure.

It holds no sources and no submodules. The repositories stay where they are; nothing is ever
written inside them. Everything this project produces lands in `build/` and `install/` here.

```
CMakeLists.txt              the superbuild
CMakePresets.json           the vs2026 preset an IDE reads
vcpkg.json                  one manifest for the whole project
cmake/superbuild-redirects/ makes find_package(mo2-*) work without installing first
```

## Prerequisites

| | |
|---|---|
| Visual Studio 2026 with the **v145** toolset | the C++/CLI plugins need MSBuild; no Ninja IDE can build them |
| Qt 6.11.1 (msvc2022_64) | 3.3 GB — see below |

Everything else — the 33 repositories, spdlog, 7zip, boost, lz4, stylesheets, Explorer++ — comes
from `--recursive`, vcpkg, or a download on first configure.

### Qt

Qt is the one thing this project cannot fetch for itself, and it is **not** downloaded
automatically: 3.3 GB pulled silently inside an IDE configure, with no progress and no good
recovery if the network drops, is worse than being told exactly what to run. Configure finds Qt in
`./qt/`, in a sibling `mo2-modern/tools/Qt/`, or via `QTDIR`, and otherwise prints this:

```
py -3.14 -m pip install git+https://github.com/miurahr/aqtinstall
py -3.14 -m aqt install-qt windows desktop 6.11.1 win64_msvc2022_64 \
    -m qtwebengine qtwebchannel qtpositioning qtserialport qtimageformats \
    -O ./qt
```

Two details that are easy to get wrong:

- **aqt must come from git.** The PyPI release lags Qt's repository layout and fails on current
  versions.
- **The module list is not optional.** Upstream CI compiles MO2 without ever launching it, so its
  list omits runtime-only modules. Without `qtimageformats` you get 4 image plugins instead of 9,
  and MO2 silently cannot render TGA, TIFF or WebP mod previews — nothing fails at build time.

Qt cannot come from vcpkg at all, because MO2 needs WebEngine, which means building Chromium.

Already have Qt? `cmake --preset vs2026 -DMO2_QT_DIR=<prefix>`, or set `QTDIR`.

The preset points `toolchainFile` at a **path**, deliberately, rather than `$env{VCPKG_ROOT}`:
Visual Studio's `vcvarsall.bat` overwrites that variable with VS's own bundled vcpkg, so an IDE
build that trusted it would silently resolve every dependency against the wrong vcpkg. Verified
by configuring with `VCPKG_ROOT` deliberately pointed at VS's copy — it builds correctly anyway.

## Pointing it at a different checkout

`MO2_SOURCE_ROOT` is the only path that matters. Set it in the preset, or:

```powershell
cmake --preset vs2026 -DMO2_SOURCE_ROOT=D:/some/other/mo2/build/build
```

The build fails immediately with a clear message if the path is not an MO2 checkout, rather
than producing a confusing `find_package` error twenty lines later.

## Status

**All 33 repositories build**, at 0 errors and 0 warnings, and MO2 built this way has been run:
usvfs loads from this tree and installs 46 hooks (45 `type overwrite`, 1 `type chained patch`,
0 errors), the same count the mob-driven build produces.

Install parity against the mob-built tree is **2 files**, both `usvfs_*targets-release.cmake` —
CMake export files for the Release configuration, which this build does not produce because MO2
ships RelWithDebInfo.

**usvfs is the one repository that is not simply added as a subdirectory.** It is
dual-architecture by design, and a single CMake configure produces one architecture, so both are
built and installed at *configure* time. `ExternalProject_Add` is the usual answer and does not
work here: it builds at *build* time, while `modorganizer`'s `find_package(usvfs)` has to resolve
during configure. The first configure therefore takes a few minutes; every later one skips it.

## Why nothing upstream was edited

The 63 `find_package(mo2-* CONFIG REQUIRED)` calls across the repositories are untouched, because
every edited line is merge surface against 34 upstream projects on every sync. Two mechanisms
avoid touching them:

- **`mo2-cmake` (27 calls)** — `cmake_common/mo2-cmake-config.cmake` is self-contained, so putting
  `cmake_common` on `CMAKE_PREFIX_PATH` resolves all 27 with no install step. mob already did this.
- **sibling packages (29 calls)** — their real configs include a `*-targets.cmake` that only exists
  after `install(EXPORT)`. `cmake/superbuild-redirects/` stands in, asserting the target already
  exists in this build.
