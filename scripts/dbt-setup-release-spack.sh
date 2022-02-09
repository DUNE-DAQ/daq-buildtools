#------------------------------------------------------------------------------

HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)
scriptname=$(basename $(readlink -f ${BASH_SOURCE}))

CUSTOM_BASEPATH=""
SHOW_RELEASE_LIST=false
NIGHTLY=false
DEFAULT_BUILD_TYPE=RelWithDebInfo

UPS_PKGLIST="${DBT_AREA_FILE}.sh"

options=$(getopt -o 'hnlr:' -l ',help,nightly,list,release-path:' -- "$@") || return 10
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
            cat << EOU
Usage
-----

To setup a new running environement for a DAQ release:
      
    ${scriptname} [-r/--release-path <path to release area>] [-n/--nightly] <dunedaq-release>

To list the available DUNE DAQ releases:

    n{scriptname} -l/--list [-n/--nightly] [-r/--release-path <path to release area>]

Arguments and options:

    dunedaq-release: is the name of the release the running environment will be based on (e.g. dunedaq-v2.0.0)
    -n/--nightly: switch to nightly releases
    -l/--list: show the list of available releases
    -r/--release-path: is the path to the release archive (RELEASE_BASEPATH var; default: /cvmfs/dunedaq.opensciencegrid.org/releases)

EOU
            return 0;;           # error
        (--)  shift; break;;
        (*) 
            echo "ERROR $@"  
            return 1;;           # error
    esac
done

if [[ ${NIGHTLY} == true ]]; then
    error "Nightly builds not yet supported in Spack; returning..."
    return 12
fi

ARGS=("$@")

source ${HERE}/dbt-setup-tools.sh

if [[ ! -z "${CUSTOM_BASEPATH}" ]]; then
    RELEASE_BASEPATH="${CUSTOM_BASEPATH}"
elif [ "${NIGHTLY}" = false ]; then
    RELEASE_BASEPATH="${PROD_BASEPATH}"
else
    RELEASE_BASEPATH="${NIGHTLY_BASEPATH}"
fi

if [[ "${SHOW_RELEASE_LIST}" == true ]]; then
    list_releases
    return 0;
fi

if [[ ${#ARGS[@]} -eq 0 ]]; then 
    error "Wrong number of arguments. Run '${scriptname} -h' for more information." 
    return 11 
fi

RELEASE=${ARGS[0]}
RELEASE_PATH=$(realpath -m "${RELEASE_BASEPATH}/${RELEASE}")

if [[ ! -d ${RELEASE_PATH} ]]; then 
    error  "Release path '${RELEASE_PATH}' does not exist. Note that you need to pass \"-n\" for a nightly build. Exiting..." 
    return 11
fi

if [[ -n ${DBT_WORKAREA_ENV_SCRIPT_SOURCED:-} ]]; then
    error "$( cat<<EOF

It appears you're trying to run this script from an environment
where another development area's been set up.  You'll want to run this
from a clean shell. Exiting...     

EOF
)"
    return 12
fi

if [[ -n ${DBT_SETUP_RELEASE_SCRIPT_SOURCED:-} ]]; then
    error "$( cat<<EOF

It appears you're trying to run this script from an environment
where another running environment been set up.  You'll want to run this
from a clean shell. Exiting...     

EOF
)"
    return 12
fi

# 1. Load the area information from the local area file + get DUNE_DAQ_BASE_RELEASE
source ${RELEASE_PATH}/${UPS_PKGLIST}

if ! [[ $? -eq 0 ]]; then
    error "There was a problem sourcing ${RELEASE_PATH}/${UPS_PKGLIST}. Returning..." 
    return 1
fi

spack_setup_env
spack_load_target_package dune-daqpackages

# Let's use Spack python instead of the python installed in ups

export PYTHON_SPACK_VIRTUALENV=`mktemp -d -t ${RELEASE}-XXXX`
pushd $PYTHON_SPACK_VIRTUALENV >/dev/null

${HERE}/../bin/clonevirtualenv.py ${RELEASE_PATH}/${DBT_VENV} ${DBT_VENV}
test $? -eq 0 || error "Problem creating virtual_env ${RELEASE_PATH}/${DBT_VENV}. Exiting..." 

python_basedir=$( spack find -d -p --loaded dune-daqpackages | sed -r -n "s/^\s*python.*\s+(\S+)$/\1/p" )
if [[ -z $python_basedir || "$python_basedir" == "" ]]; then
    error "Somehow unable to determine the location of Spack-installed python. Exiting..."
fi
	
if [[ ! -e ${PYTHON_SPACK_VIRTUALENV}/${DBT_VENV}/pyvenv.cfg ]]; then
    error "${PYTHON_SPACK_VIRTUALENV}/${DBT_VENV}/pyvenv.cfg expected to exist but doesn't. Exiting..."
fi

sed -i -r 's!^\s*home\s*=.*!home = '${python_basedir}'/bin!' ${PYTHON_SPACK_VIRTUALENV}/${DBT_VENV}/pyvenv.cfg

if [[ ! -L ${PYTHON_SPACK_VIRTUALENV}/${DBT_VENV}/bin/python ]]; then
    error "Expected ${PYTHON_SPACK_VIRTUALENV}/${DBT_VENV}/bin/python linkfile to exist but it doesn't. Exiting..."
fi

if [[ ! -e $python_basedir/bin/python ]]; then
    error "Expected $python_basedir/bin/python to exist but it doesn't. Exiting..."
fi

rm -f ${PYTHON_SPACK_VIRTUALENV}/${DBT_VENV}/bin/python
pushd ${PYTHON_SPACK_VIRTUALENV}/${DBT_VENV}/bin > /dev/null
ln -s $python_basedir/bin/python
popd > /dev/null
popd > /dev/null

source ${PYTHON_SPACK_VIRTUALENV}/${DBT_VENV}/bin/activate

if [[ "$VIRTUAL_ENV" == "" ]]
then
    error "You are already in a virtual env. Please deactivate first. Returning..." 
    return 13
fi

export PYTHONPYCACHEPREFIX=`mktemp -d -t ${RELEASE}-XXXX`

export DBT_PACKAGE_SETUP_DONE=1
export DBT_SETUP_RELEASE_SCRIPT_SOURCED=1

echo -e "${COL_GREEN}This script has been sourced successfully${COL_RESET}"
echo

