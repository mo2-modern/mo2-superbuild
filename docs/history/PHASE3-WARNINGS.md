# Phase 3 — the warnings-as-errors campaign (ARCHIVE)

> **Status: COMPLETE, 2026-08-10. This is a historical work log, kept for provenance.**
>
> Nothing here is an outstanding action. It records how the tree went from 368 raw warnings in
> `modorganizer` and an unmeasurable `usvfs` to **0 warnings / 0 errors tree-wide with `/WX`
> enforced in every C++ repo**, and how **15 real bugs** were found on the way.
>
> **You do not need to read this to work on the project.** Read it when you want to know *why* a
> particular line looks the way it does, or when a similar campaign is being planned.
>
> The durable lessons extracted from this campaign live in [`../TRAPS.md`](../TRAPS.md) and
> [`../DECISIONS.md`](../DECISIONS.md); the bugs it found are inventoried in
> [`../UPSTREAM.md`](../UPSTREAM.md). Those are the maintained documents — this one is frozen.
>
> Section numbers (`3.0`, `3.0b`, `3.4`…) are preserved exactly as written so that commit messages
> and older notes citing them still resolve. They are in *writing* order, not numeric order.
> References to `3.2` point at [`../TOOLING.md`](../TOOLING.md), which was extracted from this
> campaign because it describes live tooling rather than finished work.

---

### 3.0 — Warning baseline, measured 2026-08-09

Logs: `baseline-mo.log` (uibase + modorganizer, `-c`), `baseline-usvfs.log` (usvfs, `-b`). Both
`mob done`, 0 errors.

**The warning level is NOT uniform, and the doc previously described it wrongly.** Every repo's
`CMakePresets.json` sets `CMAKE_CXX_FLAGS = "/EHsc /MP /W4"` as a global floor;
`mo2_configure_warnings` (`cmake_common/mo2_cpp.cmake:13`) then appends a per-target `/W` flag that
wins because MSVC takes the last one. So:

| Call site | Target flag added | Effective | Count |
|---|---|---|---|
| default / `WARNINGS ON` | `/Wall` | **`/Wall`** | e.g. `uibase` |
| `WARNINGS 4` | `/W4` | `/W4` | 37 sites, incl. `modorganizer` |
| `WARNINGS OFF` | *nothing* | **`/W4`** (preset floor still applies) | 10 sites |

⚠️ **`WARNINGS OFF` does not mean off** — it means "don't add a target flag", leaving the preset's
`/W4`. No target in the tree is silent. `usvfs` is outside all of this: it never calls
`mo2_configure_*` at all.

**Result — the debt is in the application, not the library:**

| Repo | Level | Warnings |
|---|---|---|
| `uibase` | **`/Wall`** + external warnings **off** | **6** → **0, now `/WX`** (3.3) |
| `modorganizer` | `/W4` | **368** |
| `usvfs` | — | **not measured, see 3.0b** |

`/Wall` is *not* the unusable noise wall it normally is, because `mo2_configure_warnings` pairs it
with `/external:anglebrackets`, which puts every `<...>` include on a separate (lower) warning
level. Zero C4820/C4626/C4711 padding-and-codegen chatter in the whole log. **uibase was six fixes
away from `/Wall + /WX`** — and it is the repo the other 16 link against, so it was the
highest-leverage, lowest-risk place to set the warning policy.

⚠️ **Read the generated `.vcxproj`, not the CMake, to learn a target's real warning flags.** mob
builds at minimal msbuild verbosity, so no compiler command line ever reaches the log. For uibase,
`vsbuild/src/uibase.vcxproj` shows `WarningLevel=EnableAllWarnings`,
`TreatAngleIncludeAsExternal=true`, `TreatWarningAsError=true` and
**`ExternalWarningLevel=TurnOffAllWarnings`** — external headers are fully silenced, which is the
real reason `/Wall` yielded only 6.

⚠️ **Inconsistency in `cmake_common` — RESOLVED 2026-08-10.** `mo2_configure_target` documents and
parses `EXTERNAL_WARNINGS`, but forwards `${ARGN}` to `mo2_configure_warnings`, which parses
`EXTERNAL`. The two keywords never meet, so `EXTERNAL_WARNINGS ON` at a call site (uibase does this)
does **not** produce the `/external:W3` it reads like — `MO2_EXTERNAL` falls back to its default and
MO2 emits `/external:W1`.

The observed `W0` had a second cause, found via the Ninja side tree (3.2): **Qt's own CMake also
adds `/external:W0`.** Under the VS generator CMake folds both into the single
`<ExternalWarningLevel>` property and Qt's W0 wins — which is why the project reads
`TurnOffAllWarnings`. Under Ninja both flags land on the command line literally and MSVC says:
```
cl : Command line warning D9025 : overriding '/external:W0' with '/external:W1'
```
…which `/WX` then promotes to an error. Harmless for the VS build; only bites a Ninja tree.
Do not "fix" the keyword casually — external warnings are effectively off today, and repairing the
keyword would switch uibase to W1 and surface Qt-header warnings tree-wide.

`modorganizer`'s 368, by nature:

| Bucket | Codes | Count | Risk |
|---|---|---|---|
| Cosmetic | C4100 (130), C4189 (26), C4456/7/8/9 (43), C4101 (1) | **200** | none — mechanical |
| Deprecated API | C4996 | ~46 distinct sites | low, but API migration |
| Conversions | C4267 (24), C4245 (22), C4018 (1) | 47 | **real bugs hide here** |
| `[[nodiscard]]` discarded | C4834 | 8 | each needs a judgment |
| Deprecated enum-to-enum `==` | C5054 | 8 | C++20 deprecation |
| Possibly uninitialized | C4701 | **1** | **highest-value line in the set** |

⚠️ **Count DISTINCT `file(line,col)` sites, never matching log lines.** Two independent inflators:
1. MSVC repeats the warning prefix on the `with [ T=... ]` continuation lines of template
   diagnostics (hits C4996 hardest).
2. A warning in a **header** is re-reported by every `.cpp` that includes it —
   `modinfoforeign.h` showed 24 mentions for **8** real sites.

Deduplicated, modorganizer's **368 raw mentions are 271 distinct sites** across 85 files:

| C4100 | C4996 | C4189 | C4267 | C4456 | C4458 | C4459 | C4834 | C5054 | C4245 | C4457 | rest |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 104 | 45 | 26 | 23 | 18 | 10 | 10 | 8 | 8 | 6 | 5 | 8 |

⚠️ **An incremental build under-reports.** Only recompiled TUs emit warnings, so a count taken after
a partial rebuild is a *lower bound*. Use `-c` before trusting any total.

