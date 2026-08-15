# MO2 superbuild -- see README.md to build it, docs/DECISIONS.md for why it is
# shaped this way.
#
# Copyright (C) 2026 Leo Schlosser
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This covers the superbuild only: the projects under repos/ carry their own
# copyright and licences, and the third-party texts shipped with a build are
# vendored in licenses/.
#
# This file assembles the 33 buildable MO2 repositories -- 32 as subdirectories,
# plus usvfs, which cannot be one and is built at configure time below. It edits
# none of them, because every edited line is merge surface on sync (ADR-001), so
# their 63 find_package(mo2-*) calls -- which normally each require a prior
# install -- have to be satisfied from outside. Three ways:
#
#   mo2-cmake (27 calls)   cmake_common on CMAKE_PREFIX_PATH; its config file is
#                          self-contained, so no install step is needed.
#   siblings (29 calls)    cmake/superbuild-redirects/ stands in for configs that
#                          would otherwise need install(EXPORT) to have run.
#   vcpkg ports (7 calls)  mo2-dds-header, mo2-libbsarch -- resolve normally.
#
# Recounting these: a grep for "find_package(mo2-" across repos/ returns 66, and
# three of those are not call sites -- two README examples and one COMMENT inside
# cmake_common's own mo2_versions.cmake. An earlier count here read 64 / 28
# because it included that comment. cmake_common corroborates 27 independently:
# the comment in question notes its version block "printed these four lines 27
# times in the superbuild".

# 3.25 for the SYSTEM target property, which is load-bearing here -- see
# mo2_mark_package_target below.
cmake_minimum_required(VERSION 3.25)

# CMake reads the toolchain file inside project(), so without this a clone made
# without --recursive dies there with "Could not find toolchain file" and no hint.
if(CMAKE_TOOLCHAIN_FILE AND NOT EXISTS "${CMAKE_TOOLCHAIN_FILE}")
  message(FATAL_ERROR
    "vcpkg is missing. Expected its toolchain file at:\n"
    "  ${CMAKE_TOOLCHAIN_FILE}\n"
    "vcpkg is a submodule of this repository, pinned to the commit every "
    "manifest in the tree names as its baseline. Fetch it with:\n"
    "  git submodule update --init vcpkg\n"
    "That is 0.14 GB. `git clone --recursive` fetches it along with the 34 "
    "repositories under repos/; if you cloned without it, run "
    "`git submodule update --init` to get everything.")
endif()

project(mo2 LANGUAGES CXX)

# --- where the repositories live ----------------------------------------------
# The 34 repositories are submodules under repos/, so `git clone --recursive`
# gives a complete checkout. That is the only default.
#
# There used to be a fallback to a sibling ../mo2-modern/build/build, so a machine
# that had used mob did not have to clone several GB twice. mob is retired
# (ADR-027) and that tree no longer exists anywhere, so the fallback pointed at a
# layout nothing produces -- while re-arming the trap in docs/TRAPS.md where a
# sibling checkout silently won and the submodules were verified present but never
# used. Overriding the location is still supported; it is now explicit.
#
# Point this anywhere; nothing else in this file assumes a location. This project
# writes nothing into it -- but note that the BUILD does: mo2_add_translations
# runs lupdate, which rewrites each repository's *_en.ts in place. See
# docs/TRAPS.md.
set(MO2_SOURCE_ROOT "${CMAKE_CURRENT_LIST_DIR}/repos"
    CACHE PATH "Directory containing the MO2 repositories (uibase, usvfs, ...)")

get_filename_component(MO2_SOURCE_ROOT "${MO2_SOURCE_ROOT}" ABSOLUTE)

# An override is a deliberate act, but it should never be a silent one: building
# something other than this clone's own submodules is exactly the confusion
# docs/TRAPS.md records as clone-defect #2.
if(NOT MO2_SOURCE_ROOT STREQUAL "${CMAKE_CURRENT_LIST_DIR}/repos")
  message(STATUS
    "[MO2] MO2_SOURCE_ROOT is overridden -- building sources from outside this "
    "repository, and NOT the submodules under repos/")
endif()

if(NOT EXISTS "${MO2_SOURCE_ROOT}/uibase/CMakeLists.txt")
  # Distinguish "your submodules are missing" from "you pointed this somewhere
  # wrong". They are the same symptom and completely different fixes, and the
  # first is far more common: someone who cloned without --recursive, or who
  # followed the toolchain error above and fetched only the vcpkg submodule.
  if(MO2_SOURCE_ROOT STREQUAL "${CMAKE_CURRENT_LIST_DIR}/repos")
    message(FATAL_ERROR
      "The MO2 repositories are missing from repos/.\n"
      "\n"
      "They are submodules of this repository. Fetch them with:\n"
      "  git submodule update --init\n"
      "\n"
      "That is several GB. `git clone --recursive` would have done it at clone "
      "time.\n"
      "\n"
      "Already have an MO2 checkout elsewhere? Use it instead of cloning twice:\n"
      "  cmake --preset vs2026 -DMO2_SOURCE_ROOT=<path to the directory holding uibase>")
  endif()

  message(FATAL_ERROR
    "MO2_SOURCE_ROOT does not look like an MO2 checkout: ${MO2_SOURCE_ROOT}\n"
    "Expected to find uibase/CMakeLists.txt under it. Set -DMO2_SOURCE_ROOT=<path>.")
endif()

message(STATUS "[MO2] sources: ${MO2_SOURCE_ROOT}")

