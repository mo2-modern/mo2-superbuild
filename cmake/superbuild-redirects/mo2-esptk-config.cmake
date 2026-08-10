# Superbuild redirect for find_package(mo2-esptk CONFIG REQUIRED). See
# mo2-uibase-config.cmake for why these exist.
#
# esptk/cmake/config.cmake.in has no find_dependency calls, so neither does this.

if(NOT TARGET mo2::esptk)
  message(FATAL_ERROR
    "mo2-esptk superbuild redirect was used, but target mo2::esptk does not "
    "exist yet. esptk must be added before any consumer of it.")
endif()

set(mo2-esptk_FOUND TRUE)
