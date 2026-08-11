# Phases 0-1 - bootstrap and toolchain migration (ARCHIVE)

> **Status: COMPLETE, 2026-08-09. Tagged `toolchain-vs2026` in all 34 repos.**
>
> This is the step-by-step record of moving MO2 from VS2022 / MSVC v143 / CMake 3.31.6 / Python 3.13
> onto **VS2026 / MSVC v145 / CMake 4.4.2 / Qt 6.11.1 / Python 3.14**, with the existing source
> building and running unchanged.
>
> **You do not need to read this to work on the project.** It is here because the *method* - change
> exactly one toolchain variable per build - is worth reusing at the next toolchain jump, and
> because several findings are load-bearing (why `qt_vs` stays `2022`, why the Qt module list is
> larger than upstream CI's, why two Pythons are correct).
>
> The durable rules extracted from this phase live in [`../TRAPS.md`](../TRAPS.md),
> [`../DECISIONS.md`](../DECISIONS.md) and [`../BUILD.md`](../BUILD.md). Those are maintained;
> this file is frozen.

---

## PHASE 0 — Bootstrap

### Step 0.1 — Create the directory and grant access
```powershell
mkdir F:\dev\mo2-modern
```
Then in Claude: `/add-dir F:\dev\mo2-modern`
**Check:** I can read the new dir, and still read `F:\dev\mo2`.

### Step 0.2 — Install `gh` (not currently installed)
```powershell
winget install --id GitHub.cli -e
gh auth login            # interactive — run as `! gh auth login`
```
**Check:** `gh auth status` shows you logged in.

### Step 0.3 — Verify all 49 forks are clean
The 7 I sampled were identical; confirm the rest.
```powershell
gh repo list mo2-modern --limit 100 --json name -q '.[].name' | ForEach-Object {
  $r = gh api "repos/mo2-modern/$_" -q '.parent.full_name + " " + .default_branch' 2>$null
  if ($r) { $p,$b = $r.Split(' ')
    gh api "repos/mo2-modern/$_/compare/$b...$($p.Split('/')[0]):$_`:$b" -q "\"$_ -> \(.status) ahead:\(.ahead_by) behind:\(.behind_by)\"" 2>$null }
}
```
**Check:** every line reads `identical ahead:0 behind:0`. Anything else, we look at it together.

### Step 0.4 — Install VS 2026, keep VS 2022
```powershell
winget install --id Microsoft.VisualStudio.Community -e
```
Workloads: **Desktop development with C++** (gives `v145` / MSVC 14.51), **.NET desktop**
(`installer_fomod_csharp` builds C++/CLI), Windows SDK 10.0.26100+.

> ⚠️ **Having both toolchains breaks mob's auto-detection.** `vswhere -version 17`
> (`tools/tools.cpp:180`) is a *minimum*, so it matches 2022 **and** 2026, and mob bails with
> "vswhere returned multiple installations" (`core/paths.cpp:234`). The fix: pin `paths.vs`
> explicitly in `mob.ini`, which short-circuits detection (`core/conf.cpp:511`, `set_path_if_empty`).
> Your old `build\mob.ini` already does this — we carry the pattern over.

**Check:** `vswhere -all -products * -format value -property installationVersion` lists both 17.x and 18.x.

### Step 0.5 — Clone mob from your fork
```powershell
cd F:\dev\mo2-modern
git clone https://github.com/mo2-modern/mob.git
cd mob
git remote add upstream https://github.com/ModOrganizer2/mob.git
git switch -c modern
git push -u origin modern
```
**Check:** `git remote -v` shows origin=mo2-modern, upstream=ModOrganizer2; you're on `modern`.

### Step 0.6 — Build mob itself
```powershell
.\bootstrap.ps1
```
This builds mob with **VS 2022 first** — we change one variable at a time. Do not point mob at
VS 2026 yet.
**Check:** `mob.exe` exists and `.\mob.exe --version` runs.

---

## PHASE 1 — Toolchain modernization

*Detailed step-by-step written when Phase 0 is green. Outline and the key findings:*

### 1.1 — Point mob at your fork
Set the `[task]` keys from the fork-model section above in `mob.ini`. Run `mob build` on VS 2022
**first**. This isolates "does the fork work?" from "does VS 2026 work?" — if this build is green,
the fork is proven and any later breakage is the toolchain's fault.

### 1.1c — METHOD: change exactly one toolchain variable per build
Installing standalone CMake made an *implicit* variable explicit: the baseline used VS-bundled
CMake **3.31.6**, and simply pointing `env.ps1` at VS2026 would have silently swapped in VS2026's
CMake **4.3.1** alongside the compiler. Standalone CMake (**4.4.2**, `C:\Program Files\CMake\bin`,
placed first on PATH) decouples them. Sequence:

| Step | Compiler | CMake |
|---|---|---|
| 1.1 baseline ✅ | VS2022 / v143 | 3.31.6 |
| 1.1c | VS2022 / v143 | **4.4.2** |
| 1.2 | **VS2026 / v145** | 4.4.2 |

**Always use `-c` when the CMake version changes.** (Corrected 2026-08-09 — an earlier note here
claimed a version bump reconfigures in place. It does not.) Verified: CMake 4.4.2 re-running inside
a build tree created by 3.31.6 leaves `CMAKE_CXX_COMPILE_FEATURES` empty, and every **C++/CLI**
target then fails at generate time with:
```
CMake Error in src/CMakeLists.txt:
  No known features for CXX compiler "MSVC" version 19.44.35228.0.
