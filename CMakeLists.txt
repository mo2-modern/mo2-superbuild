# MO2 superbuild -- open this folder in Visual Studio or Rider, pick the vs2026
# preset, click build.
#
# This directory is deliberately tiny and self-contained. It holds no sources, no
# submodules and no build artifacts from mob: the repositories stay where they
# are, and everything this project produces goes into ./build. Nothing here edits
# any of the 33 forked repositories, so the whole superbuild costs zero merge
# surface on sync -- see ADR-001. The 63 find_package(mo2-*) call sites upstream
# are left exactly as written.
#
# Two mechanisms make that possible:
#
#   mo2-cmake (27 call sites)
#       cmake_common ships mo2-cmake-config.cmake, which only does
#       include(${CMAKE_CURRENT_LIST_DIR}/mo2.cmake) -- self-contained, no install
#       step. Putting cmake_common on CMAKE_PREFIX_PATH resolves all 27. mob has
#       always done this, so the mechanism is proven rather than novel.
#
#   sibling packages (uibase 23, bsatk 3, esptk/archive/lootcli-header 1 each)
#       Their real configs include a *-targets.cmake that install(EXPORT) writes
#       only at install time -- the install-then-find cycle this project exists to
#       break. cmake/superbuild-redirects/ stands in, asserting the alias target
#       already exists.

# 3.25 for the SYSTEM target property, which is load-bearing here -- see
# mo2_mark_package_target below.
cmake_minimum_required(VERSION 3.25)

project(mo2 LANGUAGES CXX)

# --- where the repositories live ----------------------------------------------
# Defaults to a sibling mo2-modern checkout. Point this anywhere; nothing else in
# this file assumes a location, and no file is ever written inside it.
set(MO2_SOURCE_ROOT "${CMAKE_CURRENT_LIST_DIR}/../mo2-modern/build/build"
    CACHE PATH "Directory containing the MO2 repositories (uibase, usvfs, ...)")

get_filename_component(MO2_SOURCE_ROOT "${MO2_SOURCE_ROOT}" ABSOLUTE)

if(NOT EXISTS "${MO2_SOURCE_ROOT}/uibase/CMakeLists.txt")
  message(FATAL_ERROR
    "MO2_SOURCE_ROOT does not look like an MO2 checkout: ${MO2_SOURCE_ROOT}\n"
    "Expected to find uibase/CMakeLists.txt under it. Set -DMO2_SOURCE_ROOT=<path>.")
endif()

message(STATUS "[MO2] sources: ${MO2_SOURCE_ROOT}")

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

# usvfs writes usvfsConfig.cmake, NOT usvfs-config.cmake. find_package accepts
# either spelling, so getting this wrong does not break resolution -- it breaks
# the guard silently, and usvfs is rebuilt from scratch on every configure.
if(NOT EXISTS "${MO2_USVFS_PREFIX}/lib/cmake/usvfs/usvfsConfig.cmake")
  foreach(_pair "Win32:x86-windows-static-md" "x64:x64-windows-static-md")
    string(REPLACE ":" ";" _pair "${_pair}")
    list(GET _pair 0 _arch)
    list(GET _pair 1 _triplet)

    message(STATUS "[MO2] building usvfs (${_arch}) -- first configure only")

    execute_process(
      COMMAND "${CMAKE_COMMAND}"
        -S "${MO2_SOURCE_ROOT}/usvfs"
        -B "${CMAKE_BINARY_DIR}/usvfs-${_arch}"
        -G "${CMAKE_GENERATOR}"
        -A "${_arch}"
        -T "${CMAKE_GENERATOR_TOOLSET}"
        "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}"
        "-DVCPKG_TARGET_TRIPLET=${_triplet}"
        "-DCMAKE_INSTALL_PREFIX=${MO2_USVFS_PREFIX}"
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
endif()

list(APPEND CMAKE_PREFIX_PATH "${MO2_USVFS_PREFIX}")

# Copy usvfs's private install tree into the shared prefix at install time, so
# the headers, import libraries and CMake package land beside everything else
# exactly as mob leaves them. This runs during `cmake --install`, long after
# every include path has been decided, so it cannot reintroduce the duplicate
# header problem described above.
install(DIRECTORY "${MO2_USVFS_PREFIX}/" DESTINATION "." USE_SOURCE_PERMISSIONS)

# --- deployment: the parts of mob that are not a build system --------------------
#
# mob does more than orchestrate builds. It also fetches two components that are
# not git repositories at all, and copies license texts out of its own checkout.
# A build system that only builds produces an MO2 that starts and looks broken.

# stylesheets: mob downloads nine release archives from GitHub and copies each
# one's contents FLAT into bin/stylesheets -- every release in mob's table has an
# empty top_level_folder, so there is no per-release subdirectory to strip. The
# archives are already extracted in the checkout, one directory per release.
file(GLOB _mo2_ss_releases "${MO2_SOURCE_ROOT}/stylesheets/*")
foreach(_ss ${_mo2_ss_releases})
  if(IS_DIRECTORY "${_ss}")
    install(DIRECTORY "${_ss}/" DESTINATION bin/stylesheets)
  endif()
endforeach()

# explorer++: a prebuilt binary MO2 ships, not a repository.
if(EXISTS "${MO2_SOURCE_ROOT}/explorer++")
  install(DIRECTORY "${MO2_SOURCE_ROOT}/explorer++/" DESTINATION bin/explorer++)
endif()

# licenses: these live in mob's own checkout rather than in any MO2 repository.
# Retiring mob does not remove the obligation to ship them.
set(MO2_LICENSES_DIR "${MO2_SOURCE_ROOT}/../../mob/licenses"
    CACHE PATH "Directory of third-party license texts to ship in bin/licenses")
if(EXISTS "${MO2_LICENSES_DIR}")
  install(DIRECTORY "${MO2_LICENSES_DIR}/" DESTINATION bin/licenses)
else()
  message(STATUS "[MO2] licenses not found at ${MO2_LICENSES_DIR} -- bin/licenses will be empty")
endif()

# 7zip's runtime DLL. OPTIONAL because the file only exists once vcpkg has
# populated the build tree, and a configure-time install() rule is evaluated
# before that on a clean tree.
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
function(mo2_mark_package_target target)
  if(TARGET ${target})
    set_target_properties(${target} PROPERTIES SYSTEM TRUE)
  endif()
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
#
#   installer_omod, installer_fomod_csharp
#                   C++/CLI. MSBuild-only, and installer_omod needs a NuGet
#                   restore for its .NET references.
