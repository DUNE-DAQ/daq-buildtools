####################################################################################################
# Experimental Color Support
set(DAQ_CMAKE_COLOR_MESSAGES TRUE)
if ( ${DAQ_CMAKE_COLOR_MESSAGES} )
  string(ASCII 27 Esc)
  set(ColourReset "${Esc}[m")
  set(ColourBold  "${Esc}[1m")
  set(Red         "${Esc}[31m")
  set(Green       "${Esc}[32m")
  set(Yellow      "${Esc}[33m")
  set(Blue        "${Esc}[34m")
  set(Magenta     "${Esc}[35m")
  set(Cyan        "${Esc}[36m")
  set(White       "${Esc}[37m")
  set(BoldRed     "${Esc}[1;31m")
  set(BoldGreen   "${Esc}[1;32m")
  set(BoldYellow  "${Esc}[1;33m")
  set(BoldBlue    "${Esc}[1;34m")
  set(BoldMagenta "${Esc}[1;35m")
  set(BoldCyan    "${Esc}[1;36m")
  set(BoldWhite   "${Esc}[1;37m")

  function(message)
    list(GET ARGV 0 MessageType)
    if(MessageType STREQUAL FATAL_ERROR OR MessageType STREQUAL SEND_ERROR)
      list(REMOVE_AT ARGV 0)
      _message(${MessageType} "${BoldRed}${ARGV}${ColourReset}")
    elseif(MessageType STREQUAL WARNING)
      list(REMOVE_AT ARGV 0)
      _message(${MessageType} "${BoldYellow}${ARGV}${ColourReset}")
    elseif(MessageType STREQUAL AUTHOR_WARNING)
      list(REMOVE_AT ARGV 0)
      _message(${MessageType} "${BoldCyan}${ARGV}${ColourReset}")
    elseif(MessageType STREQUAL STATUS)
      list(REMOVE_AT ARGV 0)
      _message(${MessageType} "${Green}${ARGV}${ColourReset}")
    elseif(MessageType STREQUAL NOTICE)
      list(REMOVE_AT ARGV 0)
      _message(${MessageType} "${Blue}${ARGV}${ColourReset}")
    else()
      _message("${ARGV}")
    endif()
  endfunction()
endif()


####################################################################################################
# daq_list_proj_subdirs
# This macro lists all the subdirectories of curdir which contain a CMakeLists.txt file
macro(daq_list_proj_subdirs result curdir)
  file(GLOB children RELATIVE ${curdir} CONFIGURE_DEPENDS ${curdir}/*)
  set(dirlist "")
  foreach (child ${children})
    if (IS_DIRECTORY "${curdir}/${child}")
      if (EXISTS "${curdir}/${child}/CMakeLists.txt")
        list(APPEND dirlist ${child})
      else()
        message(WARNING "Skipping directory ${child}: No CMakeLists.txt found." )
      endif()
    endif()
  endforeach()
  set(${result} ${dirlist})
endmacro()


####################################################################################################
# daq_topproj_save_gnudirs
# This macro stores the current value of the GnuInstallDirs variables (CMAKE_INSTALL_*) 
# into a matching set of TOPPROJ_CMAKE_INSTALL_* counterparts
macro(daq_topproj_save_gnudirs)

  set(TOPPROJ_CMAKE_INSTALL_LIBDIR ${CMAKE_INSTALL_LIBDIR})
  set(TOPPROJ_CMAKE_INSTALL_BINDIR ${CMAKE_INSTALL_BINDIR})
  set(TOPPROJ_CMAKE_INSTALL_INCLUDEDIR ${CMAKE_INSTALL_INCLUDEDIR})
  set(TOPPROJ_CMAKE_INSTALL_DATADIR ${CMAKE_INSTALL_DATADIR})

endmacro()


####################################################################################################
# daq_topproj_restore_gnudirs
# This macro restores the value of the GnuInstallDirs variables (CMAKE_INSTALL_*) from the matching 
# set of  TOPPROJ_CMAKE_INSTALL_* counterparts
macro(daq_topproj_restore_gnudirs)

  set(CMAKE_INSTALL_LIBDIR ${TOPPROJ_CMAKE_INSTALL_LIBDIR})
  set(CMAKE_INSTALL_BINDIR ${TOPPROJ_CMAKE_INSTALL_BINDIR})
  set(CMAKE_INSTALL_INCLUDEDIR ${TOPPROJ_CMAKE_INSTALL_INCLUDEDIR})
  set(CMAKE_INSTALL_DATADIR ${TOPPROJ_CMAKE_INSTALL_DATADIR})

endmacro()


####################################################################################################
# daq_topproj_setpkg_gnudirs
# This macro sets the GnuInstallDirs CMAKE_INSTALL_* to ${pkg}/TOPPROJ_CMAKE_INSTALL_*
macro(daq_topproj_setpkg_gnudirs pkg)
      # Forcefully adding the poackage name in front of the installation directories
    set(CMAKE_INSTALL_LIBDIR "${pkg}/${TOPPROJ_CMAKE_INSTALL_LIBDIR}")
    set(CMAKE_INSTALL_BINDIR "${pkg}/${TOPPROJ_CMAKE_INSTALL_BINDIR}")
    set(CMAKE_INSTALL_INCLUDEDIR "${pkg}/${TOPPROJ_CMAKE_INSTALL_INCLUDEDIR}")
    set(CMAKE_INSTALL_DATADIR "${pkg}/${TOPPROJ_CMAKE_INSTALL_DATADIR}")

endmacro(daq_topproj_setpkg_gnudirs)


####################################################################################################
macro(daq_add_subpackages build_order)

  daq_topproj_save_gnudirs()
  
  daq_list_proj_subdirs(found_pkgs ${CMAKE_CURRENT_LIST_DIR})

  set(reverse_build_order ${build_order})
  list(REVERSE reverse_build_order)

  set(known_pkgs "")
  foreach(pkg ${reverse_build_order})
    if (${pkg} IN_LIST found_pkgs)
      list(REMOVE_ITEM found_pkgs ${pkg})
      set(known_pkgs ${pkg} ${known_pkgs})
    endif()
  endforeach()

  # Warn the user that the build order of some package is not known
  foreach(pkg ${found_pkgs})
    message(WARNING "Package \"${pkg}\" not provided to the daq_add_subpackages function in ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt. ${pkg} will only be built after the provided packages are built. There's no guarantee this is the correct order; if you know where ${pkg} should be in the dependency hierarchy add it to its appropriate place in the list of packages provided to daq_add_subpackages.")
  endforeach()
  
  set(pkgs ${known_pkgs} ${found_pkgs})
  message(STATUS "Package build order: ${pkgs}")

  foreach (pkg ${pkgs})
    message(STATUS "Building ${pkg}")
    daq_topproj_setpkg_gnudirs(${pkg})
    add_subdirectory(${pkg})
  endforeach()

  daq_topproj_restore_gnudirs()

endmacro()