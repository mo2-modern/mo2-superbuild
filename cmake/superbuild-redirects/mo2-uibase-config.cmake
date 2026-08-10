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

set(mo2-uibase_FOUND TRUE)
