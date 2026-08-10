# MO2 — open, build, run

Open this folder in **Visual Studio 2026** or **Rider**, pick the `vs2026` preset, build.
No `env.ps1`, no mob, no environment variables.

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
| Qt 6.11.1 (msvc2022_64) | 3.3 GB, cannot come from vcpkg — MO2 needs WebEngine, i.e. a Chromium build |
| An MO2 checkout | defaults to a sibling `mo2-modern`; override with `MO2_SOURCE_ROOT` |

Everything else — spdlog, 7zip, boost, lz4 — is fetched by vcpkg on first configure.

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

**4 of 33 repositories** are wired up so far — `uibase`, `esptk`, `archive`, `installer_bain` —
building clean at 0 errors / 0 warnings. The remaining 29 are mechanical additions, plus two
that are not:

- **usvfs** is dual-architecture (x86 *and* x64). One configure produces one architecture, so
  it needs `ExternalProject_Add` no matter how clean the rest becomes.
- **installer_omod** needs a NuGet restore for its .NET references.

## Why nothing upstream was edited

The 63 `find_package(mo2-* CONFIG REQUIRED)` calls across the repositories are untouched, because
every edited line is merge surface against 34 upstream projects on every sync. Two mechanisms
avoid touching them:

- **`mo2-cmake` (27 calls)** — `cmake_common/mo2-cmake-config.cmake` is self-contained, so putting
  `cmake_common` on `CMAKE_PREFIX_PATH` resolves all 27 with no install step. mob already did this.
- **sibling packages (29 calls)** — their real configs include a `*-targets.cmake` that only exists
  after `install(EXPORT)`. `cmake/superbuild-redirects/` stands in, asserting the target already
  exists in this build.
