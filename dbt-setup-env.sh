#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

export DBT_ROOT=${HERE}

# Import add_many_paths function
source ${DBT_ROOT}/scripts/dbt-setup-tools.sh

add_many_paths PATH ${DBT_ROOT}/bin ${DBT_ROOT}/scripts
export PATH

alias dbt-setup-build-environment="source ${DBT_ROOT}/scripts/dbt-setup-build-environment.sh"
alias dbt-setup-runtime-environment="source ${DBT_ROOT}/scripts/dbt-setup-runtime-environment.sh"
echo -e "${COL_GREEN}DBT setuptools loaded${COL_NULL}"
