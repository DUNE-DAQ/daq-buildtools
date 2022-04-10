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

    
    if [[ -z $SPACK_RELEASE ]]; then
	error "Environment variable SPACK_RELEASE needs to be set for this script to work. Exiting..."
	return 1
    fi

    if [[ -z $SPACK_RELEASES_DIR ]]; then
	error "Environment variable SPACK_RELEASES_DIR needs to be set for this script to work. Exiting..."
	return 2
    fi
    
    local spack_setup_script=`realpath $SPACK_RELEASES_DIR/$SPACK_RELEASE/spack-installation/share/spack/setup-env.sh`
    if [[ ! -e $spack_setup_script ]]; then
	error "Unable to find Spack setup script \"$spack_setup_script\""
	return 3
    fi

    source $spack_setup_script
    retval=$?
    if [[ "$retval" != "0" ]]; then
	error "There was a problem source-ing Spack setup script \"$spack_setup_script\""
	return $retval
    fi

    spack env activate ${SPACK_RELEASE//./-} -p
    retval=$?
    if [[ "$retval" != "0" ]]; then
	error "There was a problem running \"spack env activate $SPACK_RELEASE\""
	return $retval
    fi

    return 0
}  
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function spack_load_target_package() {

    local spack_pkgname=$1
    pkg_loaded_status=$(spack find --loaded -l $spack_pkgname@${SPACK_RELEASE} | sed -r -n '/^\w{7} '$spack_pkgname'/p' )
    
    if [[ -z $pkg_loaded_status || $pkg_loaded_status =~ "0 loaded packages" || $pkg_loaded_status =~ "No package matches the query: $spack_pkgname" ]]; then

	local cmd=""
	if [[ -n $SPACK_VERBOSE ]] && $SPACK_VERBOSE ; then
	    cmd="spack --debug load $spack_pkgname@${SPACK_RELEASE}"
	else
	    cmd="spack load $spack_pkgname@${SPACK_RELEASE}"
	fi


	cat<<EOF

This script is calling "$cmd"; it will print "Finished loading" 
on successful completion. 

If this is the first time the "spack load ..." command has been run in
a while on this node it may take ~15 minutes; this is because cvmfs is
populating its local cache. Please be patient; subsequent runs should
take less than a minute.

EOF
	$cmd
	retval=$?
	if [[ "$retval" == "0" ]]; then
	    echo "Finished loading"
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

    local release_path=$1
    pushd $release_path >& /dev/null
    ls | sort | xargs -i printf " - %s" {}
    popd >& /dev/null
    echo
}
#------------------------------------------------------------------------------
