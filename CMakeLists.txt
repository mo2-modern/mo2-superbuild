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
set(_mo2_redirects "${CMAKE_CURRENT_LIST_DIR}/cmake/superbuild-redirects")
set(mo2-uibase_DIR "${_mo2_redirects}" CACHE PATH "superbuild redirect" FORCE)

# --- subprojects ----------------------------------------------------------------
# Sources live outside this tree, so each needs an explicit binary directory.
function(mo2_add_repo name)
  add_subdirectory("${MO2_SOURCE_ROOT}/${name}" "${CMAKE_BINARY_DIR}/${name}")
endfunction()

# uibase first: 23 of the 63 find_package sites want it, and every plugin does.
mo2_add_repo(uibase)

# Standalone libraries -- no cmake_common, no in-tree dependencies.
mo2_add_repo(esptk)
mo2_add_repo(archive)

# First consumer of the uibase redirect, and the cheapest proof that it works:
# installer_bain needs only mo2-cmake and mo2-uibase.
mo2_add_repo(installer_bain)
