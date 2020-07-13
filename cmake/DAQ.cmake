

macro(daq_setup_environment)

  set(CMAKE_CXX_STANDARD 17)
  set(CMAKE_CXX_EXTENSIONS OFF)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)

  set(BUILD_SHARED_LIBS ON)

  # Directories should always be added *before* the current path
  set(CMAKE_INCLUDE_DIRECTORIES_PROJECT_BEFORE ON)
  include_directories( ${CMAKE_SOURCE_DIR}/include )

  # Needed for clang-tidy (called by our linters) to work
  set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

  add_compile_options( -g -pedantic -Wall -Wextra )

  enable_testing()

endmacro()


function( point_build_to output_dir )

  set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${PROJECT_NAME}/${output_dir} PARENT_SCOPE)
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${PROJECT_NAME}/${output_dir} PARENT_SCOPE)
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${PROJECT_NAME}/${output_dir} PARENT_SCOPE)

endfunction()

function(add_unit_test testname)

  add_executable( ${testname} unittest/${testname}.cxx )
  target_link_libraries( ${testname} ${DAQ_LIBRARIES_UNIVERSAL_EXE} ${DAQ_LIBRARIES_PACKAGE}  ${Boost_UNIT_TEST_FRAMEWORK_LIBRARY} ${ARGN} )
  target_include_directories( ${testname} SYSTEM PRIVATE ${DAQ_INCLUDES_UNIVERSAL})
  target_compile_definitions(${testname} PRIVATE "BOOST_TEST_DYN_LINK=1")
  add_test(NAME ${testname} COMMAND ${testname})

endfunction()

