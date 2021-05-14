#------------------------------------------------------------------------------

HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)
scriptname=$(basename $(readlink -f ${BASH_SOURCE}))

DBT_PKG_SETS=( devtools systems externals daqpackages )
REFRESH_UPS=false
# We use "$@" instead of $* to preserve argument-boundary information
options=$(getopt -o 'hs:r' -l 'help, subset:, refresh' -- "$@") || return 10
eval "set -- $options"

DBT_PKG_SET="${DBT_PKG_SETS[-1]}"
while true; do
    case $1 in
        (-r|--refresh)
            REFRESH_UPS=true
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

if [[ ("${REFRESH_UPS}" == "false" &&  -z "${DBT_UPS_SETUP_DONE}") || "${REFRESH_UPS}" == "true" ]]; then
    # 
    if [[ -z "${DBT_UPS_SETUP_DONE}" ]]; then
        echo -e "${COL_GREEN}This script hasn't yet been sourced (successfully) in this shell; setting up the build environment${COL_RESET}\n"
    else
        echo -e "${COL_GREEN}Refreshing UPS package setup${COL_RESET}\n"
    fi

    # 1. Load the UPS area information from the local area file
    source ${DBT_AREA_ROOT}/${DBT_AREA_FILE}
    if ! [[ $? -eq 0 ]]; then
        error "There was a problem sourcing ${DBT_AREA_ROOT}/${DBT_AREA_FILE}. Returning..." 
        return 1
    fi

    echo "Product directories ${dune_products_dirs[@]}"
    echo "Products ${dune_products[@]}"

    setup_ups_product_areas

    # 2. Setup the python environment
    setup_ups_products dune_systems

    if ! [[ $? -eq 0 ]]; then
        error "The \"setup_ups_products dune_systems\" (for gcc and python) call failed. Returning..." 
        return 5
    fi

    source ${DBT_AREA_ROOT}/${DBT_VENV}/bin/activate

    if [[ "$VIRTUAL_ENV" == "" ]]
    then
      error "You are already in a virtual env. Please deactivate first. Returning..." 
      return 11
    fi

    all_setup_returns=""

    for ps in ${DBT_PKG_SETS[@]}; do
      setup_ups_products dune_$ps
      all_setup_returns="${setup_ups_returns} ${all_setup_returns}"

      if [ $ps == "$DBT_PKG_SET" ]; then
        break
      fi
    done

    if ! [[ "$all_setup_returns" =~ [1-9] ]]; then
      echo "All setup calls on the packages returned 0, indicative of success"
    else
      error "At least one of the required packages this script attempted to set up didn't set up correctly. Returning..." 
      return 1
    fi

    export DBT_INSTALL_DIR=${DBT_AREA_ROOT}/install

    export DBT_UPS_SETUP_DONE=1

    unset DBT_PKG_SET DBT_PKG_SETS

else
    echo -e "${COL_YELLOW}The build environment has been already setup.\nUse '${scriptname} --refresh' to force a reload.${COL_RESET}\n"
fi

# Final step: update PATHs
echo
echo -e "${COL_GREEN}Updating paths...${COL_RESET}"

DBT_PACKAGES=$(find -L ${SOURCE_DIR}/ -mindepth 2 -maxdepth 2 -name CMakeLists.txt | sed "s#${SOURCE_DIR}/\(.*\)/CMakeLists.txt#\1#")


for p in ${DBT_PACKAGES}; do
    PNAME=${p^^}
    PKG_BLD_PATH=${BUILD_DIR}/${p}
    # Share
    pkg_share="${PNAME//-/_}_SHARE"
    declare -xg "${pkg_share}"="${BUILD_DIR}/${p}"

    add_many_paths_if_exist PATH "${PKG_BLD_PATH}/apps" "${PKG_BLD_PATH}/scripts" "${PKG_BLD_PATH}/test/apps" "${PKG_BLD_PATH}/test/scripts"
    add_many_paths_if_exist PYTHONPATH "${PKG_BLD_PATH}/python"
    add_many_paths_if_exist LD_LIBRARY_PATH "${PKG_BLD_PATH}/src"  "${PKG_BLD_PATH}/plugins"  "${PKG_BLD_PATH}/test/plugins"
    add_many_paths_if_exist CET_PLUGIN_PATH "${PKG_BLD_PATH}/plugins" "${PKG_BLD_PATH}/test/plugins"
    add_many_paths_if_exist DUNEDAQ_SHARE_PATH  "${PKG_BLD_PATH}" "${PKG_BLD_PATH}/test/share"
done

export PATH PYTHONPATH LD_LIBRARY_PATH CET_PLUGIN_PATH DUNEDAQ_SHARE_PATH
echo -e "${COL_GREEN}...done${COL_RESET}"
echo

export DBT_WORKAREA_ENV_SCRIPT_SOURCED=1

echo -e "${COL_GREEN}This script has been sourced successfully${COL_RESET}"
echo



