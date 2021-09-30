#!/bin/bash
# set -o errexit 
set -o nounset 
# set -o pipefail

function print_usage() {
                cat << EOU
Usage
-----

      "./$( basename $0 )" [-c/--clean] [-d/--debug] [-j<n>/--jobs <number parallel build jobs>] [--unittest(=<optional package name>)] [--lint(=<optional package name)>] [-v/--cpp-verbose] [-h/--help]
      
        -c/--clean means the contents of ./build are deleted and CMake's config+generate+build stages are run
        -d/--debug means you want to build your software with optimizations off and debugging info on
        -j/--jobs means you want to specify the number of jobs used by cmake to build the project
        --unittest means that unit test executables found in ./build/<optional package name>/unittest are run, or all unit tests in ./build/*/unittest are run if no package name is provided
        --lint means you check for deviations in ./sourcecode/<optional package name> from the DUNE style guide, https://dune-daq-sw.readthedocs.io/en/latest/packages/styleguide/, or deviations in all local repos if no package name is provided
        -v/--cpp-verbose means that you want verbose output from the compiler
        --cmake-msg-lvl setting "CMAKE_MESSAGE_LOG_LEVEL", default is "NOTICE", choices are ERROR|WARNING|NOTICE|STATUS|VERBOSE|DEBUG|TRACE.
        --cmake-trace enable cmake tracing
        --cmake-graphviz geneates a target dependency graph

    
    All arguments are optional. With no arguments, CMake will typically just run 
    build, unless build/CMakeCache.txt is missing    
    
EOU
}

HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Import find_work_area function
source ${DBT_ROOT}/scripts/dbt-setup-tools.sh

BASEDIR=$(find_work_area)
test -n ${BASEDIR:-} || error "DBT Work area directory not found. Exiting..." 

BUILDDIR=${BASEDIR}/build
LOGDIR=${BASEDIR}/log
SRCDIR=${BASEDIR}/sourcecode
#########################################################################################

run_tests=false
package_to_test=
clean_build=false 
debug_build=false
cpp_verbose=false
cmake_msg_level="NOTICE"
cmake_trace=false
cmake_graphviz=false
declare -i n_jobs=0
lint=false
package_to_lint=

# args=("$@")

# declare -i i_arg=0

declare -a ARGS=()

options=$(getopt -o 'hcdvj:i' -l ',help,clean,debug,unittest::,lint::,cpp-verbose,jobs:,install,cmake-msg-lvl:,cmake-trace,cmake-graphviz' -- "$@") || exit
eval "set -- $options"

while true; do
    case $1 in
        (-h|--help)
            print_usage
            exit 0;;
        (-c|--clean)
            clean_build=true
            shift;;
        (-d|--debug)
            debug_build=true
            shift;;
        (-v|--cpp-verbose)
            cpp_verbose=true
            shift;;
        (-j|--jobs)
            n_jobs=$2
            shift 2;;
        (--unittest)
            run_tests=true
            package_to_test=$2
            shift 2;;
        (--lint)
            lint=true
            package_to_lint=$2
            shift 2;;
        (-i|--install)
	    error "Use of -i/--install is deprecated as installation always occurs now; run with \" --help\" to see valid options. Exiting..."
            shift;;
        (--cmake-msg-lvl)
            cmake_msg_level=$2
            shift 2;;
        (--cmake-trace)
            cmake_trace=true
            shift;;
        (--cmake-graphviz)
            cmake_graphviz=true
            shift;;      
        (--)  shift; break;;
        (*) 
            echo "ERROR $@"  
            exit 1;;           # error
    esac
done

ARGS=("$@")

if false; then
  echo "- run_tests '$run_tests'"
  echo "- package_to_test '$package_to_test'"
  echo "- clean_build '$clean_build'"
  echo "- debug_build '$debug_build'"
  echo "- cpp_verbose '$cpp_verbose'"
  echo "- cmake_msg_level '$cmake_msg_level'"
  echo "- cmake_trace '$cmake_trace'"
  echo "- cmake_graphviz '$cmake_graphviz'"
  echo "- n_jobs '$n_jobs'"
  echo "- lint '$lint'"
  echo "- package_to_lint '$package_to_lint'"

  echo ${ARGS[@]}
fi

if [[ ! -z "${ARGS:-}" ]]; then
    error "Unknown arguments '${ARGS[@]}' provided; run with \" --help\" to see valid options. Exiting..."  
fi

if [[ -z ${DBT_WORKAREA_ENV_SCRIPT_SOURCED:-} ]]; then
 
error "$( cat<<EOF

It appears you haven't yet executed "dbt-workarea-env"; please do so before running this 
script. Exiting...

EOF
)"
fi

test -d $BUILDDIR || error "Expected build directory \"$BUILDDIR\" not found. Exiting..." 
cd $BUILDDIR

if ${clean_build}; then 
  
   # Want to be damn sure of we're in the right directory, rm -rf * is no joke...

   if  [[ $( echo $PWD | sed -r 's!.*/(.*)!\1!' ) =~ ^build/*$ ]]; then
     echo "Clean build requested, will delete all the contents of build directory \"$PWD\"."
     echo "If you wish to abort, you have 5 seconds to hit Ctrl-c"
     sleep 5
     rm -rf *
   else
       error "$( cat <<EOF

You requested a clean build, but this script thinks that $BUILDDIR isn't 
the build directory. Please contact John Freeman at jcfree@fnal.gov and notify him of this message.

EOF
)"
   fi
