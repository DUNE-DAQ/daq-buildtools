#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Import find_work_area function
source ${HERE}/dbt-setup-tools.sh

DBT_AREA_ROOT=$(find_work_area)

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

DUNEDAQ_SCRIPT_PATH=$(find -L $BUILD_DIR -maxdepth 2 -type d -not -name '*CMakeFiles*' -path '*/scripts')
DUNEDAQ_TEST_SCRIPT_PATH=$(find -L $BUILD_DIR -maxdepth 3 -type d -not -name '*CMakeFiles*' -path '*/test/scripts')
DUNEDAQ_PYTHON_PATH=$(find -L $BUILD_DIR -maxdepth 2 -type d -not -name '*CMakeFiles*' -path '*/python')
# For when configuration files will be introduces
# DUNEDAQ_SHARE_PATH=$(find -L $BUILD_DIR -maxdepth 2 -type d -not -name '*CMakeFiles*'  \( -path '*/schema' -or -path '*/config' \) -exec dirname \{\} \;)
DUNEDAQ_SHARE_PATH=$(find -L $BUILD_DIR -maxdepth 2 -type d -not -name '*CMakeFiles*' -path '*/schema' -exec dirname \{\} \;)

DUNEDAQ_APPS_PATH=$(find -L $BUILD_DIR -maxdepth 2 -type d -not -name '*CMakeFiles*' -path '*/apps')
DUNEDAQ_LIB_PATH=$(find -L $BUILD_DIR -maxdepth 2 -type d -not -name '*CMakeFiles*' -path '*/src')
DUNEDAQ_PLUGS_PATH=$(find -L $BUILD_DIR -maxdepth 2 -type d -not -name '*CMakeFiles*' -path '/*plugins')
DUNEDAQ_TEST_APPS_PATH=$(find -L $BUILD_DIR -maxdepth 3 -type d -not -name '*CMakeFiles*' -path '*/test/apps')
DUNEDAQ_TEST_PLUGS_PATH=$(find -L $BUILD_DIR -maxdepth 3 -type d -not -name '*CMakeFiles*' -path '*/test/plugins')

add_many_paths PATH ${DUNEDAQ_APPS_PATH} ${DUNEDAQ_SCRIPT_PATH} ${DUNEDAQ_TEST_APPS_PATH} ${DUNEDAQ_TEST_SCRIPT_PATH}
add_many_paths PYTHONPATH ${DUNEDAQ_PYTHON_PATH}
add_many_paths LD_LIBRARY_PATH ${DUNEDAQ_LIB_PATH}
add_many_paths CET_PLUGIN_PATH ${DUNEDAQ_PLUGS_PATH} ${DUNEDAQ_TEST_PLUGS_PATH}
add_many_paths DUNEDAQ_SHARE_PATH ${DUNEDAQ_SHARE_PATH}

unset DUNEDAQ_SCRIPT_PATH DUNEDAQ_TEST_SCRIPT_PATH DUNEDAQ_PYTHON_PATH
unset DUNEDAQ_APPS_PATH DUNEDAQ_LIB_PATH DUNEDAQ_PLUGS_PATH DUNEDAQ_TEST_APPS_PATH DUNEDAQ_TEST_PLUGS_PATH

export PATH PYTHONPATH LD_LIBRARY_PATH CET_PLUGIN_PATH DUNEDAQ_SHARE_PATH

echo -e "${COL_GREEN}This script has been sourced successfully${COL_NULL}"
echo
