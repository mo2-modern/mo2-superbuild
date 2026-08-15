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
> for example, the 64 `find_package(mo2-*)` calls are satisfied from outside rather than edited. If
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

## Building and verifying

Build instructions are in the [README](README.md); machine setup, troubleshooting and the
verification recipe are in [BUILD.md](docs/BUILD.md).

**A green build is not a verification.** In particular, a build alone deploys nothing — install is a
separate step ([ADR-023](docs/DECISIONS.md#adr-023)) — and a launch proves usvfs *loads*, not that
it hooks anything. Read [TRAPS.md](docs/TRAPS.md#verification) before claiming something works.

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
