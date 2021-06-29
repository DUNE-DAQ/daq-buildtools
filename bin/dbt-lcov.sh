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

       
  COL_YELLOW="\e[33m"
  COL_RESET="\e[0m"
  COL_RED="\e[31m"
  echo
  echo
  echo 

  package_list=$( find -L build -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles )

  for pkgname in $package_list ; do

    testdirs=$( find -L $pkgname/test -type d \( -name "apps" -o -name "scripts" \) -not -regex ".*CMakeFiles.*" )

    if [[ -z $testdirs ]]; then
      echo
      echo -e "${COL_RED}No test applications or scripts for $pkgname${COL_RESET}"
      echo
      continue
    fi

    num_tests=0

    for testdir in $testdirs; do
      echo
      echo
      echo "RUNNING TESTS IN $testdir"
      echo "======================================================================"
      for atest in $testdir/* ; do
        if [[ -x $atest ]]; then
          echo
          echo -e "${COL_YELLOW}Start of test \"$atest\"${COL_RESET}"
          $atest
          echo -e "${COL_YELLOW}End of test \"$atest\"${COL_RESET}"
          num_tests=$((num_tests + 1))
        fi
      done

    done

    echo 
    echo -e "${COL_YELLOW}Testing complete for package \"$pkgname\". Ran $num_tests tests.${COL_RESET}"
  done
     

lcov -d . --capture --output-file dunedaq.info
lcov -a dunedaq.base -a dunedaq.info --output-file dunedaq.total
lcov --remove dunedaq.total '*/products/*' '/usr/include/*' '/cvmfs/*' "$DBT_AREA_ROOT/build/*" --output-file dunedaq.info.cleaned
genhtml --demangle-cpp -o coverage dunedaq.info.cleaned
#genhtml -o coverage dunedaq.info
