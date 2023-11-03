#------------------------------------------------------------------------------



HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)
scriptname=$(basename $(readlink -f ${BASH_SOURCE}))

DBT_PKG_SETS=( devtools systems externals daqpackages )
    
DEFAULT_BUILD_TYPE=RelWithDebInfo

# We use "$@" instead of $* to preserve argument-boundary information
options=$(getopt -o 'hs:' -l 'help, subset:' -- "$@") || return 10
eval "set -- $options"

DBT_PKG_SET="${DBT_PKG_SETS[-1]}"
while true; do
    case $1 in
	(-s|--subset)
            DBT_PKG_SET=$2
            shift 2;;
        (-h|--help)
            cat << EOU
Usage
-----

  ${scriptname} [-h/--help] [-s/--subset [devtools systems externals daqpackages]]

  Sets up the environment of a dbt development area

  Arguments and options:

    -s/--subset: optional set of ups packages to load. [choices: ${DBT_PKG_SETS[@]}] 

    
EOU
            return 0;;           # error
        (--)  shift; break;;
        (*) 
            echo "ERROR $@"  
            return 1;;           # error
    esac
done

source ${HERE}/dbt-setup-tools.sh

export DBT_AREA_ROOT=$(find_work_area)
export SPACK_DISABLE_LOCAL_CONFIG=${DISABLE_USER_SPACK_CONFIG}

if [[ -z $DBT_AREA_ROOT ]]; then
    error "Expected work area directory not found via call to find_work_area. Returning..."
    return 1
else
  echo -e "${COL_BLUE}Work area: '${DBT_AREA_ROOT}'${COL_RESET}\n"
fi

if [[ -e $DBT_AREA_ROOT/dbt-workarea-constants.sh ]]; then
    . $DBT_AREA_ROOT/dbt-workarea-constants.sh 

    if [[ -z $SPACK_RELEASE || -z $SPACK_RELEASES_DIR || -z $DBT_ROOT_WHEN_CREATED ]]; then
	error "$( cat<<EOF

At least one of the following environment variables which should have been set up
by $DBT_AREA_ROOT/dbt-workarea-constants.sh is missing:

SPACK_RELEASE, SPACK_RELEASES_DIR, DBT_ROOT_WHEN_CREATED

Exiting...

EOF
)"
    return 5
    fi

else
    error "Unable to find a \"$DBT_AREA_ROOT/dbt-workarea-constants.sh\" file. Exiting..."
    return 3
fi


SOURCE_DIR="${DBT_AREA_ROOT}/sourcecode"
BUILD_DIR="${DBT_AREA_ROOT}/build"
if [ ! -d "$BUILD_DIR" ]; then
    
    echo -e "$( cat <<EOF
${COL_YELLOW}
WARNING: Expected build directory "$BUILD_DIR" not found. 
This suggests there may be a problem. 
Creating "$BUILD_DIR"
${COL_RESET}
EOF
)"
    mkdir -p $BUILD_DIR
    
    if ! [[ -e $BUILD_DIR ]]; then
	error "Unable to create $BUILD_DIR; exiting..."
	return 4
    fi
fi