fi


build_log=$LOGDIR/build_attempt_$( date | sed -r 's/[: ]+/_/g' ).log

CMAKE="cmake"

if $cmake_trace; then
  CMAKE="${CMAKE} --trace"
fi


# We usually only need to explicitly run the CMake configure+generate
# makefiles stages when it hasn't already been successfully run;
# otherwise we can skip to the compilation. We use the existence of
# CMakeCache.txt to tell us whether this has happened; notice that it
# gets renamed if it's produced but there's a failure.

if ! [ -e CMakeCache.txt ]; then

  generator_arg=
  if [ "x${SETUP_NINJA}" != "x" ]; then
    generator_arg="-G Ninja"
  fi


  starttime_cfggen_d=$( date )
  starttime_cfggen_s=$( date +%s )

  # Will use $cmd if needed for error message
  cmd="${CMAKE} -DCMAKE_MESSAGE_LOG_LEVEL=${cmake_msg_level} -DMOO_CMD=$(which moo) -DDBT_ROOT=${DBT_ROOT} -DDBT_DEBUG=${debug_build} -DCMAKE_INSTALL_PREFIX=$DBT_INSTALL_DIR ${generator_arg} $SRCDIR" 

  echo "Executing '$cmd'"
  pytee.py -l $build_log -- ${cmd}
  retval=$?  # Captures the return value of cmake, not tee
  endtime_cfggen_d=$( date )
  endtime_cfggen_s=$( date +%s )

  if [[ "$retval" == "0" ]]; then

    sed -i -r '1 i\# If you want to add or edit a variable, be aware that the config+generate stage is skipped in $build_script if this file exists' $BUILDDIR/CMakeCache.txt
    sed -i -r '2 i\# Consider setting variables you want cached with the CACHE option in the relevant CMakeLists.txt file instead' $BUILDDIR/CMakeCache.txt

    cfggentime=$(( endtime_cfggen_s - starttime_cfggen_s ))
    echo "CMake's config+generate stages took $cfggentime seconds"
    echo "Start time: $starttime_cfggen_d"
    echo "End time:   $endtime_cfggen_d"

  else

    mv -f CMakeCache.txt CMakeCache.txt.most_recent_failure

    error "$( cat <<EOF 

This script ran into a problem running 

$cmd 

from $BUILDDIR (i.e., CMake's config+generate stages). 
Scroll up for details or look at the build log via 

less -R ${build_log}

Exiting...

EOF
    )"

  exit 40
  fi

else

  echo "The config+generate stage was skipped as CMakeCache.txt was already found in $BUILDDIR"

fi # !-e CMakeCache.txt

if ${cmake_graphviz}; then
  cmd="${CMAKE} --graphviz=graphviz/targets.dot ."
  ${cmd}
  exit $?
fi

nprocs=$( grep -E "^processor\s*:\s*[0-9]+" /proc/cpuinfo  | wc -l )
nprocs_argument=""

if (( $n_jobs <= 0)); then 
  if [[ -n $nprocs && $nprocs =~ ^[0-9]+$ ]]; then
    echo "This script believes you have $nprocs processors available on this system, and will use as many of them as it can"
    nprocs_argument=" -j $nprocs"
  else
    echo "Unable to determine the number of processors available, will not pass the \"-j <nprocs>\" argument on to the build stage" >&2
  fi
else
  nprocs_argument=" -j ${n_jobs}"
fi

starttime_build_d=$( date )
starttime_build_s=$( date +%s )

build_options=""
if $cpp_verbose; then
  build_options="${build_options} --verbose"
fi

if ! $cmake_trace ; then
  build_options="${build_options} $nprocs_argument"
fi

# Will use $cmd if needed for error message
cmd="${CMAKE} --build . $build_options"
echo "Executing '$cmd'"
pytee.py -l $build_log -- ${cmd}

retval=$?  # Captures the return value of cmake --build, not tee
endtime_build_d=$( date )
endtime_build_s=$( date +%s )

if [[ "$retval" == "0" ]]; then

  buildtime=$((endtime_build_s - starttime_build_s))

