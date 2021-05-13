#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)



DBT_PKG_SETS=( devtools systems externals daqpackages )

# We use "$@" instead of $* to preserve argument-boundary information
options=$(getopt -o 'hs:' -l 'help, subset:' -- "$@") || exit
eval "set -- $options"

DBT_PKG_SET="${DBT_PKG_SETS[-1]}"
while true; do
    case $1 in
        (-s|--subset)
            DBT_PKG_SET=$2
            shift 2;;
        (-h|--help)
            cat << EOU
Usage
-----

  dbt-setup-build-environment [-h/--help] [-s/--set [devtools systems externals daqpackages]]

  Sets up the environment of a dbt development area

  Arguments and options:

    -s/--subset: optional set of ups packages to load. [choices: ${DBT_PKG_SETS[@]}]
    
EOU
            return 0;;           # error
        (--)  shift; break;;
        (*) 
            echo "ERROR $@"  
            return 1;;           # error
    esac
done

if [[ -z "${DBT_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED}" ]]; then
    echo "This script hasn't yet been sourced (successfully) in this shell; setting up the build environment"
else
    error "This script appears to have already been sourced successfully. Returning..."
    return 10
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

for ps in ${DBT_PKG_SETS[@]}; do
  setup_ups_products dune_$ps
  all_setup_returns="${setup_ups_returns} ${all_setup_returns}"

  if [ $ps == "$DBT_PKG_SET" ]; then
    break
  fi
done

if ! [[ "$all_setup_returns" =~ [1-9] ]]; then
  echo "All setup calls on the packages returned 0, indicative of success"
else
  error "At least one of the required packages this script attempted to set up didn't set up correctly. Returning..." 
  return 1
fi

export DBT_INSTALL_DIR=${DBT_AREA_ROOT}/install

export DBT_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED=1

unset DBT_PKG_SET DBT_PKG_SETS

echo "This script has been sourced successfully"
echo