The C4996s are two unrelated families:
- **Qt (~41):** `QScopedPointer::take` **15** (→ `std::unique_ptr::release`), `QVariant::Type` 6,
  `QSortFilterProxyModel::invalidateFilter` 5 (→ `invalidateRowsFilter`), `Qt::operator+` 4,
  `QDropEvent::pos` 3 (→ `position()`), `QDateTime::fromSecsSinceEpoch` 3, `QMouseEvent` ctor 2,
  `QVariant::convert` 1, `QRegularExpression::AnchoredMatchOption` 1
- **CRT (5):** `strerror` ×2, `getenv` ×2, `gmtime` ×1 — the `_CRT_SECURE_NO_WARNINGS` family.
  Replacing these is also a portability win for the clang-cl track (3.2).

The 9 signal warnings, individually:
- `modorganizer/src/envsecurity.cpp:382` — C4701 `enabledVariant` possibly uninitialized
- C4834 ×8 — `nxmaccessmanager.cpp:940`, `profile.cpp:381`, `plugincontainer.cpp:1136` and `:1185`,
  `pluginlist.cpp:707`, `selfupdater.cpp:238`, `texteditor.cpp:107`, `usvfsconnector.cpp:61`

⚠️ **TRAP: grep under-reports deprecated Qt APIs; trust the compiler.** A source survey for
`QVariant::Type` returned **0** while the compiler found **6** — the deprecated entity is reached
through `.type()`, not by naming the type. Cross-checks that *do* hold: `.take()` → 15 sources,
15 warnings. **Never conclude an API is unused from a grep.**

Legacy Qt5 debt is genuinely gone, though — upstream already paid the Qt6 port: `QLinkedList`,
`QStringRef`, `qrand`/`qsrand`, `QDesktopWidget`, `setMargin` all **0** tree-wide. 22
`foreach`/`Q_FOREACH` remain in modorganizer (38 tree-wide), and 2 `QRegExp`.

### 3.0b — usvfs was IMPOSSIBLE to force-rebuild through mob — ✅ FIXED 2026-08-09

`mob build -b usvfs` reported success in 20s having compiled **nothing** — 88 "up-to-date", four
`Build succeeded. 0 Warning(s)`. Two independent mob bugs compose:

1. **`msbuild::do_clean()` silently degenerates into a build** (`mob/src/tools/msbuild.cpp:192`). It
   maps `targets_` to `t + ":Clean"`, but `usvfs::create_msbuild_tool` never calls `.targets(...)`,
   so `targets_` is empty → the map yields empty → `run_for_targets`'s
   `if (!targets.empty())` guard emits **no `-target` argument** → msbuild runs its default target,
   Build. All four logged command lines are byte-identical. `do_clean` also sets
   `flags_ |= allow_failure`, so it cannot even report a problem.
2. **`-c` doesn't clean usvfs either** — the already-documented `vsbuild32`/`vsbuild64` blind spot.

Net: neither flag could force a usvfs rebuild. The riskiest component in the project sat behind a
measurement blind spot.

**FIX (landed on `mo2-modern/mob` branch `modern`, `tools/msbuild.cpp:192`):** fall back to the
solution-wide `Clean` target when `targets_` is empty. **Verified** — `mob build -b usvfs` went from
20s / four `0 Warning(s)` to **137s**, and the logged command lines now read:

```
target=Clean    platform=Win32     ← was <NONE>
target=Clean    platform=x64       ← was <NONE>
target=<NONE>   platform=x64       (build — correct, default target is Build)
target=<NONE>   platform=Win32
```

Bug 2 (`-c` not deleting `vsbuild32`/`vsbuild64`) is **still open** — deleting them by hand remains
the workaround for a *generator* change. `-b` now works and is the right flag for a forced rebuild.

⚠️ **Consequence worth absorbing: usvfs's warnings had NEVER been observed in this project.** The
known-good 2026-07-30 log contains exactly **1** `[usvfs]` line — the old tree hit the same bug. Any
past "usvfs rebuilt clean" reading measured nothing. Re-read old notes with that in mind.

### 3.0c — usvfs baseline, and a real bug it exposed (2026-08-09)

Log: `baseline-usvfs2.log`. **11 warnings (Win32) + 7 (x64).** usvfs does not use `cmake_common` —
no `mo2_configure_*` call anywhere — so it sets its own flags (`CMAKE_CXX_STANDARD 20`, note: not
23) and is unaffected by the warning table in 3.0.

Compiler warnings, all distinct sites:
- `shared/tree_container.h:240` and `:249` — C4459 `'manager'` hides global declaration
- `usvfs_dll/usvfs.cpp:418` — C4459 `'context'` hides global declaration
- `thooklib/ttrampolinepool.h:138` — **C4309 truncation of constant value** — in the trampoline
  allocator; worth a real look
- `shared/stringutils.cpp:56` — C4505 `usvfs::shared::normalize` unreferenced, removed

#### 🔴 `usvfs_dll` linked the DEBUG build of libudis86 — found + fixed 2026-08-09 (`6beaf55`)

`LNK4098: defaultlib 'MSVCRTD' conflicts with use of other libs`, **both architectures**, on
`usvfs_dll`. Traced to ground via `CMakeCache.txt`:

```
LIBUDIS86_LIBRARY:FILEPATH=.../x64-windows-static-md/debug/lib/libudis86.lib   ← resolved (481,116 b)
                           .../x64-windows-static-md/lib/libudis86.lib         ← ignored  (681,900 b)
```
(identical for `vsbuild32` / `x86-windows-static-md`.)

**Mechanism — and it is a general vcpkg trap, not a usvfs quirk.**
`find_library(LIBUDIS86_LIBRARY libudis86)` (`src/thooklib/CMakeLists.txt:4`) is
**configuration-agnostic**: under a multi-config generator it resolves *once* at configure time and
that single path is used for every configuration. Which path? From `vcpkg/scripts/buildsystems/
vcpkg.cmake`, `z_vcpkg_add_vcpkg_to_cmake_path()`:

```cmake
set(vcpkg_paths "<triplet>${suffix}" "<triplet>/debug${suffix}")
if(NOT DEFINED CMAKE_BUILD_TYPE OR CMAKE_BUILD_TYPE MATCHES "^[Dd][Ee][Bb][Uu][Gg]$")
    list(REVERSE vcpkg_paths) # Debug build: Put Debug paths before Release paths.
endif()
```

⚠️ **`CMAKE_BUILD_TYPE` is ALWAYS undefined under a multi-config generator**, so that `NOT DEFINED`
branch fires for *every* Visual Studio build and puts vcpkg's **debug prefix first** on
`CMAKE_PREFIX_PATH`. The comment says "Debug build", but it catches all of ours. Consequence:
**any bare `find_library()` under vcpkg + the VS generator resolves to the DEBUG library.**

Swept 2026-08-09: the MO2 tree contains **exactly one** bare `find_library` — this one. Every other
dependency arrives via an imported CONFIG target (`asmjit::asmjit`, `spdlog::…`), which maps
per-config correctly. **New `find_library` calls must never be added bare.**