```
Symptom fingerprint: the build tree's `CMakeFiles/` contains **two** version dirs (`3.31.6-msvc6`
*and* `4.4.2`). Deleting `vsbuild` and configuring fresh succeeds. Affects `installer_omod` and
`installer_fomod_csharp` — the only two `/clr` targets in the set. A *generator* change likewise
requires `-c`.

**Decision 2026-08-09: stay on standalone CMake 4.4.2, ahead of VS2026's bundled 4.3.1.** Rationale:
Microsoft will bump the bundled CMake eventually, so this breakage is inevitable — meeting it
deliberately now beats meeting it during an unrelated VS update. Being early also means our fixes
(e.g. `installer_omod`) are ready before upstream needs them.

Note: **vcpkg ignores the global CMake** and downloads its own (observed: 4.4.0). Ninja is
irrelevant here — every task uses the VS generator → msbuild (`modorganizer.cpp:180`,
`usvfs.cpp:91`), so ninja is never invoked.

### 1.2 — VS 2026 is a 3-line change
mob builds its generator as `"Visual Studio " + version + " " + year` (`tools/cmake.cpp:284`) and
its toolset as `"v" + toolset.replace(".","")` (`msbuild.cpp:132`). So:

```ini
[versions]
vs         = 18       ; was 17  → generator "Visual Studio 18 2026"
vs_year    = 2026     ; was 2022
vs_toolset = 14.5     ; was 14.3 → toolset v145
qt_vs      = 2022     ; ← LEAVE ALONE
```

**`qt_vs` stays `2022`.** Microsoft guarantees a stable ABI across all of 14.x — v140/v141/v142/
v143/**v145** binaries interlink. The `msvc2022_64` Qt build links fine against v145, and
`paths.cpp:81` derives the Qt directory name from `qt_vs`, so changing it only breaks the path.

### 1.2c — TRAP: vcpkg picks its own Visual Studio, independent of mob
Found 2026-08-09. `mob\custom-triplets\x64-windows-static-md.cmake` sets **no
`VCPKG_PLATFORM_TOOLSET`**, so vcpkg auto-detects VS and uses the **newest installed**. Merely
*installing* VS2026 switched every dependency to `vc145` while mob still built MO2 with v143
(`paths.vs` only controls mob's vcvars). Result — `modorganizer` fails at link:
```
boost_program_options-vc145-mt-x64-1_89.lib : error LNK2001:
  unresolved external symbol __std_find_first_not_of_trivial_pos_1
