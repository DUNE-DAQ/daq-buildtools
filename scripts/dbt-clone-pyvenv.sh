#!/bin/env bash

#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Import find_work_area function
source ${HERE}/dbt-setup-tools.sh

if (( $# < 1 || $# > 2)); then
    error "Usage: $( basename $0 ) <path to existing python venv>"
    exit 1
fi

PARENT_VENV=$1

#------------------------------------------------------------------------------
timenow="date \"+%D %T\""

###
# Check if inside a virtualenv already
###
if [[ "$VIRTUAL_ENV" != "" ]]
then
  error "You are already in a virtual env. Please deactivate first. Exiting..."
fi

if [[ -z $DBT_AREA_ROOT ]]; then
    error "Environment variable DBT_AREA_ROOT needs to be set for this script to work. Exiting..."
fi

if [[ -z $SPACK_RELEASE ]]; then
    error "Environment variable SPACK_RELEASE needs to be set for this script to work. Exiting..."
fi

if [[ -z $SPACK_RELEASES_DIR ]]; then
    error "Environment variable SPACK_RELEASES_DIR needs to be set for this script to work. Exiting..."
fi

spack_setup_env
spack_load_target_package systems  # Error checking occurs inside function

###
# Check existance/create the default virtual_env
###
if [ -f "${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg" ]; then
    echo -e "INFO [`eval $timenow`]: virtual_env ${DBT_VENV} already exists."
    cat "${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg"
else
    echo -e "INFO [`eval $timenow`]: creating virtual_env ${DBT_VENV} by cloning ${PARENT_VENV}. "
    ${HERE}/../bin/clonevirtualenv.py ${PARENT_VENV} ${DBT_AREA_ROOT}/${DBT_VENV}

    test $? -eq 0 || error "Problem creating virtual_env ${DBT_VENV}. Exiting..." 

    # Recall earlier we ensured one, and only one, systems package loaded in
    python_basedir=$( spack find -d -p --loaded systems | sed -r -n "s/^\s*python.*\s+(\S+)$/\1/p" )
    if [[ -z $python_basedir || "$python_basedir" == "" ]]; then
    	error "Somehow unable to determine the location of Spack-installed python. Exiting..."
    fi
	
    if [[ ! -e ${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg ]]; then
    	error "${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg expected to exist but doesn't. Exiting..."
    fi

    sed -i -r 's!^\s*home\s*=.*!home = '${python_basedir}'/bin!' ${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg

    if [[ ! -L ${DBT_AREA_ROOT}/${DBT_VENV}/bin/python ]]; then
	error "Expected ${DBT_AREA_ROOT}/${DBT_VENV}/bin/python linkfile to exist but it doesn't. Exiting..."
    fi

    if [[ ! -e $python_basedir/bin/python ]]; then
	error "Expected $python_basedir/bin/python to exist but it doesn't. Exiting..."
    fi

    rm ${DBT_AREA_ROOT}/${DBT_VENV}/bin/python
    pushd ${DBT_AREA_ROOT}/${DBT_VENV}/bin > /dev/null
    ln -s $python_basedir/bin/python
    popd > /dev/null

fi

source ${DBT_AREA_ROOT}/${DBT_VENV}/bin/activate

if [[ "$VIRTUAL_ENV" == "" ]]
then
  error "Failed to load the virtual env. Exiting..." 
fi

deactivate
test $? -eq 0 || error "Call to \"deactivate\" returned nonzero. Exiting..." 