**FIX (`6beaf55`, usvfs `modern`):** resolve release and debug separately with `NO_DEFAULT_PATH`
under `${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}`, then `select_library_configurations(LIBUDIS86)`
— which checks `GENERATOR_IS_MULTI_CONFIG` and emits `optimized <rel>;debug <dbg>`. Verified from a
deleted `vsbuild32`/`vsbuild64`: both variables now resolve to their own variant and **LNK4098 is
gone from both architectures** (warnings 11→10 Win32, 7→6 x64).

✅ **RUNTIME-VERIFIED 2026-08-09** — Skyrim SE launched through SKSE through MO2. Evidence in
`build\install\bin\logs\usvfs-2026-08-09_20-49-47.log` (written 22:51, after the 22:40 install):
- usvfs injected into **three** processes — MO2 (15120), `skse64_loader.exe` (7996), the game (19396)
- **trampolines actually built**: `hooked GetFileAttributesExA … type overwrite`,
  `SetFileAttributesW … type chained patch` — this is the libudis86 code path, since the
  disassembler is what finds instruction boundaries in the target prologue
- `inithooks in process 19396 successful`; real VFS mapping (`po3_SpellPerkItemDistributor.ini`,
  `plugins.txt` rerouting); clean teardown `releasing hook context` / `2 users left`
- **0 errors, 0 warnings** in the whole log

Recipe worth reusing: the usvfs runtime log is the authoritative proof of injection. `type overwrite`
/ `type chained patch` lines mean trampolines were built; their absence means the DLL loaded but
never hooked anything, which is *not* a verification.

`find_package` was not an option: the `libudis86` port exports **no CMake config** — its
`share/libudis86` holds only copyright and SPDX files.

**Why it matters:** libudis86 is the disassembler the hooking engine uses to decode instruction
lengths when installing trampolines. A Release `usvfs_dll` therefore ships debug-built disassembly
*and* pulls `MSVCRTD` into a DLL injected into every game process MO2 launches — two CRTs in one
address space means two heaps and two `errno`/locale states. This is exactly the "usvfs breaks
subtly" High risk in the risk table, and a clean compile never hinted at it.

**Provenance: almost certainly long-standing upstream, NOT introduced by us.** A config-agnostic
`find_library` has nothing to do with VS2026/v145 — we are simply the first to see it, because
fixing the mob bug above is what made usvfs warnings visible at all. Cannot be confirmed from the
old log (see 3.0b). **Strong upstream PR candidate.** Fix by resolving debug and release separately
and selecting with a generator expression, or by consuming a CONFIG package if the port exports one.

Also present, benign but worth knowing: `LNK4217`/`LNK4286` on `asmjit`'s `x86RegData` — symbols
defined in a static `asmjit.lib` but referenced as `dllimport`, i.e. an `ASMJIT_STATIC` define
mismatch. Cosmetic today; it would become an error if asmjit's linkage ever changed.

### 3.1 — Ordering decided 2026-08-09

1. ✅ **DONE** — fix `msbuild::do_clean` in our `mob` fork (3.0b). Immediately exposed 3.0c.
2. ✅ **DONE** — `uibase` at `/WX`, warning-clean (3.3). `WERROR` mechanism now exists in
   `cmake_common` for every later repo.
3. ✅ **DONE** — `usvfs` libudis86 debug-link fix (3.0c). Pushed (`6beaf55`), LNK4098 gone,
   runtime-verified with Skyrim SE + SKSE.
4. 🟡 **IN PROGRESS** — modorganizer's 271 distinct sites (3.4). Cosmetic buckets first
   (174 zero-risk), then conversions, then the 9 signal warnings by hand.

### 3.4 — modorganizer warning campaign (started 2026-08-09)

Target: `/W4 + /WX` on `organizer`, using the `WERROR` lever from 3.3. **271 distinct sites, 85
files.** Work in committable batches, densest files first, rebuilding between batches.

**Batch 1 — `e1cf9132`, 47 C4100 sites, 5 files** (`modinfoforeign.h`, `modinfooverwrite.h`,
`virtualfiletree.cpp`, `qdirfiletree.cpp`, `envshell.cpp`). All no-op virtual override stubs and
Win32 menu callbacks — parameters that are part of an inherited signature with nothing the body
could do with them. 0 errors; clang-format clean; net **−19 lines**, because several stubs collapse
onto one line once the names go.

**Decision: fix, don't suppress.** Suppressing C4100 tree-wide would be one line and zero merge
surface, which the "minimal diffs" rule superficially favours. Rejected because *omitting the name
is already the dominant upstream style in these files* — `modinfoforeign.h` was mostly written that
way and only the stragglers warned. Fixing makes each file more internally consistent, so it is
cheap merge surface, and it preserves the warning's real signal: a named-but-unused parameter that
*should* have been used is a genuine bug, and blanket suppression would hide it.

Remaining C4100 is a long tail — `mainwindow.cpp` 7, `modlistbypriorityproxy.cpp` 4, then 3s, 2s and
a run of single sites across ~30 files.

**Batch 2 — `127cd417`, the 9 signal warnings.** All eight C4834 were a discarded
`QIODevice::open()`. Qt marks it `[[nodiscard]]` exactly because ignoring it converts a failed open
into a **silent no-op**, and two were real data loss:

- 🔴 **`TextEditor::save()`** opened the file, ignored the failure, then called
  `document()->setModified(false)` and **returned `true`**. On a failed open the editor reported
  success, cleared the modified flag, and dropped the user's edits with no indication. Now logs and
  returns false.
- 🔴 **`Profile` mod list rename** opened for writing, ignored the failure, wrote nothing, and still
  logged `"Renamed N mods"`. Now logs the error and returns instead of claiming success.

The other six are the same shape at lower severity — a failed open would leave the locked load order
silently empty, the update file unwritten, the skipped-plugin loadcheck unremembered, or the usvfs
log missing. The app icon is a compiled-in resource, so that one only warns.

**C4701 `envsecurity.cpp`** was *latent, not live*: `enabledVariant` is only assigned inside
`if (policy)`, but `policy` cannot actually be null there — the block above either returns or resets
it to non-null. The compiler can't prove that. Initialised to `VARIANT_FALSE` so the defensive
branch has a sane answer rather than stack garbage if the early return is ever changed.

⚠️ **Lesson: `[[nodiscard]]` warnings are worth reading individually, not batch-silencing.** Eight
identical-looking warnings contained two silent-data-loss bugs. A `(void)` cast or a blanket
suppression would have buried both.

**Batch 3 — `821b487f`, the C4100 tail (57 sites, 36 files) + C4101.** Mostly Qt slots and
overrides whose signature is fixed by the base class or by the connected signal. **C4100 and C4101
are now at zero.**

