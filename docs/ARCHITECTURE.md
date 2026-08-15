# Architecture

How this project is put together: what the repositories are, how our fork relates to upstream, what
the toolchain is, and how dependencies resolve.

For *how to build it*, see [BUILD.md](BUILD.md). For *why* any of it is shaped this way, see
[DECISIONS.md](DECISIONS.md).

## Two trees

**This repository** is the superbuild. It holds no sources of its own: the repositories arrive as
submodules under `repos/`, vcpkg under `vcpkg/`.

**The mob working tree** is separate and is not published. It holds mob, its own checkout of the
repositories under `build/build/`, Qt, and the `tidy/` side trees clangd uses. Sections below that
mention `build/build/`, `mob.ini` or `env.ps1` describe that tree, not this repository.

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
| CMake | **4.4.2** standalone *for mob* | [ADR-004](DECISIONS.md#adr-004). **The superbuild does not need it** — it requires 3.25 and is built with the CMake Visual Studio ships (4.3.1). Only the mob path wants 4.4.2 first on `PATH` |
| Qt | **6.11.1** `msvc2022_64` | via `aqtinstall` from git; 3.3 GB; `qt_vs` stays `2022` |
| Python (build) | **3.14** | found by CMake through the registry, not PATH |
| Python (tooling) | **3.14** | `aqt`, `pre-commit` — always `py -3.14 -m <tool>` |
| LLVM | 22.1.8 | clangd / clang-tidy / clang-cl; **not** on the global PATH |
| vcpkg | pinned clone | baselines unified at HEAD |

Upstream is on VS2022 / v143 / CMake 3.31.6 / Python 3.13. Every one of those moved.

---

## Repository model

**34 repos**: 33 MO2 repos plus `mob`, all forked into the
[`mo2-modern`](https://github.com/mo2-modern) org, tracking `ModOrganizer2/*`.

Two permanent branches per repo — see [ADR-001](DECISIONS.md#adr-001):

```
upstream/master ──ff──> origin/master ──merge──> origin/modern
                                                   ↑ our commits
```

- **`master`** — pure mirror of upstream. **Never commit here.** Fast-forward only.
- **`modern`** — default branch, all our work.

`mob` implements this natively through four `mob.ini` keys:

```ini
[task]
mo_org            = mo2-modern   ; clone from the fork
mo_branch         = modern       ; check out our branch
mo_fallback       = master       ; repos without `modern` fall back silently
set_origin_remote = true         ; origin=mo2-modern, upstream=ModOrganizer2
remote_org        = mo2-modern
```

`mo_fallback` is what made a staged rollout possible — `modern` branches could be created one repo
at a time while everything else kept building from `master`.

### Current diff surface against upstream

Measured 2026-08-10 across all 34 repos: **248 files, +1003 / −922 lines.** The near-1:1 ratio is
the number that matters — it means the changes are in-place modernization, not accretion. Keeping it
that way is the whole point of [ADR-001](DECISIONS.md#adr-001).

### Upstream sync

`sync-upstream.ps1` pulls upstream into every repo's `master` and merges into `modern`. It is
idempotent and self-heals a missing remote.

⚠️ **Do not use `mob git add-remote`** — it builds **SSH** URLs (`tools/git.cpp:33`), which will not
authenticate against an HTTPS + gh-credential-helper setup. All `upstream` remotes are
`set-url --push upstream DISABLED`, i.e. fetch-only.

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

## Directory layout of the mob working tree

Not this repository. See [Two trees](#two-trees).

| Path | What |
|---|---|
| `mob/` | the build orchestrator (our fork, branch `modern`) |
| `build/build/` | 33 MO2 repos as git submodules, plus `usvfs`, which mob clones through its own task and is **not** a submodule. Source edits happen here |
| `build/install/` | build output; `bin/ModOrganizer.exe` is the thing to run |
| `vcpkg/` | pinned vcpkg clone |
| `vcpkg-registry/` | our port registry (branch `main` — [ADR-008](DECISIONS.md#adr-008)) |
| `tools/Qt/` | Qt 6.11.1, 3.3 GB, via `aqtinstall` |
| `tidy/` | tooling-only Ninja trees — **never** build artifacts; see TOOLING.md in the mob working tree |
| `docs/ROADMAP.md` | current state; the rest of the documentation is in this repository |
| `env.ps1` | session environment — **source before any build** |
| `mob.ini` | machine-local paths; never committed |
| `sync-upstream.ps1` | pulls upstream into every repo |
| `regen-tidy.ps1` | rebuilds the clangd compile databases |
| `*.log` (root) | only the 7 logs the docs cite; `final.log` is the definitive full-tree run |
| `logs-archive/` | superseded build logs, kept for history — nothing references them |

`F:\dev\mo2` is the **old, pre-fork tree**. Treat it as **read-only** — it is the known-good
reference build used for output diffs.

⚠️ **`tidy/`, `regen-tidy.ps1` and `%LocalAppData%\clangd\config.yaml` are not in any repo.** A
fresh clone lacks all of them — the same trap as `.git/hooks`.

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
that is **dual-architecture — x86 *and* x64**. One configure produces one architecture, so it uses
`vsbuild32`/`vsbuild64` rather than the `vsbuild` every other repo uses. That non-standard layout is
the direct cause of mob's rebuild blind spot ([TRAPS.md](TRAPS.md#mobs-own-bugs)).

The superbuild builds and installs both architectures at *configure* time. `ExternalProject_Add`
does not work here: it builds at build time, and `find_package(usvfs)` has to resolve during
configure.

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
2026-06): `microsoft/vcpkg` → `ea1a7396`, `mo2-modern/vcpkg-registry` → `1316300c`. The local vcpkg
clone sits on the same microsoft commit so tool and ports share one tree state.

⚠️ **Every registry change forces a baseline update in all 33 repos.** That is the recurring cost of
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
7. Bump the baseline in all 33 repos, rebuild.

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
