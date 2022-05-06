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

if [[ -e $PWD/dbt-workarea-constants.sh ]]; then
    . $PWD/dbt-workarea-constants.sh 
else
    error "Unable to find dbt-workarea-constants.sh file; you need to be in the base of a work area to run this"
    return 3
fi

SOURCE_DIR="${DBT_AREA_ROOT}/sourcecode"
BUILD_DIR="${DBT_AREA_ROOT}/build"
if [ ! -d "$BUILD_DIR" ]; then
    
    error "$( cat <<EOF 

There doesn't appear to be a "build" subdirectory in ${DBT_AREA_ROOT}.
Please run a copy of this script from the base directory of a development area installed with dbt-create
Returning...
EOF
)"
    return 1

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
	spack_load_target_package dunedaq
    else
	spack_load_target_package $DBT_PKG_SET
    fi

    retval=$?
    if [[ "$retval" != "0" ]]; then
      error "Failed to load spack target package. Returning..."
      return $retval
    fi

    # Assumption is you've already spack loaded python, etc...

    source ${DBT_AREA_ROOT}/${DBT_VENV}/bin/activate

    if [[ "$VIRTUAL_ENV" == "" ]]
    then
	error "You are already in a virtual env. Please deactivate first. Returning..." 
	return 11
    fi
     
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