⚠️ **My site survey missed `src/shared/`.** The extraction regex only matched files directly under
`src/`, so `shared/directoryentry.cpp` and `shared/fileregister.cpp` never appeared in the list of
55 and only surfaced when the compiler was asked again. Second instance today of the same lesson:
**derive worklists from the compiler, not from a regex over paths.**

`organizercore.cpp` had `catch (std::exception& e) {}` — an *empty* handler, which is why C4101
fired for the unused `e`. The warning was cosmetic; what it pointed at was not. Any failure while
generating a preview was swallowed with no trace anywhere. Now logged at debug; the preview stays
optional and the user is still not interrupted.

⚠️ **clang-format reflowed 37 files on this batch** (removing parameter names changes line lengths,
so wrapping and `AlignConsecutiveAssignments` runs shift). Always run the hooks *and rebuild* after
a mass parameter edit — the reformat is not a no-op on the diff.

**Progress after batch 3: 111 of 265 modorganizer sites done, 154 remain.** (The original "271"
covered uibase + modorganizer; uibase's 6 are done, so modorganizer alone was 265. 47 + 9 + 55 + 2
= 111 — the arithmetic closes exactly against a full `-c` rebuild.) 0 errors throughout.

**Batch 4 — `6e032a8f`, C4189 (all 26).** *"Initialized but not referenced" does not mean the
initializer is side-effect free*, so these were not one fix:
- pure reads (getters, singleton accessors, copies) → deleted outright
- **side-effecting calls keep the call, lose only the variable**: `QMessageBox::warning()` and
  `QDialog::exec()` put a modal dialog on screen; `addButton()` adds a button;
  `QString::toInt(&ok)` is called purely for the `ok` out-parameter read on the next line
- 🔴 **a real leak**: `modlistviewactions.cpp` allocated `ok`/`cancel` `QPushButton`s that were
  never parented, never added to a layout and never referenced — a `QDialogButtonBox` with its own
  buttons is built three lines later. Leaked on every export-dialog open.
- `[[maybe_unused]]` kept two: `env.cpp`'s `LDR_DLL_NOTIFICATION_REASON_UNLOADED` documents the API
  beside the LOADED value that *is* used, and `processrunner.cpp`'s `GetLastError()` feeds a log
  statement that is commented out on purpose.

**Batch 5 — `951138e6`, C4245 + C4018 (7).** Every signed→unsigned conversion left was a
**deliberate sentinel or an already-guarded comparison — no bugs**, but each relied on implicit
wrapping to say so (`NoSelection = -1`, `firstRowIndex = -1`, `childIndex` returning `-1`,
`m_exitCode(-1)`). Now explicit casts; `instancemanagerdialog` passes the existing `NoSelection`
constant instead of a bare `-1`. Worth stating plainly: unlike C4834, **this bucket contained no
defects** — the value is intent, not correctness.

**Zero as of 2026-08-09: C4100, C4101, C4189, C4245, C4018.**

⚠️ **Line numbers drift between batches** (edits *and* clang-format reflow). A worklist built from
an older log will point at the wrong lines. Re-derive from a fresh `-c` build before each batch, or
match by symbol name rather than line.

| Remaining (authoritative `-c`, 125) | C4996 | C4267 | C4456 | C4458 | C4459 | C5054 | C4457 | C4505 |
|---|---|---|---|---|---|---|---|---|
| **125** | 42 | 22 | 18 | 10 | 10 | 8 | 5 | 2 |

**Batch 6 — `d479fc76`, C4996 (all 39).** `QScopedPointer::take` → `std::unique_ptr::release` (15),
`Qt::ALT + Qt::Key_X` → `|` (4), `invalidateFilter()` → `begin/endFilterChange()` (4),
`QDropEvent::pos()` → `position().toPoint()` (3), `fromSecsSinceEpoch(_, Qt::UTC)` →
`QTimeZone::UTC` (3), `QVariant::type()` → `typeId()`/`QMetaType` (3), `convert(type)` →
`convert(metaType())`, `AnchoredMatchOption` → `AnchorAtOffsetMatchOption`, `getenv` → `qgetenv` (2),
`strerror` → `std::generic_category().message()` (2), `std::gmtime` → `gmtime_s`.

🔴 **A double-delete found while converting** `categoriesdialog.cpp`:
```cpp
QScopedPointer<QTableWidgetItem> blankItem(new QTableWidgetItem());
table->setItem(item->row(), 3, blankItem.get());   // .get(), not .take()
```
`QTableWidget::setItem` **takes ownership**, so the item was owned by both the table and the scoped
pointer, which deleted it at end of block — double delete, and a dangling pointer left in the table.
Every sibling call in that file releases correctly; this one did not.

⚠️⚠️ **CRLF DISASTER — `sed -i` cost a force-push. Do not repeat.** The first attempt at this batch
used `sed -i` from Git Bash, which rewrites files as **LF**. `.gitattributes` mandates
`*.cpp text eol=crlf` and `.clang-format` sets `UseCRLF: true` / `DeriveLineEnding: false`; fed LF
input, clang-format **reflowed the block comments** and shredded the GPL/KDE license headers in
**11 of 16 files (~180 lines)** — while the real change was ~80. Proven, not guessed: restoring the
pristine `qtgroupingproxy.cpp` and running the pinned clang-format on it reports **Passed, unchanged**
— the files were already conformant, so the damage was entirely the LF conversion.
**Rule: use the Edit tool or PowerShell `[IO.File]::ReadAllText`/`WriteAllText`. Before committing,
assert every changed file has 0 bare LF** (`[regex]::Matches($raw,"(?<!\r)\n").Count -eq 0`).

⚠️ **Also: a global replace is not a scoped one.** Re-doing the batch, `event->pos()` was replaced
file-wide in `modlistview.cpp` — 7 hits, but only the **3** in `dropEvent(QDropEvent*)` are
deprecated. The other 4 are `QMouseEvent::pos()`, which does **not** warn, and `position().toPoint()`
rounds differently. Replace only what the compiler flagged.

**Batch 7 — `935e8293`, C4267 + C5054 + C4505.** 🔴 **`game_features.cpp` returned a negative
count**: `initialSize` captured *before* `erase`, then `features.size() - initialSize` — a `size_t`
subtraction that underflows and narrows to a negative `int`. `unregisterGameFeatures()` returned
`-N`, and `gamefeaturesproxy.cpp:47` hands that straight to the plugin API. `if (removed)` still
fired, so the side effect was right and only the count was wrong. C5054: two files compared against
the *wrong enum* (`QDialogButtonBox::StandardButton` vs `QMessageBox::StandardButton`) — the numeric
values coincide today, which is why it went unnoticed.

**Batch 8 — `a3b68ecb`, the boost::accumulators leak.** `downloadmanager.h` had
`using namespace boost::accumulators;` **at global scope in a header**, dumping the extractors
`count`, `max`, `min`, `sum`, `mean` into all 9 including TUs. That was what every C4459 was
colliding with. Moved to the `.cpp` (TU-local) with a class-local alias for the one type the header
needs. **10 warnings gone, zero locals renamed.** Look for a root cause before renaming symptoms.