# --- Python, preflighted before anything expensive runs ---------------------------
# cmake_common pins the version and plugin_python asks for it EXACT, with the
# Development component. Without this check the failure lands inside plugin_python,
# most of the way through a first configure, as a generic "Could NOT find Python"
# that names neither the required version nor the fact that CMake looks in the
# registry rather than on PATH.
#
# It runs HERE, above the Qt block, because it is the cheapest check in the file and
# Qt is the most expensive step in it. With the order reversed -- which is how this
# was first written -- a machine missing the development headers downloaded 3.3 GB
# of Qt and only then failed on something detectable in under a second.
#
# The version is READ from cmake_common, not restated. A second copy of a version is
# the one thing CONTRIBUTING.md tells contributors never to add, and this one drifts
# in the nastiest direction: once cmake_common bumps, a hardcoded pin here demands
# the OLD version and says so confidently -- which is exactly the misleading failure
# this preflight exists to replace.
set(_mo2_versions_file "${MO2_SOURCE_ROOT}/cmake_common/mo2_versions.cmake")
if(NOT EXISTS "${_mo2_versions_file}")
  message(FATAL_ERROR
    "cmake_common is missing from the checkout:\n"
    "  ${_mo2_versions_file}\n"
    "It is one of the 34 submodules and every repository resolves its shared CMake "
    "helpers through it. Fetch it with:\n"
    "  git submodule update --init")
endif()

file(STRINGS "${_mo2_versions_file}" _mo2_python_pin_line
     REGEX "mo2_set_if_not_defined\\(MO2_PYTHON_VERSION")
string(REGEX MATCH "\"([0-9]+\\.[0-9]+)\"" _mo2_python_pin_match "${_mo2_python_pin_line}")
if(NOT _mo2_python_pin_match)
  message(FATAL_ERROR
    "Could not read MO2_PYTHON_VERSION out of:\n"
    "  ${_mo2_versions_file}\n"
    "That file is the pin plugin_python resolves EXACT against. If the line was "
    "renamed or reformatted upstream, fix this regex -- do not work around it by "
    "hardcoding a version here, because that is how the two copies drift apart.")
endif()

# A normal variable, deliberately not a cache entry: this is a derived fact, not a
# knob. A cache entry would go stale the first time cmake_common bumped. Subdirectory
# scopes inherit it and cmake_common's own mo2_set_if_not_defined then keeps it --
# same value, since it came from that file.
set(MO2_PYTHON_VERSION "${CMAKE_MATCH_1}")

find_package(Python ${MO2_PYTHON_VERSION} EXACT QUIET
             COMPONENTS Interpreter Development.Module Development.Embed)
if(NOT Python_FOUND)
  message(FATAL_ERROR
    "Python ${MO2_PYTHON_VERSION} was not found, or was found without its development files.\n"
    "\n"
    "plugin_python requires it EXACTly, with headers and an import library --\n"
    "include/Python.h and libs/python<ver>.lib. Install it from python.org; the\n"
    "embeddable package and some Store builds ship neither.\n"
    "\n"
    "CMake finds this through the REGISTRY, not PATH, so a Python that runs in your\n"
    "shell is not necessarily one CMake can see. Check with:\n"
    "  reg query HKCU\\Software\\Python\\PythonCore\n"
    "\n"
    "Have it somewhere CMake cannot find? Point at it:\n"
    "  cmake --preset vs2026 -DPython_ROOT_DIR=<prefix>\n"
    "\n"
    "The version itself comes from cmake_common; change it there, not here.")
endif()
message(STATUS "[MO2] Python: ${Python_EXECUTABLE} (${MO2_PYTHON_VERSION}, from cmake_common)")

# --- Qt -------------------------------------------------------------------------
# Qt cannot come from vcpkg: MO2 needs WebEngine, which means a Chromium build. So
# configure downloads it, staging into qt.tmp/ and renaming only once verified --
# see ADR-024 for why that staging matters and what MO2_AUTO_INSTALL_QT=OFF does.
set(MO2_QT_VERSION "6.11.1" CACHE STRING "Qt version to build against")
set(MO2_QT_ARCH "msvc2022_64" CACHE STRING "Qt build to use; msvc2022_64 links fine against v145")
set(MO2_QT_DIR "" CACHE PATH "Qt prefix. Auto-detected when empty")
set(MO2_AUTO_INSTALL_QT ON CACHE BOOL "Download Qt with aqt when it cannot be found")
set(MO2_AQTINSTALL_COMMIT "16db45a70b5905ad596941b223469bc86a56901e"
    CACHE STRING "Commit of miurahr/aqtinstall to install Qt with")

# --- the Qt module list, defined exactly ONCE -----------------------------------
# The download, the printed fallback instructions and the CI cache key all derive
# from this variable. Change the modules here and nowhere else -- ADR-024 records
# what the previous four copies cost.
#
# Neither half of the list is optional, and they fail differently:
#   qtwebsockets, qtnetworkauth  build requirements (modorganizer/src/CMakeLists.txt)
#   qtimageformats               RUNTIME requirement that fails SILENTLY -- without
#                                it MO2 ships 4 image plugins instead of 9 and
#                                cannot render TGA, TIFF or WebP mod previews.
set(MO2_QT_MODULES
    qtwebengine qtwebchannel qtpositioning qtserialport qtimageformats
    qtwebsockets qtnetworkauth qttasktree
    CACHE STRING "Qt modules to install; the build needs all of them")

# Validate an explicitly supplied prefix too, rather than only an auto-detected
# one: a wrong -DMO2_QT_DIR should say so here, not fail later inside find_package
# with a message about Qt6Config.
if(MO2_QT_DIR AND NOT EXISTS "${MO2_QT_DIR}/lib/cmake/Qt6/Qt6Config.cmake")
  message(WARNING "MO2_QT_DIR is not a Qt prefix, ignoring it: ${MO2_QT_DIR}")
  set(MO2_QT_DIR "")
endif()

if(NOT MO2_QT_DIR)
  # qt/ is where this project installs Qt; QTDIR covers one installed elsewhere.
  # A third candidate, ../mo2-modern/tools/Qt, was dropped with mob (ADR-027).
  foreach(_qt_candidate
      "${CMAKE_CURRENT_LIST_DIR}/qt/${MO2_QT_VERSION}/${MO2_QT_ARCH}"
      "$ENV{QTDIR}")
    if(_qt_candidate AND EXISTS "${_qt_candidate}/lib/cmake/Qt6/Qt6Config.cmake")
      set(MO2_QT_DIR "${_qt_candidate}")
      break()
    endif()
  endforeach()
endif()

