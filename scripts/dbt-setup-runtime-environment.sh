#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Import find_work_area function
source ${HERE}/dbt-setup-tools.sh

DBT_AREA_ROOT=$(find_work_area)

SOURCE_DIR="${DBT_AREA_ROOT}/sourcecode"
BUILD_DIR="${DBT_AREA_ROOT}/build"
if [ ! -d "$BUILD_DIR" ]; then
    
    error "$( cat <<EOF 

There doesn't appear to be a "build" subdirectory in ${DBT_AREA_ROOT}.
Please run a copy of this script from the base directory of a development area installed with dbt-init.sh
Returning...
EOF
)"
    return 1

fi

if [[ -z $DBT_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED ]]; then
      type dbt-setup-build-environment > /dev/null
      retval="$?"

      if [[ $retval -eq 0 ]]; then
          echo "Lines between the ='s are the output of running dbt-setup-build-environment"
    echo "======================================================================"
          dbt-setup-build-environment 
    retval="$?"
    echo "======================================================================"
    if ! [[ $retval -eq 0 ]]; then
        error "There was a problem running dbt-setup-build-environment. Exiting..." 
        return $retval
    fi
      else

    error "$( cat<<EOF 

Error: this script tried to execute "dbt-setup-build-environment" but was unable 
to find it. Either the daq-buildtools environment hasn't yet been set up, or 
an assumption in the daq-buildtools framework is being broken somewhere. Returning...

EOF
)"
    return 20
      fi    
else
    cat <<EOF
The build environment setup script already appears to have been sourced, so this 
script won't try to source it

EOF
fi


DBT_PACKAGES=$(find ${SOURCE_DIR}/ -mindepth 2 -maxdepth 2 -name CMakeLists.txt | sed "s#${SOURCE_DIR}/\(.*\)/CMakeLists.txt#\1#")


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
  add_many_paths_if_exist DUNEDAQ_SHARE_PATH  "${PKG_BLD_PATH}/share" "${PKG_BLD_PATH}/test/share"

done

export PATH PYTHONPATH LD_LIBRARY_PATH CET_PLUGIN_PATH DUNEDAQ_SHARE_PATH

echo -e "${COL_GREEN}This script has been sourced successfully${COL_NULL}"
echo
