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

# Convenience function for finding paths in the 
function find_runtime_paths() {
  find -L $BUILD_DIR -maxdepth $1 -type d -path "$2" -printf "%$3 "
}


# Locate all the 
DBT_FOUND_APPS_PATH=$(find_runtime_paths 2 '*/apps' 'p')
DBT_FOUND_LIB_PATH=$(find_runtime_paths 2 '*/src' 'p')
DBT_FOUND_PLUGS_PATH=$(find_runtime_paths 2 '*/plugins' 'p')
DBT_FOUND_SCRIPT_PATH=$(find_runtime_paths 2 '*/scripts' 'p')
DBT_FOUND_PYTHON_PATH=$(find_runtime_paths 2 '*/python' 'p')
DBT_FOUND_SHARE_PATH=$(find_runtime_paths 2 '*/schema' 'h')

DBT_FOUND_TEST_APPS_PATH=$(find_runtime_paths 3 '*/test/apps' 'p')
DBT_FOUND_TEST_SCRIPT_PATH=$(find_runtime_paths 3 '*/test/scripts' 'p')
DBT_FOUND_TEST_PLUGS_PATH=$(find_runtime_paths 3 '*/test/plugins' 'p')
DBT_FOUND_TEST_SHARE_PATH=$(find_runtime_paths 3 '*/test/schema' 'h')


add_many_paths PATH ${DBT_FOUND_APPS_PATH} ${DBT_FOUND_SCRIPT_PATH} ${DBT_FOUND_TEST_APPS_PATH} ${DBT_FOUND_TEST_SCRIPT_PATH}
add_many_paths PYTHONPATH ${DBT_FOUND_PYTHON_PATH}
add_many_paths LD_LIBRARY_PATH ${DBT_FOUND_LIB_PATH} ${DBT_FOUND_PLUGS_PATH} ${DBT_FOUND_TEST_PLUGS_PATH}
add_many_paths CET_PLUGIN_PATH ${DBT_FOUND_PLUGS_PATH} ${DBT_FOUND_TEST_PLUGS_PATH}
add_many_paths DUNEDAQ_SHARE_PATH ${DBT_FOUND_SHARE_PATH} ${DBT_FOUND_TEST_SHARE_PATH}

unset DBT_FOUND_APPS_PATH DBT_FOUND_LIB_PATH DBT_FOUND_PLUGS_PATH DBT_FOUND_SCRIPT_PATH DBT_FOUND_PYTHON_PATH DBT_FOUND_SHARE_PATH
unset DBT_FOUND_TEST_APPS_PATH DBT_FOUND_TEST_SCRIPT_PATH DBT_FOUND_TEST_PLUGS_PATH DBT_FOUND_TEST_SHARE_PATH
export PATH PYTHONPATH LD_LIBRARY_PATH CET_PLUGIN_PATH DUNEDAQ_SHARE_PATH

echo -e "${COL_GREEN}This script has been sourced successfully${COL_NULL}"
echo
