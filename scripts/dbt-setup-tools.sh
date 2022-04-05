#------------------------------------------------------------------------------
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

#------------------------------------------------------------------------------
# Constants

# Colors
COL_RED="\e[31m"
COL_GREEN="\e[32m"
COL_YELLOW="\e[33m"
COL_BLUE="\e[34m"
COL_CYAN="\e[36m"
COL_RESET="\e[0m"

source ${HERE}/dbt-setup-constants.sh

#------------------------------------------------------------------------------
function deprecation_warning() {
  SCRIPT_NAME=$( basename -- $0 )
  echo 
  echo -e "${COL_YELLOW}DEPRECATION WARNING: ${SCRIPT_NAME} has been replaced by ${SCRIPT_NAME%.*}.py. ${SCRIPT_NAME} is deprecated and will be removed in future releases.${COL_RESET}"
  echo 
}

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

  if [ -z "${1}" ]; then
    echo "Usage: setup_ups_products <product list name>";
  fi

  if [ -z "${!1}" ]; then
    echo "Product list '${1}' doesn't exist";
    return 5
  fi


  product_set_name=${1}
  product_set="${product_set_name}[@]"

  # And another function here?
  setup_ups_returns=""

  for prod in "${!product_set}"; do
      prodArr=(${prod})

      setup_cmd="setup -B ${prodArr[0]//-/_} ${prodArr[1]}"
      if [[ ${#prodArr[@]} -eq 3 ]]; then
          setup_cmd="${setup_cmd} -q ${prodArr[2]}"
      fi
      echo $setup_cmd
      ${setup_cmd}
      setup_ups_returns=$setup_ups_returns"$? "
  done

  # Adding code here make setup return disappear. Mhhh...
}
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
function find_work_area() {
  SLASHES=${PWD//[^\/]/}

  SEARCH_PATH=${PWD}
  WA_PATH=""
  for(( i=${#SLASHES}-1; i>0; i--)); do
    WA_SEARCH_PATH="${SEARCH_PATH}/${DBT_AREA_FILE}"
    # echo "Looking for $WA_SEARCH_PATH"
    if [ -f "${WA_SEARCH_PATH}" ]; then
      WA_PATH="${WA_SEARCH_PATH}"
      break
    fi
    SEARCH_PATH=$(dirname ${SEARCH_PATH})
  done

  if [[ -z ${WA_PATH} ]]; then
    return
  fi
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

  ACTION="${COL_BLUE}Added"
  
  # Add the new path only if it is not already there
  if [[ ":$PATH_VAL:" == *":$PATH_ADD:"* ]]; then

    ACTION="${COL_CYAN}Updated"

    # Remove PATH_ADD from PATH_VAL, such that it can be added later.
    PATH_TMP=:$PATH_VAL:
    PATH_TMP=${PATH_TMP//:${PATH_ADD}:/:}
    PATH_TMP=${PATH_TMP#:}; PATH_TMP=${PATH_TMP%:}
    PATH_VAL=${PATH_TMP}
  fi

  # Note
  # ${PARAMETER:+WORD}
  #   This form expands to nothing if the parameter is unset or empty. If it
  #   is set, it does not expand to the parameter's value, but to some text
  #   you can specify
  PATH_VAL="$PATH_ADD${PATH_VAL:+":$PATH_VAL"}"

  echo -e "${ACTION} ${PATH_ADD} -> ${PATH_NAME}${COL_RESET}"

  # use eval to reset the target
  eval "${PATH_NAME}=${PATH_VAL}"
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
function add_many_paths_if_exist() {
  for d in "${@:2}"
  do
    if [ -d "$d" ]; then
      add_path $1 $d
    fi
  done
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function remove_path() {
  # Assert that we got enough arguments
  if [[ $# -ne 2 ]]; then
    echo "path remove: needs 2 arguments"
    return 1
  fi
  PATH_NAME=$1
  PATH_REMOVE=$2

  ACTION="${COL_BLUE}Removed"

  cmd="$PATH_NAME=$( eval echo \$$PATH_NAME | sed -r 's!'$PATH_REMOVE':!!g' )"
  eval $cmd
  
  cmd="$PATH_NAME=$( eval echo \$$PATH_NAME | sed -r 's!:'$PATH_REMOVE'$!!g' )"
  eval $cmd

  echo -e "${ACTION} ${PATH_REMOVE} -> ${PATH_NAME}${COL_RESET}"
}
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
function backtrace () {
    local deptn=${#FUNCNAME[@]}

    for ((i=1; i<$deptn; i++)); do
        local func="${FUNCNAME[$i]}"
        local line="${BASH_LINENO[$((i-1))]}"
        local src="${BASH_SOURCE[$((i))]}"
        printf '%*s' $i '' # indent
        echo "at: $func(), $src, line $line"
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

  dbt_file=$( basename ${BASH_SOURCE[2]} )

  timenow="date \"+%D %T\""
  echo -n "ERROR: [`eval $timenow`] [${dbt_file}:${BASH_LINENO[1]}]:" >&2
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function error() {

    error_preface
    echo -e " ${COL_RED} ${1} ${COL_RESET} " >&2

    if [[ "${FUNCNAME[-1]}" == "main" ]]; then
        exit 100
    fi
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function spack_setup_env() {

    
    if [[ -z $DBT_DUNE_DAQ_BASE_RELEASE ]]; then
	error "Environment variable DBT_DUNE_DAQ_BASE_RELEASE needs to be set for this script to work. Exiting..."
    fi

    if [[ -z $SPACK_RELEASES_DIR ]]; then
	error "Environment variable SPACK_RELEASES_DIR needs to be set for this script to work. Exiting..."
    fi
    
    local spack_setup_script=$SPACK_RELEASES_DIR/$DBT_DUNE_DAQ_BASE_RELEASE/spack-0.17.1/share/spack/setup-env.sh
    if [[ ! -e $spack_setup_script ]]; then
	error "Unable to find Spack setup script \"$spack_setup_script\""
	return 1
    fi

    source $spack_setup_script
    retval=$?
    if [[ "$retval" != "0" ]]; then
	error "There was a problem source-ing Spack setup script \"$spack_setup_script\""
	return $retval
    fi

    spack env activate ${DBT_DUNE_DAQ_BASE_RELEASE//./-}
    retval=$?
    if [[ "$retval" != "0" ]]; then
	error "There was a problem running \"spack env activate $DBT_DUNE_DAQ_BASE_RELEASE\""
	return $retval
    fi

    return 0
}  
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function spack_load_target_package() {

    local spack_pkgname=$1
    pkg_loaded_status=$(spack find --loaded -l $spack_pkgname@${DBT_DUNE_DAQ_BASE_RELEASE} | sed -r -n '/^\w{7} '$spack_pkgname'/p' )
    
    if [[ -z $pkg_loaded_status || $pkg_loaded_status =~ "0 loaded packages" || $pkg_loaded_status =~ "No package matches the query: $spack_pkgname" ]]; then

	local cmd=""
	if [[ -n $SPACK_VERBOSE ]] && $SPACK_VERBOSE ; then
	    cmd="spack --debug load $spack_pkgname@${DBT_DUNE_DAQ_BASE_RELEASE}"
	else
	    cmd="spack load $spack_pkgname@${DBT_DUNE_DAQ_BASE_RELEASE}"
	fi


	cat<<EOF

Calling "$cmd"; will print "Finished" 
when successfully done. If this is the first time you've run this
command in a while on this node it may take ~15 minutes; this is
because cvmfs is populating its local cache. Please be patient;
subsequent runs should take less than a minute.

EOF
	$cmd
	retval=$?
	if [[ "$retval" == "0" ]]; then
	    echo "Finished"
	else
	    error "There was a problem calling ${cmd}"
	    return $retval
	fi
	
    else
	spack find -p -l --loaded $spack_pkgname
	error "There already appear to be \"$spack_pkgname\" packages loaded in; this is disallowed."
	return 1
    fi

}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function list_releases() {
    if [[ -z $1 ]]; then
	# How? RELEASE_BASEPATH subdirs matching some condition? i.e. dunedaq_area.sh file in it?
	FOUND_RELEASES=($(find -L ${RELEASE_BASEPATH} -maxdepth 2 -name ${UPS_PKGLIST} -printf '%h '))
	readarray -t SORTED_RELEASES < <(printf '%s\n' "${FOUND_RELEASES[@]}" | sort)

	for rel in "${SORTED_RELEASES[@]}"; do
            echo " - $(basename ${rel})"
	done 
    elif [[ -n $1 && "$1" =~ "--spack" ]]; then

	spack_setup_env
	if [[ "$?" != "0" ]]; then
	    error "There was a problem setting up the Spack environment; returning..."
	    return 1
	fi

	cmd="spack find -l dune-daqpackages | sed -r -n \"s/^\\S+\\s+dune-daqpackages@(\\S+)\\s*\$/ - \\1/p\""
	eval $cmd
	if [[ "$?" != "0" ]]; then
	    error "There was a problem calling \"$cmd\"; returning..."
	    return 2
	fi
    else
	echo "Developer error. Please contact John Freeman at jcfree@fnal.gov" >&2
    fi

}
#------------------------------------------------------------------------------
