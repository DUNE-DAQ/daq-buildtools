
COL_RESET="\e[0m"
COL_RED="\e[1;31m"
COL_GREEN="\e[1;32m"

source ${DBT_ROOT}/scripts/dbt-setup-tools.sh
LOGDIR=${DBT_AREA_ROOT}/log
test_log=$LOGDIR/unit_tests_$( date | sed -r 's/[: ]+/_/g' ).log

function echo_success() {
  echo -e "${COL_GREEN}SUCCESS${COL_RESET}"
}

function echo_failure() {
  echo -e "${COL_RED}FAILED${COL_RESET}"
}

function echo_dots() {
  ndots=$1
  ii=0
  while [ $ii -lt $ndots ];do
    echo -n "."
    ii=$(($ii + 1))
  done
}

function check_unit_tests() {
  dbt-build.py >/dev/null 2>&1 || error "DAQ build FAILED, exiting"
  pushd $DBT_AREA_ROOT/build >/dev/null
  echo
  echo
  package_list=$( find -L . -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles )
  tests=
  for pkgname in $package_list ; do
    pkgtests=`find $pkgname/unittest -type f -exec readlink -f {} \; 2>/dev/null`
    if [ ${#pkgtests} -gt 0 ]; then
      tests="${tests} ${pkgtests}"
    fi
  done

  maxwidth=0
  for unittest in $tests;do
    if [ ${#unittest} -gt $maxwidth ]; then
      maxwidth=${#unittest}
    fi
  done

  for unittest in $tests;do 
    echo -n "$unittest"

    echo_dots $((${maxwidth} - ${#unittest}+2))

    $unittest >>$test_log 2>&1 && echo_success || echo_failure
  done
  popd >/dev/null
     
  echo
  echo "Test results are saved in $test_log"
  echo
}
check_unit_tests