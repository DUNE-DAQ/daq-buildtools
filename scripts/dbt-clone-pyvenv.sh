#!/bin/env bash

#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Import find_work_area function
source ${HERE}/dbt-setup-tools.sh

DBT_AREA_ROOT=$(find_work_area)
if [[ -z ${DBT_AREA_ROOT} ]]; then
    error "Expected work area directory ${DBT_AREA_ROOT} not found. Exiting..." 
fi

if [[ $# -ne 1 ]]; then
    error_preface "Wrong number of arguments"
    cat << EOU
Usage: $(basename $0) <path to existing python venv>:

EOU
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

# Source the area settings to determine the origin and version of system packages
source ${DBT_AREA_ROOT}/${DBT_AREA_FILE}

test $? -eq 0 || error "There was a problem sourcing ${DBT_AREA_ROOT}/${DBT_AREA_FILE}. Exiting..."

setup_ups_product_areas

setup_ups_products dune_systems
test $? -eq 0 || error "Failed to setup 'dune_system' products, required to build the python venv. Exiting..." 


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
fi

source ${DBT_AREA_ROOT}/${DBT_VENV}/bin/activate

if [[ "$VIRTUAL_ENV" == "" ]]
then
  error "Failed to load the virtual env. Exiting..." 
fi

deactivate
test $? -eq 0 || error "Call to \"deactivate\" returned nonzero. Exiting..." 


