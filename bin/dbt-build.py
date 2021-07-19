#!/usr/bin/env python3

import argparse
from colorama import Fore, Style
import io
import os
import re
import sh
from shutil import rmtree, which
import sys
from time import sleep

DBT_ROOT=os.environ["DBT_ROOT"]
sys.path.append('{}/scripts'.format(DBT_ROOT))

from dbt_setup_tools import error, find_work_area, get_time, get_num_processors
import pytee

usage_blurb="""

Usage
-----

      "{}" [-c/--clean] [-d/--debug] [-j<n>/--jobs <number parallel build jobs>] [--unittest (<optional package name>)] [--lint (<optional package name)>] [-v/--cpp-verbose] [-h/--help]
      
        -c/--clean means the contents of ./build are deleted and CMake's config+generate+build stages are run
        -d/--debug means you want to build your software with optimizations off and debugging info on
        -j/--jobs means you want to specify the number of jobs used by cmake to build the project
        --unittest means that unit test executables found in ./build/<optional package name>/unittest are run, or all unit tests in ./build/*/unittest are run if no package name is provided
        --lint means you check for deviations in ./sourcecode/<optional package name> from the DUNE style guide, https://dune-daq-sw.readthedocs.io/en/latest/packages/styleguide/index.html, or deviations in all local repos if no package name is provided
        -v/--cpp-verbose means that you want verbose output from the compiler
        --cmake-msg-lvl setting "CMAKE_MESSAGE_LOG_LEVEL", default is "NOTICE", choices are ERROR|WARNING|NOTICE|STATUS|VERBOSE|DEBUG|TRACE.
        --cmake-trace enable cmake tracing
        --cmake-graphviz generates a target dependency graph

    
    All arguments are optional. With no arguments, CMake will typically just run 
    build, unless build/CMakeCache.txt is missing    


""".format(os.path.basename(__file__))

BASEDIR=find_work_area()
if not os.path.exists(BASEDIR):
    error("daq-buildtools work area directory not found. Exiting...")

BUILDDIR="{}/build".format(BASEDIR)
LOGDIR="{}/log".format(BASEDIR)
SRCDIR="{}/sourcecode".format(BASEDIR)


parser = argparse.ArgumentParser(usage=usage_blurb)
parser.add_argument("-c", "--clean", action="store_true", dest="clean_build", help=argparse.SUPPRESS)
parser.add_argument("-d", "--debug", action="store_true", dest='debug_build', help=argparse.SUPPRESS)
parser.add_argument("-v", "--cpp-verbose", action="store_true", dest='cpp_verbose', help=argparse.SUPPRESS)
parser.add_argument("-j", "--jobs", action='store', type=int, dest='n_jobs', help=argparse.SUPPRESS)
parser.add_argument("--unittest", nargs="?", const="all", help=argparse.SUPPRESS)
parser.add_argument("--lint", nargs="?", const="all", help=argparse.SUPPRESS)
parser.add_argument("-i", "--install", action="store_true", help=argparse.SUPPRESS)
parser.add_argument("--cmake-msg-lvl", type=int, dest="cmake_msg_lvl", help=argparse.SUPPRESS)
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
    error("Expected build directory \"{}\" not found. Exiting...".format(BUILDDIR))
os.chdir(BUILDDIR)