# --- acquire it ------------------------------------------------------------------
# Rendered from MO2_QT_MODULES so the printed fallback cannot drift from what runs.
string(JOIN " " _mo2_qt_modules_text ${MO2_QT_MODULES})
set(_mo2_qt_manual_instructions
  "  py -3 -m pip install git+https://github.com/miurahr/aqtinstall@${MO2_AQTINSTALL_COMMIT}\n"
  "  py -3 -m aqt install-qt windows desktop ${MO2_QT_VERSION} win64_${MO2_QT_ARCH} \\\n"
  "      -m ${_mo2_qt_modules_text} \\\n"
  "      -O \"${CMAKE_CURRENT_LIST_DIR}/qt\"\n")

if(NOT MO2_QT_DIR AND MO2_AUTO_INSTALL_QT)
  set(_mo2_qt_dest "${CMAKE_CURRENT_LIST_DIR}/qt")
  set(_mo2_qt_tmp "${CMAKE_CURRENT_LIST_DIR}/qt.tmp")

  # Refuse rather than delete. Getting here means qt/ exists but holds no usable
  # Qt6Config.cmake; removing several GB that somebody may have put there on purpose
  # is not a decision a configure step gets to make silently.
  if(EXISTS "${_mo2_qt_dest}")
    message(FATAL_ERROR
      "${_mo2_qt_dest} exists but does not contain Qt ${MO2_QT_VERSION} "
      "(${MO2_QT_ARCH}).\nExpected: "
      "${_mo2_qt_dest}/${MO2_QT_VERSION}/${MO2_QT_ARCH}/lib/cmake/Qt6/Qt6Config.cmake\n"
      "Delete it and configure again, or point -DMO2_QT_DIR= at a good Qt.")
  endif()

  find_program(MO2_PYTHON_FOR_AQT NAMES py python
               DOC "Python used only to run aqt when Qt has to be downloaded")

  if(NOT MO2_PYTHON_FOR_AQT)
    message(WARNING "[MO2] Qt is missing and no Python was found to install it with.")
  else()
    if(MO2_PYTHON_FOR_AQT MATCHES "py\\.exe$")
      set(_mo2_py "${MO2_PYTHON_FOR_AQT}" -3)   # the launcher needs to be told
    else()
      set(_mo2_py "${MO2_PYTHON_FOR_AQT}")
    endif()

    message(STATUS "")
    message(STATUS "==============================================================")
    message(STATUS "[MO2] Qt ${MO2_QT_VERSION} (${MO2_QT_ARCH}) was not found.")
    message(STATUS "[MO2] Downloading it now -- this is about 3.3 GB and will take")
    message(STATUS "[MO2] a while. Progress follows. Set MO2_AUTO_INSTALL_QT=OFF")
    message(STATUS "[MO2] to be given the command instead of having it run.")
    message(STATUS "==============================================================")
    message(STATUS "")

    # A private venv: installing aqt must not mutate the user's interpreter.
    set(_mo2_venv "${CMAKE_BINARY_DIR}/qt-installer-venv")
    execute_process(COMMAND ${_mo2_py} -m venv "${_mo2_venv}"
                    RESULT_VARIABLE _mo2_rc)
    if(NOT _mo2_rc EQUAL 0)
      message(FATAL_ERROR "[MO2] could not create a venv to run aqt from.\n"
        "Install Qt by hand instead:\n" ${_mo2_qt_manual_instructions})
    endif()

    # aqt's dependencies FIRST, pinned and hash-verified, then aqt itself with
    # --no-deps so pip has nothing left to resolve.
    #
    # Two invocations rather than one because --require-hashes cannot express a
    # git+https requirement: aqt is pinned by commit, which is already a content
    # address, while its 22 dependencies came from PyPI unpinned. That was the last
    # unverified download in a project that hashes everything else it fetches -- and
    # the highest-privilege one, since this runs automatically on every fresh clone.
    execute_process(
      COMMAND "${_mo2_venv}/Scripts/python.exe" -m pip install
              --disable-pip-version-check --require-hashes
              -r "${CMAKE_CURRENT_LIST_DIR}/cmake/aqt-requirements.txt"
      RESULT_VARIABLE _mo2_rc)
    if(NOT _mo2_rc EQUAL 0)
      message(FATAL_ERROR "[MO2] could not install aqt's dependencies.\n"
        "A HASH MISMATCH here is not something to work around -- it means a release "
        "on PyPI no longer has the bytes this file recorded. A resolution failure "
        "instead usually means MO2_AQTINSTALL_COMMIT moved and aqt now wants "
        "something the lock does not carry; regenerate cmake/aqt-requirements.txt "
        "as its header describes.\nInstall Qt by hand instead:\n"
        ${_mo2_qt_manual_instructions})
    endif()

    # aqt from git, never PyPI: the released version lags Qt's repository layout
    # and fails outright on current Qt versions. Pinned to a commit rather than the
    # default branch, because configure runs this on every fresh clone and an
    # unpinned fetch would execute whatever that repository's HEAD held at the time.
    execute_process(
      COMMAND "${_mo2_venv}/Scripts/python.exe" -m pip install
              --disable-pip-version-check --no-deps
              "git+https://github.com/miurahr/aqtinstall@${MO2_AQTINSTALL_COMMIT}"
      RESULT_VARIABLE _mo2_rc)
    if(NOT _mo2_rc EQUAL 0)
      message(FATAL_ERROR "[MO2] could not install aqt (needs network, and git on "
        "PATH for a git+https install).\nInstall Qt by hand instead:\n"
        ${_mo2_qt_manual_instructions})
    endif()

    # Into qt.tmp, never straight into qt (ADR-024). No OUTPUT_VARIABLE anywhere in
    # this block -- that is what keeps the download visible while it runs.
    execute_process(
      COMMAND "${_mo2_venv}/Scripts/python.exe" -m aqt install-qt
              windows desktop "${MO2_QT_VERSION}" "win64_${MO2_QT_ARCH}"
              -m ${MO2_QT_MODULES}
              -O "${_mo2_qt_tmp}"
      RESULT_VARIABLE _mo2_rc)

    set(_mo2_qt_built "${_mo2_qt_tmp}/${MO2_QT_VERSION}/${MO2_QT_ARCH}")
    if(_mo2_rc EQUAL 0 AND EXISTS "${_mo2_qt_built}/lib/cmake/Qt6/Qt6Config.cmake")
      file(RENAME "${_mo2_qt_tmp}" "${_mo2_qt_dest}")
      set(MO2_QT_DIR "${_mo2_qt_dest}/${MO2_QT_VERSION}/${MO2_QT_ARCH}")
      message(STATUS "[MO2] Qt installed to ${MO2_QT_DIR}")
    else()
      # Leave nothing behind that a later configure could mistake for a good Qt.
      file(REMOVE_RECURSE "${_mo2_qt_tmp}")
      message(WARNING "[MO2] the Qt download did not complete; qt.tmp was removed.")
    endif()
  endif()
