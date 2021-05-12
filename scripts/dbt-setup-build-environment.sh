#------------------------------------------------------------------------------

if [[ -z "${DBT_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED}" ]]; then
    echo "This script hasn't yet been sourced (successfully) in this shell; setting up the build environment"
else
    error "This script appears to have already been sourced successfully. Returning..."
    return 10
fi

HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)
scriptname=$(basename $(readlink -f ${BASH_SOURCE}))

found_calling_script=false
desired_calling_script=dbt-refresh-work-env.sh

for dbt_file in "${BASH_SOURCE[@]}"; do
    if [[ "$dbt_file" =~ .*$desired_calling_script ]]; then
	found_calling_script=true
	break
    fi
done

if ! $found_calling_script; then

    cat<<EOF >&2

WARNING: the $scriptname script is being sourced by an entity other
than $desired_calling_script. This use is deprecated.

EOF
    sleep 5
    
fi

# Import find_work_area function
source ${HERE}/dbt-setup-tools.sh

export DBT_AREA_ROOT=$(find_work_area)

echo "DBT_AREA_ROOT=${DBT_AREA_ROOT}"
if [[ -z $DBT_AREA_ROOT ]]; then
    error "Expected work area directory $DBT_AREA_ROOT not found. Returning..." 
    return 1
fi

# 1. Load the UPS area information from the local area file
source ${DBT_AREA_ROOT}/${DBT_AREA_FILE}
if ! [[ $? -eq 0 ]]; then
    error "There was a problem sourcing ${DBT_AREA_ROOT}/${DBT_AREA_FILE}. Returning..." 
    return 1
fi

echo "Product directories ${dune_products_dirs[@]}"
echo "Products ${dune_products[@]}"

setup_ups_product_areas

# 2. Setup the python environment
setup python ${dune_python_version}

if ! [[ $? -eq 0 ]]; then
    error "The \"setup python ${dune_python_version}\" call failed. Returning..." 
    return 5
fi

source ${DBT_AREA_ROOT}/${DBT_VENV}/bin/activate

if [[ "$VIRTUAL_ENV" == "" ]]
then
  error "You are already in a virtual env. Please deactivate first. Returning..." 
  return 11
fi

all_setup_returns=""
setup_ups_products dune_devtools
all_setup_returns="${setup_ups_returns} ${all_setup_returns}"
setup_ups_products dune_systems
all_setup_returns="${setup_ups_returns} ${all_setup_returns}"
setup_ups_products dune_externals
all_setup_returns="${setup_ups_returns} ${all_setup_returns}"
setup_ups_products dune_daqpackages
all_setup_returns="${setup_ups_returns} ${all_setup_returns}"

if ! [[ "$all_setup_returns" =~ [1-9] ]]; then
  echo "All setup calls on the packages returned 0, indicative of success"
else
  error "At least one of the required packages this script attempted to set up didn't set up correctly. Returning..." 
  return 1
fi

export DBT_INSTALL_DIR=${DBT_AREA_ROOT}/install

export DBT_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED=1
echo "This script has been sourced successfully"
echo