if [[ -z "${DBT_PACKAGE_SETUP_DONE}" ]]; then
    spack_setup_env
    retval=$?
    if [[ "$retval" != "0" ]]; then
        error "Problem setting up the spack environment"
        return $retval
    fi
    
    echo -e "${COL_GREEN}This script hasn't yet been sourced (successfully) in this shell; setting up the build environment${COL_RESET}\n"
    
    if [[ "$DBT_PKG_SET" =~ "daqpackages" ]]; then
        target_package=dunedaq
	[[ "$SPACK_RELEASE" =~ (ND|nd) ]] && target_package=nddaq
	[[ "$SPACK_RELEASE" =~ (FD|fd) ]] && target_package=fddaq
    else
	target_package=$DBT_PKG_SET
    fi

    spack_load_target_package $target_package

    retval=$?
    if [[ "$retval" != "0" ]]; then
      error "Failed to load spack target package. Returning..."
      return $retval
    fi

    # Note: temporary solution - DPF May-19-2022
    # if trace is loaded, source "trace_functions.sh"
    #if spack find --loaded trace; then
    #    source `which trace_functions.sh`
    #fi
    [[ $(type -P "trace_functions.sh") ]] && source `which trace_functions.sh`

    # Assumption is you've already spack loaded python, etc...
    local_venv_dir=${DBT_AREA_ROOT}/${DBT_VENV}
    release_venv_dir=`realpath ${SPACK_RELEASES_DIR}/$SPACK_RELEASE/${DBT_VENV}`
    venv_path=""
    if [ -d $local_venv_dir ]; then
	echo
	echo "Found venv in the current workarea, activating it now... "
	venv_path=$local_venv_dir
    else
	echo
	echo "No local venv found, activating venv from the release directory on cvmfs..."
	venv_path=$release_venv_dir
    fi

    if [[ "$VIRTUAL_ENV" != "" ]]; then
	the_activated_env=$( pip -V  | sed -r 's!\pip [0-9\.]+ from (.*)/lib/python[0-9\.]+/site-packages/pip .*!\1!' )
	if [[ $the_activated_env != "$venv_path" ]]; then
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

    source ${venv_path}/bin/activate
    export PYTHONPATH=$(python -c "import sysconfig; print(sysconfig.get_path('platlib'))"):$PYTHONPATH
     
    export DBT_PACKAGE_SETUP_DONE=1

else
     echo -e "${COL_YELLOW}The build environment has already been setup. Skipping package load/Python environment activation.${COL_RESET}"
fi

if [[ -z $DBT_INSTALL_DIR ]]; then
    export DBT_INSTALL_DIR=${DBT_AREA_ROOT}/install
fi

mkdir -p $DBT_INSTALL_DIR

if [[ ! -d $DBT_INSTALL_DIR ]]; then
    error "Unable to locate/create desired installation directory DBT_INSTALL_DIR=${DBT_INSTALL_DIR}, returning..."
    return 2
fi

# Final step: update PATHs
echo
echo -e "${COL_GREEN}Updating paths...${COL_RESET}"

DBT_PACKAGES=$(find -L ${SOURCE_DIR}/ -mindepth 2 -maxdepth 2 -name CMakeLists.txt | sed "s#${SOURCE_DIR}/\(.*\)/CMakeLists.txt#\1#")


for p in ${DBT_PACKAGES}; do
    PNAME=${p^^}
    PKG_BLD_PATH=${BUILD_DIR}/${p}
    PKG_INSTALL_PATH=${DBT_INSTALL_DIR}/${p}
    # Share
    pkg_share="${PNAME//-/_}_SHARE"
    declare -xg "${pkg_share}"="${DBT_INSTALL_DIR}/${p}/share"

    add_many_paths PATH "${PKG_INSTALL_PATH}/bin" "${PKG_INSTALL_PATH}/test/bin"
    add_many_paths PYTHONPATH "${PKG_INSTALL_PATH}/lib64/python"
    add_many_paths LD_LIBRARY_PATH "${PKG_INSTALL_PATH}/lib64"  "${PKG_INSTALL_PATH}/test/lib64"
    add_many_paths CET_PLUGIN_PATH "${PKG_INSTALL_PATH}/lib64" "${PKG_INSTALL_PATH}/test/lib64"
    add_many_paths DUNEDAQ_SHARE_PATH  "${PKG_INSTALL_PATH}/share" 
done

export PATH PYTHONPATH LD_LIBRARY_PATH CET_PLUGIN_PATH DUNEDAQ_SHARE_PATH
echo -e "${COL_GREEN}...done${COL_RESET}"
echo

export DBT_WORKAREA_ENV_SCRIPT_SOURCED=1

echo -e "${COL_GREEN}This script has been sourced successfully${COL_RESET}"
echo
