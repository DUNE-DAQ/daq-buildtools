#------------------------------------------------------------------------------

HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)
scriptname=$(basename $(readlink -f ${BASH_SOURCE}))

source ${HERE}/dbt-setup-constants.sh

CUSTOM_BASEPATH=""
SHOW_RELEASE_LIST=false
NIGHTLY=false
BASETYPE='frozen'
DEFAULT_BUILD_TYPE=RelWithDebInfo

options=$(getopt -o 'hnlr:b:' -l ',help,nightly,list,release-path:,base-release:' -- "$@") || return 10
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
        (-b|--base-release)
            BASETYPE=$2
            shift 2;;
        (-h|--help)
            cat << EOU
Usage
-----

To setup a new running environment for a DAQ release:
      
    ${scriptname} [-r/--release-path <path to release area>] [-n/--nightly] [-b/--base-release <frozen, nightly, candidate>] <dunedaq-release>

To list the available DUNE DAQ releases:

    ${scriptname} -l/--list [-n/--nightly] [-b/--base-release <frozen, nightly, candidate>] [-r/--release-path <path to release area>]

Arguments and options:

    dunedaq-release: is the name of the release the running environment will be based on (e.g. dunedaq-v2.0.0)
    -n/--nightly: switch to nightly releases, shortcut for "-b/--base-release nightly"
    -b/--base-release: base release type, choosing from ['frozen', 'nighlty', 'candidate'], default is 'frozen'.
    -l/--list: show the list of available releases
    -r/--release-path: is the path to the release archive (defaults to either $PROD_BASEPATH (frozen) or $NIGHTLY_BASEPATH (nightly))

EOU
            return 0;;           # error
        (--)  shift; break;;
        (*) 
            echo "ERROR $@"  
            return 1;;           # error
    esac
done


if [[ ! -z "${CUSTOM_BASEPATH}" ]]; then
    export SPACK_RELEASES_DIR="${CUSTOM_BASEPATH}"
else
    if [ "${NIGHTLY}" = true ]; then
        BASETYPE='nightly'
    fi
    if [ "${BASETYPE}" == 'frozen' ]; then
        export SPACK_RELEASES_DIR="${PROD_BASEPATH}"
    elif [ "${BASETYPE}" = 'nightly' ]; then
        export SPACK_RELEASES_DIR="${NIGHTLY_BASEPATH}"
    elif [ "${BASETYPE}" = 'candidate' ]; then
        export SPACK_RELEASES_DIR="${CANDIDATE_RELEASE_BASEPATH}"
    else
        error "Wrong option for -b/--base-release, please choose from [frozen, nightly, candidate]."
    fi
fi

ARGS=("$@")

source ${HERE}/dbt-setup-tools.sh

if [[ ! -e $SPACK_RELEASES_DIR ]]; then
    error "Directory \"$SPACK_RELEASES_DIR\" does not appear to exist; exiting..."
    return 10
fi


if [[ "${SHOW_RELEASE_LIST}" == true ]]; then
    list_releases $SPACK_RELEASES_DIR
    return 0;
fi

if [[ ${#ARGS[@]} -eq 0 ]]; then 
    error "Wrong number of arguments. Run '${scriptname} -h' for more information." 
    return 11 
fi

RELEASE_TAG=${ARGS[0]}
RELEASE_PATH=$(realpath -m "${SPACK_RELEASES_DIR}/${RELEASE_TAG}")
export SPACK_RELEASE=$( echo $RELEASE_PATH | sed -r 's!.*/([^/]+)/?$!\1!' )

test ! "$SPACK_RELEASE" == "$RELEASE_TAG"  && echo "Release \"$RELEASE_TAG\" requested; interpreting this as release \"$SPACK_RELEASE\""

if [[ ! -d ${RELEASE_PATH} ]]; then 
    error  "Release path '${RELEASE_PATH}' does not exist. Note that you need to pass \"-n\" for a nightly build. Exiting..." 
    return 11
fi

if [[ -n ${DBT_WORKAREA_ENV_SCRIPT_SOURCED:-} ]]; then
    error "$( cat<<EOF

It appears you're trying to run this script from an environment
where a work area's been set up.  You'll want to run this
from a clean shell. Exiting...     

EOF
)"
    return 12
fi

if [[ -n ${DBT_SETUP_RELEASE_SCRIPT_SOURCED:-} ]]; then
    error "$( cat<<EOF

It appears a release environment was set up prior to you running this script ($RELEASE_TAG).  
You'll want to run this from a clean shell. Exiting...     

EOF
)"
    return 12
fi

spack_setup_env
retval=$?
if [[ "$retval" != "0" ]]; then
    error "Problem setting up the spack environment"
    return $retval
fi

spack_load_target_package dunedaq
retval=$?
if [[ "$retval" != "0" ]]; then
    error "Failed to load spack target package. Returning..." 
    return $retval
fi

if [[ "$VIRTUAL_ENV" != "" ]]; then
    the_activated_env=$( pip -V  | sed -r 's!\pip [0-9\.]+ from (.*)/lib/python[0-9\.]+/site-packages/pip .*!\1!' )
    if [[ $the_activated_env != "${DBT_AREA_ROOT}/${DBT_VENV}" ]]; then
	error "$( cat<<EOF

A python environment outside this work area has already been activated: 
${the_activated_env}
If you understand why this is the case and wish to deactivate it, you can
do so by running "deactivate", then try this script again. Exiting...
EOF
)"
	spack unload $target_package
	return 7
    fi
fi


source ${RELEASE_PATH}/${DBT_VENV}/bin/activate

export PYTHONPYCACHEPREFIX=`mktemp -d -t ${SPACK_RELEASE}-XXXX`

export DBT_PACKAGE_SETUP_DONE=1
export DBT_SETUP_RELEASE_SCRIPT_SOURCED=1

echo -e "${COL_GREEN}This script has been sourced successfully${COL_RESET}"
echo

