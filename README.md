# MO2 — open, build, run

Every Mod Organizer 2 repository, built as one CMake project. Open the folder, press build, get a
working MO2. No `env.ps1`, no mob, no environment variables.

## You need

| | |
|---|---|
| **Visual Studio 2026**, with the **v145** toolset | `.vsconfig` here lists the components to select, and VS offers to install them when you open the folder |
| **Python 3.14**, with the **development headers** | use the python.org installer — a Store or embeddable build may lack `Python.h`, and CMake finds Python through the registry, not `PATH` |
| **git** on `PATH` | needed to clone, and again during configure: Qt's installer is fetched with `pip install git+https://…` |
| **~25 GB free** | Qt 3.3 GB, the vcpkg packages, ~1.9 GB of usvfs build trees, and the build and install trees |

That is the whole list — you do not need a standalone CMake, and one registered Python 3.14 serves
both the build and the Qt installer. Qt, vcpkg, the repositories and every dependency are fetched
for you.

## Then

```
git clone --recursive https://github.com/mo2-modern/mo2-superbuild
```

1. Open the **folder** in Visual Studio 2026 or Rider.
2. Pick the **`vs2026`** preset. Configure starts on its own.
3. **Build → Build All.** This also installs — that is what makes the result runnable.
4. Set the startup item to **`ModOrganizer 2 (install tree)`** and press Run.

⚠️ **Step 4 is Visual Studio only.** It relies on `.vs/launch.vs.json`, which Rider does not read.
In Rider, run `install\bin\ModOrganizer.exe` directly, or add a native-executable run configuration
pointing at it. Everything before step 4 works the same in both.

⏱ **The first configure takes a while and looks idle in the middle of it.** It downloads Qt
(3.3 GB), resolves ~112 vcpkg packages, and builds `usvfs` twice — once per architecture, because
it ships both. The usvfs step prints nothing while it runs. It is not stuck. Later configures skip
all of it.

▶ **Run must launch out of `install\`.** The `ModOrganizer.exe` in `build\` has no plugins, no Qt
runtime and no usvfs beside it, and cannot start. Step 4 picks the right one.

## If something looks wrong

| | |
|---|---|
| Cloned without `--recursive` | `git submodule update --init`. Configure stops and says so rather than failing on a missing toolchain file |
| Run starts the wrong executable | pick the `ModOrganizer 2 (install tree)` startup item; if it is absent see [TRAPS.md](docs/TRAPS.md#ides) |
| 25 submodules show as modified after a build | expected — `lupdate` rewrites `*_en.ts` in place. Noise, not damage. [TRAPS.md](docs/TRAPS.md#superbuild-and-clone) |
| A green build with an empty `install\` | should be impossible now; if you see it, read [ADR-023](docs/DECISIONS.md#adr-023) |
| You already have Qt | `-DMO2_QT_DIR=<prefix>`, or set `QTDIR`. Skips the download |
| You would rather install Qt yourself | `-DMO2_AUTO_INSTALL_QT=OFF` — configure prints the exact `aqt` command and stops |
| You already have an MO2 checkout from mob | `-DMO2_SOURCE_ROOT=<path>` reuses it instead of cloning several GB twice |

## Documentation

| Document | Read it when |
|---|---|
| [docs/BUILD.md](docs/BUILD.md) | Setting up a machine, building, verifying |
| [docs/TRAPS.md](docs/TRAPS.md) | Before trusting any build output. Failure modes that report success instead of failing |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Getting oriented: repos, fork model, toolchain |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Before changing anything structural |
| [docs/UPSTREAM.md](docs/UPSTREAM.md) | Bugs found here that belong to upstream MO2 |

Some of these describe `mob`, the original build orchestrator, and the working tree it needs. That
tree is not published. Treat those parts as background.

## What this is

A superbuild: one CMake project that configures every MO2 repository at once, so there is one
solution to open and one button to press. It replaces the mob-driven cycle in which each repository
had to be built *and installed* before the next could even configure.

It holds no sources of its own. The repositories arrive as submodules under `repos/`, and everything
this project produces lands in `build/` and `install/`.

```
CMakeLists.txt              the superbuild
CMakePresets.json           the vs2026 preset an IDE reads
vcpkg.json                  one manifest for the whole project
cmake/superbuild-redirects/ makes find_package(mo2-*) work without installing first
.vs/launch.vs.json          aims Run at install\, in Open-Folder mode
```

**usvfs is the one repository not simply added as a subdirectory.** It is dual-architecture by
design, and a single CMake configure produces one architecture, so both are built and installed at
*configure* time. `ExternalProject_Add` is the usual answer and is wrong here: it builds at *build*
time, while `modorganizer`'s `find_package(usvfs)` must resolve during configure.

**Nothing upstream was edited.** The **64** `find_package(mo2-*)` calls across the repositories are
untouched, because every edited line is merge surface on every sync. They resolve three ways:
`cmake_common` on `CMAKE_PREFIX_PATH` covers the **28** `mo2-cmake` calls with no install step;
`cmake/superbuild-redirects/` stands in for the **29** sibling-library calls; the remaining **7**
(`mo2-dds-header`, `mo2-libbsarch`) are vcpkg registry ports and need nothing. See
[ADR-001](docs/DECISIONS.md#adr-001).

## Status

**All 33 buildable repositories build**, at 0 errors and 0 warnings. (`repos/` holds 34 submodules;
`cmake_common` is CMake modules and is consumed, not built.) Verified 2026-08-15 from a cold tree —
no `build/`, no `qt/`, no `install/` — running nothing but `cmake --preset vs2026` and
`cmake --build build --config RelWithDebInfo`:

| | |
|---|---|
| Qt | downloaded automatically: 3.32 GB, all modules, 23 s |
| vcpkg | 112 packages restored from a local binary cache in 6.9 s |
| configure | 0 errors, 0 warnings, 309 s — nearly all of it `usvfs`, built twice |
| build | 0 errors, 0 warnings; 471 translation units, 46 projects linked |
| install | populated by the build itself, no second command |
| launch | reaches the first-run *Creating an instance* window, loading `usvfs_x64.dll`, `uibase.dll`, `Qt6Core.dll` and `platforms\qwindows.dll` from this tree |

⚠️ **That 309 s is not a first-run estimate.** vcpkg's 112 packages came from a *local* cache. On a
machine that has never built them, that step compiles from source and dominates everything else.

⚠️ **A launch is not a usvfs verification.** It proves the DLL loads, not that it hooks anything.
That needs a game launched **through** MO2 and is read out of the instance's `logs\usvfs-*.log` —
see [TRAPS.md](docs/TRAPS.md#verification). An earlier run on a machine with a game installed showed
46 hooks (45 `type overwrite`, 1 `type chained patch`), matching the mob-driven build; that was not
re-measured here.

Install parity against the mob-built tree is **2 files**, both `usvfs_*targets-release.cmake` —
Release-configuration CMake exports, which this build does not produce because MO2 ships
RelWithDebInfo.