endif()

if(NOT MO2_QT_DIR)
  # One string per branch, not a list: message() joins list elements with ";",
  # which puts a stray semicolon in the middle of the sentence.
  if(NOT MO2_AUTO_INSTALL_QT)
    set(_mo2_qt_auto_hint
        "This project can also fetch Qt itself; that is MO2_AUTO_INSTALL_QT, which is currently OFF.")
  else()
    set(_mo2_qt_auto_hint
        "MO2_AUTO_INSTALL_QT is ON, so this was attempted and did not succeed -- the reason is in the output above. Fix that, or install Qt by hand with the command above.")
  endif()

  message(FATAL_ERROR
    "Qt ${MO2_QT_VERSION} (${MO2_QT_ARCH}) was not found.\n"
    "\n"
    "Install it with aqt, which must come from git -- the PyPI release lags Qt's\n"
    "repository layout and fails on current versions:\n"
    "\n"
    ${_mo2_qt_manual_instructions}
    "\n"
    "The module list above is not optional; the comment beside MO2_QT_MODULES in\n"
    "CMakeLists.txt explains how each half of it fails.\n"
    "\n"
    "Already have Qt elsewhere? Point at it instead:\n"
    "  cmake --preset vs2026 -DMO2_QT_DIR=<prefix>   (or set QTDIR)\n"
    "\n"
    # Conditional: three paths reach this error and only one has the option off.
    "${_mo2_qt_auto_hint}")
endif()

message(STATUS "[MO2] Qt: ${MO2_QT_DIR}")
list(APPEND CMAKE_PREFIX_PATH "${MO2_QT_DIR}")

# --- resolve mo2-cmake from source, no install required ------------------------
list(APPEND CMAKE_PREFIX_PATH "${MO2_SOURCE_ROOT}/cmake_common")

# --- redirect sibling packages to in-tree targets -------------------------------
# <pkg>_DIR points straight at the directory holding <pkg>-config.cmake, which is
# more explicit than relying on CMAKE_PREFIX_PATH search order.
# mo2-dds-header and mo2-libbsarch are vcpkg registry ports, not sibling
# repositories -- they resolve normally and need no redirect.
set(_mo2_redirects "${CMAKE_CURRENT_LIST_DIR}/cmake/superbuild-redirects")
foreach(_pkg mo2-uibase mo2-bsatk mo2-esptk mo2-archive mo2-lootcli-header)
  set(${_pkg}_DIR "${_mo2_redirects}" CACHE PATH "superbuild redirect" FORCE)
endforeach()

# --- usvfs: both architectures, built at configure time --------------------------
#
# usvfs is the one repository that cannot simply be add_subdirectory()'d. It is
# dual-architecture by design -- the x86 DLL is injected into 32-bit games, the
# x64 one into 64-bit games -- and a single CMake configure produces exactly one
# architecture. Its installed usvfs-config.cmake includes BOTH usvfs_x86Targets
# and usvfs_x64Targets from one prefix and then aliases usvfs::usvfs, and
# modorganizer references usvfs_x86::usvfs_dll and usvfs_x64::usvfs_proxy
# directly in generator expressions. So both must exist as imported targets.
#
# ExternalProject_Add is the usual answer and is wrong here: it builds at BUILD
# time, while modorganizer's find_package(usvfs) resolves at CONFIGURE time.
# Building it here instead keeps modorganizer a first-class project in the
# solution rather than a nested sub-build the IDE cannot see into.
#
# Cost: the first configure builds usvfs twice, a few minutes. Afterwards the
# guard below skips it. Delete build/usvfs-install to force a rebuild -- and note
# that deleting only the usvfs-Win32/usvfs-x64 directories is NOT enough, since
# the guard checks the install.

# usvfs gets a PRIVATE prefix, and it must stay private.
#
# Pointing it at CMAKE_INSTALL_PREFIX looks tidier and breaks the build. That
# prefix already holds installed copies of uibase's headers from a previous
# install, and this prefix goes on CMAKE_PREFIX_PATH so find_package(usvfs)
# works -- which puts a second physical copy of every uibase header on the
# include path, competing with the in-tree sources. uibase's formatters headers
# use #pragma once, which dedupes by file identity rather than by guard macro,
# so both copies are included and every std::formatter specialisation is defined
# twice:
#
#   error C2953: 'std::formatter<QSize,CharT>': class template has already been defined
#
# 3137 errors, from a change that only meant to relocate an install. The usvfs
# artifacts are copied into the shared prefix at install time instead, below,
# which cannot affect any include path.
set(MO2_USVFS_PREFIX "${CMAKE_BINARY_DIR}/usvfs-install")

