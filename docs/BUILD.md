# Building and verifying

Read [TRAPS.md](TRAPS.md) before trusting any build output. Several failure modes in this project
report success: a build that compiles nothing, a log that greps as "0 warnings" because it holds no
compiler output. They are documented there, not repeated here.

## There are two ways to build

**The superbuild** is the one you want. Clone this repository, open the folder in Visual Studio or
Rider, build — Qt installs itself on the first configure ([ADR-024](DECISIONS.md#adr-024)). The
steps are in the [README](../README.md); nothing below is needed for it except
[Verification](#verification), which applies to both.

**mob** is the original orchestrator. It still works, it is still what produces `build\install`, and
both paths are kept green. It needs a separate working tree that is not published, so the setup
below only applies if you are working in that tree.

The rest of this document is troubleshooting, then the mob path, then the verification recipe that
both share.

---

## Troubleshooting

Symptoms a first build actually produces, and what each one means.

| Symptom | Cause and fix |
|---|---|
| Configure stops asking for `git submodule update --init` | Cloned without `--recursive`. Run it; the check exists so you fail here rather than on a missing toolchain file. |
| Configure appears frozen for several minutes with no output | `usvfs` is building, twice, once per architecture. It captures its output, so nothing prints. Expected on the first configure only. |
| Run launches something that immediately fails to start | The startup item is pointing at `build\`, not `install\`. Pick **ModOrganizer 2 (install tree)** in Visual Studio. In Rider, which does not read `.vs\launch.vs.json`, run `install\bin\ModOrganizer.exe` directly. |
| The build is green but `install\` is empty or stale | Expected — install is a separate step ([ADR-023](DECISIONS.md#adr-023)). Run **Build → Install mo2**, or `cmake --install build --config RelWithDebInfo`. |
| You cannot find `install\` or `build\` in Solution Explorer | Both are gitignored, and Visual Studio's Folder View hides ignored items. Toggle **Show All Files** in the Solution Explorer toolbar. |
| 25 submodules show as modified after a build | `lupdate` rewrites each repository's `*_en.ts` in place. It is churn, not damage; clear it with `git -C repos/<name> checkout -- .` and do not commit it. |
| Configure fails on a missing Qt component after a long wait | The Qt module list is incomplete. It is generated from `MO2_QT_MODULES`; do not hand-edit a copy of it anywhere. See [TRAPS.md](TRAPS.md#toolchain). |
| Configure fails saying `qt/` holds the wrong Qt | Deliberate: the build refuses to delete several GB it did not create. Remove `qt/` yourself, or point `-DMO2_QT_DIR=` at a good one. |
| You would rather install Qt by hand | `-DMO2_AUTO_INSTALL_QT=OFF`. Configure then prints the exact `aqt` command and stops. Note that on a cold tree this still runs the full vcpkg install first, so it is not a quick way to obtain the command. |
| You already have an MO2 checkout from mob | `-DMO2_SOURCE_ROOT=<path>` reuses it instead of cloning several GB twice. Configure fails immediately with a clear message if the path is not an MO2 checkout. |

---

## Setting up the mob working tree

Six steps, once per machine. Skip this if you are using the superbuild.

**1. Install the tools.** All are prerequisites; none is fetched for you.

| Tool | Version | Notes |
|---|---|---|
| Visual Studio 2026 | with the **v145** toolset | the C++/CLI plugins need MSBuild. No Ninja-only IDE can build them |
| CMake | 4.4.2 | standalone, not the one bundled with VS. It must come first on `PATH` |
| Python | 3.14, with the **development headers** | both the build's and tooling's. `cmake_common/mo2_versions.cmake` pins `MO2_PYTHON_VERSION` to 3.14, and `plugin_python` asks for it `EXACT` |
| Git, `gh` | any recent | `gh` is used for fork and PR work |
| LLVM | 22.1.8 | for `clang-tidy` and `clangd`. Not required to build |

**2. Get the sources.**

```powershell
git clone --recursive https://github.com/mo2-modern/mob.git F:\dev\mo2-modern\mob
```

The 33 MO2 repos are submodules of `build/build`. `usvfs` is not one of them; mob clones it through
its own task, which is why a recursive clone alone does not produce a buildable tree.

**3. Install Qt.** 3.3 GB. It cannot come from vcpkg, because MO2 needs WebEngine, which means a
Chromium build.

🔁 **Do not copy a module list into this file.** The authoritative one is `MO2_QT_MODULES` in the
superbuild's `CMakeLists.txt`, and the superbuild both installs from it and prints it. Get the exact
command by running a configure with the download turned off:

```powershell
cmake --preset vs2026 -DMO2_AUTO_INSTALL_QT=OFF
```

It stops with the full `aqt` command, correct by construction. Change `-O` to the mob tree's
`tools\Qt` if that is the tree you are populating. This indirection is deliberate: this file used to
carry its own copy of the list, it drifted, and two required modules went missing from it for four
months — see [TRAPS.md](TRAPS.md#toolchain).

Two things are easy to get wrong. **aqt must come from git**: the PyPI release lags Qt's repository
layout. **The module list is not optional**, and it fails in two directions:

- `qtwebsockets` and `qtnetworkauth` are **build** requirements — `modorganizer/src/CMakeLists.txt`
  names both. Omitting either stops configure with *"Failed to find required Qt component"*, and it
  stops there **after** vcpkg has built every dependency, so you find out roughly half an hour in.
- `qtimageformats` is a **runtime** requirement and fails silently instead. Upstream CI compiles MO2
  without launching it, so its list omits runtime-only modules. Without this one you get 4 image
  plugins instead of 9, and MO2 cannot render TGA, TIFF or WebP mod previews. Nothing fails at
  build time.

**4. Get vcpkg.**

```powershell
git clone https://github.com/microsoft/vcpkg.git F:\dev\mo2-modern\vcpkg
git -C F:\dev\mo2-modern\vcpkg checkout ea1a7396b05637a53bf23c078647ecc0edee4b80
```

That commit is the baseline every manifest in the tree declares. Do not use a newer one without
updating the baselines with it.

**5. Write `mob.ini`** in the root of the working tree. It is never committed, because every path in
it is specific to one machine. mob reads it from the current working directory, so always run mob
from that root; run it from anywhere else and mob silently falls back to auto-detection.

```ini
[paths]
prefix     = F:/dev/mo2-modern/build
qt_install = F:/dev/mo2-modern/tools/Qt/6.11.1/msvc2022_64
vcpkg      = F:/dev/mo2-modern/vcpkg
vs         = C:/Program Files/Microsoft Visual Studio/18/Community

[tools]
vswhere    = C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe
vcvars     = C:/Program Files/Microsoft Visual Studio/18/Community/VC/Auxiliary/Build/vcvarsall.bat
```

Set `vcpkg` and `vs` explicitly, not from the environment. Visual Studio's `vcvarsall.bat`
overwrites `VCPKG_ROOT` with its own bundled vcpkg, and `vswhere -version 17` is a minimum, so with
both VS2022 and VS2026 installed it matches both and mob bails out.

**6. Install the commit hooks, per repo.** They are not cloned.

```powershell
py -3.14 -m pre_commit install
```

Paths in this document are `F:\dev\mo2-modern` because that is the tree they were written against.
Nothing requires that location except `mob.ini` and `env.ps1`, both of which you are editing anyway.

---

## Every session starts here

```powershell
cd F:\dev\mo2-modern
.\env.ps1
```

**The banner must show `VS .../18/Community` and `cmake 4.4.2`.** If it does not, stop — you are
about to build against the wrong toolchain, and it will mostly appear to work.

🔴 **`env.ps1` is not optional.** VS's `vcvarsall.bat` sets `VCPKG_ROOT` to VS's own bundled vcpkg,
and mob resolves `paths.vcpkg` from the shell at startup. Without `env.ps1`, mob silently builds
against the wrong vcpkg while still appearing to work.

Verify before building:

```powershell
cmake --version        # 4.4.2
$env:VCPKG_ROOT        # the pinned clone, not <VS>\VC\vcpkg
```

---

## Commands

```powershell
.\mob\mob.exe build            # incremental
.\mob\mob.exe build -c         # reconfigure — REQUIRED after any generator or CMake-version change
.\mob\mob.exe build -l 5       # with real compiler output — REQUIRED for any warning work
.\mob\mob.exe build -b <task>  # force rebuild one task
.\mob\mob.exe git branches -a  # which repos are on `modern`

.\sync-upstream.ps1            # pull upstream into every repo's master, merge into modern
.\regen-tidy.ps1               # refresh clangd's compile databases after adding/removing sources
```

**Forcing a `usvfs` rebuild** — the only reliable way:

```powershell
rm -r build\build\usvfs\vsbuild32, build\build\usvfs\vsbuild64
```

A full tree build is **36 tasks, ~10–11 minutes**.

### When `-c` is mandatory

- the **generator** changed
- the **CMake version** changed
- you are about to trust a **total** warning count (an incremental build under-reports)

⚠️ `-c` takes the installed tree out of service for the duration. Launching MO2 mid-build aborts
with *"no Qt platform plugin could be initialized"* — that is the clean, not a regression.

⚠️ `-c` does **not** clean `usvfs`. See above.

---

## Reading the log

🔴 **`mob build` at the default log level prints no compiler output at all**, so its log greps as
"0 warnings" regardless of what the compiler said.

```powershell
.\mob\mob.exe build -l 5 *> build.log
```

**Then check the denominator before believing any zero:** a full tree run produces roughly **8000
lines** of compiler output. `final.log` — the definitive full-tree run — has 8527, including 128
usvfs translation units. A "0 warnings" result from a 200-line log is measuring nothing.

Root-level logs are only the ones the docs cite:

| Log | What |
|---|---|
| `final.log` | **the definitive full-tree run** — 0 errors / 0 warnings, `/WX` everywhere |
| `usvfs-wx.log` | usvfs's first verified `/WX` build |
| `tree-baseline.log`, `warnwalk2.log` | warning-campaign inventories |
| `baseline-mo.log`, `baseline-usvfs.log`, `baseline-usvfs2.log` | pre-campaign baselines |

Everything superseded lives in `logs-archive/` and nothing references it.

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

1. `.\env.ps1` — banner shows VS 18 and cmake 4.4.2
2. `mob build -l 5` from clean; confirm the generator line reads `Visual Studio 18 2026` / `v145`
3. `ctest` where targets exist (`uibase`, `plugin_python`)
4. **Launch `ModOrganizer.exe`, add a game instance, install a mod, and launch the game through it**
5. Diff `build\install\bin` against the known-good `F:\dev\mo2\build\install\bin`

### Proof that usvfs actually worked

Read the instance's `logs\usvfs-*.log`. Lines reading **`type overwrite`** or **`type chained
patch`** mean trampolines were really built — that is the libudis86 code path, since the
disassembler is what finds instruction boundaries in the target prologue.

**Their absence means the DLL loaded but hooked nothing, which is not a verification.**

A good log also shows injection into three processes (MO2, the loader, the game),
`inithooks in process <pid> successful`, real VFS mapping, and a clean teardown.

### Diffing the install tree

⚠️ **Wipe `build\install` and re-run `mob build` first.** `cmake --install` never deletes, so the
tree accumulates stale artifacts that silently invalidate the diff — after the Python 3.13 → 3.14
bump it held **262 stale `*313*` files**.

Expect noise you must filter out: `__pycache__\*.pyc` (~257 files), runtime files (`*.ini`, `*.log`,
`*.dat`), and Python-version artifacts (`cp313` vs `cp314`, `python313.dll`, and the 3.14-only
stdlib modules `_zstd.pyd` / `_remote_debugging.pyd`). **Anything left after filtering those is
real.**

### Paths worth re-checking on any change

These fail *silently* rather than loudly:

- **Gamebryo save-game parsing** — a stream-position slip corrupts the plugin list
- **Save timestamps** — `QTimeZone::UTC` touches every Gamebryo save
- **BSA read/write** — `bsatk`'s `writeBString` clamp
- **LOOT sorting** — `lootcli`'s `GetFile` restructure
- **Username masking** — `mo_interface.log` must show `C:/Users/USERNAME/...`; a regression leaks
  the real username into logs
- **UI paths that log nothing** — mod-list filtering, Group by, Change Categories, the categories
  editor. These must be clicked by hand.

### What mob does not do

**mob produces no archive and no installer.** The `installer` task is disabled by default and needs
the un-forked `ModOrganizer2/modorganizer-Installer`. `mob build` populates
`install\{bin,include,lib,pdb}` and stops there.
