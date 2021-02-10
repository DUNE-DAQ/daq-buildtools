#!/bin/bash

# lcov has to be installed manually -- 
# https://github.com/linux-test-project/lcov/releases/tag/v1.15
# lcov-1.15-1.noarch.rpm

# Upon success, the output will be in the "coverage" directory
# Load the file coverage/index.html in your browser to view the coverage report

# The following should be in CMakeLists.txt at or above the level of the code
# for which coverage information should be collected 
# (e.g. sourcecode/CMakeLists.txt):
#
# SET(GCC_COVERAGE_COMPILE_FLAGS "-O0 -g -fprofile-arcs -ftest-coverage -fno-inline")
# SET(GCC_COVERAGE_LINK_FLAGS    "-lgcov")
#
# SET(CMAKE_CXX_FLAGS  "${CMAKE_CXX_FLAGS} ${GCC_COVERAGE_COMPILE_FLAGS}")
# SET(CMAKE_EXE_LINKER_FLAGS  "${CMAKE_EXE_LINKER_FLAGS} ${GCC_COVERAGE_LINK_FLAGS}")
#

# Coverage requires at least GCC v9_3_0 to work properly
if [[ "${GCC_VERSION}" =~ v[78]_ ]]; then
  unsetup gcc
  setup gcc v9_3_0
fi

dbt-build.sh --clean

lcov -d . --zerocounters
lcov -c -i -d . -o dunedaq.base

# RUN THE TESTS
dbt-build.sh --unittest

lcov -d . --capture --output-file dunedaq.info
lcov -a dunedaq.base -a dunedaq.info --output-file dunedaq.total
lcov --remove dunedaq.total */products/* /usr/include/curl/* --output-file dunedaq.info.cleaned
genhtml -o coverage dunedaq.info.cleaned
#genhtml -o coverage dunedaq.info
