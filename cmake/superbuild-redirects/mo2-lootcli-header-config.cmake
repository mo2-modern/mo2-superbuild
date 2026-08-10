# Superbuild redirect for find_package(mo2-lootcli-header CONFIG REQUIRED). See
# mo2-uibase-config.cmake for why these exist.
#
# lootcli/cmake/config.cmake.in has no find_dependency calls: the package is the
# header-only interface target, not the lootcli executable itself.

if(NOT TARGET mo2::lootcli-header)
  message(FATAL_ERROR
    "mo2-lootcli-header superbuild redirect was used, but target "
    "mo2::lootcli-header does not exist yet. lootcli must be added before any "
    "consumer of it.")
endif()

set(mo2-lootcli-header_FOUND TRUE)
