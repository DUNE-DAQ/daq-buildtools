#!/usr/bin/env python3

import os
DBT_ROOT=os.environ["DBT_ROOT"]
exec(open(f'{DBT_ROOT}/scripts/dbt_setup_constants.py').read())

import sys
if sys.prefix == sys.base_prefix:
    rich.print("You need your Python virtualenv to be set up for this script to work; have you run dbt-workarea-env yet?", file=sys.stderr)
    rich.print("See https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-buildtools/ for details", file=sys.stderr)
    sys.exit(1)

import argparse
from colorama import Fore, Style
import io
import re
import sh
import shutil
from shutil import rmtree, which
from time import sleep
import rich
import json

sys.path.append(f'{DBT_ROOT}/scripts')

from dbt_setup_tools import error, find_work_area, get_time, get_num_processors
import pytee


def get_package_list( build_dir ) :
    return sh.find(r"-L . -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles  -printf %f\n".split()).split()


usage_blurb=f"""

Usage
-----

      {os.path.basename(__file__)} [-c/--clean] [-d/--debug] [-j<n>/--jobs <number parallel build jobs>] [--unittest (<optional package name>)] [--lint (<optional package name)>] [-v/--cpp-verbose] [-h/--help]
      
        -c/--clean means the contents of ./build are deleted and CMake's config+generate+build stages are run
        -d/--debug means you want to build your software with optimizations off and debugging info on
        -j/--jobs means you want to specify the number of jobs used by cmake to build the project
        --unittest means that unit test executables found in ./build/<optional package name>/unittest are run, or all unit tests in ./build/*/unittest are run if no package name is provided
        --lint means you check for deviations in ./sourcecode/<optional package name> from the DUNE style guide, https://dune-daq-sw.readthedocs.io/en/latest/packages/styleguide/, or deviations in all local repos if no package name is provided
        -v/--cpp-verbose means that you want verbose output from the compiler
        --cmake-msg-lvl setting "CMAKE_MESSAGE_LOG_LEVEL", default is "NOTICE", choices are ERROR|WARNING|NOTICE|STATUS|VERBOSE|DEBUG|TRACE.
        --cmake-trace enable cmake tracing
        --cmake-graphviz generates a target dependency graph

    
    All arguments are optional. With no arguments, CMake will typically just run 
    build, unless build/CMakeCache.txt is missing    


"""

BASEDIR=find_work_area()
if not os.path.exists(BASEDIR):
    error("daq-buildtools work area directory not found. Exiting...")

BUILDDIR=f"{BASEDIR}/build"
LOGDIR=f"{BASEDIR}/log"
SRCDIR=f"{BASEDIR}/sourcecode"
INSTALLDIR=os.environ['DBT_INSTALL_DIR']

parser = argparse.ArgumentParser(usage=usage_blurb)
parser.add_argument("-c", "--clean", action="store_true", dest="clean_build", help=argparse.SUPPRESS)
parser.add_argument("-d", "--debug", action="store_true", dest='debug_build', help=argparse.SUPPRESS)
parser.add_argument("-v", "--cpp-verbose", action="store_true", dest='cpp_verbose', help=argparse.SUPPRESS)
parser.add_argument("-j", "--jobs", action='store', type=int, dest='n_jobs', help=argparse.SUPPRESS)
parser.add_argument("--unittest", nargs="?", const="all", help=argparse.SUPPRESS)
parser.add_argument("--lint", nargs="?", const="all", help=argparse.SUPPRESS)
parser.add_argument("-i", "--install", action="store_true", help=argparse.SUPPRESS)
parser.add_argument("--cmake-msg-lvl", dest="cmake_msg_lvl", help=argparse.SUPPRESS)
parser.add_argument("--cmake-trace", action="store_true", dest="cmake_trace", help=argparse.SUPPRESS)
parser.add_argument("--cmake-graphviz", action="store_true", dest="cmake_graphviz", help=argparse.SUPPRESS)

args = parser.parse_args()

run_tests = False
if args.unittest:
    run_tests=True
    if args.unittest != "all":
        package_to_test = args.unittest

if args.lint:
    lint=True
    if args.lint != "all":
        package_to_lint = args.lint

if args.install:
    error("Use of -i/--install is deprecated as installation always occurs now; run with \" --help\" to see valid options. Exiting...")

if "DBT_WORKAREA_ENV_SCRIPT_SOURCED" not in os.environ:
    error("""
It appears you haven't yet executed "dbt-workarea-env"; please do so before 
running this script. Exiting...                                                                                 
    """)

if not os.path.exists(BUILDDIR):
    error(f"Expected build directory \"{BUILDDIR}\" not found. Exiting...")
os.chdir(BUILDDIR)

