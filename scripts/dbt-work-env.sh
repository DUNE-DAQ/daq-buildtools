#------------------------------------------------------------------------------

HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Import find_work_area function
source ${HERE}/dbt-setup-tools.sh

if [[ -n $1 ]]; then
    if [[ "$1" =~ "--refresh" ]]; then
	if [[ -z "${DBT_WORK_ENV_SCRIPT_SOURCED}" ]]; then
	    error "This script hasn't yet been sourced (successfully) in this shell; please run it without arguments. Returning..."
	    return 30
	fi
    else
	error "Unknown argument(s) passed to ${BASH_SOURCE}; returning..."
	return 40
    fi
else
    if [[ -n "${DBT_WORK_ENV_SCRIPT_SOURCED}" ]]; then
	error "This script has already been sourced (successfully) in this shell; to source it again please pass it the \"--refresh\" argument. Returning..."
	return 50
    fi
fi


DBT_AREA_ROOT=$(find_work_area)

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

if [[ -z $DBT_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED ]]; then

    build_env_script=${DBT_ROOT}/scripts/dbt-setup-build-environment.sh
    
    if [[ ! -f $build_env_script ]]; then

	  error "$( cat<<EOF 

Error: this script is trying to source
$build_env_script but is unable to
find it. It's likely an assumption in the daq-buildtools framework is
being broken somewhere. Returning...

EOF
)"
    return 20
    fi

    echo "Lines between the ='s are the output of sourcing $build_env_script"
    echo "======================================================================"
    . $build_env_script
    retval="$?"
    echo "======================================================================"
    if ! [[ $retval -eq 0 ]]; then
        error "There was a problem sourcing $build_env_script. Exiting..." 
        return $retval
    fi

else
    cat <<EOF
The build environment setup script already appears to have been sourced, so this script doesn't need to source it again.

EOF
fi


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

export DBT_WORK_ENV_SCRIPT_SOURCED=1

echo -e "${COL_GREEN}This script has been sourced successfully${COL_NULL}"
echo
