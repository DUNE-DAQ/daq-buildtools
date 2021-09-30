#!/usr/bin/env bash

# set -o errexit
# set -o nounset
# set -o pipefail

function print_usage() {
                cat << EOU
Usage
-----

To create a new DUNE DAQ development area:
      
    $( basename $0 ) [-r/--release-path <path to release area>] <dunedaq-release> <target directory>

To list the available DUNE DAQ releases:

    $( basename $0 ) -l/--list [-r/--release-path <path to release area>]

Arguments and options:

    dunedaq-release: is the name of the release the new work area will be based on (e.g. dunedaq-v2.0.0)
    -n/--nightly: switch to nightly releases
    -l/--list: show the list of available releases
    -r/--release-path: is the path to the release archive (RELEASE_BASEPATH var; default: /cvmfs/dunedaq.opensciencegrid.org/releases)

EOU
}


EMPTY_DIR_CHECK=true
PROD_BASEPATH="/cvmfs/dunedaq.opensciencegrid.org/releases"
NIGHTLY_BASEPATH="/cvmfs/dunedaq-development.opensciencegrid.org/nightly"
CUSTOM_BASEPATH=""
# TARGETDIR=""
SHOW_RELEASE_LIST=false
NIGHTLY=false

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
options=$(getopt -o 'hnlr:' -l ',help,nightly,list,release-base-path:' -- "$@") || exit
eval "set -- $options"

while true; do
    case $1 in
        (-n|--nightly)
            NIGHTLY=true
            shift;;
        (-l|--list)
            # List available releases
            SHOW_RELEASE_LIST=true
            shift;;
        (-r|--release-path)
            CUSTOM_BASEPATH=$2
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

if [[ ! -z "${CUSTOM_BASEPATH}" ]]; then
    RELEASE_BASEPATH="${CUSTOM_BASEPATH}"
elif [ "${NIGHTLY}" = false ]; then
    RELEASE_BASEPATH="${PROD_BASEPATH}"
else
    RELEASE_BASEPATH="${NIGHTLY_BASEPATH}"
fi

if [[ "${SHOW_RELEASE_LIST}" == true ]]; then
    list_releases
    exit 0;
fi

test ${#ARGS[@]} -eq 2 || error "Wrong number of arguments. Run '$( basename $0 ) -h' for more information." 


RELEASE=${ARGS[0]}
RELEASE_PATH=$(realpath -m "${RELEASE_BASEPATH}/${RELEASE}")
TARGETDIR=${ARGS[1]}

test -d ${RELEASE_PATH} || error  "Release path '${RELEASE_PATH}' does not exist. Note that you need to pass \"-n\" for a nightly build. Exiting..."

if [[ -n ${DBT_WORKAREA_ENV_SCRIPT_SOURCED:-} ]]; then
    error "$( cat<<EOF

It appears you're trying to run this script from an environment
where another development area's been set up.  You'll want to run this
from a clean shell. Exiting...     

EOF
)"
fi

starttime_d=$( date )
starttime_s=$( date +%s )

if [ ! -d "${TARGETDIR}" ] ; then
    mkdir -p ${TARGETDIR}
fi

TARGETDIR=$(cd $TARGETDIR >/dev/null && pwd)  # redirect cd to /dev/null b/c CDPATH may be used

cd ${TARGETDIR}

BUILDDIR=${TARGETDIR}/build
LOGDIR=${TARGETDIR}/log
SRCDIR=${TARGETDIR}/sourcecode

export USER=${USER:-$(whoami)}
export HOSTNAME=${HOSTNAME:-$(hostname)}

if [[ -z $USER || -z $HOSTNAME ]]; then
    error "Problem getting one or both of the environment variables \$USER and \$HOSTNAME. Exiting..." 
fi

if $EMPTY_DIR_CHECK && [[ -n $( ls -a1 $TARGETDIR | grep -E -v "^\.\.?$" ) ]]; then

error "$( cat <<EOF

There appear to be files in $TARGETDIR besides this script 
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
cp ${RELEASE_PATH}/${UPS_PKGLIST} $TARGETDIR/${DBT_AREA_FILE}
test $? -eq 0 || error "There was a problem copying over the daq area signature file. Exiting..." 

# Create the daq area signature file
dbt_setup_env_script=${DBT_ROOT}/env.sh
ln -s ${dbt_setup_env_script} $TARGETDIR/dbt-env.sh
test $? -eq 0 || error "There was a problem linking the daq-buildtools setup file. Exiting..."

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
echo "See https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-buildtools/index.html for build instructions"
echo
echo "Script completed successfully"
echo
exit 0

