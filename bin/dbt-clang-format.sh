#!/bin/bash

source ${DBT_ROOT}/scripts/dbt-setup-tools.sh
if [[ "$?" != 0 ]]; then
    echo "The source of dbt-setup-tools.sh failed; this may mean you need to set up the dbt-buildtools environment. Exiting..." >&2
    exit 1
fi

print_usage() {
    cat <<EOF >&2

Usage: $(basename "$0") <file or directory to format> [ -v | --view-differences-only ] [ -m | --markdown-summary ]

Given a file, this script will apply clang-format to that file.

Given a directory, it will apply clang-format to all the
source (*.cxx, *.cpp) and header (*.hpp) files in that directory as well as all
of its subdirectories.

Optional arguments:
  -v | --view-differences-only    Show differences without applying them.
  -m | --markdown-summary         Output results in markdown format.
EOF
    exit 1
}

if [[ $# -eq 0 || $# -gt 3 ]]; then
    print_usage
fi

filename=$1
shift
differences_only=false
output_markdown_file=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--view-differences-only)
        if $differences_only ; then
            error "The -v flag can only be used once. Exiting..."
        fi
        differences_only=true
        shift
        ;;
    -m|--markdown-summary)
        if $output_markdown_file ; then
            error "The -m flag can only be used once. Exiting..."
        fi
        output_markdown_file=true
        shift
        ;;
    --)
        shift
        break
        ;;
    -*)
        echo "Invalid option: $1" >&2
        exit 1
        ;;
    *)
        echo "Unexpected argument: $1" >&2
        exit 1
        ;;
  esac
done

if [[ ! -e $filename ]]; then
    error "Unable to find $filename; make sure to pass a file or directory name as the first argument. Exiting..." 
fi

if [[ -z ${DBT_WORKAREA_ENV_SCRIPT_SOURCED:-} ]]; then
 
error "
It appears you haven't yet executed "dbt-workarea-env"; please do so before running this 
script. Exiting..."

fi

which clang-format > /dev/null 2>&1
retval=$?

if [[ "$retval" != "0" ]]; then
    if [[ -n $SPACK_ROOT ]]; then
    
        clang_spack_dir="/cvmfs/dunedaq.opensciencegrid.org/spack/externals"
        llvmdir=$( spack find -p llvm | sed -r -n 's!.*('$clang_spack_dir'.*)$!\1!p' )
    
        if [[ -z $llvmdir ]]; then
            echo "Spack appears to be set up (SPACK_ROOT == $SPACK_ROOT) but unable to find directory for package llvm. Exiting..." >&2
            exit 101
        fi

        cmd="spack load llvm"
        $cmd

        if [[ "$?" != "0" ]]; then
            echo "Unable to successfully call \"$cmd\"; exiting..." >&2
            exit 11
        fi

    else
        clang_version=$( ups list -aK+ clang | sort -n | tail -1 | sed -r 's/^\s*\S+\s+"([^"]+)".*/\1/' )
    
        if [[ -n $clang_version ]]; then
    	    setup clang $clang_version
	    retval="$?"

            if [[ "$retval" == "0" ]]; then
	        echo "Set up clang $clang_version"
            else
                error "
Error: there was a problem executing \"setup clang $clang_version\"
(return value was $retval). Please check the products directories
you've got set up. Exiting..."
            fi
        fi
    fi
fi

clang_format_link="https://raw.githubusercontent.com/DUNE-DAQ/daq-buildtools/develop/configs/.clang-format"

mv -f .clang-format .clang-format.previous  2>/dev/null # In case .clang-format's been updated in daq-buildtools since this script was run

cp ${DBT_ROOT}/configs/.clang-format .

if [[ "$?" != "0" ]]; then
    error "There was a problem copying ${DBT_ROOT}/configs/.clang-format to this directory. Exiting..."
fi

function format_files() {

    local differences_only=$1
    local files_to_format=$2
    local output_markdown_table=$3
    if $output_markdown_table ; then 
        local markdown_content="# Clang-Format Report"
    fi
    previous_package_name=""

    for orig_file in $files_to_format ; do

    this_package_name=$(echo "$orig_file" | cut -d '/' -f 1)
    if [[ "$this_package_name" != "$previous_package_name" ]]; then
        markdown_content+="## $this_package_name \n"
        markdown_content+="| Test | Status| \n| --- | --- |\n"
        previous_package_name=$this_package_name
    fi

	echo "Processing ${orig_file}..."
	tmpfile=/tmp/$( uuidgen )
	clang-format -style=file $orig_file > $tmpfile
	res=$( diff $tmpfile $orig_file )
	diff_retval="$?"
	echo -e " ${COL_RED} ${res} ${COL_RESET} " 
	
	if [[ "$diff_retval" == 0 ]]; then
	    echo
	    echo "$orig_file already properly formatted"
	    echo
        if $output_markdown_table ; then
            markdown_content+="| $orig_file | :white_check_mark: Already formatted |\n"
        fi
    else
        if $output_markdown_table ; then
            markdown_content+="| $orig_file | :x: Needs formatting |\n"
        fi
        if ! $differences_only ; then
            echo "Updating $orig_file with new formatting"
            echo
            mv $tmpfile $orig_file
        fi
    fi
    done
    
    if $output_markdown_table ; then
        markdown_file_name="clang_format_summary_table.md"
        echo -e $markdown_content > $markdown_file_name
        echo -e "Markdown summary table saved as $(readlink -f $markdown_file_name)\n"
    fi
}

files_to_format=""
extensions="*.hpp *.cpp *.cxx *.hxx"

if [[ -d $filename ]]; then
    files_to_format=$( for extension in $extensions ; do find $filename -name $extension; done )
elif [[ -f $filename ]]; then
    extension=$( echo $filename | sed -r 's/.*\.([^.]+)$/\1/' )

    if [[ "$extensions" =~ .*\*\.$extension ]]; then 
	files_to_format=$filename
    else
	error "Filename provided has unknown extension; exiting..." 
    fi
fi

format_files true "$files_to_format" $output_markdown_file

if ! $differences_only ; then
    
    cat<<EOF
You ran this script without the $view_only_option option, are you
sure you want it to perform the edits (if any) suggested by the
file-by-file diffs shown above? Type in yes or no.

EOF

    while true; do
	read -p "" yn
	case $yn in
            [Yy]* ) format_files false "$files_to_format" false; break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
	esac
    done
fi

exit 0
