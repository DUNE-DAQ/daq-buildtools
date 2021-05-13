#!/bin/sh
#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

export DBT_ROOT=${HERE}

# Import add_many_paths function
source ${DBT_ROOT}/scripts/dbt-setup-tools.sh

add_many_paths PATH ${DBT_ROOT}/bin ${DBT_ROOT}/scripts
export PATH

dbt-setup-build-environment() { echo "This command is deprecated; please run \"dbt-workarea-env\" instead" >&2 ; }
dbt-workarea-env() { source ${DBT_ROOT}/scripts/dbt-workarea-env.sh $@; }

echo -e "${COL_GREEN}DBT setuptools loaded${COL_NULL}"
