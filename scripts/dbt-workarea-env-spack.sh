#------------------------------------------------------------------------------



HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)
scriptname=$(basename $(readlink -f ${BASH_SOURCE}))

DBT_PKG_SETS=( devtools systems externals daqpackages )
    
DEFAULT_BUILD_TYPE=RelWithDebInfo
REFRESH_PACKAGES=false
# We use "$@" instead of $* to preserve argument-boundary information
options=$(getopt -o 'hs:r' -l 'help, subset:, refresh' -- "$@") || return 10
eval "set -- $options"

DBT_PKG_SET="${DBT_PKG_SETS[-1]}"
while true; do
    case $1 in
        (-r|--refresh)
            REFRESH_PACKAGES=true
            shift;;
	(-s|--subset)
            DBT_PKG_SET=$2
            shift 2;;
        (-h|--help)
            cat << EOU
Usage
-----

  ${scriptname} [-h/--help] [--refresh] [-s/--subset [devtools systems externals daqpackages]]

  Sets up the environment of a dbt development area

  Arguments and options:

    --refresh: re-runs the build environment setup
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

if [[ -z $DBT_AREA_ROOT ]]; then
    error "Expected work area directory \"$DBT_AREA_ROOT\" not found. Returning..." 
    return 1
else
  echo -e "${COL_BLUE}Work area: '${DBT_AREA_ROOT}'${COL_RESET}\n"
fi

SOURCE_DIR="${DBT_AREA_ROOT}/sourcecode"
BUILD_DIR="${DBT_AREA_ROOT}/build"
if [ ! -d "$BUILD_DIR" ]; then
    
    error "$( cat <<EOF 

There doesn't appear to be a "build" subdirectory in ${DBT_AREA_ROOT}.
Please run a copy of this script from the base directory of a development area installed with dbt-create.sh
Returning...
EOF
)"
    return 1

fi

spack_setup_env

if [[ ("${REFRESH_PACKAGES}" == "false" &&  -z "${DBT_PACKAGE_SETUP_DONE}") || "${REFRESH_PACKAGES}" == "true" ]]; then
    
     if [[ -z "${DBT_PACKAGE_SETUP_DONE}" ]]; then
         echo -e "${COL_GREEN}This script hasn't yet been sourced (successfully) in this shell; setting up the build environment${COL_RESET}\n"
     else
         echo -e "${COL_GREEN}Refreshing package setup${COL_RESET}\n"
         # Clean up
         echo -e "${COL_BLUE}Deactivating python environment${COL_RESET}\n"
         deactivate
         echo -e "${COL_BLUE}Unloading packages${COL_RESET}\n"

         if [[ "$DBT_PKG_SET" == "daqpackages" ]]; then
           spack unload dune-daqpackages@${DUNE_DAQ_BASE_RELEASE}
         else
	   spack unload $DBT_PKG_SET@${DUNE_DAQ_BASE_RELEASE}
         fi

     fi

    source ${DBT_AREA_ROOT}/${DBT_AREA_FILE}  

    if [[ "$DBT_PKG_SET" =~ "daqpackages" ]]; then
	spack_load_target_package dune-daqpackages
    else
	spack_load_target_package $DBT_PKG_SET
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
     echo -e "${COL_YELLOW}The build environment has been already setup.\nUse '${scriptname} --refresh' to force a reload.${COL_RESET}\n"
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



