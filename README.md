# Mod Organizer 2 — Superbuild

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

One CMake project that builds all of Mod Organizer 2 from source. Clone it, open the folder in your
IDE, press build, and get a working `ModOrganizer.exe`.

[Mod Organizer 2](https://github.com/ModOrganizer2) is a mod manager for Bethesda games. Its source
is spread across 34 git repositories, and upstream builds them with `mob`, a purpose-built
orchestrator that clones, configures, builds and *installs* each repository in turn so that the next
one can find it. That works, but it means a bespoke tool, a machine-specific `mob.ini`, an
environment script, and a build you cannot drive from an IDE.

This repository replaces that with an ordinary CMake superbuild: the repositories are submodules,
one `CMakeLists.txt` adds them all, and dependencies resolve in-tree without an install step. There
is one project to open and one button to press.

The submodules under `repos/` are [`mo2-modern`](https://github.com/mo2-modern) forks of the
upstream projects, not the upstream repositories themselves — they carry a toolchain modernization
and a set of bug fixes ([UPSTREAM.md](docs/UPSTREAM.md)). What the superbuild does not do is *edit*
them: the assembly is arranged so that not one line inside those 34 repositories has to change,
because every changed line is merge surface on every upstream sync
([ADR-001](docs/DECISIONS.md#adr-001)). Point `MO2_SOURCE_ROOT` at a different checkout and it
builds that instead.

## Requirements

| Requirement | Notes |
| --- | --- |
| Visual Studio 2026, v145 toolset | The C++/CLI plugins require MSBuild; no Ninja-only setup can build them. `.vsconfig` lists the components to select. |
| Python 3.14, with development headers | Use the python.org installer. CMake locates it through the registry, not `PATH`. |
| Git, on `PATH` | Used to clone, and again during configure to fetch the Qt installer. |
| ~25 GB free disk space | Qt is 3.3 GB; vcpkg packages, usvfs build trees and the output account for the rest. **Roughly 3 GB of it goes to `%LOCALAPPDATA%\vcpkg`, not to the drive you cloned to** — vcpkg's build trees, packages and downloads are redirected there to keep them out of the workspace. |

Qt, vcpkg, and every third-party dependency are downloaded automatically. A standalone CMake is not
required — the build uses the one Visual Studio ships.

Windows only. MO2 depends on Windows APIs and on DLL injection, and does not target other platforms.

## Getting started

```console
git clone --recursive https://github.com/mo2-modern/mo2-superbuild
```

`--recursive` fetches the 34 repositories into `repos/` and vcpkg into `vcpkg/`. If you forget it,
configure stops and tells you to run `git submodule update --init`.

### Visual Studio

1. Open the **folder** (not a solution file) and select the `vs2026` preset. Configuring starts
   automatically.
2. **Build → Build All.**
3. **Build → Install mo2.**
4. Select the **ModOrganizer 2 (install tree)** startup item and run. It appears once step 3 has
   produced the executable, so build and install before looking for it.

### Command line

```console
cmake --preset vs2026
cmake --build build --config RelWithDebInfo
cmake --install build --config RelWithDebInfo
```

Both routes produce `install/bin/ModOrganizer.exe`.

> **Build and install are separate steps, and MO2 only runs from `install/`.** The executable left
> in `build/` has no plugins, Qt runtime or usvfs alongside it and will not start. Building without
> installing is not an error — it just means the install tree still holds whatever was last deployed
> there. See [ADR-023](docs/DECISIONS.md#adr-023).

> **RelWithDebInfo is the only configuration.** It is what MO2 ships and the only one this tree is
> built and verified in, so the preset sets `CMAKE_CONFIGURATION_TYPES` to it alone and the IDE's
> configuration dropdown offers nothing else. It carries full debug symbols; you can set
> breakpoints and step through code normally.
>
> This used to leave Debug selectable-but-unsupported, which was a trap rather than a freedom:
> `usvfs` is built as RelWithDebInfo regardless of the setting and the vcpkg runtime DLLs are
> installed from the release tree, so choosing Debug produced a build that mixed configurations
> across a DLL boundary. If you genuinely need it, remove the line from `CMakePresets.json` — and
> read [ADR-025](docs/DECISIONS.md#adr-025) first.

`install/` and `build/` are in `.gitignore`, so Visual Studio's Folder View hides them by default.
Use **Show All Files** in the Solution Explorer toolbar if you want to browse the output.

> **The first configure takes roughly ten minutes and appears to stall.** It downloads Qt, resolves
> around 112 vcpkg packages, and builds usvfs twice, once per architecture. The usvfs step produces
> no output while it runs. Subsequent configures skip all of it.

Running into something unexpected? See [Troubleshooting](docs/BUILD.md#troubleshooting).

## Configuration

Pass any of these to `cmake --preset vs2026 -D<option>=<value>`, or set them in your IDE's CMake
settings.

| Option | Default | Purpose |
| --- | --- | --- |
| `MO2_AUTO_INSTALL_QT` | `ON` | Download Qt when it cannot be found. Set `OFF` to be given the exact `aqt` command instead. |
| `MO2_QT_DIR` | auto-detected | Use an existing Qt instead of downloading one. `QTDIR` works too. |
| `MO2_QT_VERSION` | `6.11.1` | Qt version to build against. |
| `MO2_SOURCE_ROOT` | `repos/` | Build a different MO2 checkout instead of this clone's submodules. |
| `MO2_QT_MODULES` | see `CMakeLists.txt` | Qt modules to install. The only copy of this list; the download and the printed instructions are both generated from it. |

## How it works

The repositories are submodules under `repos/`. This project holds no sources of its own, and
everything it produces lands in `build/` and `install/`.

One exception, and it is upstream's rather than this project's: `mo2_add_translations` runs
`lupdate`, which rewrites each repository's `*_en.ts` **in place**. A first build therefore leaves
25 submodules showing as modified. It is line-number churn, not damage — clear it with
`git -C repos/<name> checkout -- .` and do not commit it.

The problem a superbuild has to solve here is that the upstream repositories locate each other with
63 `find_package(mo2-*)` calls, which normally require a prior `install`. Editing those calls would
create merge conflicts against 34 projects on every sync, so they are left untouched and satisfied
three ways: `cmake_common` on `CMAKE_PREFIX_PATH` resolves the 27 `mo2-cmake` calls directly,
`cmake/superbuild-redirects/` stands in for the 29 sibling-library calls by asserting the target
already exists in this build, and the remaining 7 are vcpkg registry ports that need no help.

`usvfs` is the exception to the pattern. It is dual-architecture by design — the 32-bit DLL is
injected into 32-bit games, the 64-bit one into 64-bit games — and a single CMake configure produces
only one architecture. It is therefore built and installed for both at *configure* time.
`ExternalProject_Add` cannot be used, because it builds at build time while `find_package(usvfs)`
must resolve during configure.

The install step does more than copy build output. It deploys the Qt runtime with `windeployqt`,
and the stylesheets, Explorer++ and third-party license texts that MO2 ships are fetched and laid
out there. That is why a build alone leaves nothing runnable.

```
CMakeLists.txt               the superbuild
CMakePresets.json            the vs2026 preset
vcpkg.json                   one dependency manifest for the whole project
cmake/superbuild-redirects/  satisfies find_package(mo2-*) without installing
.vs/launch.vs.json           points Run at the install tree
repos/                       the 34 upstream repositories, as submodules
```

## Documentation

| Document | Read it when |
| --- | --- |
| [BUILD.md](docs/BUILD.md) | Setting up a machine, building, troubleshooting, verifying a build |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Getting oriented: repositories, fork model, toolchain |
| [DECISIONS.md](docs/DECISIONS.md) | Before changing anything structural — the reasoning is recorded as ADRs |
| [TRAPS.md](docs/TRAPS.md) | Before trusting a build result. Failure modes that report success instead of failing |
| [UPSTREAM.md](docs/UPSTREAM.md) | Bugs found here that belong to upstream MO2 |

Everything they describe is in this repository. They used to document a second, unpublished tree
built around `mob` as well; that is retired ([ADR-027](docs/DECISIONS.md#adr-027)) and what it was
is frozen in [`history/MOB.md`](docs/history/MOB.md), which you only need in order to read older
notes.

## Status

All 33 buildable repositories compile at 0 errors and 0 warnings. (`repos/` holds 34 submodules;
`cmake_common` is CMake modules, consumed rather than built.)

Last verified 2026-08-15 from a cold tree, with no `build/`, `qt/` or `install/` present, running a
configure, a build and an install: Qt downloaded automatically, configure and build clean at 0
errors and 0 warnings, 471 translation units, 46 projects linked, and `ModOrganizer.exe` reaching
its first-run window with usvfs, uibase and the Qt runtime loaded from `install/`.

That exercise does not cover usvfs *hooking*, which requires launching a game through MO2 and
reading the result out of the instance log. See [TRAPS.md](docs/TRAPS.md#verification).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: the repositories under `repos/` are forks tracking
`ModOrganizer2/*`, each keeping `master` as an untouched upstream mirror and doing all work on
`modern` ([ADR-001](docs/DECISIONS.md#adr-001)); changes to the assembly belong here and changes to
MO2 belong in the relevant submodule; and please do not add a second copy of any version, module
list or hash — several of the failures recorded in [TRAPS.md](docs/TRAPS.md) are duplicated facts
that drifted apart.

## AI assistance

This project was built with substantial help from an AI assistant (Claude). Much of the CMake, the
documentation, the CI workflow and the release tooling was written that way, as was a good part of
the analysis behind the fixes in [UPSTREAM.md](docs/UPSTREAM.md).

What that does and does not mean:

- **A person decided, and a person checked.** Every structural decision is mine and recorded as an
  ADR in [DECISIONS.md](docs/DECISIONS.md), several of them overruling a suggestion. Builds were run,
  MO2 was launched, and the things a compiler cannot check — usvfs actually hooking, downloads
  actually downloading — were verified by hand.
- **Being wrong is written down, not hidden.** [TRAPS.md](docs/TRAPS.md) exists because this project
  kept producing confident, wrong answers — greps that under-reported, builds that compiled nothing
  and reported success. Several entries record claims that were made twice and were wrong both times.
- **Commits carry no AI attribution, deliberately** — see
  [CONTRIBUTING.md](CONTRIBUTING.md#commits). That is not concealment: these commits are candidates
  for pull requests against 34 upstream projects, where an assistant trailer is noise a maintainer
  would have to strip. The disclosure belongs here, once, where it is actually informative.

Judge the code and the verification, not the authorship. Everything asserted here is checkable, and
where something was *not* verified this documentation tries to say so plainly.

## License

[GPL-3.0](LICENSE), matching Mod Organizer 2 itself.

Copyright © 2026 Leo Schlosser. The licence is granted by the copyright holder, which is why the
notice exists — it is what makes the GPL grant effective, not a restriction on top of it.

This repository contains no MO2 source. The repositories under `repos/` carry their own licences,
and the third-party texts redistributed with a build are vendored in [`licenses/`](licenses/) and
installed alongside the application.