if args.clean_build:
    # Want to be damn sure we're in the right directory, recursive directory removal is no joke...
    if os.path.basename(os.getcwd()) == "build":
        rich.print(f"""
Clean build requested, will delete all the contents of build directory \"{os.getcwd()}\".
If you wish to abort, you have 5 seconds to hit Ctrl-c"
        """)
        sleep(5)
        
        for filename in os.listdir(os.getcwd()):
            file_path = os.path.join(os.getcwd(), filename)
            if os.path.isfile(file_path) or os.path.islink(file_path):
                os.unlink(file_path)
            elif os.path.isdir(file_path):
                rmtree(file_path)
    else:
        error(f"""
You requested a clean build, but this script thinks that {os.getcwd()} isn't 
the build directory. Please contact John Freeman at jcfree@fnal.gov and notify him of this message.
        """)


stringio_obj2 = io.StringIO()
sh.date(_out=stringio_obj2)
datestring=re.sub("[: ]+", "_", stringio_obj2.getvalue().strip())

build_log=f"{LOGDIR}/build_attempt_{datestring}.log"

cmake="cmake"
if args.cmake_trace:
    cmake = f"{cmake} --trace"

# We usually only need to explicitly run the CMake configure+generate
# makefiles stages when it hasn't already been successfully run;
# otherwise we can skip to the compilation. We use the existence of
# CMakeCache.txt to tell us whether this has happened; notice that it
# gets renamed if it's produced but there's a failure.

running_config_and_generate=False

if not os.path.exists("CMakeCache.txt"):
    running_config_and_generate = True

    generator_arg=""
    if "SETUP_NINJA" in os.environ:
        generator_arg="-G Ninja"

    stringio_obj3 = io.StringIO()
    the_which_cmd = sh.Command("which")  # Needed because of a complex alias, at least on mu2edaq
    the_which_cmd("moo", _out=stringio_obj3)
    moo_path=stringio_obj3.getvalue().strip().split()[-1]
    
    starttime_cfggen_d=get_time("as_date")
    starttime_cfggen_s=get_time("as_seconds_since_epoch")

    debug_build="false"
    if args.debug_build:
        debug_build="true"

    cmake_msg_lvl="NOTICE"
    if args.cmake_msg_lvl:
        cmake_msg_lvl = args.cmake_msg_lvl

    fullcmd="{} -DCMAKE_MESSAGE_LOG_LEVEL={} -DMOO_CMD={} -DDBT_ROOT={} -DDBT_DEBUG={} -DCMAKE_INSTALL_PREFIX={} {} {}".format(cmake, cmake_msg_lvl, moo_path, os.environ["DBT_ROOT"], debug_build, os.environ["DBT_INSTALL_DIR"], generator_arg, SRCDIR)

    rich.print(f"Executing '{fullcmd}'")
    retval=pytee.run(fullcmd.split(" ")[0], fullcmd.split(" ")[1:], build_log)

    endtime_cfggen_d=get_time("as_date")
    endtime_cfggen_s=get_time("as_seconds_since_epoch")
    
    if retval == 0:
        cfggentime=int(endtime_cfggen_s) - int(starttime_cfggen_s)
        rich.print("CMake's config+generate stages took {} seconds".format(cfggentime))
        rich.print("Start time: {}".format(starttime_cfggen_d))
        rich.print("End time:   {}".format(endtime_cfggen_d))
    else:
        shutil.move("CMakeCache.txt", "CMakeCache.txt.most_recent_failure")

        error(f"""

This script ran into a problem running 

{fullcmd} 

from {BUILDDIR} (i.e., CMake's config+generate stages). 
Scroll up for details or look at the build log via 

less -R {BUILDDIR}

Exiting...

""")

else: 
    rich.print(f"The config+generate stage was skipped as CMakeCache.txt was already found in {BUILDDIR}")

if args.cmake_graphviz:
    output = sh.cmake(["--graphviz=graphviz/targets.dot", "."])
    sys.exit(output.exit_code)

if args.n_jobs:
    nprocs_argument = f"-j {args.n_jobs}"
else:
    nprocs = get_num_processors()
    nprocs_argument = f"-j {nprocs}"
    
    rich.print(f"This script believes you have {nprocs} processors available on this system, and will use as many of them as it can")

starttime_build_d=get_time("as_date")    
starttime_build_s=get_time("as_seconds_since_epoch")

build_options=""
if args.cpp_verbose:
    build_options=" --verbose"

if not args.cmake_trace:
    build_options=f"{build_options} {nprocs_argument}"

fullcmd=f"{cmake} --build . {build_options}"

rich.print(f"Executing '{fullcmd}'")
retval=pytee.run(fullcmd.split(" ")[0], fullcmd.split(" ")[1:], build_log)

endtime_build_d=get_time("as_date")
endtime_build_s=get_time("as_seconds_since_epoch")

if retval == 0:
    buildtime=int(endtime_build_s) - int(starttime_build_s)
else:
    error(f"""
This script ran into a problem running 

{fullcmd} 

from {BUILDDIR} (i.e.,
CMake's build stage). Scroll up for details or look at the build log via 

less -R {build_log}

Exiting...
""")

stringio_obj4 = io.StringIO()

num_estimated_warnings = 0
try:
    sh.wc(sh.grep("warning: ", build_log), "-l", _out=stringio_obj4)
    num_estimated_warnings=stringio_obj4.getvalue().strip()
