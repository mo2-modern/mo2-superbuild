# Upstream contributions

Fixes found in this project that belong to upstream `ModOrganizer2/*` rather than to our
modernization. Each is already implemented and verified on our `modern` branches.

> 🔴 **Status: NOT submitting — [ADR-015](DECISIONS.md#adr-015). Do not open PRs against
> `ModOrganizer2/*`.**
>
> This file is bookkeeping so the set stays submittable the day that reverses. **Upstreaming means
> cutting a fresh branch from `master` and applying the single change — never merging `modern`**,
> which carries our toolchain and fork-identity commits.

## The count

**27 fixes: 21 source bugs, 4 mob fixes, 2 toolchain fixes.** The tables below are the source of
this number. Count the rows, do not copy the total into another file.

None was found by reading code speculatively. 15 came from the warnings-as-errors campaign, 3 from
clang-tidy, the rest from the build and superbuild work. The narrative is in
[`history/PHASE3-WARNINGS.md`](history/PHASE3-WARNINGS.md).

---

## Real bugs

Ordered roughly by severity.

| # | Bug | Repo | Our commit |
|---|---|---|---|
| 1 | Release DLL links the **debug** libudis86 — `find_library` is config-agnostic, dragging `MSVCRTD` into a DLL injected into every game process | `usvfs` | `6beaf55` |
| 2 | `TextEditor::save()` reports success and clears the modified flag after a **failed open** — silent data loss | `modorganizer` | `127cd417` |
| 3 | Profile mod-list rename logs `"Renamed N"` having written nothing | `modorganizer` | `127cd417` |
| 4 | `setItem(blankItem.get())` **double-delete** in the category importer, leaving a dangling pointer in the table | `modorganizer` | `d479fc76` |
| 5 | `unregisterGameFeatures()` returns a **negative** count — `size_t` subtraction underflows, narrows to `int`, and goes straight to the plugin API | `modorganizer` | `935e8293` |
| 6 | Every Fallout 76 save dated from an **uninitialised** `FILETIME` — out-param never written | `game_bethesda` | `034bd61` |
| 7 | Fallout 76 save fields taken **by value**, so name/level/location/number never reach the caller | `game_bethesda` | `b98c17d` |
| 8 | `DummyBSA::write` silently writes nothing — BSA invalidation switched on with no BSA on disk | `game_bethesda` | `034bd61` |
| 9 | Blueprint-plugin regex `"\.es(m\|p\|l)$"` — `\.` is an unrecognised escape and collapses to `.`, matching any character | `game_bethesda` | `034bd61` |
| 10 | `readImageBGRA` iterates rows by **`width`** instead of `height` | `game_bethesda` | `5506c90` |
| 11 | `writeBString` length byte **wraps to 0** at 255 chars — a 256-byte record announced as empty | `bsatk` | `d1adc5c` |
| 12 | `calculateBSAHash` passes a possibly-negative `char` to `tolower` — UB | `bsatk` | `d1adc5c` |
| 13 | `GetFile` `fflush`/`fclose` an **uninitialised** `FILE*` on every failure path | `lootcli` | `d8b325b` |
| 14 | A failed shader open becomes a **zero-length shader** in the generated SDP, still mapped over the game's own | `installer_omod` | `879d4fe` |
| 15 | A failed `QTemporaryFile` still registers a virtual SDP, mapping the shader package onto nothing | `installer_omod` | `879d4fe` |
| 16 | Chrome fix reports "applied" after a failed write open — and the usual cause of that failure is **exactly the condition the dialog had just warned about** | `nxmhandler` | `5ac6c25` |
| 17 | `DLLEXPORT` macro collision between two **installed public headers** — whichever is included second wins | `archive` | `764f2d3` |
| 18 | `Guard`'s move constructor never initialises `m_call`, so a moved RAII guard runs its action — or leaks the resource — on indeterminate stack memory. It is used to `::CloseHandle`. Move assignment has the mirror defect | `uibase` | `02ef8be` |
| 19 | `nexusExpires` / `nexusDownloadUser` uninitialised in **both** `ModRepositoryFileInfo` constructors and not copied by the copy constructor, while `nexusinterface.cpp` reads both to decide whether a cached Nexus download URL is still authorised | `uibase` | `822a657` |
| 20 | `ModDataChecker::fix()` takes `fileTree` and never uses it — C4100 in a **public** header, so every third-party plugin at `/W4` eats it. **Not yet fixed**, see below | `uibase` | — |
| 21 | **~120 members left indeterminate by their constructors, across 13 repos** — save-game fields shown in the UI, download bookkeeping, FOMOD condition types, raw `IOrganizer`/tree/hook pointers, semaphore state. Whole family below | 13 repos | see below |

### Notes on the strongest candidates

**#21 is the tree-wide sweep of that same check**, 2026-08-11, and it is **finished outside usvfs**:
310 findings → 108, of which **every single one is either a false positive (32) or one of the 76
usvfs findings deliberately refused** (below). No real, unaddressed finding remains in the other
23 repositories. `modorganizer` alone went 158 → 11, all 11 false positives.

Commits are one per repository:
`archive 3a3036f`, `esptk d21e9ae`, `bsatk cee9b6b`, `lootcli eb0c48e`, `nxmhandler 76f4607`,
`installer_bain df9a86e`, `installer_bundle 3644032`, `installer_manual 9d5e705`, `uibase deccda5`,
`game_bethesda c86472b`, `installer_fomod 49b4e8f`, `modorganizer 1f6771ae`, `usvfs 200c316`
(**usvfs is committed but NOT pushed** — it is the hooking layer and this is not runtime-verified).

The fix is `{}` at the declaration rather than entries in initialiser lists: type-agnostic, covers
every constructor at once, and cannot reorder a list into C5038.

🔴 **The mechanical fix is wrong in two places, and both would have compiled.**

1. **`usvfs` shared memory.** `sharedparameters.h`, `directory_tree.h` and `tree_container.h` hold
   `boost::interprocess` types — `StringT` is `bc::basic_string` with a `CharAllocatorT`, and the
   lists and maps are allocator-aware. Every constructor already initialises them with an allocator
   bound to the segment manager. A `{}` there builds an allocator bound to **no segment**: dead
   while the constructors keep working, a corruption source in a DLL injected into every game
   process the moment one stops. Reverted; clang-tidy cannot see the difference.
2. **Two-declarator lines.** `uint64_t m_FileSize, m_CompressedFileSize;` — appending `{}` once
   initialises only the second and leaves the first exactly as it was, which *looks* like a fix in
   the diff. Caught by reading the diff, not by the build.

⚠️ **Two of the three message shapes this check emits are noise here**, and counting them as defects
would have inflated the sweep by a fifth: *"does not initialize these bases"* ×1 is
`PropertyVariant`, whose body calls `PropVariantInit(this)`; *"uninitialized record type"* ×25 are
locals fully assigned on the next line (`_ULARGE_INTEGER time; time.LowPart = …`). Only
*"does not initialize these fields"* found real defects.

**#18 and #19 came from clang-tidy**, on its first correctly-configured run — one check,
`cppcoreguidelines-pro-type-member-init`, against `uibase` alone. Neither is visible to MSVC at
`/W4 /WX`, and neither would fail a test. That is the argument for the check family, and the reason
the tree-wide scan is worth its runtime.

**#20 is not fixed and is deliberately still open.** `moddatachecker.h:59` is a genuine unused
parameter in a public header, but MO2's own builds structurally cannot see it: under mob,
`mo2::uibase` is an IMPORTED target, so CMake passes its headers as `/external:I` and
`ExternalWarningLevel=TurnOffAllWarnings` silences them. It only surfaced because the superbuild
consumes uibase as an ordinary in-tree target — 84 instances, which broke `modorganizer`'s `/WX`.

That reframes the project's headline number: **"0 warnings tree-wide" has always meant "0 warnings
in each repository's own sources".** Warnings a public header inflicts on its *consumers* were
invisible by construction, and third-party plugin authors have been seeing them all along. The
superbuild restores parity with `SYSTEM` rather than editing upstream to satisfy a build-system
artifact — but the defect is real, one line, and worth submitting.

**#1 — usvfs / libudis86** is the highest-severity item and the cleanest good-faith PR. A bare
`find_library` under a multi-config generator always resolves to vcpkg's **debug** copy, because
`CMAKE_BUILD_TYPE` is undefined for every Visual Studio build. The release `usvfs_dll` therefore
shipped debug-built disassembly *and* two CRTs in one address space — two heaps, two `errno`/locale
states — inside a DLL injected into every game MO2 launches. **Almost certainly long-standing
upstream, not introduced by us**: a config-agnostic `find_library` has nothing to do with VS2026 or
v145. We are simply the first to see it, because usvfs had never actually been recompiled in this
project until mob's clean bug was fixed.

**#17 — `DLLEXPORT`** is latent today (both headers resolve to `dllimport` in a normal build) but
live under `MO2_ARCHIVE_BUILD_STATIC`, where `archive` defines the macro *empty* and following usvfs
declarations silently lose their import attribute. Two more warts sit in the same six lines:
`_declspec` (single underscore, an MSVC-only legacy spelling clang-cl rejects) and
`#endif DLLEXPORT` (stray tokens after `#endif`). **Affects third-party plugins too** — these are
shipped headers. Fix by guarding `archive`'s define with `#ifndef`, or better, giving each library
its own prefixed macro.

**#2, #3, #8, #14, #15, #16** are one pattern repeated: **an unchecked `QFile::open` whose failure
path still looks like success downstream.** Qt marks `open()` `[[nodiscard]]` for exactly this
reason. Running tally for that warning class across the tree: **6 real bugs, 0 false alarms.**

---

## Build-tool fixes (`mob`)

| Fix | Status |
|---|---|
| **`msbuild::do_clean()` runs a BUILD when no targets are set** (`tools/msbuild.cpp:192`) — it maps `targets_` to `t + ":Clean"`, but with `targets_` empty the guard emits no `-target` argument at all, so msbuild runs its default target. `flags_ \|= allow_failure` hides the consequence. **`usvfs` is the only affected task**, which is why `mob build -b usvfs` compiled nothing and reported success. One-line fix. | **Fixed** (`fb0b12b`), ready to PR |
| **`mob build -c` does not clean preset-defined binary dirs** (`tools/cmake.cpp:273`) — the clean deletes directories named after mob's *own* generators. 32 repos match by luck; `usvfs` uses `vsbuild32`/`vsbuild64` and is never cleaned. Fatal on a generator change. | **Open** — delete by hand |
| **`mob --dry` always reports download failure** (`net.cpp:108-112`) — sets `ok_ = false`, then returns early on `dry()` without ever setting it true. Every download task fails in dry mode *by construction*, so `--dry` can never validate tasks sequenced after the first downloader. Two-line fix. | Open |
| **`bootstrap.ps1` continues after a failed configure** — it only checks `$?` after the *build* step, so a failed `cmake --preset` produces a stale `mob.exe` instead of an error. | Open |

---

## Toolchain fixes that are also PR candidates

| Fix | Repo | Why upstream wants it |
|---|---|---|
| `set(CMAKE_VS_GLOBALS "ResolveNuGetPackages=false")` — one hunk that makes the repo build under CMake 4.x | `installer_omod` | CMake 4.4.2 emits `<target>_autogen` helper projects that inherit the globally-set `<TargetFrameworkVersion>`, so MSBuild runs `Microsoft.NuGet.targets` on a project with no lock file. **Ordering is load-bearing** — the `set()` must come after `dummy_cs_project` is created and before `installer_omod`. Upstream will hit this the moment they move off CMake 3.x. See [`history/PHASE1-TOOLCHAIN.md`](history/PHASE1-TOOLCHAIN.md). |
| Prefer `.slnx`, fall back to `.sln` | `mob` | The VS2026 generator emits the XML solution format and there is no CMake variable to choose. Only usvfs is affected, because it is the one task mob drives through msbuild directly. |

⚠️ **The `toolchain-vs2026` tag is the clean cut point** for a toolchain-only PR branch — see
[ARCHITECTURE.md](ARCHITECTURE.md#the-toolchain-vs2026-tag). One mob commit in that tag (`cdd5779`,
fork identity) must **not** be included.

---

## Missing forks, and what they actually block

Two upstream action repos are **not** forked into the org. Measured 2026-08-11; this had been
recorded as one ten-minute task blocking Phase 4 entirely, and the two halves are not alike.

| Action | Repos referencing it | What forking buys |
|---|---|---|
| `ModOrganizer2/build-with-mob-action@master` | 18 | **Correctness.** It builds against *upstream's* mob, not our fork on `modern`, so per-repo CI cannot verify this tree |
| `ModOrganizer2/check-formatting-action@master` | 20 | **A pinned SHA.** Nothing else — see below |

The formatting action pins clang-format **22** internally and exposes no version input; its only
inputs are `check-path`, `exclude-regex`, `fallback-style` and `include-regex`. Our repos pin three
versions in `.pre-commit-config.yaml`, not the four long recorded: **`22.1.5` ×19, `19.1.5` ×5,
`22.1.2` ×2**. Only three of the five 19.1.5 repos run the action, and all three are clean under
*both* formatters — checked with the actual pinned binaries from the pre-commit cache. They agree by
being 4, 11 and 6 files, not because the versions match.

**Neither fork blocks CI any longer.** The superbuild needs no action at all, and its workflow lives
in this repository at `.github/workflows/build.yml`.

### An upstream gap this turned up (not counted above — nothing is fixed)

**Three C++ repositories ship no `.clang-format`**, and there is none anywhere up the parent tree,
so clang-format falls back to LLVM style in them:

| Repo | C++ files | Runs the formatting action |
|---|---|---|
| `bsapacker` | 123 | no |
| `installer_omod` | 27 | no |
| `bsa_extractor` | 2 | **yes** — passes, because two files happen to satisfy LLVM style |

Nothing is red today, and that is luck rather than design: under their own pinned formatter
`bsapacker` and `installer_omod` produce roughly **3200 and 800** complaints. This is upstream's
configuration, not ours.

⚠️ **The trap is in the remedy.** Rolling a lint workflow out uniformly turns both repos red at
once, and the obvious response — run the formatter over them — is the mass-reformat anti-pattern:
a semantic, tree-wide diff against repositories we have to keep merging from upstream, which turns
every sync into a conflict-resolution session. Add a `.clang-format` matching the sibling repos
first, or leave these three out of the rollout.
