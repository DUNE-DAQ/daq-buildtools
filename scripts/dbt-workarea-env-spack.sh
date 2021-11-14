#------------------------------------------------------------------------------


spack_script=$HOME/spack/share/spack/setup-env.sh

if [[ ! -e $spack_script ]]; then
    echo "Unable to find spack setup script ("$spack_script"); exiting..." >&2
    return 1
fi

source $spack_script


HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)
scriptname=$(basename $(readlink -f ${BASH_SOURCE}))

DBT_GCC_PKG="gcc@8.2.0 +binutils"
DBT_PKG_SET="dune-daqpackages@dunedaq-v2.8.0 build_type=RelWithDebInfo"

REFRESH_PACKAGES=false
# We use "$@" instead of $* to preserve argument-boundary information
options=$(getopt -o 'h:r' -l 'help:, refresh' -- "$@") || return 10
eval "set -- $options"

while true; do
    case $1 in
        (-r|--refresh)
            REFRESH_PACKAGES=true
            shift;;
        (-h|--help)
            cat << EOU
Usage
-----

  ${scriptname} [-h/--help] [--refresh]

  Sets up the environment of a dbt development area

  Arguments and options:

    --refresh: re-runs the build environment setup
    
EOU
            return 0;;           # error
        (--)  shift; break;;
        (*) 
            echo "ERROR $@"  
            return 1;;           # error
    esac
done

source ${HERE}/dbt-setup-tools.sh
# Import find_work_area function

export DBT_AREA_ROOT=$(find_work_area)

if [[ -z $DBT_AREA_ROOT ]]; then
    error "Expected work area directory not found. Returning..." 
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


if [[ ("${REFRESH_PACKAGES}" == "false" &&  -z "${DBT_PACKAGE_SETUP_DONE}") || "${REFRESH_PACKAGES}" == "true" ]]; then
    
     if [[ -z "${DBT_PACKAGE_SETUP_DONE}" ]]; then
         echo -e "${COL_GREEN}This script hasn't yet been sourced (successfully) in this shell; setting up the build environment${COL_RESET}\n"
     else
         echo -e "${COL_GREEN}Refreshing package setup${COL_RESET}\n"
         # Clean up
         echo -e "${COL_BLUE}Deactivating python environment${COL_RESET}\n"
         deactivate
         echo -e "${COL_BLUE}Unloading packages${COL_RESET}\n"
         spack unload $DBT_GCC_PKG
	 spack unload $DBT_PKG_SET
     fi

          
    spack load $DBT_GCC_PKG

    if [[ "$?" != "0" ]]; then
	error "There was a problem running spack load $DBT_GCC_PKG; returning..."
        return 2
    fi

    spack load $DBT_PKG_SET

    if [[ "$?" != "0" ]]; then
	error "There was a problem running spack load $DBT_PKG_SET; returning..." 
	return 3
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


