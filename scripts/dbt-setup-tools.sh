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
  echo -e "${COL_YELLOW}DEPRECATION WARNING: ${SCRIPT_NAME} has been replaced by ${SCRIPT_NAME%.*}. ${SCRIPT_NAME} is deprecated and will be removed in future releases.${COL_RESET}"
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

    local spack_setup_script=""
    if [[ -z $LOCAL_SPACK_DIR ]]; then
	spack_setup_script=$( realpath $SPACK_RELEASES_DIR/$SPACK_RELEASE/spack-0.22.0/share/spack/setup-env.sh 2>/dev/null )
	if [[ -z $spack_setup_script ]]; then   # Backwards compatibility with the old directory structure
	    spack_setup_script=$( realpath $SPACK_RELEASES_DIR/$SPACK_RELEASE/default/spack-0.22.0/share/spack/setup-env.sh )
	fi

    else
	echo -e "${COL_GREEN}Local spack directory is set, loading...${COL_RESET}\n"
	spack_setup_script=`realpath $LOCAL_SPACK_DIR/share/spack/setup-env.sh`
    fi
    
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

    return 0
}  
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function spack_load_target_package() {

    local spack_pkgname=$1
    local spack_pkg

    if [[ $spack_pkgname =~ (nd|fd|core|dune)daq ]]; then
        spack_pkg=$spack_pkgname@${SPACK_RELEASE}
    else
	local base_release=$( spack find --format "{version}" coredaq )

	# JCF, Apr-11-2024: Check and see if the old name for the core
	# packages is used in this release

	if [[ "$base_release" =~ "No package matches the query" ]]; then
	    base_release=$( spack find --format "{version}" dunedaq )
	fi

	if [[ "$base_release" =~ "No package matches the query" ]]; then
	    spack_pkg=$spack_pkgname
        else
	    spack_pkg=$spack_pkgname@${base_release}
	fi
    fi

    pkg_loaded_status=$(spack find --loaded -l $spack_pkg | sed -r -n '/^\w{7} '$spack_pkgname'/p' )
    
    if [[ -z $pkg_loaded_status || $pkg_loaded_status =~ "0 loaded packages" || $pkg_loaded_status =~ "No package matches the query: $spack_pkgname" ]]; then

	local cmd=""
	if [[ -n $SPACK_VERBOSE ]] && $SPACK_VERBOSE ; then
	    cmd="spack --debug load $spack_pkg"
	else
	    cmd="spack load $spack_pkg"
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
    echo
    ls | sort | grep -Ev "^dunedaq-|^NB|^rc-|^coredaq-" | xargs -i printf " - %s\n" {}
    echo
    popd >& /dev/null
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function stack_new_spack() {

    local existing_spack_dir=$1
    local new_spack_dir=$2

    rsync -rlpt --exclude 'opt/spack/gcc*' --exclude 'opt/spack/linux*' --exclude 'spack-repo' $existing_spack_dir/* $new_spack_dir

    mkdir -p $new_spack_dir/spack-repo/packages
    echo "repo:" > $new_spack_dir/spack-repo/repo.yaml
    echo "  namespace: 'LOCAL_SPACK'" >> $new_spack_dir/spack-repo/repo.yaml
    
    sed -i '2 i \  - '"$new_spack_dir"'/spack-repo' $new_spack_dir/etc/spack/defaults/repos.yaml
    sed -i '2 i \  '"$SPACK_RELEASE"':' $new_spack_dir/etc/spack/defaults/upstreams.yaml
    sed -i '3 i \    install_tree: '"$existing_spack_dir"'/opt/spack' $new_spack_dir/etc/spack/defaults/upstreams.yaml

    source $new_spack_dir/share/spack/setup-env.sh
    spack reindex
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
function load_yaml() {
    python3 -c "import yaml;print(yaml.safe_load(open('$1'))$2)"
}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------

# JCF, Apr-16-2024
# Based on the requirements in Issue #273, this function will take the
# name of an environment variable (DUNEDAQ_DB_PATH, e.g.) and proceed
# to prioritize directories as follows:

# 1) User directories that aren't a source code or local installation directory
# 2) Source code directories in the work area
# 3) Installation directories in the work area
# 4) Any other directories (/cvmfs, etc.)

function prioritize_directories() {

    local dirlist_name="$1"

    local install_patt="$DBT_INSTALL_DIR/*"
    local sourcecode_patt="$DBT_AREA_ROOT/sourcecode/*"
    local user_patt="$HOME/*"

    local priority_level1=()
    local priority_level2=()
    local priority_level3=()
    local priority_level4=()

    local dirlist="${!dirlist_name}"
    IFS=':' read -r -a dirs <<< "$dirlist"

    for dir in "${dirs[@]}"; do

        if [[ "$dir" == $user_patt && ! "$dir" == $sourcecode_patt && ! "$dir" == $install_patt ]]; then
	    priority_level1+=("$dir")
	elif [[ "$dir" == $sourcecode_patt ]]; then
	    priority_level2+=("$dir")
	elif [[ "$dir" == $install_patt ]]; then
	    priority_level3+=("$dir")
	else
	    priority_level4+=("$dir")
	fi
    done

    # First sed command is swapping whitespace for a ":", second is to remove leading and trailing ":"s

    local reordered_dirs=$( echo "${priority_level1[*]}" "${priority_level2[*]}" "${priority_level3[*]}" "${priority_level4[*]}" | sed -r 's/\s+/:/g' | sed -r 's/^:*(.*[^:]).*$/\1/' )

    eval "$dirlist_name=\"$reordered_dirs\""

}


#------------------------------------------------------------------------------