ModOrganizer.exe : fatal error LNK1120: 2 unresolved externals
```
Those are v145-only vectorized STL helpers.

**Precise ABI rule** (refines the loose "v143↔v145 interlink" note elsewhere): the linker must be
the **same version as its inputs or newer**.
- deps `v143` → app `v145` ✅ supported — this is what makes the 1.3 fallback viable
- deps `v145` → app `v143` ❌ unsupported — the accidental case above

**Diagnostic:** `ls build\build\modorganizer\vsbuild\vcpkg_installed\x64-windows-static-md\lib` and
read the `vcNNN` infix. To pin deliberately, add to the custom triplet:
`set(VCPKG_PLATFORM_TOOLSET v143)` plus `set(VCPKG_VISUAL_STUDIO_PATH "...")`.

### 1.2d — VS2026 emits `.slnx`, not `.sln`
The `Visual Studio 18 2026` generator writes `usvfs.slnx` (the XML solution format). **There is no
CMake variable to choose the format.** mob hardcoded `usvfs.sln` at `tasks/usvfs.cpp:100`, so
configure succeeded and the build then failed with `MSBUILD : error MSB1009: Project file does not
exist.` Only usvfs is affected — it is the one task mob builds by invoking msbuild directly;
everything else uses `cmake --build`, which finds the solution itself. Fixed on `modern` by
preferring `.slnx` and falling back to `.sln`. MSBuild 18.8 reads `.slnx` natively.

### 1.2e — what the VS2026 switch actually required (my "3-line change" was wrong)
`mob.ini` alone was **not** enough. Preset-based tasks ignore `[versions]` entirely. The full set:
1. `mob.ini` `[versions]` → `vs=18`, `vs_year=2026`, `vs_toolset=14.5`
2. local `mob.ini` `[paths] vs` + `[tools] vcvars` → `...\18\Community`
3. **`CMakePresets.json` in all 33 repos** — `vs2022-windows*` → `vs2026-windows*`,
   generator → `Visual Studio 18 2026`, toolset → `v145`; plus 7 CI `build.yml` preset references
4. `mob` source — derive the preset name from `vs_year` instead of hardcoding it
   (`tasks/modorganizer.cpp`, `tasks/usvfs.cpp`), and accept `.slnx`
5. `mob/CMakePresets.json` — mob builds *itself* with VS2026 too, else it links v143 against
   v145 vcpkg deps
6. Delete every `build\build\*\vsbuild*` — CMake cannot switch generators in an existing cache, and
   `mob build -c` misses usvfs's non-standard `vsbuild32`/`vsbuild64`

### 1.3 — vcpkg + v145 is the highest risk
[microsoft/vcpkg#49058](https://github.com/microsoft/vcpkg/issues/49058) — "VS 2026 not recognized
as a valid instance" — is **still open**, and neither `VCPKG_FORCE_SYSTEM_BINARIES` nor
`VCPKG_VISUAL_STUDIO_PATH` worked around it. In order:

1. Use a current vcpkg and retry — fixes land continuously.
2. Overlay triplet with `VCPKG_PLATFORM_TOOLSET v145` (mob has `custom-triplets/` plumbing; the
   build uses `x64-windows-static-md`).
3. **Split the toolchains.** Let vcpkg build *dependencies* with v143 while MO2 builds with v145.
   Not a hack — it's the documented ABI guarantee, and it shrinks the blast radius to MO2's own
   code. If vcpkg fights us, take this and move on.

### 1.2b — GOTCHA: `vcvarsall.bat` hijacks `VCPKG_ROOT`
Verified 2026-08-09: VS2022's `vcvarsall.bat` **sets `VCPKG_ROOT` to VS's own bundled vcpkg**
(`<VS>\VC\vcpkg`), and its PATH includes VS's cmake. mob resolves `paths.vcpkg` from the *shell's*
`VCPKG_ROOT` at startup, so if `env.ps1` isn't dot-sourced, mob silently builds against VS's vcpkg
instead of our pinned clone — while still appearing to work, because vcvars supplies cmake.

Symptom when it bites: cmake **configure** succeeds but the **build** step dies with
`'"cmake.exe"' is not recognized` — the build step runs without the vcvars environment.

**Fix: set `vcpkg` explicitly in the local `mob.ini` `[paths]`**, never rely on `VCPKG_ROOT`.
Always `. .\env.ps1` first and verify `cmake --version` and `$env:VCPKG_ROOT` before building.
Recovery after a wrong-toolchain configure: `mob build -c` (`--reconfigure` deletes the generator
dirs, `cmake.cpp:273`) — CMake bakes `CMAKE_TOOLCHAIN_FILE` into its cache, so a plain re-run
will not switch it.

### 1.3b — Qt acquisition: aqtinstall MUST come from git, not PyPI
**mob has no Qt task** — Qt is an external prerequisite that `aqtinstall` provides, and mob just
reads it via `paths.qt_install` (`core/paths.cpp:81` builds the dir name as `msvc<qt_vs>_64`).

**PyPI's `aqtinstall` lags behind Qt's repository layout changes.** Verified 2026-08-09: PyPI stable
is **3.3.0**, while the known-good 2026-07-30 build required **3.3.1.dev162** (a git build). A stable
install cannot resolve Qt 6.11.1's paths. Always:

```powershell
python -m pip install --user --upgrade "aqtinstall @ git+https://github.com/miurahr/aqtinstall.git"
python -m aqt install-qt windows desktop 6.11.1 win64_msvc2022_64 `
  -m qtpositioning qtwebchannel qtwebengine qtwebsockets qtnetworkauth qtserialport qttasktree `
  -O F:\dev\mo2-modern\tools\Qt
