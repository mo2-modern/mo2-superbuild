# Architecture

How this project is put together: what the repositories are, how our fork relates to upstream, what
the toolchain is, and how dependencies resolve.

For *how to build it*, see [BUILD.md](BUILD.md). For *why* any of it is shaped this way, see
[DECISIONS.md](DECISIONS.md).

## One tree

**This repository is the whole thing.** It holds no sources of its own: the repositories arrive as
submodules under `repos/`, vcpkg under `vcpkg/`, and everything it produces lands in `build/` and
`install/`.

There used to be a second, unpublished tree built around `mob`. It is retired
([ADR-027](DECISIONS.md#adr-027)) and gone. Older notes referring to `build/build/`, `mob.ini`,
`env.ps1` or the `tidy/` trees describe that tree; what it was is frozen in
[`history/MOB.md`](history/MOB.md).

> **"34" means three different things in older notes; here it means one.** `repos/` holds **34
> submodules**. **33** of them are buildable — `cmake_common` is CMake modules, consumed rather than
> built. Of those 33, **32** are added as subdirectories and `usvfs` is built separately at
> configure time. `mob` itself is **not** in `repos/` at all. Where a document says "34
> repositories build", it is wrong: 33 do.

---

## The toolchain

| Component | Version | Notes |
|---|---|---|
| Visual Studio | **2026** (18.x, Community) | generator `Visual Studio 18 2026`; VS2022 kept as fallback |
| MSVC toolset | **v145** (14.51) | ABI-compatible with all of 14.x — [ADR-005](DECISIONS.md#adr-005) |
| CMake | whatever VS ships (**4.3.1**) | The superbuild requires 3.25 and needs no standalone install. [ADR-004](DECISIONS.md#adr-004) put mob on 4.4.2 first on `PATH`; with mob retired that only matters for reading older notes |
| Qt | **6.11.1** `msvc2022_64` | via `aqtinstall` from git; 3.3 GB; `qt_vs` stays `2022` |
| Python (build) | **3.14** | found by CMake through the registry, not PATH |
| Python (tooling) | **3.14** | `aqt`, `pre-commit` — always `py -3.14 -m <tool>` |
| LLVM | 22.1.8 | clangd / clang-tidy / clang-cl; **not** on the global PATH |
| vcpkg | pinned clone | baselines unified at HEAD |

Upstream is on VS2022 / v143 / CMake 3.31.6 / Python 3.13. Every one of those moved.

---

## What the preset sets, and why

`CMakePresets.json` is JSON, so it cannot carry comments. Each non-obvious setting is recorded here
instead.

| Setting | Why |
|---|---|
| `toolchainFile` as a **path**, not `$env{VCPKG_ROOT}` | Visual Studio's `vcvarsall.bat` overwrites that variable with VS's own bundled vcpkg, so a build trusting it resolves every dependency against the wrong one — see [TRAPS.md](TRAPS.md#vcpkg) |
| `VCPKG_TARGET_TRIPLET: x64-windows-static-md` | The whole tree is static-CRT-with-dynamic-MD. Mixing this across a DLL boundary is an ABI mismatch, not a warning |
| `VCPKG_INSTALL_OPTIONS` → `%LOCALAPPDATA%\vcpkg` | Keeps buildtrees, packages and downloads (~3 GB) out of the workspace. `CMakeLists.txt` forwards this to the nested usvfs configures, which would otherwise write into `vcpkg/` |
| `CMAKE_VS_NUGET_PACKAGE_RESTORE: ON` | `installer_omod` has .NET references that need a NuGet restore |
| `CMAKE_INSTALL_PREFIX: ${sourceDir}/install` | MO2 only runs from a populated install tree; keeping it beside `build/` makes both gitignored by one rule |
| `CMAKE_DISABLE_FIND_PACKAGE_WrapVulkanHeaders: ON` | ⚠️ **Provenance not recorded.** It suppresses Qt's optional Vulkan-headers lookup, presumably to avoid a failure on machines without the Vulkan SDK. Nobody wrote down which failure. **Re-test at the next Qt bump** — if a future Qt genuinely needs Vulkan headers this breaks silently and the reason will not be findable |

## Repository model

**35 forked projects**: the 34 submodules under `repos/` plus `mob`, all forked into the
[`mo2-modern`](https://github.com/mo2-modern) org, tracking `ModOrganizer2/*`.

Two permanent branches per repo — see [ADR-001](DECISIONS.md#adr-001):

```
upstream/master ──ff──> origin/master ──merge──> origin/modern
                                                   ↑ our commits
```

- **`master`** — pure mirror of upstream. **Never commit here.** Fast-forward only.
- **`modern`** — default branch, all our work.

The superbuild pins each repository by submodule gitlink, so the branch a commit came from is not
something the build knows or cares about — it builds exact commits. That is stricter than mob's
arrangement, which resolved a branch name per repository and could fall back
([`history/MOB.md`](history/MOB.md)); the tradeoff is that a `modern` branch moving forward does
nothing here until the gitlink is bumped.

### Current diff surface against upstream

Measured 2026-08-10 across all 34 repos: **248 files, +1003 / −922 lines.** The near-1:1 ratio is
the number that matters — it means the changes are in-place modernization, not accretion. Keeping it
that way is the whole point of [ADR-001](DECISIONS.md#adr-001).

Restricted to CMake files, the divergence is smaller than that suggests and almost entirely uniform:
one line per repo adding `WERROR ON`, plus `CXX_STANDARD 20` → `23` in the six repos that do not use
`cmake_common` ([ADR-021](DECISIONS.md#adr-021)). Only four carry substantial build changes —
`cmake_common`, `usvfs`, `installer_omod` and `installer_fomod_csharp` — and those are fixes, not
assembly logic.

### The superbuild is not fork-specific

**Verified 2026-08-15.** The superbuild was pointed at unmodified upstream sources and built them
end to end. This matters because the obvious objection to the project is that it only builds *our*
forks, and that turns out not to be true.

**To do it yourself:** clone the `build-upstream` branch, which is this same superbuild with every
submodule pointed at `ModOrganizer2/*` instead of the forks.

```powershell
git clone --recursive -b build-upstream https://github.com/mo2-modern/mo2-superbuild mo2-upstream
```

Then build it exactly as the README describes. Nothing else differs: same `CMakeLists.txt`, same
preset, same CI, same redirects — only `.gitmodules` and the gitlinks change.

⚠️ **It needs Python 3.13, not 3.14.** Upstream's `cmake_common` pins `MO2_PYTHON_VERSION` to 3.13
and `plugin_python` requires it `EXACT`, so configure stops at the preflight otherwise. That is
upstream's constraint, not a superbuild limitation, and it is the one thing that differs from
building `main`.

**What "upstream" does and does not mean here.** The *sources* are upstream's, unmodified. The
*dependency graph* is still ours: the superbuild resolves everything from one root `vcpkg.json`
([ADR-013](DECISIONS.md#adr-013)), which names `mo2-modern/vcpkg-registry`, while upstream's own
repositories name `ModOrganizer2/vcpkg-registry` at older baselines. So this branch answers "do
upstream's sources build under our infrastructure", which is the question worth asking, and not "is
this byte-identical to what upstream's own CI produces".

**Keeping it current:** bump the gitlinks to upstream's newer `master` commits, and merge `main`
into the branch to pick up build-system changes. That merge conflicts on `.gitmodules` every time,
predictably and in one file — the branch exists precisely to hold that one difference.

| Stage | Result |
|---|---|
| Configure | 0 errors, 597 s, both usvfs architectures built |
| Build | 0 MSBuild errors; `ModOrganizer.exe`, `installer_omod.dll`, `installer_fomod_csharp.dll` all produced |
| Install | 7 s |
| CI's install-tree checks | 30 plugins, 9 image plugins, 29 stylesheet entries, 18 licence texts — identical to the fork build |

**Exactly one deviation was needed**, and it is upstream's own pin rather than a superbuild
limitation: upstream `cmake_common` sets `MO2_PYTHON_VERSION` to **3.13** and `plugin_python`
requires it `EXACT`, so a machine with only 3.14 registered stops at the preflight. Changing that one
line in the exported copy was enough. On a machine with 3.13 installed, no deviation is needed.

⚠️ **What this does not establish.** The upstream build was never launched, so nothing about its
runtime or usvfs hooking is verified. It emitted **930 warnings** — upstream's unfixed load, which is
what the `/WX` campaign removed on `modern`. And "upstream" here means each fork's `master` as of the
last sync (~2026-08-10); with no `upstream` remotes there is no fresher reference available locally.

🕰 One prediction failed and is worth recording so it is not repeated: `installer_omod` was expected
to fail without our `CMAKE_VS_GLOBALS "ResolveNuGetPackages=false"` fix, and it built cleanly.
[UPSTREAM.md](UPSTREAM.md) attributes that failure to **CMake 4.4.2**, while the superbuild runs on
the **4.3.1** Visual Studio ships — so the fix looks specific to the standalone-CMake path. Not
confirmed against 4.4.2.

### Upstream sync

🔴 **There is no sync tooling in this repository, and the submodules have no `upstream` remote.**
Each `repos/*` checkout has only `origin`, pointing at the `mo2-modern` fork, so nothing here can
even fetch `ModOrganizer2/*` to compare against. A `sync-upstream.ps1` existed in the mob tree and
survives among its leftovers; bringing it in — or rewriting it — is the first task of any upstream
sweep, because the survey cannot be run without it.

When it is restored, the flow is [ADR-001](DECISIONS.md#adr-001)'s:
`upstream/master → origin/master → merge into origin/modern`, never rebase. Keep `upstream` remotes
fetch-only (`set-url --push upstream DISABLED`), and build their URLs over HTTPS — mob's
`git add-remote` produced SSH URLs, which do not authenticate against a gh-credential-helper setup.

⚠️ **The merge-conflict path has never been exercised.** The one sync run that happened was clean
because upstream had not moved.

⚠️ **Conflict handling is still untested.** The first sync run was clean because upstream had not
moved. The loop is proven; the merge-conflict path is not.

### Staying upstream-conformant

Verified 2026-08-09: **upstream has no written `CONTRIBUTING.md`**, no CLA, no DCO. The contract is
purely mechanical:

- `.clang-format` (~20 repos): LLVM base, **IndentWidth 2**, **ColumnLimit 88**,
  `PointerAlignment: Left`, `UseCRLF: true` / `DeriveLineEnding: false`.
  *(The file's own comment claims "4 columns indentation" — it is stale. Trust the setting.)*
- `.pre-commit-config.yaml` (**every** repo): trailing-whitespace, end-of-file-fixer,
  check-merge-conflict, check-case-conflict, clang-format — **pinned per repo**, not uniformly;
  see [TRAPS.md](TRAPS.md#editing-source) and [ADR-011](DECISIONS.md#adr-011).
- `linting.yml` runs `ModOrganizer2/check-formatting-action` — a format deviation fails CI.
- `.git-blame-ignore-revs` — mass-reformat commits excluded from blame.

---

## Directory layout

| Path | What |
|---|---|
| `CMakeLists.txt` | the superbuild — the only build logic in the project |
| `CMakePresets.json` | the `vs2026` preset; `RelWithDebInfo` only ([ADR-025](DECISIONS.md#adr-025)) |
| `vcpkg.json` | one dependency manifest for the whole project |
| `cmake/superbuild-redirects/` | satisfies `find_package(mo2-*)` without installing |
| `cmake/aqt-requirements.txt` | hash-locked dependency closure for the Qt installer |
| `repos/` | the 34 upstream repositories, as submodules. Source edits happen here |
| `vcpkg/` | pinned vcpkg clone, as a submodule |
| `licenses/` | third-party texts shipped in `bin/licenses` |
| `qt/` | Qt, downloaded by configure; gitignored |
| `build/`, `install/` | everything generated; both gitignored |
| `.vs/launch.vs.json` | points Run at the install tree |

A pre-fork tree, if you kept one, is the **known-good reference** for output diffs. Treat it as
**read-only**. This document deliberately does not name a location for it — it is wherever you put
it.

⚠️ **Nothing provides the clangd tooling any more.** The `tidy/` Ninja trees, `regen-tidy.ps1` and
`%LocalAppData%\clangd\config.yaml` lived in the mob tree and are not in any repository. Re-creating
them against the superbuild is unstarted work; until then, clang-tidy and clangd have no compile
database to read.

### Repo inventory by kind

| Group | Repos |
|---|---|
| **C++, under `/W4 /WX`** | 21 repos, plus the 17 `game_bethesda` and 5 `plugin_python` targets |
| **C++/CLI** — clang cannot parse | `installer_omod`, `installer_fomod_csharp` |
| **Python only, no C++** | `basic_games`, `fnistool`, `form43_checker`, `installer_wizard`, `preview_dds`, `script_extender_plugin_checker`, `tool_configurator` |
| **Not our source** | `explorer++`, `stylesheets` (downloads), `cmake_common` (no targets) |

---

## Components with unusual shapes

**`usvfs` is the risk centre.** It is a DLL-injection and hooking library (`asmjit` + `libudis86`)
that is **dual-architecture — x86 *and* x64**. One configure produces one architecture, so it needs
two, and that non-standard shape was the direct cause of mob's rebuild blind spot, where
`mob build -b usvfs` reported success in 20 seconds having compiled nothing
([`history/MOB.md`](history/MOB.md)).

The superbuild builds and installs both architectures at *configure* time. `ExternalProject_Add`
does not work here: it builds at build time, and `find_package(usvfs)` has to resolve during
configure. Staleness is guarded by a stamp recording the toolchain **and** the usvfs source
revision, so the equivalent blind spot cannot reopen — the earlier version of that stamp omitted the
revision, and did reopen it.

It is also the reason **a green build is never sufficient verification** — see
[BUILD.md](BUILD.md#verification).

**`cmake_common` exports CMake *modules*, not targets.** 27 of the 63 `find_package(mo2-*)` call
sites depend on it, and `if(NOT TARGET …)` cannot guard a module package — see
[ADR-017](DECISIONS.md#adr-017).

**Qt cannot be built through vcpkg.** MO2 needs WebEngine, i.e. a Chromium build. Qt stays a
3.3 GB external prerequisite, either documented or automated by invoking `aqt` from CMake.

---

## Dependency management

Dependencies resolve through **`mo2-modern/vcpkg-registry`** — ours, and we publish to it.

Baselines are unified at **2 registries, both at HEAD** (from 13 baselines spanning 2024-07 →
2026-06): `microsoft/vcpkg` → `ea1a7396`, `mo2-modern/vcpkg-registry` → `a71daa87`. The local vcpkg
clone sits on the same microsoft commit so tool and ports share one tree state.

⚠️ **Every registry change forces a baseline update in all 31 repos that carry a manifest.**
(`cmake_common`, `esptk` and `helper` have no `vcpkg.json`.) That is the recurring cost of
the current design, and it is what [ADR-013](DECISIONS.md#adr-013) is about.

### Port bump recipe

Proven for `7zip` 26.01→26.02 and `libloot` 0.29.5→0.29.6.

1. `ports/<p>/vcpkg.json` — **mind the field**: 7zip uses `version-string`, libloot uses `version`.
2. `ports/<p>/portfile.cmake` — **each portfile has TWO SHA512s; change only the first.** 7zip's
   second is a `CMakeLists.txt` from a pinned microsoft/vcpkg commit; libloot's second is the
   LICENSE. **Handy tell: the ones to change are lowercase, the ones to leave are uppercase.**
3. Get the hash by downloading the artifact and running `Get-FileHash -Algorithm SHA512` — beats the
   usual build-until-vcpkg-tells-you loop.
4. **`git commit` the ports first** — `x-add-version` hashes the committed git tree.
5. `vcpkg.exe --x-builtin-ports-root=ports --x-builtin-registry-versions-dir=versions x-add-version <ports>`
6. `git add versions && git commit --amend --no-edit && git push --force-with-lease`
7. Bump the baseline in the 31 repos that carry a manifest, rebuild.

**Deliberately pinned down:** `pybind11` and `spdlog` — [ADR-014](DECISIONS.md#adr-014).

### Baseline rewriting technique

Parse each file to learn which registry a SHA belongs to, then string-replace that exact SHA.
`baseline` appears both before *and* after `repository` across these files, so **adjacency regexes
are unsafe**; and `ConvertTo-Json` would reformat the whole file into an unreadable diff.

---

## The `toolchain-vs2026` tag

Created 2026-08-09 across **all 34 repos**, signed and pushed. It marks the point where `modern`
contained **toolchain work and nothing else** — no source modernization, no dependency changes.

Produce a PR-able branch from it at any time:

```powershell
git switch -c upstream-toolchain toolchain-vs2026
```

⚠️ **mob's tag includes one commit upstream must NOT take:** `cdd5779` ("build from the mo2-modern
fork org") sets `mo_org`/`mo_branch`/`mo_fallback` and is **fork identity, not toolchain**. The other
five mob commits are upstreamable. Cherry-pick rather than merging mob's tag wholesale.

`cmake_common` is not tagged — it had no toolchain commits, and its first `modern` commit is the
Python bump, deliberately landed after this line.
