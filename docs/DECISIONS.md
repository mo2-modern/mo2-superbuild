# Decision log

Architecture Decision Records for mo2-modern. Each entry states what was decided, **why**, and
whether it is still binding. The *why* is the point: this project's constraints are unusual (34
tracked forks, a bleeding-edge toolchain, a DLL-injection component that a green build cannot
verify) and several decisions look wrong without it.

**Status values:** `Accepted` · `Proposed` (needs a call) · `Superseded` · `Reversed`

> **Before proposing a change in any of these areas, read the relevant ADR.** Two decisions here
> exist specifically to stop work that looks obviously correct — [ADR-011](#adr-011) and
> [ADR-012](#adr-012) — and one records a claim that was wrong twice ([ADR-021](#adr-021)).

| # | Decision | Status |
|---|---|---|
| [001](#adr-001) | Tracking fork: `master` mirrors upstream, all work on `modern`, merge never rebase | Accepted |
| [002](#adr-002) | The Phase 1 baseline carries **zero** source changes | Accepted |
| [003](#adr-003) | Change exactly **one** toolchain variable per build | Accepted |
| [004](#adr-004) | Stay on standalone CMake 4.4.2, ahead of VS2026's bundled 4.3.1 | Accepted |
| [005](#adr-005) | `qt_vs` stays `2022` | Accepted |
| [006](#adr-006) | Qt policy: newest **stable** only | Accepted |
| [007](#adr-007) | Build Python and tooling Python are configured separately | Accepted |
| [008](#adr-008) | `vcpkg-registry` works on `main`, not `modern` | Accepted |
| [009](#adr-009) | `/WX` is **opt-in per target**, never global | Accepted |
| [010](#adr-010) | Fix warnings; do not suppress them | Accepted |
| [011](#adr-011) | Do **not** unify the clang-format pins | Accepted |
| [012](#adr-012) | Do **not** repair the `EXTERNAL_WARNINGS` keyword | Accepted |
| [013](#adr-013) | Centralizing `vcpkg-configuration` is blocked on Phase 5, not a Phase 2 task | Superseded by Phase 5 |
| [014](#adr-014) | `pybind11` and `spdlog` are pinned **down** deliberately | Accepted |
| [015](#adr-015) | Do not open upstream PRs yet | Accepted |
| [016](#adr-016) | Drop the `cmake_minimum_required` bumps | Accepted |
| [017](#adr-017) | Defer the superbuild `find_package` guards | Superseded: the guards were never needed |
| [018](#adr-018) | Phase order is fixed — do not reorder | Accepted |
| [019](#adr-019) | Archive, don't delete, the 13 retired mirror repos | Accepted |
| [020](#adr-020) | Boost → std: **cut from scope** | **Accepted — cut** |
| [021](#adr-021) | C++23: raise the six standalone repos in place | **Accepted — done** |
| [022](#adr-022) | Documentation is split by content **lifetime** | Accepted |

---

## ADR-001
### Tracking fork — `master` mirrors upstream, all work on `modern`, merge never rebase
**2026-08-09 · Accepted**

Two permanent branches per repo. `master` is a pure mirror of upstream and is **never committed
to** — only fast-forwarded. `modern` is the default branch and carries all our work; upstream flows
in via `git merge master`.

```
upstream/master ──ff──> origin/master ──merge──> origin/modern
                                                   ↑ our commits
```

**Why merge, not rebase:** upstream changes must flow in *forever*, and rebasing would rewrite
published history across 34 repos on every sync. If one of our fixes is worth upstreaming, cut a
*separate* small branch from `master` and PR that — never merge our branch.

**Consequence that drives everything else:** every changed line is merge surface against 34
upstreams. Keep diffs minimal and config-shaped. This rule is cited by [ADR-011](#adr-011),
[ADR-017](#adr-017) and [ADR-020](#adr-020).

`mob` implements this natively — four `mob.ini` keys, no custom tooling. `mo_fallback = master` is
what made a staged rollout possible: repos without a `modern` branch keep building from `master`, so
branches could be created one repo at a time with no big-bang cutover.

---

## ADR-002
### The Phase 1 baseline carries zero source changes
**2026-08-09 · Accepted**

The baseline build compiled **unmodified upstream source** from every repo. The only modernization
commit anywhere was `mob.ini`'s three fork-identity lines.

**Why:** if the baseline is green, "the fork builds upstream's code on VS2022" is proven with no
confound, and every later failure is attributable to exactly one deliberate change.

**Consequence:** Python 3.13 had to be installed, because upstream pins `MO2_PYTHON_VERSION "3.13"`
— which is what produced [ADR-007](#adr-007).

---

## ADR-003
### Change exactly one toolchain variable per build
**2026-08-09 · Accepted**

| Step | Compiler | CMake |
|---|---|---|
| baseline | VS2022 / v143 | 3.31.6 |
| next | VS2022 / v143 | **4.4.2** |
| next | **VS2026 / v145** | 4.4.2 |

**Why:** installing standalone CMake made an *implicit* variable explicit. Simply pointing `env.ps1`
at VS2026 would have silently swapped in VS2026's bundled CMake alongside the new compiler, and any
breakage would have had two candidate causes.

This method is the reason the CMake 4.4.2 / `installer_omod` breakage was diagnosed in hours rather
than days. **Reuse it at the next toolchain jump.**

---

## ADR-004
### Stay on standalone CMake 4.4.2, ahead of VS2026's bundled 4.3.1
**2026-08-09 · Accepted**

Standalone CMake at `C:\Program Files\CMake\bin`, placed first on PATH, decoupled from whatever VS
ships.

**Why:** Microsoft will bump the bundled CMake eventually, so this breakage is inevitable. Meeting
it deliberately now beats meeting it during an unrelated VS update. Being early also means our fixes
are ready before upstream needs them — which is exactly how it played out for `installer_omod`.

Note vcpkg ignores the global CMake and downloads its own.

---

## ADR-005
### `qt_vs` stays `2022`
**2026-08-09 · Accepted**

**Why:** Microsoft guarantees a stable ABI across all of 14.x — v140/v141/v142/v143/**v145**
binaries interlink, so the `msvc2022_64` Qt build links fine against v145. `paths.cpp` derives the
Qt *directory name* from `qt_vs`, so changing it only breaks the path.

**Verified against the repository, not assumed:** `aqt list-qt windows desktop --arch` reports the
same architectures for 6.11.1 and 6.12.0, and **no msvc2026 build exists**.

⚠️ **Re-check at every Qt bump rather than assuming.** Qt shipped separate `msvc2019_64` and
`msvc2022_64` builds even though v142/v143 are ABI-compatible — ABI compatibility alone does not
predict Qt's packaging.

---

## ADR-006
### Qt policy — newest stable only
**2026-08-09 · Accepted**

Stay on 6.11.1. Do not chase 6.12 pre-releases even though 6.12.0 is already in the repository.

**Why:** this closes an open risk permanently rather than re-deciding it each time Qt tags
something. When 6.12 ships stable, re-verify `qt_vs` and the module list ([ADR-005](#adr-005)) and
move.

---

## ADR-007
### Build Python and tooling Python are configured separately
**2026-08-09 · Accepted**

Always invoke tooling as `py -3.14 -m <tool>`. Never rely on bare `python`.

**What is separate is the selection mechanism, not the version.** The *build's* Python is found by
CMake through `HKCU\SOFTWARE\Python\PythonCore\<version>`, not PATH. *Tooling's* is found through
the `py` launcher, and `aqt` and `pre-commit` live in that interpreter's user site-packages. Neither
mechanism can see an interpreter the other one found, so both have to be satisfied independently —
that is the part of this decision that still binds.

**Both are 3.14 today**, since `cmake_common` commit `686fdeb versions: target Python 3.14`.
One correctly registered 3.14 with development headers therefore satisfies both roles: verified
2026-08-15 by configuring and building the whole tree on a machine whose registry listed 3.14 and
nothing else.

🕰 **This ADR originally read "3.13 is the build's Python" and "this split must not be unified",**
written when the two roles really did need different versions. Superseded by the bump above; the
mechanism split survives it, the version split does not.

---

## ADR-008
### `vcpkg-registry` works on `main`, not a `modern` branch
**2026-08-09 · Accepted**

Deliberately unlike the 33 code repos.

**Why:** vcpkg resolves a baseline by fetching that commit, and keeping it on the default branch
removes any question of reachability. It is a dependency database, never something we would PR
upstream — so the `master`/`modern` split in [ADR-001](#adr-001) buys nothing here.

---

## ADR-009
### `/WX` is opt-in per target, never global
**2026-08-09 · Accepted**

A `WERROR` option on `mo2_configure_warnings` / `mo2_configure_target`, default **OFF**.

**Why:** a global `/WX` would have failed most repos on day one, and one noisy target must not be
able to block the whole tree. Opt-in made the campaign incremental — each repo latched only once it
was actually clean.

⚠️ In `usvfs`, `/WX` is applied with `target_compile_options` over the six shipping targets, **not**
`add_compile_options` — the latter would also reach the `if (BUILD_TESTING)` subtree, which mob
never builds and nobody has verified against the flag.

---

## ADR-010
### Fix warnings; do not suppress them
**2026-08-09 · Accepted**

Suppressing C4100 tree-wide would have been one line and zero merge surface, which the "minimal
diffs" rule superficially favours.

**Why rejected:** omitting the parameter name is *already the dominant upstream style* in the
affected files — only the stragglers warned — so fixing makes each file more internally consistent
and is therefore cheap merge surface. More importantly, **blanket suppression destroys the warning's
real signal**: a named-but-unused parameter that *should* have been used is a genuine bug.

**Vindicated repeatedly.** The eight "identical-looking" C4834 warnings contained two
silent-data-loss bugs. A `qtgroupingproxy.cpp` shadowing fix failed to compile when renamed,
revealing that the original was correct *only by virtue of the shadowing*. In total the campaign
found **15 real bugs** ([UPSTREAM.md](UPSTREAM.md)).

---

## ADR-011
### Do NOT unify the clang-format pins
**2026-08-10 · Accepted**

Four different states are active across the repos, one a **major release** behind (`v19.1.5` in
three repos). See [TRAPS.md](TRAPS.md#editing-source) for the table.

**Why leave it:** commits are already safe — pre-commit fetches the correct binary *per repo*. This
is an accuracy problem in our docs, not a correctness one. Bumping `v19.1.5` → `v22.1.5` would
**reformat those files wholesale**, which is exactly the merge surface [ADR-001](#adr-001) exists to
avoid.

The rule that matters is unchanged: **let pre-commit format, never an editor.**

---

## ADR-012
### Do NOT repair the `EXTERNAL_WARNINGS` keyword mismatch
**2026-08-10 · Accepted**

`mo2_configure_target` documents and parses `EXTERNAL_WARNINGS`, but forwards `${ARGN}` to
`mo2_configure_warnings`, which parses `EXTERNAL`. The two keywords never meet, so
`EXTERNAL_WARNINGS ON` at a call site does not produce the `/external:W3` it reads like.

**Why leave it:** external warnings are effectively **off** today, and repairing the keyword would
switch `uibase` to `/external:W1` and surface Qt-header warnings tree-wide — turning a clean tree
noisy for no defect yield.

Second cause worth knowing: **Qt's own CMake also adds `/external:W0`.** Under the VS generator
CMake folds both into one `<ExternalWarningLevel>` and Qt's W0 wins. Under Ninja both land literally
and MSVC emits `D9025 overriding '/external:W0' with '/external:W1'`, which `/WX` then promotes to
an error — harmless for the VS build, but it bites the `tidy/` trees.

---

## ADR-013
### Centralizing `vcpkg-configuration` is blocked on Phase 5
**2026-08-09 · Accepted**

This was listed as a cheap standalone Phase 2 task. **It is not a task at all — vcpkg has no such
feature.** Per the official reference: *"All fields in the `vcpkg-configuration.json` file are only
used from the top-level project — the files in any dependencies are ignored."* No inheritance, no
parent-directory search, no global config in manifest mode. Sharing one file is an open feature
request.

**That same rule is the way out:** in a **superbuild with one top-level manifest, the other 32
configs become inert** — they need neither deleting nor migrating, they simply stop being read.
So the real fix *is* Phase 5.

⚠️ **This does not promote Phase 5.** The remnant stays parked; see [ADR-018](#adr-018).

---

## ADR-014
### `pybind11` and `spdlog` are pinned down deliberately
**2026-08-09 · Accepted**

`pybind11` 2.13.6 (upstream 3.1.0) and `spdlog` 1.15.3 (upstream 1.17.0). Our registry lists them so
it wins over `microsoft/vcpkg`.

**Why:** pybind11 2.x → 3.x is a breaking major **in the library that generates `mobase`** — that is
a project, not a bump. Revisit only when modernizing `plugin_python`.

---

## ADR-015
### Do not open upstream PRs yet — gated on a week of real use
**2026-08-10 · Accepted · gate defined 2026-08-11**

**31 verified bug fixes** and 4 build-tool fixes are ready. **Not submitting yet.**

🔴 **The gate, set by the owner:** submit only after MO2 has been *used* for roughly a week and a
real mod list has been built with it.

**Why that is the right gate, not a delay.** Every fix in the inventory is verified against the
compiler or a static analyser, and the tree is runtime-verified only in the narrow sense that usvfs
injects and MO2 starts. None of it has been exercised the way a mod list exercises it — installers
running against real archives, the save-game parsers reading real saves, the download manager
resuming real downloads. Several fixes are in exactly those paths (`ModRepositoryFileInfo`'s
Nexus fields, the FOMOD condition types, the Gamebryo save readers), and a PR that turns out to
change behaviour under real use is far more expensive to withdraw than to delay.

⚠️ **Known cost, stated so the decision stays informed:** every upstream commit touching those files
raises the rebase price on fixes already paid for, and the bugs remain live for upstream users.

The inventory is maintained in [UPSTREAM.md](UPSTREAM.md) so the set stays submittable the day
this reverses. Upstreaming means cutting a fresh branch from `master` and applying the single
change, never merging `modern`.

---

## ADR-016
### Drop the `cmake_minimum_required` bumps
**2026-08-09 · Reversed from an earlier plan · Accepted**

**Why:** tested empirically against CMake 4.4.2 — it warns only below **3.10**. The 62 declarations
at 3.16 (plus 3.18/3.21/3.22/3.23) produce **no warning at all**. Bumping would change CMake policy
defaults, i.e. behavioural risk for zero benefit.

---

## ADR-017
### Defer the superbuild `find_package` guards
**2026-08-09 · Accepted**

57 `find_package(mo2-* CONFIG REQUIRED)` calls would each need an `if(NOT TARGET …)` guard for a
superbuild. **22 are mechanical; 27 need a real decision** — `mo2-cmake` exports *CMake modules*,
not targets, so `if(NOT TARGET)` cannot work and it needs an
`if(NOT COMMAND mo2_configure_target)` sentinel or a top-level `include()`.

**Why defer:** the guards are safe but deliver **zero value until a superbuild exists**, and each
adds merge surface across 22 repos. Doing them speculatively, ahead of settling the `mo2-cmake`
question, would be work without payoff.

---

## ADR-018
### Phase order is fixed — do not reorder
**2026-08-09 · Accepted**

Each phase must be green before the next starts. See ROADMAP.md (mob working tree).

**Why it keeps coming up:** the one parked Phase 2 remnant is blocked on Phase 5
([ADR-013](#adr-013)), and Phase 5 would also deliver the "open in an IDE and click build" goal
sooner. **Moving Phase 5 earlier would be a deliberate decision and has not been made.**

---

## ADR-019
### Archive, don't delete, the 13 retired mirror repos
**2026-08-09 · Accepted**

Upstream folded all per-game plugins into `game_bethesda`, so the org mirrors ~13 repos that no
longer exist upstream: `game_enderal`, `game_fallout3/4/4vr/nv`, `game_features`, `game_gamebryo`,
`game_morrowind`, `game_oblivion`, `game_skyrim/SE/VR`, `game_starfield`, `game_ttw`,
`modorganizer-NCC`, `modorganizer-installer_ncc`.

**Why archive:** they are the only record of the pre-consolidation layout, and deleting a fork is
irreversible. Confirm the list with the owner before acting.

---

## ADR-020
### Boost → std — cut from scope
**2026-08-10 · ACCEPTED 2026-08-11 — CUT. Do not start this.**

**Measured, not estimated:** **39 files / 135 includes / 5 repos** — the *smallest* remaining Phase 3
item, not "the largest and most invasive" as previously recorded. (A naïve grep says ~34,000 because
`vcpkg_installed/` sits inside the repos; see [TRAPS.md](TRAPS.md#surveys-and-worklists).)

| Repo | Files | Includes |
|---|---|---|
| `usvfs` | 19 | 70 |
| `modorganizer` | 17 | 50 |
| `lootcli` | 1 | 10 |
| `bsatk` | 1 | 4 |
| `bsapacker` | 1 | 1 |

**Size is the wrong axis — destination is:**

| | Libraries | ~Includes |
|---|---|---|
| **Mechanical** (std equivalent exists) | `filesystem` 15, `algorithm` 9, `type_traits` 6, `bind` 4, `shared_ptr` 3, `lexical_cast` 3, `scoped_ptr` 2, `function` 2, `static_assert` 2, `optional`, `any`, `scoped_array`, `shared_array` | ~55 |
| **No std destination** | `interprocess` 11, `fusion` 11, `thread` 10, `signals2` 6, `container` 6, `predef` 6, `log` 5, `accumulators` 3, `multi_index` 3, `ptr_container` 2, `uuid` 2, `locale` 2, `range` 2, `di`, `dll`, `mp11`, `program_options`, `format` | ~80 |

`usvfs` `interprocess` ×11 is the shared-memory IPC the VFS is built on; `modorganizer`
`fusion` ×11 + `signals2` ×6 is its event plumbing. **Porting those means rewriting subsystems, not
swapping headers.**

**Argument for cutting:**
- It finds **zero bugs**. Every other Phase 3 item is a defect finder — the warning campaign
  returned 15 real bugs for ~1000 lines. This returns 0 for more.
- It produces the **largest merge surface in the project**, against [ADR-001](#adr-001).
- Upstream has not asked for it, so none of it is cherry-pickable back — it is divergence we own
  forever and pay for on every sync.

**Decision, 2026-08-11: cut.** Struck from the Phase 3 goal in ROADMAP.md (mob working tree).

**This includes the ~55 "mechanical" includes.** They were the tempting middle option and they are
not worth it either: the same zero defects, still spread across 5 upstreams, and a half-migrated
tree is worse than either end state because the next person cannot tell which remaining `boost::`
include is deliberate. `boost::interprocess` in a DLL-injection VFS, and `fusion` + `signals2` in
MO2's event plumbing, are dependencies that happen to be spelled `boost` — not debt.

---

## ADR-021
### C++23 — raise the six standalone repos in place
**2026-08-10 · ACCEPTED — implemented 2026-08-10, 6 signed commits (unpushed)**

The roadmap described this as *"currently `CXX_STANDARD 20` in most repos."* **That was wrong twice
over.**

`cmake_common/mo2_cpp.cmake:163` has defaulted to **23** since *upstream* commit `ec11e37` (17 only
for C++/CLI), so every repo routing through `mo2_configure_msvc` is **already at 23**. Exactly six
repos name `20`, and they **do not use `cmake_common` at all** — that line is their only standard
declaration:

| Repo | Site |
|---|---|
| `archive` | `src/CMakeLists.txt:7` |
| `bsatk` | `src/CMakeLists.txt:37` |
| `esptk` | `src/CMakeLists.txt:26` |
| `helper` | `src/CMakeLists.txt:9` |
| `lootcli` | `src/CMakeLists.txt:24` |
| `usvfs` | `CMakeLists.txt:9` (directory-scope `CMAKE_CXX_STANDARD`) |

🪤 **The obvious edit is the wrong one.** These are *not* downward overrides of a 23 default — there
is no default reaching them. **Deleting the line drops them to the MSVC default, not up to 23.** The
correct change is `20` → `23` in place, six lines.

⚠️ **`uibase/tests/cmake/CMakeLists.txt:10` also says 20 and must STAY at 20** — it is the
out-of-tree consumer fixture proving a C++20 third-party plugin still compiles against uibase's
installed headers. Raising it deletes the only guarantee that MO2's plugin ABI stays reachable from
C++20.

**Cost:** six lines. Budget a **full** `usvfs` rebuild, not an incremental one — see
[TRAPS.md](TRAPS.md#mobs-own-bugs).

---

**Outcome (2026-08-10).** Applied as specified; six one-line commits, signed, **not pushed**.
Verified at the effective command line, not from the CMake call: all six now emit
`<LanguageStandard>stdcpplatest</LanguageStandard>`. usvfs rebuilt both architectures from scratch
(1843 log lines vs 1852 in `final.log` — a real build, not the 20-second no-op). **0 errors, 0 new
warnings**; the 25 linker/STL warning lines observed are present in `final.log` too. Consumers
relinked (`modorganizer`, `preview_bsa`, `bsa_extractor` — `archive`/`bsatk`/`esptk` are **static**,
so their code is copied into each consumer). ✅ **usvfs runtime-verified 2026-08-10** — Explorer++
through MO2, 45 `type overwrite` + 1 `type chained patch`, 0 errors.

**Two corrections to the analysis above:**

1. **"Exactly six repos name 20" undercounted — there are eight.** `installer_omod`
   (`src/CMakeLists.txt:40`) and `installer_fomod_csharp` (`src/CMakeLists.txt:11`) also set
   `CXX_STANDARD 20`, and unlike the six these **are** genuine overrides: both pass `CLI ON`, so
   `mo2_configure_msvc` sets 17, and each repo then raises it back to 20. **Leave them.** `/clr` is
   incompatible with `/std:c++latest`, so **C++20 is their hard ceiling**, and the override is
   raising them to it, not holding them down. They are the source of the 7 `STL4038`
   (`<generator>` needs C++23) warnings, which are therefore **not fixable by raising the standard**.

2. **C++23 and C++26 are the same flag here.** MSVC has no `/std:c++23`; CMake maps `CXX_STANDARD`
   `23` *and* `26` to `/std:c++latest`. Post-change the tree measures **92 of 94 generated projects
   at `stdcpplatest`**, the other 2 being the C++/CLI pair above. So this ADR did not put the tree
   "on C++23 with C++26 as runway" — it put it on the **latest working draft**, and a follow-up
   C++26 build task would change nothing. See ROADMAP.md (mob working tree).

---

## ADR-022
### Documentation is split by content lifetime
**2026-08-10 · Accepted**

The single 1762-line `MODERNIZATION.md` was replaced by this `docs/` tree. 68% of its Phase 3
section was a completed work log that nobody needed to read, with the durable traps buried inside
it — which is why it had grown a "START HERE" block instead of an organization.

**Split by lifetime, not by phase:**

| Lifetime | Files |
|---|---|
| Changes every session | ROADMAP.md (mob working tree) |
| Changes when a decision is made | `DECISIONS.md` (this file), [UPSTREAM.md](UPSTREAM.md) |
| Changes when the system changes | [ARCHITECTURE.md](ARCHITECTURE.md), [BUILD.md](BUILD.md), TOOLING.md (mob working tree) |
| Append-only, never rewritten | [TRAPS.md](TRAPS.md) |
| Frozen | [`history/`](history/) |

**Why it matters for an assistant-driven project:** context is finite. A new session reading
`ROADMAP.md` + `TRAPS.md` (~700 lines) has everything it needs to act correctly, instead of 1762
lines of which two-thirds is archive.

**The old `3.x` section numbers are preserved inside `history/PHASE3-WARNINGS.md`** so commit
messages and older notes citing them still resolve. Do not renumber them.

---

## ADR-023
### Building installs, via a target in `ALL` rather than the solution setting alone
**2026-08-15 · Accepted**

`CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD` stays, and a `mo2-install` custom target in `ALL` is
added beside it. It depends on every target collected by walking `SUBDIRECTORIES` /
`BUILDSYSTEM_TARGETS`, so it runs last, and it invokes `cmake --install` with `$<CONFIG>`.

**Why:** the setting alone only covers opening the generated `build\mo2.slnx`. The flow the README
documents — open the *folder* — is Visual Studio's CMake mode, which builds via `cmake --build` and
never reads the solution's project list. Measured on a clean clone: exit 0, 0 errors, 0 warnings,
46 projects linked, and **no `install/` at all**, leaving only the `build\` copy of
`ModOrganizer.exe`, which has no plugins, Qt runtime or usvfs beside it and cannot start.

**Why a collected dependency list and not a written one:** a hand-listed set silently stops covering
repositories as they are added, and the failure is a race rather than an error.

**Cost, measured warm:** `ALL_BUILD` alone 5.3 s, with the install 12.8 s. Accepted, because the
install is idempotent — every rename in `mo2_deploy_qt` is guarded by an `EXISTS` test.

**Rejected:** telling people to build the `INSTALL` target by hand. "Open the folder and press
build" is the entire premise of this repository; a second mandatory step is the thing it exists to
remove.

---

## ADR-024
### Configure downloads Qt, and `MO2_QT_MODULES` is the only copy of the module list
**2026-08-15 · Accepted**

Qt is fetched automatically when it cannot be found (`MO2_AUTO_INSTALL_QT`, default ON), and the
module list lives in exactly one place, from which both the download and the printed fallback are
generated.

**This reverses the earlier position** that 3.3 GB must never be pulled silently inside an IDE
configure. That position was right about the risks and wrong that they were inherent:

| Objection | What answers it |
|---|---|
| silent | aqt's output is not captured, so it streams to the CMake output pane, behind a banner naming the size first |
| no recovery | staged into `qt.tmp/`, renamed to `qt/` only after `Qt6Config.cmake` verifies — a dropped connection leaves *no* `qt/`, so the next configure retries |
| not the user's choice | `MO2_AUTO_INSTALL_QT=OFF` prints the command and stops, exactly as before |

It never deletes: a `qt/` holding the wrong Qt is an error, not something to clear. And aqt is
installed into a throwaway venv under `build/`, because configuring a project must not mutate the
site-packages of an interpreter used for other things.

**The single module list is the more important half**, and would be worth doing even without the
download. The list was duplicated across `CMakeLists.txt`, `README.md`, `docs/BUILD.md` and
`.github/workflows/build.yml`; they drifted, and [TRAPS.md](TRAPS.md#toolchain) records the four
months in which `qtwebsockets` and `qtnetworkauth` were missing from the documented copies, so
anyone following this project's own instructions on a clean machine could not configure. Deriving
both the executed and the printed command from `MO2_QT_MODULES` makes them the same string by
construction. **Do not reintroduce a second copy anywhere, including in CI.**

**Verified 2026-08-15** end to end from a tree with no `qt/`: 3.32 GB downloaded, all modules
present, staged and renamed, 23 s. The failure paths were exercised separately — a rejected version
leaves no `qt.tmp` and no `qt/`, and a pre-existing wrong `qt/` stops configure without deleting it.
