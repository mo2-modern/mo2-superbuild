# Superbuild redirect for find_package(mo2-bsatk CONFIG REQUIRED). See
# mo2-uibase-config.cmake for why these exist.
#
# Mirrors the find_dependency calls in bsatk/cmake/config.cmake.in, because
# consumers rely on them resolving transitively.

if(NOT TARGET mo2::bsatk)
  message(FATAL_ERROR
    "mo2-bsatk superbuild redirect was used, but target mo2::bsatk does not "
    "exist yet. bsatk must be added before any consumer of it.")
endif()

include(CMakeFindDependencyMacro)
find_dependency(Boost CONFIG COMPONENTS thread interprocess)
find_dependency(ZLIB)
find_dependency(lz4 CONFIG)
find_dependency(mo2-dds-header CONFIG)

set(mo2-bsatk_FOUND TRUE)