# The guard is a stamp this file writes after BOTH passes, and it has to be.
#
# The obvious candidate -- usvfsConfig.cmake, which usvfs installs -- is written
# by whichever pass runs, so it exists as soon as Win32 finishes. If x64 then
# fails for any reason, the FATAL_ERROR below is correct but the next configure
# sees that file, skips the whole loop, and dies later inside
# find_package(usvfs) on a missing usvfs_x64Targets.cmake -- a path nobody
# created, with nothing pointing at `build/usvfs-install` as the thing to delete.
# usvfs's own config includes BOTH usvfs_x86Targets.cmake and
# usvfs_x64Targets.cmake (repos/usvfs/cmake/config.cmake.in), so a half-built
# prefix is worse than none.
#
# Note for anyone tempted to guard on the config file anyway: usvfs writes
# usvfsConfig.cmake, not usvfs-config.cmake, and find_package accepts either
# spelling -- so that mistake does not break resolution, it silently rebuilds
# usvfs on every configure.
# The stamp records WHAT built usvfs, not merely that something did. Existence
# alone would silently reuse a v145 usvfs -- the DLL-injection component, injected
# into every game process -- inside a v146 build after a toolset change, with no
# error anywhere. The CI cache key already carries the toolset for exactly this
# reason; this is the same rule applied locally.
#
# The SOURCE revision belongs in it for the same reason the toolchain does, and was
# missing: with only the toolchain recorded, bumping the repos/usvfs gitlink or
# editing usvfs's sources left the stamp valid, so configure skipped the rebuild and
# the whole tree linked against the previously built DLL. Nothing failed, nothing
# printed. CI was already stricter than the local build here -- its cache key is the
# gitlink SHA (.github/workflows/build.yml) -- which is backwards, because the local
# build is the one people run while changing usvfs.
#
# git may be absent, or repos/usvfs may not be a git checkout at all when
# MO2_SOURCE_ROOT points somewhere else. Then the revision is simply unknown, and
# the honest response is to say so rather than to pretend: rebuilding on every
# configure would cost several minutes each time to guard a case the README already
# rules out (git is a stated requirement), and silently recording "unknown" as if it
# were a revision is the failure this whole block is about.
find_package(Git QUIET)
set(_mo2_usvfs_rev "unknown")
if(GIT_EXECUTABLE AND EXISTS "${MO2_SOURCE_ROOT}/usvfs/.git")
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" -C "${MO2_SOURCE_ROOT}/usvfs" rev-parse HEAD
    OUTPUT_VARIABLE _mo2_usvfs_head OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET RESULT_VARIABLE _mo2_usvfs_rc)
  if(_mo2_usvfs_rc EQUAL 0 AND _mo2_usvfs_head)
    # Uncommitted work counts as a different source. `git status --porcelain` is
    # non-empty for any modification, so hashing it distinguishes one dirty state
    # from another rather than merely flagging "dirty" -- editing usvfs twice in a
    # row has to rebuild twice.
    execute_process(
      COMMAND "${GIT_EXECUTABLE}" -C "${MO2_SOURCE_ROOT}/usvfs" status --porcelain
      OUTPUT_VARIABLE _mo2_usvfs_dirty ERROR_QUIET)
    string(SHA256 _mo2_usvfs_dirty_hash "${_mo2_usvfs_dirty}")
    string(SUBSTRING "${_mo2_usvfs_dirty_hash}" 0 12 _mo2_usvfs_dirty_hash)
    set(_mo2_usvfs_rev "${_mo2_usvfs_head}+${_mo2_usvfs_dirty_hash}")
  endif()
endif()

if(_mo2_usvfs_rev STREQUAL "unknown")
  message(WARNING
    "[MO2] cannot determine the usvfs source revision (no git, or "
    "${MO2_SOURCE_ROOT}/usvfs is not a git checkout).\n"
    "usvfs will be built once and then reused for as long as the toolchain is "
    "unchanged, INCLUDING after its sources change. Force a rebuild by deleting "
    "${MO2_USVFS_PREFIX}.")
endif()

set(_mo2_usvfs_stamp "${MO2_USVFS_PREFIX}/.mo2-usvfs-complete")
set(_mo2_usvfs_id
    "generator=${CMAKE_GENERATOR}\ntoolset=${CMAKE_GENERATOR_TOOLSET}\n"
    "triplets=x86-windows-static-md,x64-windows-static-md\nconfig=RelWithDebInfo\n"
    "usvfs=${_mo2_usvfs_rev}\n")
string(REPLACE ";" "" _mo2_usvfs_id "${_mo2_usvfs_id}")

set(_mo2_usvfs_stale TRUE)
set(_mo2_usvfs_reason "first build")
if(EXISTS "${_mo2_usvfs_stamp}")
  file(READ "${_mo2_usvfs_stamp}" _mo2_usvfs_prev)
  if(_mo2_usvfs_prev STREQUAL "${_mo2_usvfs_id}")
    set(_mo2_usvfs_stale FALSE)
  else()
    # Name what actually changed. "different toolchain" was the only message this
    # ever printed, and it became wrong half the time once the source revision
    # joined the identity -- a rebuild attributed to the wrong cause is how someone
    # goes looking for a toolset change that never happened.
    if(_mo2_usvfs_prev MATCHES "usvfs=([^\n]*)")
      set(_mo2_usvfs_prev_rev "${CMAKE_MATCH_1}")
      if(NOT _mo2_usvfs_prev_rev STREQUAL "${_mo2_usvfs_rev}")
        set(_mo2_usvfs_reason "usvfs sources changed")
      else()
        set(_mo2_usvfs_reason "toolchain changed")
      endif()
    else()
      set(_mo2_usvfs_reason "stamp predates source tracking")
    endif()
    message(STATUS "[MO2] usvfs stamp does not match -- rebuilding (${_mo2_usvfs_reason})")
  endif()
endif()

