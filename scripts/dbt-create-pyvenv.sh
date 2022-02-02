#!/bin/env bash

#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Import find_work_area function
source ${HERE}/dbt-setup-tools.sh

DBT_AREA_ROOT=$(find_work_area)
if [[ -z ${DBT_AREA_ROOT} ]]; then
    error "Expected work area directory ${DBT_AREA_ROOT} not found. Exiting..." 
fi

if (( $# < 1 || $# > 2)); then
    error "Usage: $( basename $0 ) (--spack) <path to requirements.txt>"
    exit 1
fi

SPACK=false
PYENV_REQS=""

if (( $# == 1 )); then
    PYENV_REQS=$1
else
    SPACK=true
    PYENV_REQS=$2
fi

#------------------------------------------------------------------------------
timenow="date \"+%D %T\""

###
# Check if inside a virtualenv already
###
if [[ "$VIRTUAL_ENV" != "" ]]
then
  error "You are already in a virtual env. Please deactivate first. Exiting..."
fi

###
# Source dune system packages
###

# Source the area settings to determine the origin and version of system packages
source ${DBT_AREA_ROOT}/${DBT_AREA_FILE}

test $? -eq 0 || error "There was a problem sourcing ${DBT_AREA_ROOT}/${DBT_AREA_FILE}. Exiting..."

if ! $SPACK ; then
    echo "USING UPS"
    setup_ups_product_areas
    setup_ups_products dune_systems
    test $? -eq 0 || error "Failed to setup 'dune_system' products, required to build the python venv. Exiting..." 
else
    echo "USING SPACK"
    source ~/spack/share/spack/setup-env.sh
    cmd="spack load systems@${DUNE_DAQ_BASE_RELEASE}~debug"
    $cmd
    test $? -eq 0 || error "There was a problem calling ${cmd}, required to build the python venv. Exiting..."
fi

###
# Check existance/create the default virtual_env
###
if [ -f "${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg" ]; then
    echo -e "INFO [`eval $timenow`]: virtual_env ${DBT_VENV} already exists."
    cat "${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg"
else
    echo -e "INFO [`eval $timenow`]: creating virtual_env ${DBT_VENV}. "
    python -m venv ${DBT_AREA_ROOT}/${DBT_VENV}

    test $? -eq 0 || error "Problem creating virtual_env ${DBT_VENV}. Exiting..." 
fi

source ${DBT_AREA_ROOT}/${DBT_VENV}/bin/activate

if [[ "$VIRTUAL_ENV" == "" ]]
then
  error "Failed to load the virtual env. Exiting..." 
fi

python -m pip install -r ${PYENV_REQS}
test $? -eq 0 || error "Installing required modules from ${PYENV_REQS} failed. Exiting..." 

deactivate
test $? -eq 0 || error "Call to \"deactivate\" returned nonzero. Exiting..." 