except sh.ErrorReturnCode_1:
    pass

rich.print("")

if running_config_and_generate:
    rich.print("CMake's config+generate+build stages all completed successfully")
    rich.print("")
else:
    rich.print("CMake's build stage completed successfully")

if "DBT_INSTALL_DIR" in os.environ and not re.search(r"^/?$", os.environ["DBT_INSTALL_DIR"]):
    for filename in os.listdir(os.environ["DBT_INSTALL_DIR"]):
        file_path = os.path.join(os.environ["DBT_INSTALL_DIR"], filename)
        if os.path.isfile(file_path) or os.path.islink(file_path):
            os.unlink(file_path)
        elif os.path.isdir(file_path):
            rmtree(file_path)
else:
    error("$DBT_INSTALL_DIR is not properly defined, which would result in the deletion of the entire contents of this system if it weren't for this check!!!")


os.chdir(BUILDDIR)

fullcmd=f"cmake --build . --target install -- {nprocs_argument}"
retval = pytee.run(fullcmd.split()[0], fullcmd.split()[1:], None)
if retval == 0:
    rich.print(f"""
Installation complete.
This implies your code successfully compiled before installation; you can
either scroll up or run \"less -R {build_log}\" to see build results""")
else:
    error(f"Installation failed. There was a problem running \"{fullcmd}\". Exiting...")

summary_build_info = {}
for pkg in get_package_list(BUILDDIR):
    with open(f"{INSTALLDIR}/{pkg}/{pkg}_build_info.json") as f:
        summary_build_info[pkg] = json.load(f)

with open(f"{INSTALLDIR}/build_summary_info.json", 'w') as sbi_f:
    json.dump( summary_build_info, sbi_f, sort_keys=True, indent=4 )

if run_tests:
    stringio_obj5 = io.StringIO()
    sh.date(_out=stringio_obj5)
    datestring=re.sub("[: ]+", "_", stringio_obj5.getvalue().strip())

    test_log=f"{LOGDIR}/unit_tests_{datestring}.log"

    os.chdir(BUILDDIR)
    
    if args.unittest == "all":
        stringio_obj6 = io.StringIO()
        sh.find("-L . -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles".split(), _out = stringio_obj6)
        package_list = stringio_obj6.getvalue().split()
    else:
        package_list = [ package_to_test ]

    for pkgname in package_list:
        fullcmd=(f"find -L {BUILDDIR}/{pkgname} -type d -name unittest -not -regex .*CMakeFiles.*")
        stringio_obj7 = io.StringIO()
        sh.find(fullcmd.split()[1:], _out=stringio_obj7)
        unittestdirs = stringio_obj7.getvalue().split()

        if len(unittestdirs) == 0:
            rich.print("{}No unit tests have been written for {}{}".format(Fore.RED, pkgname, Style.RESET_ALL), file = sys.stderr)            
            continue

        if not "BOOST_TEST_LOG_LEVEL" in os.environ:
            os.environ["BOOST_TEST_LOG_LEVEL"] = "all"

        num_unit_tests = 0

        for unittestdir in unittestdirs:
            rich.print(f"""

RUNNING UNIT TESTS IN {unittestdir}
======================================================================
""")
            for unittest in os.listdir(unittestdir):
                rich.print(f"unittest == {unittest}")
                if which(f"{unittestdir}/{unittest}", mode=os.X_OK) is not None:
                    pytee.run("echo", "-e Start of unit test suite {}".format(unittest).split(), test_log)
                    pytee.run(f"{unittestdir}/{unittest}", "", test_log)
                    num_unit_tests += 1

            rich.print("{}Testing complete for package \"{}\". Ran {} unit test suites.{}".format(Fore.YELLOW, pkgname, num_unit_tests, Style.RESET_ALL))
            rich.print("")
            rich.print(f"Test results are saved in {test_log}")

if args.lint:
    os.chdir(BASEDIR)

    stringio_obj8 = io.StringIO()
    sh.date(_out=stringio_obj8)
    datestring=re.sub("[: ]+", "_", stringio_obj8.getvalue().strip())
    
    lint_log=f"{BASEDIR}/linting_{datestring}.log"

    if not os.path.exists("styleguide"):
        rich.print(f"Cloning styleguide into {os.getcwd()} so linting can be applied")
        sh.git("clone", "https://github.com/DUNE-DAQ/styleguide.git")

        if not os.path.exists("styleguide"):
            error("There was a problem cloning the styleguide repo needed for linting into {}".format(os.getcwd()))

    if args.lint == "all":
        stringio_obj9 = io.StringIO()
        sh.find("-L build -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles".split(), _out = stringio_obj9)
        package_list = stringio_obj9.getvalue().split()
    else:
        package_list = [ package_to_lint ]

    for pkgdir in package_list:
        pkgname=os.path.basename(pkgdir)
        rich.print(f"Package to lint is {pkgname}")
        fullcmd = f"./styleguide/cpplint/dune-cpp-style-check.sh build sourcecode/{pkgname}"
        pytee.run(fullcmd.split()[0], fullcmd.split()[1:], lint_log)

 