if args.clean_build:
    # Want to be damn sure we're in the right directory, recursive directory removal is no joke...
    if os.path.basename(os.getcwd()) == "build":
        print("""
Clean build requested, will delete all the contents of build directory \"{}\".
If you wish to abort, you have 5 seconds to hit Ctrl-c"
        """.format(os.getcwd()))
        sleep(5)
        
        for filename in os.listdir(os.getcwd()):
            file_path = os.path.join(os.getcwd(), filename)
            if os.path.isfile(file_path) or os.path.islink(file_path):
                os.unlink(file_path)
            elif os.path.isdir(file_path):
                rmtree(file_path)
    else:
        error("""
You requested a clean build, but this script thinks that {} isn't 
the build directory. Please contact John Freeman at jcfree@fnal.gov and notify him of this message.
        """.format(os.getcwd()))

    stringio_obj1 = io.StringIO()
    sh.xargs(sh.find(SRCDIR, "-mindepth", "1", "-maxdepth", "1", "-type", "d"), "-i", "basename", "{}", _out=stringio_obj1)
    package_list = stringio_obj1.getvalue().strip().split()

    for pkgname in package_list: 
        if os.path.isdir("{}/{}".format(os.environ["DBT_INSTALL_DIR"], pkgname)):
            rmtree("{}/{}".format(os.environ["DBT_INSTALL_DIR"], pkgname))

stringio_obj2 = io.StringIO()
sh.date(_out=stringio_obj2)
datestring=re.sub("[: ]+", "_", stringio_obj2.getvalue().strip())

build_log="{}/build_attempt_{}.log".format(LOGDIR, datestring)

cmake="cmake"
if args.cmake_trace:
    cmake = "{} --trace"

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

    fullcmd="{} -DCMAKE_MESSAGE_LOG_LEVEL={} -DMOO_CMD={} -DDBT_ROOT={} -DDBT_DEBUG={} -DCMAKE_INSTALL_PREFIX={} {} {}".format(cmake, args.cmake_msg_lvl, moo_path, os.environ["DBT_ROOT"], args.debug_build, os.environ["DBT_INSTALL_DIR"], generator_arg, SRCDIR)

    fullcmd.split(" ")[1:]
    
    print("Executing '{}'".format(fullcmd))
    retval=pytee.run(fullcmd.split(" ")[0], fullcmd.split(" ")[1:], build_log)

    endtime_cfggen_d=get_time("as_date")
    endtime_cfggen_s=get_time("as_seconds_since_epoch")
    
    if retval == 0:
        cfggentime=int(endtime_cfggen_s) - int(starttime_cfggen_s)
        print("CMake's config+generate stages took {} seconds".format(cfggentime))
        print("Start time: {}".format(starttime_cfggen_d))
        print("End time:   {}".format(endtime_cfggen_d))
    else:
        shutil.move("CMakeCache.txt", "CMakeCache.txt.most_recent_failure")

        error("""

This script ran into a problem running 

{} 

from {} (i.e., CMake's config+generate stages). 
Scroll up for details or look at the build log via 

less -R {}

Exiting...

""".format(fullcmd, BUILDDIR, BUILDDIR))

else: 
    print("The config+generate stage was skipped as CMakeCache.txt was already found in {}".format(BUILDDIR))

if args.cmake_graphviz:
    output = sh.cmake(["--graphviz=graphviz/targets.dot", "."])
    sys.exit(output.exit_code)

if args.n_jobs:
    nprocs_argument = "-j {}".format(args.n_jobs)
else:
    nprocs = get_num_processors()
    nprocs_argument = "-j {}".format(nprocs)
    
    print("This script believes you have {} processors available on this system, and will use as many of them as it can".format(nprocs))

starttime_build_d=get_time("as_date")    
starttime_build_s=get_time("as_seconds_since_epoch")

build_options=""
if args.cpp_verbose:
    build_options=" --verbose"

if not args.cmake_trace:
    build_options="{} {}".format(build_options, nprocs_argument)

fullcmd="{} --build . {}".format(cmake, build_options)
print("Executing '{}'".format(fullcmd))
retval=pytee.run(fullcmd.split(" ")[0], fullcmd.split(" ")[1:], build_log)

endtime_build_d=get_time("as_date")
endtime_build_s=get_time("as_seconds_since_epoch")

if retval == 0:
    buildtime=int(endtime_build_s) - int(starttime_build_s)
else:
    error("""
This script ran into a problem running 

{} 

from {} (i.e.,
CMake's build stage). Scroll up for details or look at the build log via 

less -R {}

Exiting...
""".format(fullcmd, BUILDDIR, build_log))

