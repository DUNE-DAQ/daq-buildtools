#!/bin/env bash

#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

source ${HERE}/dbt-setup-tools.sh

if (( $# < 1 || $# > 2)); then
    error "Usage: $( basename $0 ) <path to requirements.txt>"
    exit 1
fi

PYENV_REQS=$1

#------------------------------------------------------------------------------
timenow="date \"+%D %T\""

###
# Check if inside a virtualenv already
###
if [[ "$VIRTUAL_ENV" != "" ]]
then
  error "You are already in a virtual env. Please deactivate first. Exiting..."
fi

DBT_AREA_ROOT=$(find_work_area)
if [[ -z ${DBT_AREA_ROOT} ]]; then
    error "Expected work area directory not found via call to find_work_area. Exiting..."
fi

if [[ -z $SPACK_RELEASE ]]; then
    error "Environment variable SPACK_RELEASE needs to be set for this script to work. Exiting..."
fi

if [[ -z $SPACK_RELEASES_DIR ]]; then
    error "Environment variable SPACK_RELEASES_DIR needs to be set for this script to work. Exiting..."
fi

[[ $DBT_USE_UV=="true" ]] && ! command -v uv >/dev/null && error "--uv requested but uv not found. Exiting..."

spack_setup_env
spack_load_target_package systems  # Error checking occurs inside function

###
# Check existance/create the default virtual_env
###
if [ -f "${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg" ]; then
    echo -e "INFO [`eval $timenow`]: virtual_env ${DBT_VENV} already exists."
    cat "${DBT_AREA_ROOT}/${DBT_VENV}/pyvenv.cfg"
elif [[ "$DBT_USE_UV"=="true" ]]; then
    echo -e "INFO [`eval $timenow`]: creating virtual_env ${DBT_VENV} using uv."
    uv venv --seed --prompt ${DBT_VENV_PROMPT} --python "$(command -v python)" ${DBT_AREA_ROOT}/${DBT_VENV}
    test $? -eq 0 || error "Problem creating virtual_env ${DBT_VENV}. Exiting..."
else
    echo -e "INFO [`eval $timenow`]: creating virtual_env ${DBT_VENV}. "
    python -m venv --prompt ${DBT_VENV_PROMPT} ${DBT_AREA_ROOT}/${DBT_VENV}

    test $? -eq 0 || error "Problem creating virtual_env ${DBT_VENV}. Exiting..." 
fi

source ${DBT_AREA_ROOT}/${DBT_VENV}/bin/activate

if [[ "$VIRTUAL_ENV" == "" ]]
then
  error "Failed to load the virtual env. Exiting..." 
fi

if [[ -n $DBT_USE_UV=="true" ]]; then
    uv pip install -r ${PYENV_REQS}
else
    # JCF, Sep-27-2022: Spack's openssl is preventing the install command below from working
    spack unload openssl
    python -m pip install -r ${PYENV_REQS}
fi
test $? -eq 0 || error "Installing required modules from ${PYENV_REQS} failed. Exiting..." 

deactivate
test $? -eq 0 || error "Call to \"deactivate\" returned nonzero. Exiting..." 



