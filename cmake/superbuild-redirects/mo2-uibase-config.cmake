# Superbuild redirect for find_package(mo2-uibase CONFIG REQUIRED).
#
# In the superbuild uibase is built here via add_subdirectory, so the alias target
# mo2::uibase already exists in this project. The real installed config cannot be
# used: it includes mo2-uibase-targets.cmake, which install(EXPORT) only writes at
# install time -- which is precisely the install-then-find cycle the superbuild
# exists to break.
#
# The 23 find_package(mo2-uibase) call sites are left untouched. They are spread
# across upstream repositories, and every edited line is merge surface on every
# sync; a redirect here is a new file in a repository that has no upstream at all.

if(NOT TARGET mo2::uibase)
  message(FATAL_ERROR
    "mo2-uibase superbuild redirect was used, but target mo2::uibase does not "
    "exist yet. uibase must be add_subdirectory()'d before any consumer of it.")
endif()

# The real config does this, and consumers rely on Qt6 being found transitively.
find_package(Qt6 CONFIG REQUIRED COMPONENTS Network QuickWidgets Widgets)

# uibase's installed config adds these when the consumer sets
# MO2_CMAKE_DEPRECATED_UIBASE_INCLUDE before calling find_package. Three repos do
# -- bsapacker, game_bethesda and modorganizer -- because they still include
# <iplugintool.h> rather than <uibase/iplugintool.h>.
#
# Without them moc does not report a missing header. It reports the far less
# obvious "error: Undefined interface" at the Q_INTERFACES line, because moc
# only warns about includes it cannot resolve and then cannot see the interface
# declaration.
#
# The installed config points these at the install prefix; here the headers are
# still in the source tree, which is the entire point of the superbuild.
if(MO2_CMAKE_DEPRECATED_UIBASE_INCLUDE)
  get_property(_mo2_legacy_added GLOBAL PROPERTY _MO2_UIBASE_LEGACY_INCLUDES)
  if(NOT _mo2_legacy_added)
    # mo2::uibase is an ALIAS, and alias targets cannot be modified, so this
    # applies to the underlying target. The directories therefore become visible
    # to every consumer rather than only those that asked -- which is also what
    # the installed layout does, since uibase is installed once with them present.
    target_include_directories(uibase INTERFACE
      "${MO2_SOURCE_ROOT}/uibase/include/uibase"
      "${MO2_SOURCE_ROOT}/uibase/include/uibase/game_features")
    set_property(GLOBAL PROPERTY _MO2_UIBASE_LEGACY_INCLUDES TRUE)
  endif()
endif()

set(mo2-uibase_FOUND TRUE)