stringio_obj4 = io.StringIO()

num_estimated_warnings = 0
try:
    sh.wc(sh.grep("warning: ", build_log), "-l", _out=stringio_obj4)
    num_estimated_warnings=stringio_obj4.getvalue().strip()
except sh.ErrorReturnCode_1:
    pass

print("")

if running_config_and_generate:
    print("CMake's config+generate+build stages all completed successfully")
    print("")
else:
    print("CMake's build stage completed successfully")

os.chdir(BUILDDIR)
fullcmd="cmake --build . --target install -- {}".format(nprocs_argument)
retval = pytee.run(fullcmd.split()[0], fullcmd.split()[1:], None)

if retval == 0:
    print("""
Installation complete.
This implies your code successfully compiled before installation; you can
either scroll up or run \"less -R {}\" to see build results""".format(build_log))
else:
    error("Installation failed. There was a problem running \"{}\". Exiting...".format(fullcmd))

if run_tests:
    stringio_obj5 = io.StringIO()
    sh.date(_out=stringio_obj5)
    datestring=re.sub("[: ]+", "_", stringio_obj5.getvalue().strip())

    test_log="{}/unit_tests_{}.log".format(LOGDIR, datestring)

    os.chdir(BUILDDIR)
    
    if args.unittest == "all":
        stringio_obj6 = io.StringIO()
        sh.find("-L . -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles".split(), _out = stringio_obj6)
        package_list = stringio_obj6.getvalue().split()
    else:
        package_list = [ package_to_test ]

    for pkgname in package_list:
        fullcmd=("find -L {}/{} -type d -name unittest -not -regex .*CMakeFiles.*".format(BUILDDIR, pkgname))
        stringio_obj7 = io.StringIO()
        sh.find(fullcmd.split()[1:], _out=stringio_obj7)
        unittestdirs = stringio_obj7.getvalue().split()

        if len(unittestdirs) == 0:
            print("{}No unit tests have been written for {}{}".format(Fore.RED, pkgname, Style.RESET_ALL), file = sys.stderr)            
            continue

        if not "BOOST_TEST_LOG_LEVEL" in os.environ:
            os.environ["BOOST_TEST_LOG_LEVEL"] = "all"

        num_unit_tests = 0

        for unittestdir in unittestdirs:
            print("""

RUNNING UNIT TESTS IN {}
======================================================================
""".format(unittestdir))
            for unittest in os.listdir(unittestdir):
                print("unittest == {}".format(unittest))
                if which("{}/{}".format(unittestdir, unittest), mode=os.X_OK) is not None:
                    pytee.run("echo", "-e Start of unit test suite {}".format(unittest).split(), test_log)
                    pytee.run("{}/{}".format(unittestdir, unittest), "", test_log)
                    #pytee.run("echo", "-e End of unit test suite {}".format(unittest).split(), test_log)
                    num_unit_tests += 1

            print("{}Testing complete for package \"{}\". Ran {} unit test suites.{}".format(Fore.YELLOW, pkgname, num_unit_tests, Style.RESET_ALL))
            print("")
            print("Test results are saved in {}".format(test_log))

if args.lint:
    os.chdir(BASEDIR)

    stringio_obj8 = io.StringIO()
    sh.date(_out=stringio_obj8)
    datestring=re.sub("[: ]+", "_", stringio_obj8.getvalue().strip())
    
    lint_log="{}/linting_{}.log".format(BASEDIR, datestring)

    if not os.path.exists("styleguide"):
        print("Cloning styleguide into {} so linting can be applied".format(os.getcwd()))
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
        print("Package to lint is {}".format(pkgname))
        fullcmd = "./styleguide/cpplint/dune-cpp-style-check.sh build sourcecode/{}".format(pkgname)
        pytee.run(fullcmd.split()[0], fullcmd.split()[1:], lint_log)

 
