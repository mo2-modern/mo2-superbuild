# Building and verifying

Read [TRAPS.md](TRAPS.md) before trusting any build output. Several failure modes in this project
report success rather than failing: a build that deploys nothing, a `ctest` that runs nothing and
exits 0. They are documented there, not repeated here.

The build steps themselves are in the [README](../README.md) — clone, open the folder, build,
install. This document is what to do when that does not go smoothly, and how to verify a result once
it does.

> There used to be a second way to build, through `mob`. It is retired
> ([ADR-027](DECISIONS.md#adr-027)) and the working tree it needed no longer exists; the superbuild
> is the only path. What mob did, and the traps that came with it, are frozen in
> [`history/MOB.md`](history/MOB.md) for anyone reading older notes.

---

## Troubleshooting

Symptoms a first build actually produces, and what each one means.

| Symptom | Cause and fix |
|---|---|
| Configure stops asking for `git submodule update --init` | Cloned without `--recursive`. Run it; the check exists so you fail here rather than on a missing toolchain file. |
| Configure appears frozen for several minutes with no output | `usvfs` is building, twice, once per architecture. It captures its output, so nothing prints. Expected on a first configure, and again after a toolchain or `usvfs` source change. |
| Run fails with *"the application configuration is incorrect"* | The startup item is pointing into `build\`, whose `ModOrganizer.exe` has no dependencies beside it. Pick **ModOrganizer 2 (install tree)**. In Rider, which does not read `.vs\launch.vs.json`, run `install\bin\ModOrganizer.exe` directly. |
| **ModOrganizer 2 (install tree)** is missing from the startup dropdown | It resolves a path to `install\bin\ModOrganizer.exe`, so it only appears after a successful install. Run **Build → Install mo2** first. |
| The build is green but `install\` is empty or stale | Expected — install is a separate step ([ADR-023](DECISIONS.md#adr-023)). Run **Build → Install mo2**, or `cmake --install build --config RelWithDebInfo`. |
| You cannot find `install\` or `build\` in Solution Explorer | Both are gitignored, and Visual Studio's Folder View hides ignored items. Toggle **Show All Files** in the Solution Explorer toolbar. |
| 25 submodules show as modified after a build | `lupdate` rewrites each repository's `*_en.ts` in place. It is churn, not damage; clear it with `git -C repos/<name> checkout -- .` and do not commit it. |
| Configure fails on a missing Qt component after a long wait | The Qt module list is incomplete. It is generated from `MO2_QT_MODULES`; do not hand-edit a copy of it anywhere. See [TRAPS.md](TRAPS.md#toolchain). |
| Configure fails saying `qt/` holds the wrong Qt | Deliberate: the build refuses to delete several GB it did not create. Remove `qt/` yourself, or point `-DMO2_QT_DIR=` at a good one. |
| Configure fails on a hash mismatch | Do not work around it. An upstream tag was re-pushed at different bytes, or a PyPI release changed — that is the situation the hashes exist to catch. See [CONTRIBUTING](../CONTRIBUTING.md#bumping-a-pinned-version). |
| A `usvfs` change seems to have no effect | It is built at configure time and skipped while the stamp matches. The stamp carries the toolchain *and* the `usvfs` revision, so a committed change rebuilds automatically; an uncommitted one does too. If you need to force it, delete `build\usvfs-install`. |
| You already have an MO2 checkout elsewhere | `-DMO2_SOURCE_ROOT=<path>` builds that instead of the submodules. Configure says so on every run, and fails immediately with a clear message if the path is not an MO2 checkout. |

---

## Installing Qt by hand

Configure downloads Qt when it cannot find one ([ADR-024](DECISIONS.md#adr-024)). To do it yourself:

```powershell
cmake --preset vs2026 -DMO2_AUTO_INSTALL_QT=OFF
```

Configure then prints the exact `aqt` command and stops. On a cold tree this still runs the full
vcpkg install first, so it is not a quick way to obtain the command.

🔁 **Do not copy the module list into this file, or any other.** The authoritative one is
`MO2_QT_MODULES` in `CMakeLists.txt`, and both the download and the printed command are generated
from it. This document used to carry its own copy, it drifted, and two required modules went missing
from it for four months — see [TRAPS.md](TRAPS.md#toolchain).

Two things are easy to get wrong. **aqt must come from git**: the PyPI release lags Qt's repository
layout. **The module list is not optional**, and it fails in two directions:

- `qtwebsockets` and `qtnetworkauth` are **build** requirements — `modorganizer/src/CMakeLists.txt`
  names both. Omitting either stops configure with *"Failed to find required Qt component"*, and it
  stops there **after** vcpkg has built every dependency, so you find out roughly half an hour in.
- `qtimageformats` is a **runtime** requirement and fails silently instead. Upstream CI compiles MO2
  without launching it, so its list omits runtime-only modules. Without this one you get 4 image
  plugins instead of 9, and MO2 cannot render TGA, TIFF or WebP mod previews. Nothing fails at
  build time.

---

## Committing

Commits are **GPG-signed**, and `pre-commit` runs clang-format **pinned per repo**.

```powershell
py -3.14 -m pre_commit install                       # per repo — hooks are NOT cloned
py -3.14 -m pre_commit run --files <changed files>   # format without committing
```

Expect the reformat-then-recommit loop on C++ changes.

🚫 **Never hand-format with the LLVM clang-format on PATH (22.1.8)** — it matches **no** repo's pin.
🚫 **Never use `sed -i` or any LF-writing tool.** See [TRAPS.md](TRAPS.md#editing-source) — this cost
a force-push once.
🚫 **Never add AI/assistant attribution to commits or PRs.** No `Co-Authored-By`, no "Generated
with", no 🤖 line. The author is the repo owner. These commits are upstream PR candidates against 34
real projects; an assistant trailer is noise that has to be stripped before submission.

Cheap pre-commit check: **every changed file must have 0 bare LF.**

```powershell
git diff --name-only | ForEach-Object {
  if ([regex]::Matches([IO.File]::ReadAllText((Resolve-Path $_)), "(?<!`r)`n").Count) { "BARE LF: $_" }
}
```

---

## Verification

🔴 **A green build is not verification.** `usvfs` is DLL injection; compiling proves nothing about
it. **Opening a mod list is not enough either** — usvfs only injects when you launch a program
**through** MO2.

### The standard pass

1. Configure, build and install from a clean tree; confirm the generator line reads
   `Visual Studio 18 2026` / `v145`
2. Confirm `install\bin\ModOrganizer.exe` exists — **never assert on the build's exit code**
   ([TRAPS.md](TRAPS.md#superbuild-and-clone))
3. **Launch it, add a game instance, install a mod, and launch the game through it**
4. Read the instance's usvfs log, below

CI performs a mechanical version of steps 1 and 2 on every dispatched run — it asserts the
application, uibase, both usvfs architectures and proxies, the Qt platform plugin and runtime, and
non-empty plugin, stylesheet and licence counts. The image-plugin count is the only automated check
in the project that can see a missing `qtimageformats`.

🔴 **`ctest` runs nothing and reports success.** Verified 2026-08-15: `ctest -C RelWithDebInfo` in
`build/` prints *"No tests were found!!!"* and **exits 0**. Do not use it as a verification step, and
do not read a passing `ctest` as evidence of anything.

The cause is not that the tests are missing. `uibase`, `bsapacker` and `plugin_python` each carry a
`tests/` directory gated on `BUILD_TESTING`, and the superbuild never calls `include(CTest)` or
`enable_testing()`, so `BUILD_TESTING` is off, the subdirectories are never added, and no
`CTestTestfile.cmake` is generated.

**Turning it on is not a one-line change.** Those repositories declare `gtest` in their own
`vcpkg.json`, but the superbuild builds from a single root manifest that does not, so enabling
`BUILD_TESTING` without first adding `gtest` there fails at `find_package`. That is a deliberate
decision to take, not an oversight to patch: it adds a dependency and lengthens every build.

### Proof that usvfs actually worked

Read the instance's `logs\usvfs-*.log`. Lines reading **`type overwrite`** or **`type chained
patch`** mean trampolines were really built — that is the libudis86 code path, since the
disassembler is what finds instruction boundaries in the target prologue.

**Their absence means the DLL loaded but hooked nothing, which is not a verification.**

A good log also shows injection into three processes (MO2, the loader, the game),
`inithooks in process <pid> successful`, real VFS mapping, and a clean teardown.

### Diffing the install tree

⚠️ **Wipe `install\` and re-install first.** `cmake --install` never deletes, so the tree accumulates
stale artifacts that silently invalidate any diff against a reference build — after the Python
3.13 → 3.14 bump it held **262 stale `*313*` files**, including a dead `python313.dll`.

Expect noise you must filter out: `__pycache__\*.pyc` (~257 files), runtime files (`*.ini`, `*.log`,
`*.dat`), and Python-version artifacts. **Anything left after filtering those is real.**

### Paths worth re-checking on any change

These fail *silently* rather than loudly:

- **Gamebryo save-game parsing** — a stream-position slip corrupts the plugin list
- **Save timestamps** — `QTimeZone::UTC` touches every Gamebryo save
- **BSA read/write** — `bsatk`'s `writeBString` clamp
- **LOOT sorting** — `lootcli`'s `GetFile` restructure
- **Username masking** — the instance's `mo_interface.log` must show `C:/Users/USERNAME/...`; a
  regression leaks the real username into logs
- **UI paths that log nothing** — mod-list filtering, Group by, Change Categories, the categories
  editor. These must be clicked by hand.

### There is no packaging step

The build produces an install tree and stops. No archive, no installer — that needs
`ModOrganizer2/modorganizer-Installer`, which is not part of this project.