else

  error "$( cat<<EOF 

This script ran into a problem running 

$cmd 

from $BUILDDIR (i.e.,
CMake's build stage). Scroll up for details or look at the build log via 

less -R ${build_log}

Exiting...

EOF
  )"

  exit 40
fi

num_estimated_warnings=$( grep "warning: " ${build_log} | wc -l )

echo

if [[ -n ${cfggentime:-} ]]; then
  echo
  echo "config+generate stage took $cfggentime seconds"
  echo "Start time: $starttime_cfggen_d"
  echo "End time:   $endtime_cfggen_d"
  echo
else
  echo "config+generate stage was skipped"
fi
echo "build stage took $buildtime seconds"
echo "Start time: $starttime_build_d"
echo "End time:   $endtime_build_d"
echo
echo "Output of build contains an estimated $num_estimated_warnings warnings, and can be viewed later via: "
echo 
echo "   less -R ${build_log}"
echo

if [[ -n ${cfggentime:-} ]]; then
  echo "CMake's config+generate+build stages all completed successfully"
  echo
else
  echo "CMake's build stage completed successfully"
fi


cd $BUILDDIR

if [[ -n $DBT_INSTALL_DIR && ! $DBT_INSTALL_DIR =~ ^/?$ ]]; then
   rm -rf $DBT_INSTALL_DIR/*
else
   error "\$DBT_INSTALL_DIR is not properly defined, which would result in the deletion of the entire contents of this system if it weren't for this check!!!"
fi

# Will use $cmd if needed for error message
cmd="cmake --build . --target install -- $nprocs_argument"
${cmd}
 
if [[ "$?" == "0" ]]; then
  echo 
  echo "Installation complete."
  echo "This implies your code successfully compiled before installation; you can either scroll up or run \"less -R $build_log\" to see build results"
else
  error "Installation failed. There was a problem running \"$cmd\". Exiting.."
fi

if $run_tests ; then
  COL_YELLOW="\e[33m"
  COL_RESET="\e[0m"
  COL_RED="\e[31m"
  echo 
  echo
  echo
  echo 
  test_log=$LOGDIR/unit_tests_$( date | sed -r 's/[: ]+/_/g' ).log

  cd $BUILDDIR

  if [[ -z $package_to_test ]]; then
    package_list=$( find -L . -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles )
  else
    package_list=$package_to_test
  fi

  for pkgname in $package_list ; do

    unittestdirs=$( find -L $BUILDDIR/$pkgname -type d -name "unittest" -not -regex ".*CMakeFiles.*" )

    if [[ -z $unittestdirs ]]; then
      echo
      echo -e "${COL_RED}No unit tests have been written for $pkgname${COL_RESET}"
      echo
      continue
    fi

    if [[ -z ${BOOST_TEST_LOG_LEVEL:-} ]]; then
       export BOOST_TEST_LOG_LEVEL=all
    fi

    num_unit_tests=0

    for unittestdir in $unittestdirs; do
      echo
      echo
      echo "RUNNING UNIT TESTS IN $unittestdir"
      echo "======================================================================"
      for unittest in $unittestdir/* ; do
        if [[ -x $unittest ]]; then
          echo
          echo -e "${COL_YELLOW}Start of unit test suite \"$unittest\"${COL_RESET}" |& tee -a $test_log
          $unittest |& tee -a $test_log
          echo -e "${COL_YELLOW}End of unit test suite \"$unittest\"${COL_RESET}" |& tee -a $test_log
          num_unit_tests=$((num_unit_tests + 1))
        fi
      done

    done

    echo 
    echo -e "${COL_YELLOW}Testing complete for package \"$pkgname\". Ran $num_unit_tests unit test suites.${COL_RESET}"
  done
     
     echo
     echo "Test results are saved in $test_log"
     echo
fi

if $lint; then
  cd $BASEDIR

  lint_log=$LOGDIR/linting_$( date | sed -r 's/[: ]+/_/g' ).log

  if [[ ! -d ./styleguide ]]; then
    echo "Cloning styleguide into $BASEDIR so linting can be applied"
    git clone https://github.com/DUNE-DAQ/styleguide.git
  fi

  if [[ -z $package_to_lint ]]; then
    package_list=$( find build -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles )
  else
    package_list=$package_to_lint
  fi

  for pkgdir in $package_list; do
    pkgname=$( echo $pkgdir | sed -r 's!.*/(.*)!\1!' )
    ./styleguide/cpplint/dune-cpp-style-check.sh build sourcecode/$pkgname |& tee -a $lint_log
  done

  echo
  echo "For more on our coding guidelines, see https://dune-daq-sw.readthedocs.io/en/latest/packages/styleguide/"
  echo
fi