```

**`qt_vs` stays `2022` — verified against the repository, not assumed.** `aqt list-qt windows desktop
--arch` reports the same architectures for **6.11.1 and 6.12.0**: `win64_msvc2022_64`,
`win64_msvc2022_arm64_cross_compiled`, `win64_mingw`, `win64_llvm_mingw`. **No msvc2026 build
exists.** Re-check at every Qt bump rather than assuming — Qt did ship separate `msvc2019_64` and
`msvc2022_64` builds even though v142/v143 are ABI-compatible, so ABI compatibility alone does not
predict Qt's packaging.

> ⚠️ **Two Pythons — always invoke tooling as `py -3.14 -m <tool>`.** Installing Python 3.13 put it
> ahead of 3.14 on PATH, so bare `python` resolves to **3.13** even though `py -0p` shows 3.14 as
> the launcher default. `aqt` and `pre-commit` live in 3.14's user site-packages and fail with
> "No module named aqt" under 3.13. **This split is correct, don't unify it:** 3.13 is the *build's*
> Python (CMake finds it via `HKCU\SOFTWARE\Python\PythonCore\3.13`, not PATH), 3.14 is *tooling's*.

**Qt policy: newest stable only.** Decided 2026-08-09 — stay on 6.11.1 (the newest 6.11); do not
chase 6.12 pre-releases even though 6.12.0 is already in the repository.

**`qttasktree` fixes the `Qt6QmlAssetDownloaderPrivate` warning.** Qt ships that private QML plugin
but not its `Qt6TaskTree` dependency by default, so `Qt6QmlConfig.cmake:199` (which auto-includes
every QML plugin config) emits a NOT FOUND warning in *every* repo's configure. The module is
installable — no source or Qt-tree patching needed.

Base archives (`qtbase`, `qtdeclarative`, `qtsvg`, `qttools`, `qttranslations`, `d3dcompiler_47`,
`opengl32sw`) come by default. **Re-check the module list when bumping to Qt 6.12** — it is the
single most likely step to break.

> ⚠️ **Upstream's CI `qt-modules:` list is INCOMPLETE for a runnable build.** CI compiles MO2 and
> never launches it, so runtime-only modules are missing from it. Two confirmed gaps, both found by
> diffing against the known-good build (2026-08-09):
> - **`qtserialport`** — `Qt6SerialPort.dll` is listed in `modorganizer/src/dlls.manifest.qt6` and
>   shipped by the known-good build.
> - **`qtimageformats`** — provides `qtiff / qwebp / qtga / qicns / qwbmp` plugins. Without it the
>   build silently produces 4 image format plugins instead of 9, and MO2 cannot render TGA/TIFF/WebP
>   mod preview images. Nothing fails at build time.
>
> **CORRECTION (2026-08-09): a missing `dlls.manifest` entry is NOT fatal.** `liblz4.dll` is listed
> in the manifest but present in *neither* build, and the known-good build ran fine (runtime
> `ModOrganizer.ini` + usvfs logs prove it). Almost certainly a stale upstream entry — the
> `x64-windows-static-md` triplet links lz4 statically, so that DLL never exists. Treat the manifest
> as a cross-check, not a spec.
>
> ⚠️ **The install tree accumulates stale artifacts — `cmake --install` never deletes.** After the
> Python 3.13 → 3.14 bump the tree held **262 stale `*313*` files** (including a whole dead
> `python313.dll`, `mobase.cp313.pyd`, `sip.cp313.pyd`) beside 262 fresh `*314*` ones. Any change
> that renames outputs leaves the old ones behind forever, which silently invalidates the
> diff-against-known-good check below. **Before trusting that diff, or before shipping, wipe
> `build\install` and re-run `mob build`** (no `-c` — build dirs are unaffected, only the install
> step re-runs).
>
> **Authoritative verification recipe** — diff the whole `install\bin` tree against the known-good
> `F:\dev\mo2\build\install\bin`. Expect noise you must filter: `__pycache__\*.pyc` (~257 files),
> runtime files (`*.ini`, `*.log`, `*.dat`), and Python-version artifacts (`cp313` vs `cp314`,
> `python313.dll`, and 3.14-only stdlib modules `_zstd.pyd` / `_remote_debugging.pyd`). Anything
> left over after filtering those is real.

### 1.1b — DECISION: the baseline is UNMODIFIED upstream source
Decided 2026-08-09. Phase 1.1's baseline build carries **zero source changes** — every repo builds
from upstream `master` via the fork. The only modernization commit anywhere is `mob.ini`'s three
fork-identity lines (`cdd5779`). Rationale: if the baseline is green, "the fork builds upstream's
code on VS2022" is proven with no confound; every later failure is attributable to exactly one
deliberate change.

Consequence: **Python 3.13 must be installed**, because upstream `cmake_common/mo2_versions.cmake:34`
pins `MO2_PYTHON_VERSION "3.13"` and `mo2_utils.cmake:52` does
`find_package(Python ${MO2_PYTHON_VERSION} EXACT ...)`. Install via
`winget install --id Python.Python.3.13 -e` and **do not add it to PATH** — `python` must stay 3.14,
which is where `aqt` and `pre-commit` live. CMake finds 3.13 through the Windows registry
(`HKCU\SOFTWARE\Python\PythonCore\3.13`), not PATH. Note `mo2_python.cmake:114`
(`mo2_python_install_pyqt`) pip-installs PyQt6/SIP into whichever Python it finds, so 3.13 gets its
own isolated set — which also validates upstream's pinned PyQt 6.11.0 / SIP 6.15.3 as-is.

### 1.4 — Python 3.14 (deliberate, isolated — AFTER the baseline is green)
The old tree ran 3.14 via a hand-patch to `mo2_versions.cmake:34` (uncommitted, `.bak` left behind),
so 3.14 is known to work end-to-end. Promote it to a real commit on `cmake_common`'s `modern`
branch — this will be the **first** repo to get a `modern` branch, and the first test of the
`mo_fallback` staged rollout.

### 1.4b — original Python notes
`cmake_common/mo2_versions.cmake:34` was hand-patched 3.13 → 3.14 in the old tree (uncommitted,
with a stray `.bak`). Make it a real commit on `cmake_common`'s `modern` branch. First verify
PyQt6 6.11.0 / SIP 6.15.3 (lines 37–39) have cp314 wheels — if not, we stay on 3.13 and this slips
to Phase 2.

### 1.5 — Definition of done
- `mob build` populates `install\{bin,include,lib,pdb}`. **mob does not produce an archive or an
  installer** — the `installer` task is disabled by default (`mob.ini` `[installer:task] enabled=false`,
  needs the un-forked `ModOrganizer2/modorganizer-Installer`). The old tree's
  `Mod.Organizer-2.5.2-efe2a02.7z.7z` was packed by hand, not by mob.
- **It launches, manages a real mod list, and starts a game through it.** usvfs is a DLL-injection/
  hooking library (`asmjit` + `libudis86`); a clean compile proves *nothing* about it. Hand-test it.
- VS 2022 still works as a fallback (keep `mob.ini` versioned so you can flip back)

---

## CMake 4.4.2 broke `installer_omod` - found and fixed 2026-08-09 (see 1.1c above)

> Kept in full because of the **dead ends** list: three plausible fixes that do not work, and
> retrying them is the natural instinct. Also a strong upstream PR candidate - see
> [`../UPSTREAM.md`](../UPSTREAM.md).

**Fix landed on `mo2-modern/modorganizer-installer_omod` branch `modern`** — one hunk in
`src/CMakeLists.txt`, inserted *after* `dummy_cs_project` is created and *before* `installer_omod`:
```cmake
set(CMAKE_VS_GLOBALS "ResolveNuGetPackages=false")
```
Ordering is load-bearing: `CMAKE_VS_GLOBALS` applies to targets **as they are created**, so
`dummy_cs_project` (created first) keeps its NuGet restore, while `installer_omod` and every
CMake-generated helper get resolution disabled. Verified: `installer_omod.dll` builds and
`dummy_cs_project` compiles without `CS0246`. Strong upstream PR candidate.

**Dead ends (do not retry):** `AUTOGEN_BETTER_GRAPH_MULTI_CONFIG OFF` as a target property *or* as
`CMAKE_*` variable — neither suppresses the helper projects. `AUTOGEN_ORIGIN_DEPENDS OFF` removes
the helper's `<ProjectReference>` to the `.csproj` but does **not** fix the failure, so the
ProjectReference was never the trigger. The trigger is simply that the helper inherits a
`<TargetFrameworkVersion>`, which makes MSBuild run `Microsoft.NuGet.targets` on it.

**Diagnostic that cracked it:** `cmake --build vsbuild --config RelWithDebInfo -- /p:ResolveNuGetPackages=false`
— isolates the lever in one command. Also note: a fresh `vsbuild` makes the *first* `cmake --build`
regenerate mid-flight (glob verify), so MSBuild evaluates stale project files. **Always build twice
after deleting `vsbuild` before believing a failure.**

### Original diagnosis (superseded by the fix above)

**CMake 4.4.2 emits `<target>_autogen` and `<target>_autogen_timestamp_deps` helper projects for the
Visual Studio generator; CMake 3.31.6 did not.** Now happens in 37 projects across the repos
(CMake's docs describe `_autogen_timestamp_deps` as Ninja/Makefile-only, so this is a behavior
change). Only `installer_omod` fails, via this interaction:

1. `installer_omod/CMakeLists.txt:5` sets `CMAKE_DOTNET_TARGET_FRAMEWORK_VERSION "v4.8"` **globally**
   — deliberate upstream workaround ("Nuget gets confused about ZERO_CHECK, ALL_BUILD and INSTALL")
2. that stamps `<TargetFrameworkVersion>v4.8` onto the new autogen helper project
3. MSBuild then runs `Microsoft.NuGet.targets` on it
4. the helper has no lock file of its own (only `dummy_cs_project` has `project.assets.json`)
   → `ResolveNuGetPackageAssets.GiveErrorForMissingFramework()` → `Sequence contains no elements`

It is the only repo setting a .NET framework globally, hence the only one that breaks.

Superseded by the fix above.
