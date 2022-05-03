#!/bin/bash

function print_usage() {
                cat << EOU
Usage
-----

lcov has to be installed manually -- 
https://github.com/linux-test-project/lcov/releases/tag/v1.15
lcov-1.15-1.noarch.rpm

Upon success, the output will be in the "coverage" directory
Load the file coverage/index.html in your browser to view the coverage report

The following should be in CMakeLists.txt at or above the level of the code
for which coverage information should be collected 
(e.g. sourcecode/CMakeLists.txt, above its daq_add_subpackages call):

SET(GCC_COVERAGE_COMPILE_FLAGS "-O0 -g -fprofile-arcs -ftest-coverage -fno-inline")
SET(GCC_COVERAGE_LINK_FLAGS    "-lgcov")

SET(CMAKE_CXX_FLAGS  "\${CMAKE_CXX_FLAGS} \${GCC_COVERAGE_COMPILE_FLAGS}")
SET(CMAKE_EXE_LINKER_FLAGS  "\${CMAKE_EXE_LINKER_FLAGS} \${GCC_COVERAGE_LINK_FLAGS}")

Coverage requires at least GCC v9_3_0 to work properly
    
EOU
}

if [ $# -gt 0 ]; then
  print_usage
  exit 0
fi

source ${DBT_ROOT}/scripts/dbt-setup-tools.sh
LOGDIR=${DBT_AREA_ROOT}/log
lcov_log=$LOGDIR/lcov_report_$( date | sed -r 's/[: ]+/_/g' ).log

lcov_found=`type lcov >/dev/null 2>&1 && echo 0 || echo 1`
if [ $lcov_found -ne 0 ]; then
  echo "lcov executable not found!" >&2
  echo
  print_usage
  exit 1
fi

gccver=`gcc -v 2>&1|grep version|awk '{print $3}'|cut -d. -f1`
if [ $gccver -lt 9 ]; then
  echo "GCC v9 or greater required for proper stats collection! (You have `gcc -v 2>&1|grep version|awk '{print $3}'`)" >&2
  echo
  print_usage
  exit 2
fi

echo "Performing clean build, please wait" |& tee -a $lcov_log
dbt-build --clean >$lcov_log 2>&1 || error "dbt-build --clean returned nonzero; exiting..."
echo "Clean build complete. Setting up LCOV counters" |& tee -a $lcov_log

lcov -d $DBT_AREA_ROOT --zerocounters >>$lcov_log 2>&1 || error "lcov -d $DBT_AREA_ROOT --zerocounters returned nonzero; exiting..."
lcov -c -i -d $DBT_AREA_ROOT -o  $DBT_AREA_ROOT/dunedaq.base >>$lcov_log 2>&1 || error "lcov -c -i -d $DBT_AREA_ROOT -o  $DBT_AREA_ROOT/dunedaq.base returned nonzero; exiting..."

# RUN THE TESTS
dbt-unittest-summary.sh |& tee -a $lcov_log

       
  COL_YELLOW="\e[33m"
  COL_RESET="\e[0m"
  COL_RED="\e[31m"
  echo |& tee -a $lcov_log
  echo |& tee -a $lcov_log
  echo |& tee -a $lcov_log

  package_list=$( find -L  $DBT_INSTALL_DIR -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles )

  for pkgname in $package_list ; do

    testdirs=$( find -L $pkgname/test -type d -name "bin" -not -regex ".*CMakeFiles.*" )

    if [[ -z $testdirs ]]; then
      echo |& tee -a $lcov_log
      echo -e "${COL_RED}No test applications or scripts for $pkgname${COL_RESET}" |& tee -a $lcov_log
      echo |& tee -a $lcov_log
      continue
    fi

    num_tests=0

    for testdir in $testdirs; do
      echo |& tee -a $lcov_log
      echo |& tee -a $lcov_log
      echo "RUNNING TESTS IN $testdir" |& tee -a $lcov_log
      echo "======================================================================" |& tee -a $lcov_log
      for atest in $testdir/* ; do
        if [[ -x $atest ]]; then
          echo |& tee -a $lcov_log
          echo -e "${COL_YELLOW}Start of test \"$atest\"${COL_RESET}" |& tee -a $lcov_log
          $atest |& tee -a $lcov_log
          echo -e "${COL_YELLOW}End of test \"$atest\"${COL_RESET}" |& tee -a $lcov_log
          num_tests=$((num_tests + 1))
        fi
      done

    done

    echo  |& tee -a $lcov_log
    echo -e "${COL_YELLOW}Testing complete for package \"$pkgname\". Ran $num_tests tests.${COL_RESET}" |& tee -a $lcov_log
  done
     
  echo "Collecting coverage results"  |& tee -a $lcov_log
lcov -d  $DBT_AREA_ROOT --capture --output-file  $DBT_AREA_ROOT/dunedaq.info >>$lcov_log 2>&1 || \
error "lcov -d  $DBT_AREA_ROOT --capture --output-file  $DBT_AREA_ROOT/dunedaq.info returned nonzero; exiting..."

lcov -a dunedaq.base -a  $DBT_AREA_ROOT/dunedaq.info --output-file  $DBT_AREA_ROOT/dunedaq.total >>$lcov_log 2>&1 || \
error "lcov -a dunedaq.base -a  $DBT_AREA_ROOT/dunedaq.info --output-file  $DBT_AREA_ROOT/dunedaq.total returned nonzero; exiting..."

lcov --remove  $DBT_AREA_ROOT/dunedaq.total '*/products/*' '/usr/include/*' '/cvmfs/*' "$DBT_AREA_ROOT/build/*" "*/pybindsrc/*" --output-file  $DBT_AREA_ROOT/dunedaq.info.cleaned >>$lcov_log 2>&1 || \
error "lcov --remove  $DBT_AREA_ROOT/dunedaq.total '*/products/*' '/usr/include/*' '/cvmfs/*' "$DBT_AREA_ROOT/build/*" --output-file  $DBT_AREA_ROOT/dunedaq.info.cleaned returned nonzero; exiting..."

  echo "Creationg HTML output"  |& tee -a $lcov_log
genhtml --demangle-cpp -o  $DBT_AREA_ROOT/coverage  $DBT_AREA_ROOT/dunedaq.info.cleaned >>$lcov_log 2>&1 || \
error "genhtml --demangle-cpp -o  $DBT_AREA_ROOT/coverage  $DBT_AREA_ROOT/dunedaq.info.cleaned returned nonzero; exiting..."
#genhtml -o coverage dunedaq.info

echo
echo "Full LCOV output saved in $lcov_log"
echo 