**Batches 9–10 — `c59a00f6`, `70261ea1`, the shadowing tail, then `/WX`.** All C4458 `data` sites are
locals in **QWidget subclasses** — `QWidget` has a public member `QWidgetData* data`, so the shadow
is unavoidable and the locals get renamed. `CategoryFactory` was different: a `s_Instance` pointer
member that is **never assigned**, a `cleanup()` deleting it, and an `atexit(&cleanup)` registering
that no-op — all three deleted.

🔴 **`qtgroupingproxy.cpp` is the argument for fixing C4456 rather than suppressing it.** An inner
loop counter `i` shadowed a `QMapIterator i`, and the body ended `rowDataList.insert(i, rowData);`.
Renaming the counter made that line **fail to compile**, because it then bound to the iterator. The
original was correct *only by virtue of the shadowing*, and nothing in the line said which `i` it
meant.

### ✅ modorganizer is at `/W4 /WX` — 265 → 0 (2026-08-10)

`mo2_configure_target(organizer WARNINGS 4 WERROR ON ...)`. Verified in the generated project:
`TreatWarningAsError=true`, `WarningLevel=Level4`, and a full `-c` build at **0 warnings / 0 errors**.
Two repos now enforce warnings-as-errors: `uibase` (`/Wall /WX`) and `modorganizer` (`/W4 /WX`).
*(Snapshot as of this section's date — by the end of 2026-08-10 every C++ repo does; see 3.7.)*

⚠️ **Two traps hit while renaming — both caught by the compiler, not by review:**
1. **A "unique" string may not be.** `for (const auto& [priority, index] : ...)` appears **3×** in
   `profile.cpp`; a blind replace renamed all three but only fixed one body. Always assert the
   match count before replacing.
2. **Rename the *whole* scope.** `grep` for `cleanup` missed `atexit(&cleanup)`; the `i` rename
   missed `rowDataList.insert(i, …)`. Both broke the build. Third and fourth instances today of
   grep under-reporting — **the compiler is the authority.**

**Left in modorganizer, deliberately:** `modlistviewactions.cpp` has an inner `origin` that
re-fetches and re-disables an origin the enclosing scope already handled. Renamed to
`existingOrigin` so the duplication is visible; removing it is a behaviour change and wants its own
commit + runtime test.

#### Runtime verification 2026-08-10 (`revision 70261ea1`)

Launched, exercised, and a game started through it. **0 errors**, 1 warning, and that warning is
**pre-existing** — `QIODevice::read (QSslSocket): device not open` appears exactly once in the
known-good VS2022 log from 2026-07-30 too, so it predates every change here. Confirmed from
`build\install\bin\logs\mo_interface.log`:

- **username masking works** — `C:/Users/USERNAME/AppData/...`, i.e. the `getenv` → `qgetenv` swap
  still redacts. Worth checking every time: a regression here leaks the real username into logs
- **usvfs log created** (the C4834 success branch), and injection verified again: `hooked: true`,
  25 dirs / 5 files mapped, `skse64_loader.exe` → `SkyrimSE.exe`, clean exit + refresh
- **profile mod-list write** — `Renamed 1 "SRO" mod to "Skyrim Realistic Overhaul" in
  .../modlist.txt` — data-loss fix #1 on its happy path
- **proxied-plugin master resolution** — the `replacing plugin 'X' with interfaces [File Mapper] by
  one with [Game]` lines *are* the `pluginsForName` rename's code path; ~15 of them, all correct
- full Python 3.14 / PyQt6 / basic_games stack, mod enable/disable, Nexus OAuth

✅ **UI paths confirmed by hand 2026-08-10** — the two highest-traffic changes emit nothing to the
log, so they were clicked deliberately and all behaved: mod-list **filtering**, **Group by**
(`invalidateFilter` → `begin/endFilterChange` in both sort proxies, plus `qtgroupingproxy`'s
`QVariant::typeId()` migration and the `insert(i, …)` shadowing fix), **Change Categories**, and the
**categories editor** (15 `take()` → `release()` conversions and the double-delete fix).

**Phase 3's source changes are therefore fully runtime-verified**: log evidence for the startup,
profile-write, plugin and usvfs paths, and hand-verification for the UI paths that log nothing.

**Batch 11 — `d9b0019a`, the first dividend from the clang side tree.** Two things MSVC `/W4` does
not report: `modinfodialogtab.cpp` initialised members in an order that did not match the
declaration order (misleading rather than wrong — members always init in declaration order, and none
of these depend on each other), and `modinfoseparator.h` declared `setName()` virtual without
`override`, alone among its siblings. MSVC only reports the first at `/Wall` and the second never.

⚠️ **clangd is only partly usable on this codebase.** Some TUs fail to parse with
`constexpr variable 'is_integral_v<std::_Base128>' must be initialized by a constant expression` and
`no type named 'T' in 'Qt::totally_ordered_wrapper<ModInfo *>'` — clang tripping over **MSVC STL and
Qt internals**, which then poisons the AST and cascades into dozens of bogus follow-on errors
(`Cannot initialize object parameter of type 'QAbstractProxyModel'…`, spurious
`marked 'override' but does not override…`). **Those are not real.** MSVC builds the same files
clean at `/W4 /WX`. Treat a clangd diagnostic as signal only if it survives in a TU that parsed.
Running this down is its own project.

### 3.5 — Tree-wide warning inventory (2026-08-10)

One unattended `mob build -c` over all 36 tasks, 11 min, **0 errors**. Log: `tree-baseline.log`.

**159 distinct sites, and only 9 repos have any — the other 22 are already at zero**, as are
`uibase` and `modorganizer` (now under `/WX`).

| Repo | sites | | Repo | sites |
|---|---|---|---|---|
| `esptk` | 78 | | `lootcli` | 5 |
| `game_bethesda` | 42 | | `diagnose_basic` | 1 |
| `nxmhandler` | 14 | | `installer_fomod` | 1 |
| `bsatk` | 12 | | `installer_fomod_csharp` | 1 |
| `installer_omod` | 5 | | | |

⚠️ **Half the count is `/Wall`-only noise from exactly two repos.** `esptk` and `nxmhandler` are
still on the `WARNINGS ON` default, and they produce essentially all of C4710 (56, "function not
inlined"), C4514 (13, unreferenced inline removed), C5045 (8, Spectre note) and C4820 (4, padding).
**Dropping those two to `WARNINGS 4` erases ~81 sites without touching a line of code** — the same
`/Wall` unusability seen in 3.0, just in the repos nobody had looked at.

Real remainder, roughly 78 sites: C4100 (26), C4189 (11), **C4834 (6)**, C4456 (6), **C4715 (4)**,
C4101 (3), C4267 (3), C4996 (2), plus a tail.

#### 🔴 C4715 — undefined behaviour in two game plugins — FIXED `d3b52cd`

`GameFallout4::shortDescription/fullDescription` and the identical pair in
`GameFallout4London` switch on an `unsigned int key` with **one case and no default**, so any other
key falls off the end of a function returning `QString`. That is UB — and since the return travels
through a hidden pointer, a caller receives an *unconstructed* `QString`, not an empty one.

Unreachable today (only `PROBLEM_TEST_FILE` is ever reported by `activeProblems()` in these two),
so latent rather than live. **`GameStarfield::shortDescription` in the same repo already ends its
switch with `return "";`** — the other two simply missed it. Now matched.

**Still open:** 6 × **C4834** (discarded `[[nodiscard]]`) in `game_bethesda` (2), `installer_omod`
(3) and `nxmhandler` (1). That exact warning class produced the two silent-data-loss bugs in
modorganizer, so these six deserve reading one at a time rather than batch-silencing.

~~**Next:** flip `esptk` and `nxmhandler` to `WARNINGS 4`…~~ — **all of this is done**, see 3.6
and 3.7. Two of its premises were also wrong; the retraction in 3.6 explains why.

### ✅ 3.6 — the whole tree is at 0 warnings (2026-08-10)

Nine commits, one per repo. Verified by a full `mob -l 5 build -c` (36 tasks, 10 min):
**0 warnings, 0 errors**, with 7674 lines of real compiler output in the log — the count matters,
because a `mob build` at the default log level prints **no compiler output at all** and will
cheerfully grep as "0 warnings". Log: `warnwalk2.log`. ⚠️ **Always confirm `stdout` line count
before believing a zero.**

| Repo | commit | what |
|---|---|---|
| `esptk` | `d5988a2` | `/Wall` → `/W4 /WX`, 1 dead local |
| `nxmhandler` | `5ac6c25` | `WARNINGS 4 WERROR ON`, C4834 + 4 × C4100 |
| `bsatk` | `d1adc5c` | 12 sites, incl. two real bugs |
| `lootcli` | `d8b325b` | uninitialised `FILE*` |
| `game_bethesda` | `034bd61` | 42 sites, incl. four real bugs |
| `installer_omod` | `879d4fe` | 3 × C4834 |
| `installer_fomod` | `77ce835` | C4389 |
| `installer_fomod_csharp` | `d7c1407` | C4456 |
| `diagnose_basic` | `8d54133` | C4456 |

`esptk` and `nxmhandler` join `uibase` and `modorganizer` under warnings-as-errors —
`TreatWarningAsError=true` / `WarningLevel=Level4` confirmed in both generated projects.

✅ **Runtime-verified 2026-08-10** — MO2 launched and exercised after the nine commits, working.
The paths worth re-checking on any future change here, because a slip in them is silent rather than
loud: Gamebryo **save-game parsing** (`skyrimse`/`skyrimvr`/`enderalse` each lost two locals whose
`readChar()`/`readShort()` calls stay in place — a stream-position slip would corrupt the plugin
list), **save timestamps** (`Qt::UTC` → `QTimeZone::UTC` touches every Gamebryo save), **BSA
read/write** (`bsatk`'s `writeBString` clamp and the `recordsOffset` rename), and **LOOT sorting**
(`lootcli`'s `GetFile` restructure).

⚠️ **`mob build -c` takes the installed tree out of service for ~10 minutes.** The reconfigure clean
wipes `build\install\bin`, and `platforms\qwindows.dll` is only rewritten by `mo2_deploy_qt` at the
*end* of the last task. Launching MO2 mid-build aborts with *"no Qt platform plugin could be
initialized"* — that is the clean, not a regression. Same for `styles\` and `tutorials\`.

#### 🔴 The six C4834 were the right thing to read one at a time

Four were **live silent failures**, and the pattern is identical every time: an unchecked
`QFile::open` whose failure path still looks like success to everything downstream.

- **`installer_omod` shader replacement** — a failed open fell through to `readAll()`, which returns
  an *empty* `QByteArray`. That empty array was stored as the shader's bytecode, so the generated
  SDP contained a zero-length shader and was still mapped over the game's own.
- **`nxmhandler` chrome fix** — the write open was unchecked, then it logged `chrome fix applied`.
  The usual reason that open fails is chrome holding the file, i.e. **exactly the condition the
  dialog had just warned the user about.** The one case the message most needed to be honest about
  was the one it lied about.
- **`DummyBSA::write`** — silent no-op, while the caller went on to add the archive to the ini and
  mark the profile dirty. BSA invalidation switched *on*, with no BSA on disk.
- **`installer_omod` temp SDP** — a failed `QTemporaryFile::open` still registered the virtual SDP,
  mapping the game's shader package onto nothing.

The remaining two (`GameGamebryo::copyToProfile`, the base-package read) degrade less badly but now
log. **Running tally: C4834 has produced 6 real bugs across the tree and 0 false alarms.** It should
be treated as an error class, never batch-silenced.

#### 🔴 Three more real bugs, found via warnings that are usually noise

- **`bsatk` `writeBString` (C4244)** — clamped the string to 255, then wrote `length + 1` into an
  `unsigned char`. At exactly 255 that **wraps to 0**: a 256-byte record announced as empty. The
  length byte counts the terminating null, so the clamp has to be 254.
- **`gamestarfield.cpp` (C4129)** — `"^" + parent + "\.es(m|p|l)$"`. In C++ `\.` is an *unrecognised
  escape* and collapses to `.`, so the blueprint-plugin regex matched any character where it meant a
  literal dot. C4129 is the only thing that can see this; no grep for `\.` would look wrong.
- **`Fallout76SaveGame::fetchInformationFields` (C4100)** — takes `FILETIME& creationTime` and never
  writes it, reading the timestamp into a local and dropping it. The constructor passes that
  reference straight to `FileTimeToSystemTime`/`setCreationTime`, so **every Fallout 76 save was
  dated from an uninitialised stack `FILETIME`.** C4100 on an *out*-parameter is worth a second look
  — an unused out-param is nearly always a bug, not a tidy-up.

#### Left deliberately, with reasons

- **The rest of the FO76 signature.** `playerName`, `playerLevel`, `playerLocation` and `saveNumber`
  are taken **by value**, so they are never populated either. The fix is the `QString&` signature its
  Starfield sibling already uses, plus dummy locals in the `const` `fetchDataFields` (which cannot
  bind non-const refs to members). That is a behaviour change on a path needing a real FO76 save to
  verify — its own commit.
- **`morrowindsavegame.cpp` `readImageBGRA`** loops `h < width` instead of `h < height`. Harmless
  only because Morrowind screenshots are 128×128. Not a warning; found while reading around one.
- **`vdf_parser.h`** is vendored third party (ValveFileVDF, MIT) and stays byte-identical; its
  C4456 is suppressed around the `#include` in `gamegamebryo.cpp` instead.

#### ⚠️ ~~`WARNINGS OFF` makes `WERROR ON` meaningless~~ — WRONG, corrected 2026-08-10

**Retracted.** The original claim here was that `diagnose_basic`, `installer_fomod`,
`installer_fomod_csharp` and `installer_omod` were below level 4, so `WERROR ON` would certify
nothing until they were raised. Both halves were wrong, and the error came from reading the
`mo2_configure_*` call and stopping there.

🔴 **`/W4` does not come from `mo2_configure_*` at all. It comes from each repo's own
`CMakePresets.json`:** `"CMAKE_CXX_FLAGS": "/EHsc /MP /W4"`. Every C++ repo in the tree carries that
line. `WARNINGS OFF` therefore means only *"do not add a second `/W` flag"* — those targets have
been compiling at **`WarningLevel=Level4`** the whole time. Confirmed in the generated projects:
`diagnose_basic`, `bsa_extractor`, `bsapacker` and `installer_bain` all say `Level4` while their
CMakeLists say `WARNINGS OFF`.

Two consequences:
- There is **no hidden batch** behind `WARNINGS OFF`, and `WERROR ON` on those repos is meaningful
  today. No level raise needed.
- The count was wrong too — **nine** repos are on `WARNINGS OFF`, not four (`bsa_extractor`,
  `bsapacker`, `check_fnis`, `diagnose_basic`, `installer_bain`, `installer_bundle`,
  `installer_fomod`, `installer_fomod_csharp`, `installer_omod`). Only the four that happened to
  emit something got noticed; the other five were invisible precisely *because* they were clean.

**Lesson, and it is the same one as "trust the compiler, not grep":** a warning level is a property
of the *effective command line*, not of the call that looks like it sets it. Read
`<WarningLevel>` in the generated `.vcxproj`, or `CMAKE_CXX_FLAGS` in `CMakeCache.txt`. Both were one
grep away and would have caught this immediately.

🔴 **Worse: 3.0 already said this, correctly, the day before.** *"Every repo's `CMakePresets.json`
sets `CMAKE_CXX_FLAGS = "/EHsc /MP /W4"` as a global floor"* — written 2026-08-09, in this file,
under a heading that itself announces the doc had previously described warning levels wrongly. The
claim in 3.6 was made without re-reading it, and so repeated the very mistake 3.0 was written to
correct. **Before asserting anything about build configuration, grep this document for the subsystem
first.** It is the source of truth precisely so that this does not have to be rediscovered, and it
has now been rediscovered twice.

#### 🔴 `installer_omod` is the one repo that really was below /W4

It is the sole C++ repo whose `CMakePresets.json` **omits** `CMAKE_CXX_FLAGS` — its cache reads
`/wd4566 /DWIN32 /D_WINDOWS /GR /EHsc`, and its `.vcxproj` has **no `<WarningLevel>` element at
all**, i.e. the MSVC default of **/W1**. That is why only 3 warnings (all C4834, a level-1 class)
ever appeared from 14 translation units. Raised via `mo2_configure_plugin(... WARNINGS 4 CLI ON)`
rather than by editing the preset, to keep it expressed the same way as every other repo.

#### Coverage map (2026-08-10)

| Group | repos |
|---|---|
| Python-only, no C++ | `basic_games`, `fnistool`, `form43_checker`, `installer_wizard`, `preview_dds`, `script_extender_plugin_checker`, `tool_configurator` |
| not our source | `explorer++`, `stylesheets` (downloads), `cmake_common` (no targets) |
| C++, `/W4` from preset | everything else — 21 repos plus the 17 `game_bethesda` and 5 `plugin_python` targets |
| was **/W1** | `installer_omod` — fixed |

⚠️ **`usvfs` is deliberately excluded from the `/WX` latch.** Its preset does set `/W4`, but neither
`-b` nor `-c` can force it to rebuild (3.0b) — proving it clean needs the manual
`vsbuild32`/`vsbuild64` delete, so it gets its own pass rather than an unverified flag.

### 3.7 — `/WX` across the whole tree (2026-08-10)

Every C++ repo now enforces warnings-as-errors. Verified by `mob -l 5 build -c`: **0 errors,
0 warnings**, `TreatWarningAsError=true` spot-checked in the generated projects for
`installer_omod`, `bsa_packer`, `game_fallout76`, `helper`, `archive`, `lootcli` and both usvfs
architectures.

Logs kept at the repo root: **`final.log`** (the definitive full-tree run — 8527 lines of compiler
output, 128 usvfs TUs) and **`usvfs-wx.log`** (usvfs's first verified `/WX` build). Everything else
from the campaign is in `logs-archive/`.

Mechanism per repo type: `WERROR ON` where `mo2_configure_*` is used; a literal `"/WX"` next to the
hand-rolled `"/W4"` in `archive` / `bsatk` / `lootcli` / `esptk`; and a `target_compile_options`
line in `helper`, which has no warning configuration of its own at all.

**Commits — 25, all signed, all pushed to the forks on `modern` (2026-08-10).**

| What | Repo → commit |
|---|---|
| `/WX` latch, one line each | `archive` `e2b43d3`, `bsa_extractor` `2c0b962`, `bsapacker` `d51253e`, `bsatk` `31b5025`, `check_fnis` `b2be6d8`, `diagnose_basic` `3899cc7`, `helper` `d8c05dc`, `installer_bain` `d3e20c4`, `installer_bundle` `134b170`, `installer_fomod` `c41a0d5`, `installer_fomod_csharp` `10a9aee`, `installer_manual` `7fe56bf`, `installer_quick` `424d4f4`, `lootcli` `3e468c9`, `plugin_python` `0e61220`, `preview_base` `45345d6`, `preview_bsa` `aff6cca`, `tool_inibakery` `3df935e`, `tool_inieditor` `7eb731e` |
| /W1 → /W4 + 20 fixes + `/WX` | `installer_omod` `f3fbe66` |
| 5 fixes + `/WX` | `usvfs` `3d43d64` |
| `/WX` on 17 targets | `game_bethesda` `4b1856d` |
| FO76 out-parameters | `game_bethesda` `b98c17d` |
| Morrowind screenshot bounds | `game_bethesda` `5506c90` |

`game_bethesda` is deliberately **three** commits: the latch and the two bug fixes are unrelated and
are separate upstream PR candidates.

#### `installer_omod` — 20 warnings, and the three scary ones were false alarms

Raising it off /W1 surfaced 15 × C4100, 2 × C4101 and **3 × C4701 "potentially uninitialized
`response`"**. C4701 is the class that turned out to be a genuine crash in `lootcli`, so all three
got read properly — and all three are **compiler conservatism, not bugs**:

```cpp
QMessageBox::StandardButton response;      // no initialiser
if (!yesToAll) { … response = question(…); yesToAll |= (response == YesToAll); }
if (yesToAll || response == QMessageBox::Yes)   // ← C4701 points here
```

`||` short-circuits. `response` is only *read* when `yesToAll` is false, which is exactly the branch
that *assigns* it. MSVC cannot see the correlation between the flag and the assignment. Initialised
to `QMessageBox::NoButton` to make the invariant explicit — no behaviour change.

The C4101s are `catch (const std::exception& e) { throw; }` — handlers that only rethrow. The
C4100s are almost all `throw gcnew System::NotImplementedException();` stubs implementing an
OMODFramework interface; names dropped in the definitions, kept in the headers as documentation.

⚠️ **Worth recording as a counterexample.** The running tally had been "C4834: 6 real bugs, 0 false
alarms", which makes it tempting to treat a scary warning class as guilty by default. C4701 is now
1 real / 3 false. **The warning class tells you where to look, never what you'll find.**

#### 🔴 `usvfs` measured for the first time — 5 sites, 0 live bugs

`mob` has never once compiled usvfs in any run of this project: its `-c` "cleaning (reconfigure)"
deletes directories named after mob's own generators, and usvfs uses `vsbuild32`/`vsbuild64`
(3.0b). Deleting those by hand got **68 translation units** to actually compile, and only then did
any warning data exist for it.

- **C4309, `ttrampolinepool.h`** — `static const intptr_t ADDRESS_MASK = 0xFFFFFFFFFF000000LL;`.
  usvfs builds **both** x86 and x64; on x86 `intptr_t` is 32-bit and the literal truncates to
  `0xFF000000`. That *happens* to preserve the intent (zero the low 24 bits, group trampolines per
  16 MB), so it was correct by luck. Moot anyway — the constant is **referenced nowhere**. Deleted.
- **C4505, `stringutils.cpp`** — `static fs::path normalize(…)`, dead, deleted.
- **C4459 ×3 — locals hiding file-scope globals, and the code is right.** `usvfs.cpp` has globals
  `manager` and `context`. In `InitHooks`, `auto context = manager->context();` shadows the global —
  but `InitHooks` runs in the **injected process**, where the global `context` is still null
  (`usvfsConnectVFS` creates it in the *controlling* process). Using the global there would be a
  null deref. Renamed to `hookContext` with a comment, so the distinction is deliberate rather than
  accidental. Same shape for `manager` in `tree_container.h` (a Boost segment manager, unrelated
  type) → `segmentManager`.

`/WX` is applied with `target_compile_options` over the six shipping targets, **not**
`add_compile_options`: the latter would also reach the `if (BUILD_TESTING)` subtree, which mob never
builds and which no one has verified against the flag.

✅ **Runtime-verified by hand, 2026-08-10** — the owner exercised the build after the push and
confirmed it working, covering the usvfs injection path and the two save-game fixes.

Recorded without log excerpts on purpose: unlike the 3.4 block, this verification was done directly
rather than through a session, so quoting specific lines would be inventing evidence. The claim here
is exactly as strong as "the person who owns the project checked it".

#### ⚠️ The clang-format pin is NOT uniform — CLAUDE.md is wrong to say "pinned v22.1.5"

Three different versions are active across the repos, one a **major release** behind:

| pin | repos |
|---|---|
| `v22.1.5` | 19 repos (the majority) |
| `v22.1.2` | `lootcli`, `usvfs` |
| `v19.1.5` | `installer_bundle`, `installer_fomod_csharp`, `installer_manual` |
| commented out | `bsapacker`, `installer_omod` (no clang-format at all) |

Commits are still safe — pre-commit fetches the correct binary *per repo* — so this is an accuracy
problem in our own docs, not a correctness one. **Do not "fix" it by unifying the pins:** bumping
v19.1.5 → v22.1.5 would reformat those files wholesale, which is exactly the merge surface against
34 upstreams that the working agreement exists to avoid. The rule that matters is unchanged: let
pre-commit format, never an editor.

### 3.3 — uibase is warning-clean and enforces `/WX` — ✅ DONE 2026-08-09

First repo under warnings-as-errors. Two commits:

- **`cmake_common` `5379b93`** — new **`WERROR`** option on `mo2_configure_warnings` /
  `mo2_configure_target`, default **OFF**, emitting `/WX`. Deliberately **opt-in per target**: a
  global `/WX` would fail most repos on day one, and one noisy target must not be able to block
  the tree. This is the mechanism every later repo will use.
- **`uibase` `fc3ead5`** — the six fixes, then `WERROR ON`:
  - `strings.cpp` — `search_length` was cast to `std::string::difference_type` (**signed**) and then
    compared against / passed to `size_t` parameters: 1× C4018 + 2× C4365 from one variable.
    `substr()` and `replace()` both take `size_type`; nothing wanted it signed. Using `size()`
    directly killed three warnings with one word.
  - `tutorialcontrol.cpp` — the local-position-only `QMouseEvent` ctor is deprecated *because it has
    to guess the global position*. `simulateClick()` already computes `globalPos`, so passing it is
    strictly more correct, not just quieter.
  - `filterwidget` — `invalidateFilter()` → `beginFilterChange()` + `endFilterChange()`
    (defaults to `Direction::Both`, i.e. exactly what `invalidateFilter()` did). The public
    re-export of `invalidateFilter` **stays** so third-party plugins keep building; it must go when
    `QT_DISABLE_DEPRECATED_BEFORE` reaches 6.13.

Verified: uibase rebuilds **0 warnings / 0 errors** with `TreatWarningAsError=true` confirmed in the
generated project, and `modorganizer` still builds clean against the changed public header.

#### ⚠️ pre-commit was installed in NONE of the 33 repos (fixed 2026-08-09)

The rule "run `pre-commit` locally in every repo we touch" has been in this document since Phase 0
but **was never actually implemented** — only `mob` and `cmake_common` had `.git/hooks/pre-commit`.
Every other repo has the config file and no hook, so commits went in unchecked. The `usvfs`
(`6beaf55`) and first `uibase` commit both bypassed clang-format silently; re-running the pinned
hooks reformatted the uibase C++ (sorted the `using` block, realigned an assignment run) and left
usvfs untouched, since CMake files are not clang-formatted.

**Now installed in all 34.** Verify with:
```powershell
Get-ChildItem build\build -Directory | Where-Object {
  (Test-Path "$($_.FullName)\.pre-commit-config.yaml") -and
  -not (Test-Path "$($_.FullName)\.git\hooks\pre-commit") }
```
⚠️ **Hooks live in `.git/hooks`, which is not cloned** — any fresh clone or new repo starts
unhooked. Re-run the install loop after cloning. And **never** hand-format with the LLVM
clang-format on PATH (22.1.8): pre-commit fetches the pinned **22.1.5** itself, and that mismatch is
exactly the churn trap in 3.2.
