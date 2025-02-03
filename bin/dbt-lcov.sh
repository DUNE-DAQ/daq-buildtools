#!/bin/bash

if [[ -z $DBT_AREA_ROOT ]]; then
    echo "Error: work area needs to be set up for this script to function. Exiting..." >&2
    exit 1
fi

cd $DBT_AREA_ROOT

if [[ -z $( grep profile-arcs sourcecode/CMakeLists.txt ) ]]; then

    echo -n "INSTRUMENTING YOUR sourcecode/CMakeLists.txt FILE FOR lcov..."
    sleep 5
    
sed  -i '/daq_add_subpackages("\${build_order}")/i \
SET(GCC_COVERAGE_COMPILE_FLAGS "-O0 -g -fprofile-arcs -ftest-coverage -fno-inline")\
SET(GCC_COVERAGE_LINK_FLAGS    "-lgcov")\
SET(CMAKE_CXX_FLAGS  "${CMAKE_CXX_FLAGS} ${GCC_COVERAGE_COMPILE_FLAGS}")\
SET(CMAKE_EXE_LINKER_FLAGS  "${CMAKE_EXE_LINKER_FLAGS} ${GCC_COVERAGE_LINK_FLAGS}")\n' sourcecode/CMakeLists.txt || exit 5

echo "done."

fi

dbt-build --clean || exit 3

output_dir="code_coverage_results"
mkdir -p $output_dir
cd $output_dir

numerator_file=$PWD/code.numerator
denominator_file=$PWD/code.denominator

spack load lcov || exit 3

# Reset all execution counts to zero, if we've already run this script
lcov  --zerocounters --directory $DBT_AREA_ROOT || exit 4

# The --ignore-errors argument below means we don't want an error over
# a line mismatch between the source code and the coverage data. This
# is thanks to our use of macros in our unit tests and elsewhere.

lcov -i --capture --directory $DBT_AREA_ROOT/build --output-file  $denominator_file --ignore-errors mismatch,mismatch --include "$DBT_AREA_ROOT/sourcecode/*" || exit 5

spack unload lcov || exit 6

# Run the unit tests in our repos, and then we'll figure out what fraction of the code the tests hit
dbt-build --unittest || exit 7

spack load lcov || exit 8

lcov --capture --directory $DBT_AREA_ROOT/build --output-file  $numerator_file  --ignore-errors mismatch,mismatch --include "$DBT_AREA_ROOT/sourcecode/*" || exit 9

lcov --add-tracefile $denominator_file --add-tracefile $numerator_file --output-file $PWD/code.result || exit 10

genhtml --demangle-cpp -o  $PWD/html  $PWD/code.result || exit 11

echo "Script completed successfully. Results are in $output_dir"
