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

cmake_minimum_required(VERSION 3.22)

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

# --- subprojects ----------------------------------------------------------------
# Sources live outside this tree, so each needs an explicit binary directory.
function(mo2_add_repo name)
  add_subdirectory("${MO2_SOURCE_ROOT}/${name}" "${CMAKE_BINARY_DIR}/${name}")
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

# Still to come, and none is a one-liner:
#
#   usvfs           Dual-architecture (x86 AND x64). One configure produces one
#                   architecture, so it needs ExternalProject_Add regardless of
#                   how clean the rest becomes.
#
#   modorganizer    Blocked on usvfs: it calls find_package(usvfs), which is the
#                   only cross-repo dependency in the tree not named mo2-*, and
#                   so the only one a survey of find_package(mo2-*) misses.
#
#   plugin_python   pybind11 + SIP + PyQt against Python 3.14.
#
#   installer_omod, installer_fomod_csharp
#                   C++/CLI. MSBuild-only, and installer_omod needs a NuGet
#                   restore for its .NET references.