if(_mo2_usvfs_stale)
  foreach(_pair "Win32:x86-windows-static-md" "x64:x64-windows-static-md")
    string(REPLACE ":" ";" _pair "${_pair}")
    list(GET _pair 0 _arch)
    list(GET _pair 1 _triplet)

    # Not "first configure only": the stamp also invalidates on a toolchain change
    # or a usvfs source change, and saying otherwise makes a legitimate rebuild look
    # like the guard has failed.
    message(STATUS "[MO2] building usvfs (${_arch}) -- ${_mo2_usvfs_reason}")

    # Only pass -T when there is a toolset. Configuring without the preset leaves
    # CMAKE_GENERATOR_TOOLSET empty, and `-T ""` is not the same as omitting it.
    set(_usvfs_toolset "")
    if(CMAKE_GENERATOR_TOOLSET)
      set(_usvfs_toolset -T "${CMAKE_GENERATOR_TOOLSET}")
    endif()

    execute_process(
      COMMAND "${CMAKE_COMMAND}"
        -S "${MO2_SOURCE_ROOT}/usvfs"
        -B "${CMAKE_BINARY_DIR}/usvfs-${_arch}"
        -G "${CMAKE_GENERATOR}"
        -A "${_arch}"
        ${_usvfs_toolset}
        "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}"
        "-DVCPKG_TARGET_TRIPLET=${_triplet}"
        "-DCMAKE_INSTALL_PREFIX=${MO2_USVFS_PREFIX}"
        # Without this the nested builds ignore the preset's scratch redirection
        # and drop vcpkg buildtrees, packages and downloads inside vcpkg/ in the
        # workspace -- and these two are the largest consumers in the project.
        "-DVCPKG_INSTALL_OPTIONS=${VCPKG_INSTALL_OPTIONS}"
      RESULT_VARIABLE _usvfs_configure
      OUTPUT_VARIABLE _usvfs_out ERROR_VARIABLE _usvfs_out)
    if(NOT _usvfs_configure EQUAL 0)
      message(FATAL_ERROR "usvfs ${_arch} configure failed:\n${_usvfs_out}")
    endif()

    execute_process(
      COMMAND "${CMAKE_COMMAND}" --build "${CMAKE_BINARY_DIR}/usvfs-${_arch}"
              --config RelWithDebInfo --target install
      RESULT_VARIABLE _usvfs_build
      OUTPUT_VARIABLE _usvfs_out ERROR_VARIABLE _usvfs_out)
    if(NOT _usvfs_build EQUAL 0)
      message(FATAL_ERROR "usvfs ${_arch} build failed:\n${_usvfs_out}")
    endif()
  endforeach()

  # Only now is the prefix usable by find_package(usvfs), and only for this
  # toolchain -- the contents are what the guard above compares against.
  file(WRITE "${_mo2_usvfs_stamp}" "${_mo2_usvfs_id}")
endif()

list(APPEND CMAKE_PREFIX_PATH "${MO2_USVFS_PREFIX}")

# Copy usvfs's private install tree into the shared prefix at install time, so
# the headers, import libraries and CMake package land beside everything else
# exactly as mob leaves them. This runs during `cmake --install`, long after
# every include path has been decided, so it cannot reintroduce the duplicate
# header problem described above.
# The stamp is build-tree bookkeeping and was being deployed along with everything
# else, leaving a stray install/.mo2-usvfs-complete in the shipped tree.
install(DIRECTORY "${MO2_USVFS_PREFIX}/" DESTINATION "." USE_SOURCE_PERMISSIONS
        PATTERN ".mo2-usvfs-complete" EXCLUDE)

# --- deployment: the parts of mob that are not a build system --------------------
#
# mob does more than orchestrate builds. It also fetches two components that are
# not git repositories at all, and copies license texts out of its own checkout.
# A build system that only builds produces an MO2 that starts and looks broken.

# Both of these are DOWNLOADED rather than built or cloned, so no checkout has
# them. Prefer an existing directory when one is there -- re-downloading what is
# already on disk is pure waste -- and otherwise fetch into the build tree.
#
# Provenance, which is still the reason these versions are what they are: they
# match mob's release tables in src/tasks/stylesheets.cpp, src/tasks/explorerpp.cpp
# and mob.ini. Check those when bumping, since upstream MO2 still ships whatever
# mob names.

set(MO2_PREBUILT_DIR "${CMAKE_BINARY_DIR}/prebuilt"
    CACHE PATH "Where downloaded, non-buildable components are unpacked")
set(MO2_EXPLORERPP_VERSION "1.4.0"
    CACHE STRING "Explorer++ release to ship (mob.ini: explorerpp)")
# Hash of the archive this project downloaded and shipped on 2026-08-15. This one
# is an EXECUTABLE that gets installed into bin/explorer++ and launched from
# MO2's UI, which is the strongest reason in this file to pin bytes rather than a
# URL. Update it together with MO2_EXPLORERPP_VERSION.
set(MO2_EXPLORERPP_SHA256
    "81ec54586dfef888b886d409afa22e31f22d4f6ba35d52d93074b4ee64b79b0c"
    CACHE STRING "SHA256 of explorerpp_x64.zip for MO2_EXPLORERPP_VERSION")

set(MO2_STYLESHEETS_DIR "${MO2_SOURCE_ROOT}/stylesheets"
    CACHE PATH "Extracted stylesheet releases; downloaded if absent")
set(MO2_EXPLORERPP_DIR "${MO2_SOURCE_ROOT}/explorer++"
    CACHE PATH "Extracted Explorer++; downloaded if absent")

# user|repo|version|archive-name|sha256 -- mob's release table, plus a hash.
#
# The separator is | and not ; on purpose: foreach() over a list of
# semicolon-bearing strings flattens them into individual tokens, so the tuples
# would silently come apart and produce empty URLs.
#
# The hashes are here because a GitHub release tag is mutable -- it can be
# re-pushed at different bytes with no change to the URL -- and these archives are
# extracted into the tree MO2 ships. Update the hash with the version; the build
# stopping is the point.
set(_mo2_stylesheets
  "6788-00|paper-light-and-dark|7.2|paper-light-and-dark|f8399199cc8dd99d5beb121c2cbfe9a606d7238b12500b881857f2e0b93765ee"
  "6788-00|paper-automata|3.2|paper-automata|2eaea2a11f53f762c843d15e8fe1fd5c5b138ed5a215f9aaf6eb3d8176bb84f6"
  "6788-00|paper-mono|3.2|paper-mono|177033a7c74c4d90bb1f31d9fe327130afe1f1b8bd5eec0210ca39d7e98aeebc"
  "6788-00|1809-dark-mode|3.0|1809|de0d858164254c3feda3c38321e2f9530dbf1e6b64f3c8747776c4539ab7b8a1"
  "Trosski|ModOrganizer_Style_Morrowind|1.1|Morrowind-MO2-Stylesheet|e7c13960be64db22ccecc85cb4dc76152ff91bdd1f3685249a9e6658159923b1"
  "Trosski|Mod-Organizer-2-Skyrim-Stylesheet|v1.1|Skyrim-MO2-Stylesheet|502f4680eea2bcea7a6ac53a44d3fcebe8bde16d7bd590024c238211bd947577"
  "Trosski|ModOrganizer_Style_Fallout3|v1.11|Fallout3-MO2-Stylesheet|9b561c7b9c1cc56ef72f976702c92a7c374c1431ccb01bdd63745776376abe8c"
  "Trosski|Mod-Organizer2-Fallout-4-Stylesheet|v1.11|Fallout4-MO2-Stylesheet|e9591268b142b41af1ca8bc31b9ed8f2f0635b894c243b0ac413822aef3c5e4e"
  "Trosski|Starfield_MO2_Stylesheet|V1.11|Starfield.MO2.Stylsheet|257340ca4ee499422fb55ce1d2d7cc84c02cf8a76e760d0a96528154bf9b7eff")

