#!/usr/bin/env bash

# set -o errexit
# set -o nounset
# set -o pipefail

function print_usage() {
                cat << EOU
Usage
-----

To create a new DUNE DAQ development area:
      
    $( basename $0 ) <dunedaq-release>  -r/--release-path <path to release area>

To list the available DUNE DAQ releases:

    $( basename $0 ) --list

Arguments and options:

    dunedaq-release: is the name of the release the new work area will be based on (e.g. dunedaq-v2.0.0)
    -l/--list: show the list of available releases
    -r/--release-path: is the path to the release archive (RELEASE_BASEPATH var; default: /cvmfs/dune.opensciencegrid.org/dunedaq/DUNE/releases)

EOU
}


EMPTY_DIR_CHECK=true
RELEASE_BASEPATH="/cvmfs/dune.opensciencegrid.org/dunedaq/DUNE/releases"
BASEDIR=$PWD
SHOW_RELEASE_LIST=false

# Define usage function here

#####################################################################
# Load DBT common constants
source ${DBT_ROOT}/scripts/dbt-setup-tools.sh

# This is a horrible lash-up and should be replaced with a proper manifest file or equivalent.
# UPS_PKGLIST="${DBT_AREA_FILE:1}.sh"
UPS_PKGLIST="${DBT_AREA_FILE}.sh"
PY_PKGLIST="pyvenv_requirements.txt"
DAQ_BUILDORDER_PKGLIST="dbt-build-order.cmake"

# We use "$@" instead of $* to preserve argument-boundary information
options=$(getopt -o 'hlr:' -l 'help,list,release-base-path:' -- "$@") || exit
eval "set -- $options"

while true; do
    case $1 in
        (-l|--list)
            # List available releases
            SHOW_RELEASE_LIST=true
            shift;;
        (-r|--release-path)
            RELEASE_BASEPATH=$2
            shift 2;;
        (-h|--help)
            print_usage
            exit 0;;
        (--)  shift; break;;
        (*) 
            echo "ERROR $@"  
            exit 1;;           # error
    esac
done

ARGS=("$@")

if [[ "${SHOW_RELEASE_LIST}" == true ]]; then
    list_releases
    exit 0;
fi

test ${#ARGS[@]} -eq 1 || error "Wrong number of arguments. Try '$( basename $0 ) -h' for more information." 

RELEASE=${ARGS[0]}
RELEASE_PATH=$(realpath -m "${RELEASE_BASEPATH}/${RELEASE}")

test -d ${RELEASE_PATH} || error  "Release path '${RELEASE_PATH}' does not exist. Exiting..."

if [[ -n ${DBT_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED:-} ]]; then
    error "$( cat<<EOF

It appears you're trying to run this script from an environment
where another development area's been set up.  You'll want to run this
from a clean shell. Exiting...     

EOF
)"
fi

starttime_d=$( date )
starttime_s=$( date +%s )

BUILDDIR=$BASEDIR/build
LOGDIR=$BASEDIR/log
SRCDIR=$BASEDIR/sourcecode

export USER=${USER:-$(whoami)}
export HOSTNAME=${HOSTNAME:-$(hostname)}

if [[ -z $USER || -z $HOSTNAME ]]; then
    error "Problem getting one or both of the environment variables \$USER and \$HOSTNAME. Exiting..." 
fi

if $EMPTY_DIR_CHECK && [[ -n $( ls -a1 | grep -E -v "^\.\.?$" ) ]]; then

error "$( cat <<EOF

There appear to be files in $BASEDIR besides this script 
(run "ls -a1" to see this); this script should only be run in a clean
directory. Exiting...

EOF
)"

elif ! $EMPTY_DIR_CHECK ; then

    cat<<EOF >&2

WARNING: The check for whether any files besides this script exist in
its directory has been switched off. This may mean assumptions the
script makes are violated, resulting in undesired behavior.

EOF

    sleep 5

fi

mkdir -p $BUILDDIR
mkdir -p $LOGDIR
mkdir -p $SRCDIR

cd $SRCDIR

superproject_cmakeliststxt=${DBT_ROOT}/configs/CMakeLists.txt
cp ${superproject_cmakeliststxt#$SRCDIR/} $SRCDIR
test $? -eq 0 || error "There was a problem copying \"$superproject_cmakeliststxt\" to $SRCDIR. Exiting..."

superproject_graphvizcmake=${DBT_ROOT}/configs/CMakeGraphVizOptions.cmake
cp ${superproject_graphvizcmake#$SRCDIR/} $SRCDIR
test $? -eq 0 || error "There was a problem copying \"$superproject_graphvizcmake\" to $SRCDIR. Exiting..."

cp ${RELEASE_PATH}/${DAQ_BUILDORDER_PKGLIST} $SRCDIR
test $? -eq 0 || error "There was a problem copying \"$superproject_buildorder\" to $SRCDIR. Exiting..."

# Create the daq area signature file
cp ${RELEASE_PATH}/${UPS_PKGLIST} $BASEDIR/${DBT_AREA_FILE}
test $? -eq 0 || error "There was a problem copying over the daq area signature file. Exiting..." 


echo "Setting up the Python subsystem"
${DBT_ROOT}/scripts/dbt-create-pyvenv.sh ${RELEASE_PATH}/${PY_PKGLIST}

test $? -eq 0 || error "Call to create_pyvenv.sh returned nonzero. Exiting..."

endtime_d=$( date )
endtime_s=$( date +%s )

echo
echo "Total time to run "$( basename $0)": "$(( endtime_s - starttime_s ))" seconds"
echo "Start time: $starttime_d"
echo "End time:   $endtime_d"
echo
echo "See https://github.com/DUNE-DAQ/appfwk/wiki/Compiling-and-running for build instructions"
echo
echo "Script completed successfully"
echo
exit 0

