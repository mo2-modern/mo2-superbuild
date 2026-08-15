# Traps — the field guide

Each entry below gives a wrong answer instead of an error: a build that reports success having
compiled nothing, a grep that returns zero because it looked in the wrong place, a warning level
that is not what the CMake call says. None of them fail loudly.

Read the relevant section before asserting anything in that area. 🔴 marks the entries where the
tool reports success while doing nothing.

---

## Quick index

| If you are about to… | Read |
|---|---|
| Trust a build log's warning count | [Reading build output](#reading-build-output) |
| State what warning level a target uses | [Build configuration](#build-configuration) |
| Rebuild or clean `usvfs` | [mob's own bugs](#mobs-own-bugs) |
| Run a survey with `grep` | [Surveys and worklists](#surveys-and-worklists) |
| Edit C++ source in bulk | [Editing source](#editing-source) |
| Touch anything vcpkg | [vcpkg](#vcpkg) |
| Believe a clangd diagnostic | [clang tooling](#clang-tooling) |
| Change toolchain versions | [Toolchain](#toolchain) |
| Verify that a change actually works | [Verification](#verification) |
| Open the superbuild in an IDE | [IDEs](#ides) |
| Trust that a clone of the superbuild works | [Superbuild and clone](#superbuild-and-clone) |

---

## Reading build output

🔴 **`mob build` at the default log level prints no compiler output at all.** Its log therefore
greps as "0 warnings" no matter what the compiler said. **Always use `-l 5`**, and sanity-check the
`stdout` line count before trusting a zero — a full tree run produces roughly **8000 lines** of real
compiler output (`final.log` has 8527, including 128 usvfs TUs).

**An incremental build under-reports warnings.** Only recompiled translation units emit
diagnostics, so any count taken after a partial rebuild is a *lower bound*. Use `-c` before trusting
a total.

**`message(STATUS)` is invisible in mob's logs.** mob passes `--log-level=ERROR` to every cmake
invocation, so `[MO2] Qt version`, `[MO2] Python version`, `[MO2] SIP version` never appear in
configure output. They surface only when `ZERO_CHECK` triggers a regenerate during `cmake --build`.
**Never infer "it didn't reconfigure" from their absence** — verify the artifact instead.

**A zero from a silently-failed script looks exactly like a zero from a clean tree.** A
`python -c "…"` whose backslashes got eaten died with `SyntaxError`, a `2>/dev/null` hid it, and the
sweep cheerfully reported "no source found" for all 24 repos and `TOTAL: 0`. **Assert on the
denominator** — files actually checked, TUs actually compiled — before believing any numerator.

**`mob build -c` takes the installed tree out of service for ~10 minutes.** The reconfigure clean
wipes `build\install\bin`, and `platforms\qwindows.dll` is only rewritten by `mo2_deploy_qt` at the
*end* of the last task. Launching MO2 mid-build aborts with *"no Qt platform plugin could be
initialized"* — that is the clean, not a regression. Same for `styles\` and `tutorials\`.

---

## Build configuration

🔴 **Warning level comes from `CMakePresets.json`, not from `mo2_configure_*`.** Every C++ repo's
preset carries `"CMAKE_CXX_FLAGS": "/EHsc /MP /W4"` as a global floor. A `WARNINGS OFF` argument
therefore means only *"do not add a second `/W` flag"* — **it does not mean warnings are off.**
Targets whose CMakeLists say `WARNINGS OFF` have been compiling at `Level4` the whole time.

**This has been got wrong twice**, both times by reading the CMake call and stopping there, and both
times the correct answer was already written down. **To learn a target's real warning level, read
`<WarningLevel>` in the generated `.vcxproj`, or `CMAKE_CXX_FLAGS` in `CMakeCache.txt`.** Never
infer it from the CMake call.

> A warning level is a property of the **effective command line**, not of the call that looks like
> it sets it. The same reasoning applies to every other compile flag.

**`installer_omod` was the one genuine exception** — the sole C++ repo whose preset *omits*
`CMAKE_CXX_FLAGS`, leaving the MSVC default of `/W1`. Fixed; noted because it is the shape of
exception worth checking for when a repo's warning count looks implausibly low.

**`CXX_STANDARD 20` in a repo is not necessarily an override.** Six repos — `archive`, `bsatk`,
`esptk`, `helper`, `lootcli`, `usvfs` — **do not use `cmake_common` at all**, so that line is their
*only* standard declaration. `cmake_common/mo2_cpp.cmake` defaults to **23**, but nothing carries
that default into those six. **Deleting the line drops them to the MSVC default; it does not raise
them.** See [DECISIONS.md ADR-021](DECISIONS.md#adr-021).

🔴 **A `PRIVATE` link hides usage requirements from consumers — and the symptom appears at LINK
time, in a different project.** `thooklib` linked `asmjit::asmjit` `PRIVATE` while exposing
`<asmjit/asmjit.h>` through its public `ttrampolinepool.h`. So `usvfs_dll` compiled asmjit's headers
**without** asmjit's `ASMJIT_STATIC` usage requirement, saw `ASMJIT_API = __declspec(dllimport)`, and
imported symbols that live in a static lib — `LNK4217`/`LNK4286` on every x86 and x64 link.

**The diagnostic is a one-liner, and it beats reading CMake:** grep the *generated* `.vcxproj` for
the define. `thooklib` and `tinjectlib` had `ASMJIT_STATIC` in `<PreprocessorDefinitions>`;
`usvfs_dll` had **zero**. If a header is in your public interface, its dependency is `PUBLIC`.

**`/clr` caps at C++20, and exceeding it does not fail — it downgrades.** Feeding a C++/CLI target
anything newer yields `warning C4857: C++/CLI mode does not support C++ versions newer than C++20;
setting language to /std:c++20`. So "modernizing" `installer_omod` / `installer_fomod_csharp`
**adds** a warning and changes no flag. Their `CXX_STANDARD 20` lines are deliberate — see
[ADR-021](DECISIONS.md#adr-021).

🔴 **Under `/clr`, link `spdlog::spdlog` — never `spdlog::spdlog_header_only`.** The header-only
target pulls the `*-inl.h` implementation headers, which use `thread_local`; managed code forbids it
and the build dies with `C2482` (dynamic initialization of thread-local data) and `C2483`
(thread-storage object with a destructor). The **compiled-lib** target defines `SPDLOG_COMPILED_LIB`,
so `logger.h` stops at the class definition and compiles under `/clr` cleanly.

**The first attempt at this concluded "spdlog cannot be included from C++/CLI at all" and wrote it
down as permanent. That was wrong** — it tested only the header-only target. `logger.h` includes
`logger-inl.h` solely under `#ifdef SPDLOG_HEADER_ONLY`, and `mdc.h` is reached only from
`pattern_formatter-inl.h`; **both offenders are implementation headers, not the class definition.**
The fix is a one-target change, and it removes `LNK4248 … for 'spdlog.logger'` ×7 completely.

**Layout is identical between the two modes**, which is what makes this safe across a DLL boundary:
`logger`'s data members vary only on `SPDLOG_USE_STD_FORMAT` (uibase and the plugins all define it,
via the imported target's `INTERFACE_COMPILE_DEFINITIONS`) and `SPDLOG_WCHAR_TO_UTF8_SUPPORT` (nobody
defines it). `SPDLOG_API` is empty under a static triplet and `SPDLOG_INLINE` changes linkage, not
layout. **Always link the imported target rather than hand-rolling an include path** — that is what
keeps the definitions byte-identical.

**Plugin repos install nothing through vcpkg under mob.** Their `vcpkg.json` carries deps only
under the `standalone` feature, which mob never enables — `vcpkg_installed` holds just bookkeeping,
and uibase arrives from `build\install` via `find_package(mo2-uibase CONFIG REQUIRED)`. A dependency
added there must go in **top-level `dependencies`** or it is silently not installed.

🔴 **A repo whose preset omits `VCPKG_TARGET_TRIPLET` silently resolves to `x64-windows` — the
DYNAMIC CRT** — while the other 23 repos pin `x64-windows-static-md`. Mixing those across a DLL
boundary is an ABI mismatch, not a warning. This is dormant in any repo with no dependencies and
**fires the moment someone adds the first one**, which is exactly how it was found in
`installer_omod`. Fixed there. Still unset in `esptk`, `helper`, `preview_dds` and the Python-only
plugin repos — harmless today, a landmine on the first dependency. **Check the preset before adding
a dep to any repo.**

**`STL4038` and friends are `#pragma message`, not warnings — `/wd` cannot silence them.**
`_EMIT_STL_WARNING` expands to `_EMIT_STL_MESSAGE`, so the only fix is to stop including the header.
`<generator>` below C++23 is *empty except for that diagnostic*, so including it to obtain
`__cpp_lib_generator` charges every C++20 consumer for nothing. **Use `<version>` for library
feature-test macros** — that is precisely what it is for.

**Do not "fix" the `EXTERNAL_WARNINGS` / `EXTERNAL` keyword mismatch in `cmake_common`.**
`mo2_configure_target` parses `EXTERNAL_WARNINGS` but forwards `${ARGN}` to
`mo2_configure_warnings`, which parses `EXTERNAL`. The two never meet, so external warnings are
effectively off today. Repairing the keyword would switch `uibase` to `/external:W1` and surface Qt
header warnings tree-wide.

---

**`invalidateFilter` is deprecated since 6.13 — a version that does not exist yet.** The header
guards it with `#if QT_DEPRECATED_SINCE(6, 13)`, so `uibase`'s deliberate
`using QSortFilterProxyModel::invalidateFilter;` — the shim that keeps third-party plugins
resolving — survives **any** `QT_DISABLE_DEPRECATED_UP_TO` below `0x060D00`. It is therefore **not**
a blocker for raising the define today, only for the eventual bump to Qt 6.13. Earlier notes implied
it blocked the sweep outright; it does not.

**`-DCMAKE_CXX_FLAGS=…` REPLACES the defaults, it does not append.** Passing a lone define drops
`/DWIN32 /D_WINDOWS /EHsc`, and MSVC then warns `C4530` inside its own `<chrono>`, which `/WX` turns
into `C2220`. The build dies in a standard header having compiled nothing relevant, and a
measurement run this way returns a beautifully small error count that means nothing. Always restate
the defaults: `-DCMAKE_CXX_FLAGS="/DWIN32 /D_WINDOWS /EHsc <your define>"`. **Tell-tale:** the error
is in a file that has nothing to do with what you were measuring.

## mob's own bugs

🔴 **Neither `-b` nor `-c` can force a `usvfs` rebuild.** Two independent mob bugs compose, and the
result is that `mob build -b usvfs` **reports success in 20 seconds having compiled nothing.** The
riskiest component in the project sat behind this measurement blind spot for the entire project —
including in the old pre-fork tree.

```powershell
rm -r build\build\usvfs\vsbuild32, build\build\usvfs\vsbuild64   # the ONLY reliable way
```

1. `msbuild::do_clean()` degenerated into a **Build** when `targets_` was empty
   (`mob/src/tools/msbuild.cpp:192`). **Fixed on our `modern` fork**; `-b` now works for a forced
   rebuild.
2. `mob build -c` still **does not clean preset-defined binary dirs.** Its clean deletes directories
   named after mob's *own* generators (`tools/cmake.cpp:273`, e.g. `vsbuild`); 32 repos match by
   luck, but usvfs uses `vsbuild32`/`vsbuild64` and is never cleaned. **Still open.** Fatal on a
   generator change — `CMake Error: generator : Visual Studio 18 2026 Does not match the generator
   used previously`.

**Consequence worth absorbing:** any historical note saying "usvfs rebuilt clean" measured
nothing. The known-good 2026-07-30 log contains exactly **one** `[usvfs]` line.

---

## Surveys and worklists

🔴 **Greps under-report.** A survey for `QVariant::Type` returned **0** while the compiler found
**6** — the deprecated entity is reached through `.type()`, not by naming the type. **Never conclude
an API is unused from a grep.**

🔴 **Greps over-report just as badly inside `build/build`, because `vcpkg_installed/` sits *inside*
every repo.** A naïve `grep -r "boost/" build/build` returns **~34,000 files**; the true
tracked-source figure is **39**. That is a 900× error, and it is the kind that makes a task look
impossible rather than merely large.

```bash
git -C build/build/<repo> grep -l "include.*boost/" -- '*.cpp' '*.h' '*.hpp'   # sees tracked files only
```

The same inflation ruins any `CXX_STANDARD` / `cxx_std_*` survey. Exclude `vcpkg_installed`,
`vsbuild*` and `tidy` — or just use `git grep`.

**Derive worklists from the compiler, not from a regex over paths.** A site survey built from a
regex matching files directly under `src/` silently missed all of `src/shared/`, and those sites
only surfaced when the compiler was asked again.

**Line numbers drift between batches** — from the edits themselves *and* from clang-format
reflow. A worklist built from an older log points at the wrong lines. Re-derive from a fresh `-c`
build before each batch, or match by symbol name rather than by line.

> **The compiler is the authority.** Four separate instances of grep giving a wrong answer were
> recorded in a single day of work.

---

## Editing source

🚫 **NEVER use `sed -i`, or any LF-writing tool, on these repos.** It rewrites the file as **LF**.
`.gitattributes` mandates `*.cpp text eol=crlf` and `.clang-format` sets `UseCRLF: true` /
`DeriveLineEnding: false`. Fed LF input, clang-format **reflows block comments** — one batch
shredded the GPL/KDE license headers in **11 of 16 files (~180 lines)** while the real change was
~80, and cost a force-push.

Use the Edit tool, or PowerShell `[IO.File]::ReadAllText` / `WriteAllText`, which preserve bytes.
**Before committing, check every changed file has 0 bare LF.** The runnable command is in
[BUILD.md](BUILD.md#committing).

**A global replace is not a scoped one.** Replacing `event->pos()` file-wide in `modlistview.cpp`
hit 7 sites, but only the **3** inside `dropEvent(QDropEvent*)` were deprecated; the other 4 were
`QMouseEvent::pos()`, which does not warn, and where `position().toPoint()` rounds differently.
**Replace only what the compiler flagged.**

**A "unique" string may not be.** `for (const auto& [priority, index] : ...)` appears **3×** in
`profile.cpp`; a blind replace renamed all three and fixed one. **Assert the match count before
replacing.**

**Rename the *whole* scope.** A grep for `cleanup` missed `atexit(&cleanup)`; an `i` rename
missed `rowDataList.insert(i, …)`. Both broke the build — which is the good outcome; the bad one is
a rename that compiles and changes meaning.

**clang-format reflows widely after a mass parameter edit.** Removing parameter names changes
line lengths, so wrapping and `AlignConsecutiveAssignments` runs shift — one batch reformatted **37
files**. Always run the hooks *and rebuild* afterwards; the reformat is not a no-op on the diff.

**The clang-format pin is NOT uniform across repos.** Four different states are active:

| pin | repos |
|---|---|
| `v22.1.5` | 19 repos (the majority) |
| `v22.1.2` | `lootcli`, `usvfs` |
| `v19.1.5` | `installer_bundle`, `installer_fomod_csharp`, `installer_manual` |
| disabled | `bsapacker`, `installer_omod` |

Commits are safe because pre-commit fetches the correct binary **per repo**. **Never hand-format
with the LLVM clang-format on PATH (22.1.8) — it matches no repo's pin.** To format without
committing: `py -3.14 -m pre_commit run --files <changed files>`.

**`.git/hooks` is not cloned.** A fresh clone commits unchecked. Reinstall per repo with
`py -3.14 -m pre_commit install`. This rule sat in the docs unimplemented for the whole of Phase 0–2
— only `mob` and `cmake_common` ever had hooks, and two commits bypassed clang-format silently.

---

## vcpkg

🔴 **`CMAKE_BUILD_TYPE` is ALWAYS undefined under a multi-config generator**, which puts vcpkg's
**debug prefix first** on `CMAKE_PREFIX_PATH` for *every* Visual Studio build. Consequence: **any
bare `find_library()` under vcpkg + the VS generator resolves to the DEBUG library.**

This shipped a debug-built disassembler and `MSVCRTD` inside the release `usvfs_dll` — a DLL
injected into every game process. The tree contains **exactly one** bare `find_library` and it is
now fixed; every other dependency arrives via an imported CONFIG target, which maps per-config
correctly. **New `find_library` calls must never be added bare.**

🔴 **vcvarsall.bat hijacks `VCPKG_ROOT`.** VS's `vcvarsall.bat` sets it to VS's own bundled vcpkg
(`<VS>\VC\vcpkg`). mob resolves `paths.vcpkg` from the shell's `VCPKG_ROOT` at startup, so without
`. .\env.ps1` mob silently builds against the wrong vcpkg *while appearing to work*. **Set `vcpkg`
explicitly in `mob.ini` `[paths]`; never rely on the environment variable.** Symptom when it bites:
configure succeeds, build dies with `'"cmake.exe"' is not recognized`.

🔴 **vcpkg picks its own Visual Studio, independently of mob.** The custom triplet sets no
`VCPKG_PLATFORM_TOOLSET`, so vcpkg auto-detects and uses the **newest installed** VS. Merely
*installing* VS2026 switched every dependency to `vc145` while mob still built MO2 with v143.

**Precise ABI rule:** the linker must be the **same version as its inputs or newer**.
deps `v143` → app `v145` is supported; deps `v145` → app `v143` is not.
**Diagnostic:** read the `vcNNN` infix in
`build\build\modorganizer\vsbuild\vcpkg_installed\x64-windows-static-md\lib`.

**Every registry change forces a baseline update in all 33 repos.** That is the recurring cost of
the current design, and the reason centralizing `vcpkg-configuration` matters — see
[ADR-013](DECISIONS.md#adr-013).

**PyQt/SIP live in `<repo>\vsbuild\pylibs`, not the system Python.** `mo2_python_pip_install`
uses `--target`, so `pip show sip` against Python 3.14 finds nothing. Check the `*.dist-info` dirs
under `pylibs`. Because `--target` never uninstalls, **stale `dist-info` accumulates** (observed:
`sip-6.15.3` and `sip-6.16.0` side by side) — module files are overwritten so builds are correct,
but `importlib.metadata` could resolve either. Clear with `mob build -c <python repos>`.

---


## Superbuild and clone

🔴 **`cmake --build build` exits 0, links every project, and leaves `install/` untouched — by
design.** Build and install are separate steps ([ADR-023](DECISIONS.md#adr-023)), so a green build
is *not* a deployed MO2. Measured 2026-08-15 on a clean clone: exit 0, 0 errors, 0 warnings, 471
TUs, 46 projects linked, and no `install/` directory. The only `ModOrganizer.exe` was in
`build/modorganizer/src/RelWithDebInfo/`, where it has no plugins, no Qt runtime, no usvfs and no
stylesheets beside it and therefore cannot start.

Run `cmake --install build --config RelWithDebInfo`, or **Build → Install mo2** in Visual Studio.

⚠️ **`CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD` does not do what its name suggests here.** It adds
the INSTALL **project** to the generated *solution's* default build, so it affects only
`build/mo2.slnx` opened as a solution. The flow this project documents — open the folder — is
Visual Studio's **CMake mode**, which builds through `cmake --build` and never reads the solution's
project list. If you ever reach for that variable expecting folder-mode builds to install, it will
appear to do nothing.

🔴 **Assert on `install/bin/ModOrganizer.exe`, never on a build's exit code.** A build's success
says nothing about whether anything was deployed, and after any change that renames or relocates an
artifact the install tree can be simultaneously green and stale — `cmake --install` never deletes.

🪤 **A first build leaves 25 of the 34 submodules dirty, and that is expected.**
`mo2_add_translations` runs `lupdate`, which rewrites each repository's `*_en.ts` **in place** —
41 files, all of it `<location line="…">` churn from source lines having moved. Git also warns
`LF will be replaced by CRLF` on every one, because `lupdate` writes LF against a `.gitattributes`
that mandates CRLF.

It is noise rather than damage, but it means **`git status` in a submodule is not a clean signal
after a build**, and a careless `git commit -a` in one of them commits line-number churn with the
wrong line endings — the exact hazard [Editing source](#editing-source) is about, arriving from the
build system instead of from an editor. Clear it with `git -C repos/<name> checkout -- .`.

🔴 **Building from the existing checkout does NOT test the superbuild. Clone it.** Three defects
survived every prior check and all three appeared the first time `git clone --recursive` was run
into an empty directory:

1. **`usvfs` was never a submodule.** mob fetches it through its own task, so it is absent from
   `.gitmodules` in both the superbuild *and* the original superproject. A recursive clone yields
   33 repositories and no usvfs, and configure dies with
   `The source directory ".../repos/usvfs" does not exist`.
2. **`CMakePresets.json` set `MO2_SOURCE_ROOT` as a cache variable**, overriding the auto-detection
   in `CMakeLists.txt`. On a machine that has a sibling `mo2-modern`, every build silently used
   *that* instead of the submodules — so the submodules were verified present (`git submodule
   status` listed 33) while being entirely unused.
3. **SYSTEM include directories inside the project's own source tree cannot be exported.** uibase's
   legacy include dirs are marked SYSTEM to restore mob's `/external:I` warning parity; that is
   legal when the sources sit outside the project and an error once they are submodules under
   `repos/`. Fix: wrap them in `$<BUILD_INTERFACE:>`.

**The general lesson is #2.** The submodules were confirmed to *exist* and never confirmed to be
*used*. Evidence that verifies a proposition adjacent to the one that matters is not verification.

## IDEs

🪤 **`VS_DEBUGGER_COMMAND` only aims the Run button in ONE of the two ways this repository gets
opened.** `mo2_set_project_to_run_from_install` writes it into `organizer.vcxproj`, and it is
correct there — verified in the generated file, for all four configurations, pointing at
`install\bin\ModOrganizer.exe`. That covers opening `build\mo2.slnx`.

It does **not** cover opening the **folder**, which is what the README tells people to do. In
CMake/Open-Folder mode Visual Studio never reads the generated `.vcxproj`: it builds its
startup-item list from the CMake **file API**, whose artifact path for the `organizer` target is
`build\modorganizer\src\RelWithDebInfo\ModOrganizer.exe` — the copy with no plugins, no Qt runtime
and no usvfs beside it, which cannot start. `.vs\launch.vs.json` is committed to override that.

**This is the same shape as the install trap above**, and it is worth naming: a mechanism was
verified to be *set correctly* without checking that the flow the documentation recommends is the
one that *reads* it. Two different settings, same blind spot, both found in one day. **When
something is configured per-IDE-mode, name which mode you verified.**

🔴 **The superbuild emits 144 `CMake Error` lines in an IDE and none from the command line — and
exits 0 either way.** Opening `mo2-ide` in Rider (or CLion, VS Code, Visual Studio) produces a wall
of

```
CMake Error in .../uibase/src/CMakeLists.txt:
  IMPORTED_LOCATION not set for imported target "Qt::uic" configuration "Release".
```

**Every one of 34 command-line configure logs has zero of these.** The difference is the CMake
**file-API**: an IDE writes `.cmake/api/v1/query/codemodel-v2` into the build tree, and the codemodel
evaluates every imported target in every configuration. A plain `cmake --preset` never looks.
**Proven** by creating that one query file in a clean build tree — 0 errors became 144 — and the
directory persists, so every later CLI configure in that tree errors too.

**It is not CMP0111.** The message is CMake's unconditional generator error, not the policy-gated
one, so `CMAKE_POLICY_DEFAULT_CMP0111=OLD` changes nothing — tried, as a normal variable and as a
cache entry.

**Cause:** `mo2-cmake` sets `CMAKE_MAP_IMPORTED_CONFIG_*`, which leaves Qt's tool executables
(`uic`, `qmlcachegen`, `qmltyperegistrar`, `qwebengine_convert_dict`, …) and `Python::Interpreter`
with no location for the mapped configurations. **Upstream already knows**: `plugin_python`
saves, clears and restores those variables around `find_package(Python)` — and it is the one Python
repository absent from the error list. `tool_configurator`, `installer_wizard` and `basic_games`
have no such guard, and error.

**Severity: cosmetic, and verify that rather than assume it.** Generation completes, the build
succeeds and produces working binaries. The errors concern imported *tools* in configurations that
are never built — nothing linked into a shipping artifact.

## clang tooling

🔴 **`clangd --check`'s "N errors" is mostly not diagnostics.** `bsaarchive.cpp` reports *"All
checks completed, 24 errors"* with **zero** real diagnostics — every one is a line like
`tweak: ExtractFunction ==> FAIL: Cannot extract break/continue…`. `--check` probes every
*refactoring action* at every cursor position and logs each unavailable one as an error. **Count
lines matching `<basename>:<line>:<col>` instead** — that is what a user actually sees.

**`cppcoreguidelines-pro-type-member-init` emits three different messages, and only one of them
finds defects.** Counting them together inflated a tree-wide sweep by a fifth:

| message | verdict |
|---|---|
| `constructor does not initialize these fields` | **real** — this is the one |
| `constructor does not initialize these bases` | noise: the body initialises the base through a call the check cannot see, e.g. `PropVariantInit(this)` |
| `uninitialized record type: 'x'` | noise: locals fully assigned on the next line, e.g. `_ULARGE_INTEGER time; time.LowPart = …` |

**A site only clears when EVERY field it names is fixed.** Fixing two of a constructor's three
members leaves the finding reported in full, so a half-done sweep looks untouched. Judge progress by
re-scanning, not by counting edits.

🔴 **`{}` at the declaration is the right fix — except where a type is allocator-aware.**
`boost::interprocess` members (`bc::basic_string` with a `CharAllocatorT`, and the interprocess
containers) are constructed with an allocator bound to the segment manager. A `{}` default member
initialiser there builds an allocator bound to **no segment** — dead while the constructors keep
working, a corruption source in a DLL injected into every game process the moment one stops. It
compiles. `usvfs`'s `sharedparameters.h`, `directory_tree.h` and `tree_container.h` are excluded for
this reason.

**Two declarators on one line take `{}` twice.** `uint64_t m_FileSize, m_CompressedFileSize;`
appended once initialises only the second and leaves the first exactly as it was — while *looking*
like a fix in the diff.

🔴 **PCH in the `tidy/` trees makes clang-tidy report ZERO findings while analysing nothing.** The
compile database carried `/Yu` + `/Fp` pointing at an **MSVC-generated `.pch`**, which clang cannot
read — *"file doesn't start with precompiled file magic"*. **clangd survives this** (it builds its
own preamble), which is why the trees looked healthy for years, **but clang-tidy aborts every single
translation unit**: 39 of 39 in `uibase`, 0 findings, and the run still exits looking normal.

A grep for `[bugprone-` then returns 0 — **identical to a clean scan.** Fixed by adding
`-DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON` to `regen-tidy.ps1` (the file lives outside the repos, so it
costs no merge surface). **Before believing any clang-tidy result, assert the denominator:**

```powershell
# TUs attempted vs TUs that died -- these must not be equal
(Select-String -Path $log -Pattern 'Error while processing').Count
```

**clangd is only partly usable on this codebase.** Some TUs fail to parse on **MSVC STL and Qt
internals** (`constexpr variable 'is_integral_v<std::_Base128>' must be initialized by a constant
expression`), which poisons the AST and cascades into dozens of bogus follow-on errors. **Those are
not real** — MSVC builds the same files clean at `/W4 /WX`. Treat a clangd diagnostic as signal only
if it survives in a TU that parsed.

**`installer_omod` and `installer_fomod_csharp` are C++/CLI**, which clang cannot parse at all.
They carry `Diagnostics: Suppress: '*'` on purpose. 2 of 33 repos are permanently outside clang
tooling.

**`python -c "…"` inside double quotes eats backslashes.** A `.replace('\\\\','/')` collapsed to
`.replace('\','/')` and died. See the silent-zero trap above — same failure, same fix.

---

## Toolchain

**Always use `-c` when the CMake version changes**, and when the generator changes. CMake 4.4.2
re-running inside a tree created by 3.31.6 leaves `CMAKE_CXX_COMPILE_FEATURES` empty and every
C++/CLI target fails at generate time with `No known features for CXX compiler "MSVC"`.
**Fingerprint:** the build tree's `CMakeFiles/` contains **two** version directories.

🔴 **mob resolves `mob.ini` from the current working directory — run it from anywhere else and every
machine-local path silently reverts to auto-detection.** Invoked from `build\build`, mob never reads
the ini, falls back to `vswhere` for VS, and cannot find Qt at all:
`[conf] can't find qt install (bailing out)`.

**That bail-out is luck, not a safety net.** Qt is the *only* setting with no auto-detect fallback.
`paths.vs` auto-detects happily — so on a machine where Qt happens to be on `PATH`, the same mistake
builds to completion against a **different Visual Studio and a different vcpkg**, which is exactly
the `VCPKG_ROOT` hijack above with no error to notice. **Always invoke mob from `F:\dev\mo2-modern`.**

Note for tool-driven sessions: the Bash and PowerShell tools **share one working directory**, so a
`cd` in a Bash call silently relocates the next PowerShell `mob` invocation. Pin it —
`Set-Location F:\dev\mo2-modern` — in the same command that runs mob. **Diagnostic:** a good run
prints `[conf] using vcvars at …\18\Community\…` and `appending to PATH: …\tools\Qt\…` within the
first 10 lines; a run that calls `vswhere.exe` instead has not read the ini.

**Quote `-D` arguments to `cmake` in PowerShell.** An unquoted value containing dots is mangled
before CMake ever sees it — `-DMO2_QT_VERSION=6.99.0` arrives as **`6`**, while
`"-DMO2_QT_VERSION=6.99.0"` arrives intact. Nothing errors; the build simply configures against a
value nobody typed. Verified with a two-line probe project after an error message printed "Qt 6"
for a version that was passed as 6.99.0.

**The build and tooling both use Python 3.14, but they FIND it differently.** `cmake_common/
mo2_versions.cmake` pins `MO2_PYTHON_VERSION` to 3.14 and `plugin_python` asks for it `EXACT`, so a
machine whose only Python is 3.14 builds the tree fine — verified 2026-08-15 on a box with exactly
one registered interpreter (`HKCU\SOFTWARE\Python\PythonCore` listing `3.14` and nothing else).

**The mechanisms still differ, and that is what to remember:** CMake resolves the *build's* Python
through the **registry**, not PATH, while `aqt` and `pre-commit` are reached through the **launcher**
as `py -3.14 -m <tool>`. So a Python that is on PATH but unregistered is invisible to the build, and
one that is registered but not known to `py` is invisible to tooling.

⚠️ **The build's Python needs the development headers**, because `plugin_python` requests the
`Development` component — `include/Python.h` and `libs/python314.lib`. An embeddable or
headers-less install configures right up to `plugin_python` and then fails.

🕰 **Earlier revisions of this file and of [BUILD.md](BUILD.md) said 3.13 was the build's Python and
that the 3.13/3.14 split must not be unified.** That was true before `cmake_common` commit
`686fdeb versions: target Python 3.14` and is now wrong; [ADR-007](DECISIONS.md#adr-007) carries the
correction in its last paragraph while its opening lines still read the old way.

**Having both VS2022 and VS2026 installed breaks mob's auto-detection.** `vswhere -version 17` is
a *minimum*, so it matches both and mob bails with "vswhere returned multiple installations". Pin
`paths.vs` explicitly in `mob.ini`.

**VS2026 emits `.slnx`, not `.sln`**, and there is no CMake variable to choose. Only `usvfs` is
affected — it is the one task mob drives through msbuild directly. Handled on our fork.

**A fresh `vsbuild` regenerates mid-flight on the first `cmake --build`** (glob verify), so
MSBuild evaluates stale project files. **Always build twice after deleting `vsbuild` before
believing a failure.**

**The install tree accumulates stale artifacts — `cmake --install` never deletes.** After the
Python 3.13 → 3.14 bump the tree held **262 stale `*313*` files** beside 262 fresh ones, including a
dead `python313.dll`. Any change that renames outputs leaves the old ones behind forever, which
silently invalidates any diff-against-known-good. **Wipe `build\install` and re-run `mob build`
before trusting that diff or before shipping.**

**Upstream's CI `qt-modules:` list is INCOMPLETE for a runnable build.** CI compiles MO2 and
never launches it, so runtime-only modules are missing. Confirmed gaps: **`qtserialport`** and
**`qtimageformats`** (without which MO2 silently builds 4 image plugins instead of 9 and cannot
render TGA/TIFF/WebP mod previews — nothing fails at build time). **Re-check the module list at
every Qt bump.**

🔴 **And our own list was incomplete in the opposite direction, for four months.** The `aqt`
command `CMakeLists.txt` prints when Qt is missing — repeated verbatim in `README.md` and
`BUILD.md` — omitted **`qtwebsockets`** and **`qtnetworkauth`**, both named by
`modorganizer/src/CMakeLists.txt`. Anyone following the project's own instructions on a clean
machine could not configure.

It survived because **every machine here already had a fuller Qt from Phase 1**, so no local build
could expose it. `docs/history/PHASE1-TOOLCHAIN.md` had the correct list all along; the live
instructions were rewritten later and lost two entries. **Frozen history stayed right while the
live document drifted** — when they disagree, the one nobody edits is often the accurate one.

**The cost shape is what makes this expensive:** `find_package(Qt6)` resolves only *after* vcpkg has
built all 112 packages, so a one-word omission fails **30 minutes in**, every time. A missing
build-time module is loud and late; a missing runtime-only module is silent forever. Neither is
caught by any local build on a machine that already has Qt.

**Nothing verified this until CI ran it.** The instructions were checked for existing, never by
following them on a machine that lacked the thing they install.

🔴 **144 `IMPORTED_LOCATION not set` errors that only appear inside an IDE — and exit code 0.**
Visual Studio writes a CMake **file API** query into `build/.cmake/api/v1/query/`. Answering
`codemodel-v2` makes CMake resolve imported-target locations for **every** configuration, and the
imported *tool* executables (`Qt::uic`, `Qt::qmlcachegen`, `Python::Interpreter`) have no location
for all four. `Debug` passes; `Release`, `MinSizeRel` and `RelWithDebInfo` each produce a wall.

**Generation still completes, build files are written, and CMake exits 0.** So the build works and
every non-IDE check is blind to it: mob, the command line, a clean clone and CI all pass. The only
thing that sees it is the IDE, which is exactly what this project tells people to use.

**Reproduce or clear it by moving that one directory**, not by touching code. Copying only
`.cmake/api/v1/query/` into a clean build tree takes it from 0 errors to 144.

⚠️ **Four plausible explanations are wrong. Do not re-open them.** The CMake version (VS ships its
own **4.3.1** at `Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin`, while PATH has **4.4.2** —
a real difference, and not this one); a stale `Z_VCPKG_ROOT_DIR` left by a toolchain-path change;
the `vcvars` developer environment; and leftover `prebuilt`/`pylibs`. Each was tested and cleared.

**The IDE does not use the CMake on your PATH.** `env.ps1` can insist on 4.4.2 all it likes; Visual
Studio runs 4.3.1 from its own install. Any version-sensitive check must account for both.

**`dlls.manifest` is a cross-check, not a spec.** `liblz4.dll` is listed but present in neither
build, and the known-good build ran fine — the static triplet means that DLL never exists. A missing
manifest entry is not automatically a fault.

**PyPI's `aqtinstall` lags Qt's repository layout.** Install it from git, not PyPI.

---

## Verification

🔴 **A green build proves nothing about `usvfs`.** It is a DLL-injection and hooking library
(`asmjit` + `libudis86`). **Opening a mod list is not enough either** — usvfs only injects when you
launch a program **through** MO2.

**Proof lives in the instance's `logs\usvfs-*.log`.** Lines reading `type overwrite` or
`type chained patch` mean trampolines were really built — that is the libudis86 code path. Their
absence means the DLL loaded but hooked nothing, which is **not** a verification.

**Some changes emit nothing to any log and must be clicked by hand.** The mod-list filtering and
"Group by" paths, the categories editor, and Change Categories were all exercised deliberately for
exactly this reason.

**Check username masking on every run — in the INSTANCE log, not the install tree.** MO2 writes
two logs: a pre-instance-selection one to `build\install\bin\logs\mo_interface.log`, and the real one
to `%LOCALAPPDATA%\ModOrganizer\<instance>\logs\mo_interface.log`. Only the second contains
`data path: C:/Users/USERNAME/AppData/...`, which is the line the check is about.

🪤 **A portable instance cannot verify masking at all**, and fails in the shape this file is about: it
lives under `F:\`, so its log holds **no** `C:/Users/…` path, and a grep returns 0 masked *and*
0 leaked — indistinguishable from a clean pass. **Assert the denominator** (user-profile paths
present at all) before concluding anything. Verified 2026-08-10 on a global instance: 1 of 1 masked,
0 leaks.

**`[[nodiscard]]` warnings are worth reading individually, never batch-silencing.** Running tally
across this project: **C4834 produced 6 real bugs and 0 false alarms.** Every one was the same
shape — an unchecked `QFile::open` whose failure path still looks like success downstream.

**…but a warning class tells you where to look, never what you'll find.** C4701 came out **1 real
/ 3 false**: three "potentially uninitialized" reports in `installer_omod` were compiler
conservatism about a short-circuited `||`. Do not treat a scary class as guilty by default.