if(NOT EXISTS "${MO2_STYLESHEETS_DIR}")
  set(MO2_STYLESHEETS_DIR "${MO2_PREBUILT_DIR}/stylesheets")
  foreach(_entry IN LISTS _mo2_stylesheets)
    string(REPLACE "|" ";" _parts "${_entry}")
    list(GET _parts 0 _user)
    list(GET _parts 1 _repo)
    list(GET _parts 2 _ver)
    list(GET _parts 3 _file)
    list(GET _parts 4 _sha)
    # mob names the extracted directory <repo>-<version>; keep that, because the
    # install step below simply copies every release directory's contents flat.
    set(_dest "${MO2_STYLESHEETS_DIR}/${_repo}-${_ver}")
    if(NOT EXISTS "${_dest}")
      set(_archive "${MO2_PREBUILT_DIR}/${_repo}.7z")
      message(STATUS "[MO2] downloading stylesheet ${_repo} ${_ver}")
      file(DOWNLOAD
        "https://github.com/${_user}/${_repo}/releases/download/${_ver}/${_file}.7z"
        "${_archive}" STATUS _dl TLS_VERIFY ON
        EXPECTED_HASH "SHA256=${_sha}")
      list(GET _dl 0 _dl_code)
      if(NOT _dl_code EQUAL 0)
        list(GET _dl 1 _dl_msg)
        message(FATAL_ERROR "downloading ${_repo}: ${_dl_msg}")
      endif()
      file(MAKE_DIRECTORY "${_dest}")
      file(ARCHIVE_EXTRACT INPUT "${_archive}" DESTINATION "${_dest}")
    endif()
  endforeach()
endif()

# Every release in mob's table has an empty top_level_folder, so each extracted
# directory's contents go FLAT into bin/stylesheets with nothing stripped.
# CONFIGURE_DEPENDS so adding a stylesheet release is picked up by the next build
# rather than silently ignored until somebody happens to reconfigure.
file(GLOB _mo2_ss_releases CONFIGURE_DEPENDS "${MO2_STYLESHEETS_DIR}/*")
foreach(_ss ${_mo2_ss_releases})
  if(IS_DIRECTORY "${_ss}")
    install(DIRECTORY "${_ss}/" DESTINATION bin/stylesheets)
  endif()
endforeach()

# explorer++: a prebuilt binary MO2 ships, from its own site rather than GitHub.
#
# Both guards are load-bearing. The outer one resolves the location; the inner one
# is what stops a re-download, and without it this fetched the zip on EVERY
# configure -- `set()` inside the branch makes a normal variable, which shadows
# the cache entry for that configure only, so the next one sees the cache again
# and re-enters. With a fatal failure path, that also meant configure needed a
# network forever. The nesting keeps the download inside the build tree, never in
# MO2_SOURCE_ROOT.
if(NOT EXISTS "${MO2_EXPLORERPP_DIR}")
  set(MO2_EXPLORERPP_DIR "${MO2_PREBUILT_DIR}/explorer++")
  if(NOT EXISTS "${MO2_EXPLORERPP_DIR}/Explorer++.exe")
    set(_epp_zip "${MO2_PREBUILT_DIR}/explorerpp_x64.zip")
    message(STATUS "[MO2] downloading Explorer++ ${MO2_EXPLORERPP_VERSION}")
    file(DOWNLOAD
      "https://download.explorerplusplus.com/stable/${MO2_EXPLORERPP_VERSION}/explorerpp_x64.zip"
      "${_epp_zip}" STATUS _dl TLS_VERIFY ON
      EXPECTED_HASH "SHA256=${MO2_EXPLORERPP_SHA256}")
    list(GET _dl 0 _dl_code)
    if(NOT _dl_code EQUAL 0)
      list(GET _dl 1 _dl_msg)
      message(FATAL_ERROR "downloading Explorer++: ${_dl_msg}")
    endif()
    file(MAKE_DIRECTORY "${MO2_EXPLORERPP_DIR}")
    file(ARCHIVE_EXTRACT INPUT "${_epp_zip}" DESTINATION "${MO2_EXPLORERPP_DIR}")
  endif()
endif()

install(DIRECTORY "${MO2_EXPLORERPP_DIR}/" DESTINATION bin/explorer++)

# licenses: these belong to no MO2 repository -- they lived only in mob's own
# checkout, so they are vendored here. Retiring mob does not remove the
# obligation to ship them, and that obligation must not depend on a mob checkout
# happening to sit at a fixed relative offset: MO2_SOURCE_ROOT/../../mob/licenses
# resolves in a tree that was built with mob and silently does not in a clean
# clone, which shipped MO2 with no license texts at all and said so in one
# STATUS line.
set(MO2_LICENSES_DIR "${CMAKE_CURRENT_LIST_DIR}/licenses"
    CACHE PATH "Directory of third-party license texts to ship in bin/licenses")
if(EXISTS "${MO2_LICENSES_DIR}")
  install(DIRECTORY "${MO2_LICENSES_DIR}/" DESTINATION bin/licenses)
