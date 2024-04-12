#!/bin/sh

$(return 0 >/dev/null 2>&1)
# What exit code did that give?
if [ "$?" -ne "0" ]
then
    echo "This script is not meant to be execute it. Please execute 'source $(basename $BASH_SOURCE)' "
    exit 1
fi

#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Avoid conflicts with local spack environment
export SPACK_DISABLE_LOCAL_CONFIG=true
if [[ -z $DBT_AREA_ROOT ]]; then
    echo "DBT_AREA_ROOT DNE; defaulting to /tmp"
    export SPACK_USER_CACHE_PATH="/tmp/${USER}/spack"
fi

export DBT_ROOT=${HERE}

# Import add_many_paths function
source ${DBT_ROOT}/scripts/dbt-setup-tools.sh

add_many_paths PATH ${DBT_ROOT}/bin ${DBT_ROOT}/scripts
export PATH

dbt-workarea-env() { source ${DBT_ROOT}/scripts/dbt-workarea-env.sh $@; }
dbt-setup-release() { source ${DBT_ROOT}/scripts/dbt-setup-release.sh $@; }

echo -e "${COL_GREEN}DBT setuptools loaded${COL_RESET}"

