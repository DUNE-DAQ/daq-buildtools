#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

#------------------------------------------------------------------------------
# Constants

# Colors
COL_RED="\e[31m"
COL_GREEN="\e[32m"
COL_YELLOW="\e[33m"
COL_BLUE="\e[34m"
COL_NULL="\e[0m"

source ${HERE}/dbt-setup-constants.sh

#------------------------------------------------------------------------------
function setup_ups_product_areas() {
  
  if [ -z "${dune_products_dirs}" ]; then
    echo "UPS product directories variable (dune_products_dirs) undefined; no products areas will be set up" >&2
  fi

  for proddir in ${dune_products_dirs[@]}; do
      source ${proddir}/setup
      if ! [[ $? -eq 0 ]]; then
	  echo "Warning: unable to set up products area \"${proddir}\"" >&2
      fi
  done

}
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
function setup_ups_products() {

  if [ -z "${dune_products}" ]; then
    echo "UPS products variable (dune_products_dirs) undefined";
  fi

  # And another function here?
  setup_returns=""

  for prod in "${dune_products[@]}"; do
      prodArr=(${prod})

      setup_cmd="setup ${prodArr[0]//-/_} ${prodArr[1]}"
      if [[ ${#prodArr[@]} -eq 3 ]]; then
          setup_cmd="${setup_cmd} -q ${prodArr[2]}"
      fi
      echo $setup_cmd
      ${setup_cmd}
      setup_returns=$setup_returns"$? "
  done
}
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
function find_work_area() {
  SLASHES=${PWD//[^\/]/}

  SEARCH_PATH=${PWD}
  WA_PATH=""
  for(( i=${#SLASHES}; i>0; i--)); do
    WA_SEARCH_PATH="${SEARCH_PATH}/${DBT_AREA_FILE}"
    # echo "Looking for $WA_SEARCH_PATH"
    if [ -f "${WA_SEARCH_PATH}" ]; then
      WA_PATH="${WA_SEARCH_PATH}"
      break
    fi
    SEARCH_PATH=$(dirname ${SEARCH_PATH})
  done

  echo $(dirname ${WA_PATH})
}
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
function add_path() {
  # Assert that we got enough arguments
  if [[ $# -ne 2 ]]; then
    echo "path add: needs 2 arguments"
    return 1
  fi
  PATH_NAME=$1
  PATH_VAL=${!1}
  PATH_ADD=$2

  # Add the new path only if it is not already there
  if [[ ":$PATH_VAL:" != *":$PATH_ADD:"* ]]; then
    # Note
    # ${PARAMETER:+WORD}
    #   This form expands to nothing if the parameter is unset or empty. If it
    #   is set, it does not expand to the parameter's value, but to some text
    #   you can specify
    PATH_VAL="$PATH_ADD${PATH_VAL:+":$PATH_VAL"}"

    echo -e "${COL_BLUE}Added ${PATH_ADD} to ${PATH_NAME}${COL_NULL}"

    # use eval to reset the target
    eval "${PATH_NAME}=${PATH_VAL}"
  fi
}
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
function add_many_paths() {
  for d in "${@:2}"
  do
    add_path $1 $d
  done
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function error_preface() {

  for dbt_file in "${BASH_SOURCE[@]}"; do
    if ! [[ "${BASH_SOURCE[0]}" =~ "$dbt_file" ]]; then
	    break
	   fi
  done

  dbt_file=$( basename $dbt_file )

  timenow="date \"+%D %T\""
  echo -n "ERROR: [`eval $timenow`] [${dbt_file}]:" >&2
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function error() {

    error_preface
    echo -e " ${COL_RED} ${1} ${COL_NULL} " >&2

    if [[ -x ${BASH_SOURCE[-1]} ]]; then
        exit 100
    fi
}
#------------------------------------------------------------------------------

  
