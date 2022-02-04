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

export DBT_ROOT=${HERE}

# Import add_many_paths function
source ${DBT_ROOT}/scripts/dbt-setup-tools.sh

add_many_paths PATH ${DBT_ROOT}/bin ${DBT_ROOT}/scripts
export PATH

dbt-setup-build-environment() { error "This command is deprecated; please run \"dbt-workarea-env\" instead" ; }

dbt-workarea-env() { 
    args_to_forward=""

    use_spack=false
    for var in "$@"; do
	if [[ $var =~ --spack ]]; then
	    use_spack=true
	else
	    args_to_forward="$args_to_forward $var"
	fi
	shift
    done
    
    if $use_spack; then
    	source ${DBT_ROOT}/scripts/dbt-workarea-env-spack.sh $args_to_forward
    else
    	source ${DBT_ROOT}/scripts/dbt-workarea-env.sh $args_to_forward
    fi
}

dbt-setup-release() { 
    args_to_forward=""

    use_spack=false
    for var in "$@"; do
	if [[ $var =~ --spack ]]; then
	    use_spack=true
	else
	    args_to_forward="$args_to_forward $var"
	fi
	shift
    done

    if $use_spack; then
    	source ${DBT_ROOT}/scripts/dbt-setup-release-spack.sh $args_to_forward
    else
    	source ${DBT_ROOT}/scripts/dbt-setup-release.sh $args_to_forward
    fi
}

echo -e "${COL_GREEN}DBT setuptools loaded${COL_RESET}"
