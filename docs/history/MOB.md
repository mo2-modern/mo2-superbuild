# mob — the retired orchestrator

**Frozen 2026-08-15. Nothing here is live guidance.** The mob working tree no longer exists on any
machine; see [ADR-027](../DECISIONS.md#adr-027). This file is kept because it explains claims made
in older notes and commit messages, and because four of mob's own bugs are still open PR candidates
in [UPSTREAM.md](../UPSTREAM.md).

`mob` is upstream MO2's build orchestrator (`ModOrganizer2/mob`). It clones, configures, builds and
*installs* each repository in turn so the next one can find it. This project used a fork of it until
the superbuild replaced it.

---

## What the tree looked like

Two trees existed side by side: this repository, and a separate unpublished mob working tree holding
mob itself, its own checkout of the repositories under `build/build/`, Qt under `tools/Qt/`, and the
`tidy/` side trees clangd used.

| Path | What |
|---|---|
| `mob/` | the orchestrator (our fork, branch `modern`) |
| `build/build/` | 33 MO2 repos as git submodules, plus `usvfs`, which mob cloned through its own task and was **not** a submodule |
| `build/install/` | build output; `bin/ModOrganizer.exe` was the thing to run |
| `vcpkg/`, `vcpkg-registry/` | pinned vcpkg clone and our port registry |
| `tools/Qt/` | Qt 6.11.1, 3.3 GB, via `aqtinstall` |
| `tidy/` | tooling-only Ninja trees for clangd — never build artifacts |
| `env.ps1` | session environment — had to be sourced before any build |
| `mob.ini` | machine-local paths; never committed |
| `sync-upstream.ps1` | pulled upstream into every repo's `master`, merged into `modern` |
| `regen-tidy.ps1` | rebuilt the clangd compile databases |

`mob.ini` looked like this, with real absolute paths substituted:

```ini
[paths]
prefix     = <mob-tree>/build
qt_install = <mob-tree>/tools/Qt/6.11.1/msvc2022_64
vcpkg      = <mob-tree>/vcpkg
vs         = <vs>

[tools]
vswhere    = C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe
vcvars     = <vs>/VC/Auxiliary/Build/vcvarsall.bat
```

## Commands

```powershell
.\mob\mob.exe build            # incremental
.\mob\mob.exe build -c         # reconfigure — REQUIRED after any generator or CMake-version change
.\mob\mob.exe build -l 5       # with real compiler output — REQUIRED for any warning work
.\mob\mob.exe build -b <task>  # force rebuild one task
.\mob\mob.exe git branches -a  # which repos are on `modern`
```

A full tree build was **36 tasks, ~10–11 minutes**. mob produced no archive and no installer — the
`installer` task was disabled by default and needed the un-forked
`ModOrganizer2/modorganizer-Installer`. It populated `install\{bin,include,lib,pdb}` and stopped.

---

## The traps, kept because older notes rely on them

🔴 **`mob build` at the default log level printed no compiler output at all.** Its log therefore
grepped as "0 warnings" no matter what the compiler said. `-l 5` was mandatory, and the denominator
had to be checked: a full tree run produced roughly **8000 lines** of real compiler output
(`final.log` had 8527, including 128 usvfs TUs). **Any historical "0 warnings" claim taken from a
short log measured nothing.**

🔴 **Neither `-b` nor `-c` could force a `usvfs` rebuild.** Two independent mob bugs composed, and
`mob build -b usvfs` **reported success in 20 seconds having compiled nothing.** The riskiest
component in the project sat behind this measurement blind spot for the entire project, including in
the old pre-fork tree.

1. `msbuild::do_clean()` degenerated into a **Build** when `targets_` was empty
   (`mob/src/tools/msbuild.cpp:192`). Fixed on our `modern` fork.
2. `mob build -c` still did **not** clean preset-defined binary dirs (`tools/cmake.cpp:273`): its
   clean deleted directories named after mob's *own* generators, and usvfs used
   `vsbuild32`/`vsbuild64`. Never fixed.

The only reliable rebuild was `rm -r build\build\usvfs\vsbuild32, build\build\usvfs\vsbuild64`.

**Consequence worth keeping:** any historical note saying "usvfs rebuilt clean" measured nothing.
The known-good 2026-07-30 log contains exactly **one** `[usvfs]` line.

🔴 **mob resolved `mob.ini` from the current working directory.** Run from anywhere else and every
machine-local path silently reverted to auto-detection: mob never read the ini, fell back to
`vswhere` for VS, and could not find Qt at all — `[conf] can't find qt install (bailing out)`.

**That bail-out was luck, not a safety net.** Qt was the only setting with no auto-detect fallback.
`paths.vs` auto-detected happily, so on a machine where Qt happened to be on `PATH` the same mistake
built to completion against a **different Visual Studio and a different vcpkg**.

🔴 **`vcvarsall.bat` hijacked `VCPKG_ROOT`**, setting it to VS's own bundled vcpkg. mob resolved
`paths.vcpkg` from the shell at startup, so without sourcing `env.ps1` mob silently built against
the wrong vcpkg *while appearing to work*. Symptom when it bit: configure succeeded, build died with
`'"cmake.exe"' is not recognized`.

⚠️ **`mob git add-remote` built SSH URLs** (`tools/git.cpp:33`), which would not authenticate
against an HTTPS + gh-credential-helper setup.

**mob's `-c` took the installed tree out of service for ~10 minutes.** The reconfigure clean wiped
`build\install\bin`, and `platforms\qwindows.dll` was only rewritten at the end of the last task, so
launching MO2 mid-build aborted with *"no Qt platform plugin could be initialized"* — the clean, not
a regression.

---

## Why the fork model was cheap under mob

mob implemented [ADR-001](../DECISIONS.md#adr-001)'s two-branch model natively, through four
`mob.ini` keys and no custom tooling:

```ini
[task]
mo_org            = mo2-modern   ; clone from the fork
mo_branch         = modern       ; check out our branch
mo_fallback       = master       ; repos without `modern` fall back silently
set_origin_remote = true         ; origin=mo2-modern, upstream=ModOrganizer2
remote_org        = mo2-modern
```

`mo_fallback` is what made a staged rollout possible — `modern` branches could be created one repo
at a time while everything else kept building from `master`. The superbuild has no equivalent: its
submodule gitlinks name exact commits, which is stricter and simpler but does not degrade
gracefully.