else()
  # Only reachable when MO2_LICENSES_DIR has been overridden to a bad path --
  # the default is inside this repository. Loud, because shipping without them
  # is a licensing failure rather than a missing convenience.
  message(WARNING
    "[MO2] license texts not found at ${MO2_LICENSES_DIR}.\n"
    "bin/licenses will be EMPTY and the build must not be distributed.")
endif()

# 7zip's runtime DLL, which vcpkg puts in the build tree rather than anywhere
# CMake would find on its own.
#
# OPTIONAL is defensive, not load-bearing: under x64-windows-static-md the DLL is
# present and does get installed. It guards a triplet change that stops producing
# it, where a hard rule would fail the install on a path nobody recognises.
install(FILES "${CMAKE_BINARY_DIR}/vcpkg_installed/${VCPKG_TARGET_TRIPLET}/bin/7zip.dll"
        DESTINATION bin/dlls OPTIONAL)

# --- subprojects ----------------------------------------------------------------
# Sources live outside this tree, so each needs an explicit binary directory.
function(mo2_add_repo name)
  add_subdirectory("${MO2_SOURCE_ROOT}/${name}" "${CMAKE_BINARY_DIR}/${name}")
endfunction()

# Anything that stands in for an installed package must be marked SYSTEM, or the
# superbuild is stricter than mob and fails on warnings mob never sees.
#
# CMake treats an IMPORTED target's INTERFACE_INCLUDE_DIRECTORIES as SYSTEM by
# default. Under mob, mo2::uibase is imported, so modorganizer compiles with
#
#     /external:I ".../install/include/uibase"
#
# and ExternalWarningLevel=TurnOffAllWarnings silences everything in uibase's
# public headers. In the superbuild the same target is an ordinary in-tree
# target, its includes are passed as regular ones, and every warning inside a
# public header lands on the consumer's /WX. modorganizer failed with 84
# instances of C4100 in uibase's moddatachecker.h -- a real unreferenced
# parameter that mob has simply never shown anyone.
#
# Marking these SYSTEM restores parity. It does NOT hide warnings in the
# library's own build: uibase is still compiled at /W4 /WX by its own project.
# Fatal on a missing target, not silent. If an upstream rename makes this a no-op,
# the symptom is a wall of warnings-as-errors inside somebody else's public headers,
# in a different repository, naming nothing that leads back here.
function(mo2_mark_package_target target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR
      "[MO2] no target '${target}' to mark SYSTEM. It is consumed through a "
      "find_package redirect, so leaving it unmarked makes consumers compile its "
      "public headers at /W4 /WX. If the target was renamed upstream, update the "
      "list beside mo2_mark_package_target in CMakeLists.txt.")
  endif()
  set_target_properties(${target} PROPERTIES SYSTEM TRUE)
endfunction()

# Order is dependency order, derived from the find_package(mo2-*) calls in each
# repository rather than assumed. CMake needs the producing target to exist
# before a consumer's find_package redirect runs.

# --- libraries with no in-tree dependencies ---
mo2_add_repo(esptk)
mo2_add_repo(archive)
mo2_add_repo(bsatk)
mo2_add_repo(lootcli)
mo2_add_repo(helper)

# --- uibase: 23 of the 63 find_package sites want it, and every plugin does ---
mo2_add_repo(uibase)

# Every target consumed through a find_package redirect, marked SYSTEM so
# consumers see it exactly as they would the installed package.
foreach(_pkg_target uibase archive bsatk esptk lootcli-header)
  mo2_mark_package_target(${_pkg_target})
endforeach()

# --- plugins that need only uibase ---
mo2_add_repo(check_fnis)
mo2_add_repo(diagnose_basic)
mo2_add_repo(game_bethesda)
mo2_add_repo(installer_bain)
mo2_add_repo(installer_bundle)
mo2_add_repo(installer_fomod)
mo2_add_repo(installer_manual)
mo2_add_repo(installer_quick)
mo2_add_repo(nxmhandler)
mo2_add_repo(preview_base)
mo2_add_repo(tool_inibakery)
mo2_add_repo(tool_inieditor)

# --- Python-only plugins: these install .py files, no C++ target ---
mo2_add_repo(basic_games)
mo2_add_repo(fnistool)
mo2_add_repo(form43_checker)
mo2_add_repo(installer_wizard)
mo2_add_repo(preview_dds)
mo2_add_repo(script_extender_plugin_checker)
mo2_add_repo(tool_configurator)

# --- plugins needing uibase plus a sibling library ---
mo2_add_repo(bsa_extractor)
mo2_add_repo(preview_bsa)
mo2_add_repo(bsapacker)

# --- the application itself ------------------------------------------------------
# Needs archive, bsatk, esptk, lootcli-header, uibase and usvfs. find_package(usvfs)
# is the only cross-repo dependency in the tree not named mo2-*, and so the only one
# a survey of find_package(mo2-*) misses entirely.
mo2_add_repo(modorganizer)

# --- Python proxy: pybind11 + SIP + PyQt against Python 3.14 ---
# mo2_python_install_pyqt() pip-installs PyQt6 into ${CMAKE_BINARY_DIR}/pylibs.
# In the superbuild that is the top-level build directory, so there is one shared
# pylibs rather than one per repository -- which also avoids the stale *.dist-info
# accumulation that --target installs cause when each repo keeps its own.
mo2_add_repo(plugin_python)

# --- C++/CLI plugins: MSBuild only, no Ninja generator can build these ---
# installer_omod additionally restores NuGet packages, which is why the preset
# sets CMAKE_VS_NUGET_PACKAGE_RESTORE.
mo2_add_repo(installer_fomod_csharp)
mo2_add_repo(installer_omod)

# Install is deliberately NOT folded into the default build -- see ADR-023.
#
# The startup project must be set here and not in cmake_common: mo2_configure_target()
# sets VS_STARTUP_PROJECT on each repository's own directory, and Visual Studio reads
# it from the top-level source directory only, so all ~20 of those are ignored and the
# IDE falls back to the first target alphabetically -- archive, a DLL, unlaunchable.
set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
             PROPERTY VS_STARTUP_PROJECT organizer)
