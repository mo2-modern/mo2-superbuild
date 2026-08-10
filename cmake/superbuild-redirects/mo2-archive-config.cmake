# Superbuild redirect for find_package(mo2-archive CONFIG REQUIRED). See
# mo2-uibase-config.cmake for why these exist.
#
# Mirrors archive/cmake/config.cmake.in, which finds 7zip.

if(NOT TARGET mo2::archive)
  message(FATAL_ERROR
    "mo2-archive superbuild redirect was used, but target mo2::archive does not "
    "exist yet. archive must be added before any consumer of it.")
endif()

find_package(7zip CONFIG REQUIRED)

set(mo2-archive_FOUND TRUE)
