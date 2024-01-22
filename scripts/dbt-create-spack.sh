#!/bin/env bash

#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

source ${HERE}/dbt-setup-tools.sh

if (( $# > 1 )); then
    error "Usage: $( basename $0 )"
    exit 1
fi

PYENV_REQS=$1

#------------------------------------------------------------------------------
timenow="date \"+%D %T\""

###
# Check if inside a virtualenv already
###
if [[ -z ${LOCAL_SPACK_DIR} ]]
then
  error "Environment variable LOCAL_SPACK_DIR needs to be set for this script to work. Exiting..."
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


###
# Check existance/create the default virtual_env
###
if [ -d "${LOCAL_SPACK_DIR}" ]; then
    error "Directory ${LOCAL_SPACK_DIR} already exists. Exiting..."
else
    echo -e "INFO [`eval $timenow`]: creating a local spack instance under ${LOCAL_SPACK_DIR}. "
    existing_spack_dir=$( realpath $SPACK_RELEASES_DIR/$SPACK_RELEASE/spack-installation )

    if [[ -z $existing_spack_dir ]]; then   # Backwards compatibility with the old directory structure
	existing_spack_dir=$( realpath $SPACK_RELEASES_DIR/$SPACK_RELEASE/default/spack-installation )
    fi

    stack_new_spack $existing_spack_dir $LOCAL_SPACK_DIR
fi

