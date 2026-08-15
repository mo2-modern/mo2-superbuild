# Contributing

Thanks for looking. This repository is the *superbuild* — it builds Mod Organizer 2 but contains
none of its source. Knowing which repository a change belongs in is most of the work.

## Where does my change go?

| You want to change | Repository |
| --- | --- |
| MO2 itself, a plugin, usvfs, a library | the relevant submodule under `repos/` |
| Shared CMake helpers (`mo2_configure_target`, `mo2_deploy_qt`, versions) | `repos/cmake_common` |
| How the repositories are assembled, Qt acquisition, deployment, CI | **this** repository |

Everything under `repos/` is a **fork of an upstream `ModOrganizer2` project**. Each keeps `master`
as an untouched mirror of upstream and does all work on `modern`; see
[ADR-001](docs/DECISIONS.md#adr-001). Never commit to `master`.

> **Changing a submodule is not free.** Every edited line is merge surface against 34 upstream
> projects on every sync, which is why the superbuild goes to some trouble to avoid touching them —
> for example, the 63 `find_package(mo2-*)` calls are satisfied from outside rather than edited. If
> a change can be made in this repository instead, make it here.

## Before you start

Read [DECISIONS.md](docs/DECISIONS.md) if you are changing anything structural. Most of the
non-obvious choices are load-bearing and the reasoning is recorded, including several that were
tried the other way first.

Read [TRAPS.md](docs/TRAPS.md) before trusting any build result. It catalogues failure modes that
*report success* — the recurring theme of this project — and it is the file most likely to save you
a wasted afternoon.

## Adding a repository

The most common structural change, and the one with a silent failure mode. All four steps are in
this repository.

1. **Add the submodule** under `repos/`, pinned at the commit you want.
2. **Add a `mo2_add_repo(<name>)` call** in `CMakeLists.txt`, *in dependency order*. The calls are
   grouped by what they need — libraries with no in-tree dependencies, then `uibase`, then plugins,
   then the application. CMake needs the producing target to exist before a consumer's
   `find_package` redirect runs, so position matters.
3. **If other repositories will `find_package` it**, add a config file to
   `cmake/superbuild-redirects/` and add the package to the `foreach(_pkg ...)` list beside
   `_mo2_redirects`. Copy an existing one; they are short.
4. **If it is consumed through a redirect**, add its target to the `foreach(_pkg_target ...)` list
   so it is marked `SYSTEM`.

⚠️ **Step 4 is the one that bites.** Skip it and the repository still builds, but its public headers
are no longer treated as external, so consumers compile them at `/W4 /WX` and fail on warnings that
belong to someone else's code. The error appears in a *different* repository from the one you
changed and names nothing that points back here.

## Bumping a pinned version

Almost everything this project fetches is pinned, and several pins move in pairs. Changing one
without the other fails in ways that do not name the cause.

| What | Where | Moves with |
|---|---|---|
| Qt | `MO2_QT_VERSION`, `MO2_QT_ARCH` in `CMakeLists.txt` | Re-check `MO2_QT_MODULES` and `qt_vs` ([ADR-005](docs/DECISIONS.md#adr-005), [ADR-006](docs/DECISIONS.md#adr-006)). CI derives its cache key from these — do not repeat them in the workflow |
| `aqtinstall` | `MO2_AQTINSTALL_COMMIT` | A commit, not a tag, because releases lag Qt's repository layout. Re-run a real Qt install after changing it |
| Explorer++ | `MO2_EXPLORERPP_VERSION` | **`MO2_EXPLORERPP_SHA256` must change with it** |
| Stylesheets | the `_mo2_stylesheets` table | Each row carries its own SHA256; version and hash move together |
| vcpkg | the submodule commit **and** the baselines in `vcpkg.json` | Plus the baseline in the 31 repo manifests that exist — see [ADR-013](docs/DECISIONS.md#adr-013) |

To get a new hash, let the build fetch the file and hash what it downloaded:

```powershell
(Get-FileHash build\prebuilt\<archive> -Algorithm SHA256).Hash.ToLower()
```

A mismatch is meant to stop the build. If a hash fails on a version you did **not** change, do not
paper over it — an upstream tag was re-pushed at different bytes, and that is the situation the
hashes exist to catch.

**Changed `usvfs`?** It is built at configure time and skipped afterwards. Force a rebuild by
deleting `build/usvfs-install` (the stamp file inside it is the guard).

**One toolchain variable at a time.** [ADR-003](docs/DECISIONS.md#adr-003): do not bump Qt, MSVC and
Python together, or a regression cannot be attributed.

## Cutting a release

Releases are built by CI from a `v*` tag — never packaged by hand, so the artifacts are the build
that passed verification rather than whatever was in someone's tree.

1. **Bump `VER_FILEVERSION` and `VER_FILEVERSION_STR`** in `repos/modorganizer/src/version.rc`, in
   the same commit. The scheme is upstream's version plus a fourth segment
   ([ADR-028](docs/DECISIONS.md#adr-028)) — 2.5.2.1, then 2.5.2.2. Do **not** take a number upstream
   still owns.
2. **Commit it in the submodule**, push, and bump the gitlink here.
3. **Tag and push:** `git tag -s v2.5.2.1 && git push origin v2.5.2.1`.

The workflow then builds, installs, verifies, packages and publishes. Roughly 45 minutes.

⚠️ **The tag does not set the version — `version.rc` does.** CI fails the run if they disagree,
rather than producing artifacts named after a version the binaries do not report. If that check
fires, fix `version.rc` and re-tag; do not rename the tag to match a stale file.

**There is no installer**, and that is structural: upstream's `.exe` comes from
`ModOrganizer2/modorganizer-Installer`, which this project does not fork. Five of upstream's six
assets are produced; say so in the release rather than leaving people hunting.

## Building and verifying

Build instructions are in the [README](README.md); machine setup, troubleshooting and the
verification recipe are in [BUILD.md](docs/BUILD.md).

**A green build is not a verification.** In particular, a build alone deploys nothing — install is a
separate step ([ADR-023](docs/DECISIONS.md#adr-023)) — and a launch proves usvfs *loads*, not that
it hooks anything. Read [TRAPS.md](docs/TRAPS.md#verification) before claiming something works.

⚠️ **Do not expect CI to check your pull request.** The workflow needs a `windows-2025-vs2026`
runner, which is not a standard GitHub-hosted label, so a PR from a fork will queue forever rather
than fail visibly. It also does not run on `push`. Verify locally and say what you verified.

**There are no automated tests.** `uibase`, `bsapacker` and `plugin_python` each ship a `tests/`
directory, but they are gated on `BUILD_TESTING` and enabling it needs `gtest` in the root
`vcpkg.json` — see [BUILD.md](docs/BUILD.md#verification). Until that changes, the only mechanical
check is the CI install-tree verification, and everything else is manual.

## Commits

- **Line endings are load-bearing.** `.gitattributes` mandates CRLF for the files that describe the
  build, and the MO2 repositories mandate it for sources; their `clang-format` runs with
  `UseCRLF: true`. An LF-writing tool reflows block comments and has shredded licence headers here
  before. Check that every file you changed has zero bare LF — the command is in
  [BUILD.md](docs/BUILD.md#committing).
- **`clang-format` is pinned per repository**, and the pins are not uniform. Run it through
  `pre-commit` rather than with whatever `clang-format` is on your `PATH`.
- **No AI or assistant attribution** in commit messages or pull requests: no `Co-Authored-By`, no
  "Generated with", no 🤖 line. These commits are candidates for upstream PRs against real projects.
- Explain *why* in the message. The diff already shows what changed.

## Duplication is the recurring bug here

Several of the worst failures recorded in [TRAPS.md](docs/TRAPS.md) are the same shape: a fact
written down twice, drifting apart, with the stale copy being the one someone followed. The Qt
module list cost four months that way.

So: **do not add a second copy of a version, a module list, or a hash.** If you need one somewhere
else, derive it — CI reads the Qt pin out of `CMakeLists.txt` rather than repeating it, and that is
the pattern to follow.
