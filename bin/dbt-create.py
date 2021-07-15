#!/bin/env python3

import argparse
import io
import os
import sh
from shutil import copy
import sys
from time import sleep

DBT_ROOT=os.environ["DBT_ROOT"]
sys.path.append('{}/scripts'.format(DBT_ROOT))

from dbt_setup_tools import DBT_AREA_FILE, error, list_releases

usage_blurb="""

Usage
-----

To create a new DUNE DAQ development area:
      
    {} [-r/--release-path <path to release area>] <dunedaq-release> <target directory>

To list the available DUNE DAQ releases:

    {} -l/--list [-r/--release-path <path to release area>]

Arguments and options:

    dunedaq-release: is the name of the release the new work area will be based on (e.g. dunedaq-v2.8.0)
    -n/--nightly: switch to nightly releases
    -l/--list: show the list of available releases
    -r/--release-path: is the path to the release archive (RELEASE_BASEPATH var; default: /cvmfs/dunedaq.opensciencegrid.org/releases)


""".format(os.path.basename(__file__), os.path.basename(__file__))

EMPTY_DIR_CHECK=True
PROD_BASEPATH="/cvmfs/dunedaq.opensciencegrid.org/releases"
NIGHTLY_BASEPATH="/cvmfs/dunedaq-development.opensciencegrid.org/nightly"
SHOW_RELEASE_LIST=False

UPS_PKGLIST="{}.sh".format(DBT_AREA_FILE)
PY_PKGLIST="pyvenv_requirements.txt"
DAQ_BUILDORDER_PKGLIST="dbt-build-order.cmake"

parser = argparse.ArgumentParser(usage=usage_blurb)
parser.add_argument("-n", "--nightly", action="store_true")
parser.add_argument("-r", "--release-path", action='store', dest='release_path')
parser.add_argument("-l", "--list", action="store_true", dest='list_arg')
parser.add_argument("release_tag_arg", nargs='?', const="no value")
parser.add_argument("workarea_dir", nargs='?')

args = parser.parse_args()

if args.release_path:
    RELEASE_BASEPATH=args.release_path
elif not args.nightly:
    RELEASE_BASEPATH=PROD_BASEPATH
else:
    RELEASE_BASEPATH=NIGHTLY_BASEPATH

if args.list_arg:
    list_releases(RELEASE_BASEPATH)
    sys.exit(0)

if not args.release_tag_arg or not args.workarea_dir:
    error("Wrong number of arguments. Run '{} -h' for more information.".format(os.path.basename(__file__)))

RELEASE=args.release_tag_arg

stringio_obj1 = io.StringIO()
sh.realpath("-m", "{}/{}".format(RELEASE_BASEPATH, RELEASE), _out=stringio_obj1)
RELEASE_PATH=stringio_obj1.getvalue().strip()

TARGETDIR=args.workarea_dir

if not os.path.exists(RELEASE_PATH):
    error("Release path '{}' does not exist. Exiting...".format(RELEASE_PATH))

if "DBT_WORKAREA_ENV_SCRIPT_SOURCED" in os.environ:
    error("""
It appears you're trying to run this script from an environment                                             
where another development area's been set up.  You'll want to run this                                      
from a clean shell. Exiting... 
"""
)
    
stringio_obj2 = io.StringIO()
sh.date(_out=stringio_obj2)
starttime_d=stringio_obj2.getvalue().strip()

stringio_obj3 = io.StringIO()
sh.date("+%s", _out=stringio_obj3)
starttime_s=stringio_obj3.getvalue().strip()

if not os.path.exists(TARGETDIR):
    os.mkdir(TARGETDIR)

os.chdir(TARGETDIR)
TARGETDIR=os.getcwd() # Get full path

BUILDDIR="{}/build".format(TARGETDIR)
LOGDIR="{}/log".format(TARGETDIR)
SRCDIR="{}/sourcecode".format(TARGETDIR)

if "USER" not in os.environ:
    error("Environment variable \"USER\" should be set. Try \"export USER=$(whoami)\"")

if "HOSTNAME" not in os.environ:
    error("Environment variable \"HOSTNAME\" should be set. Try \"export HOSTNAME=$(hostname)\"")


if EMPTY_DIR_CHECK and len(os.listdir(".")) > 0:
    error("""
There appear to be files in {} besides this script                                                  
(run "ls -a1 {}" to see this); this script should only be run in a clean                                       
directory. Exiting...  
""".format(TARGETDIR, TARGETDIR))
elif not EMPTY_DIR_CHECK:
    print("""
WARNING: The check for whether any files besides this script exist in                                       
its directory has been switched off. This may mean assumptions the                                          
script makes are violated, resulting in undesired behavior.    
    """, file=sys.stderr)
    sleep(5)

for workareadir in [BUILDDIR, LOGDIR, SRCDIR]:
    os.mkdir(workareadir)

os.chdir(SRCDIR)

for dbtfile in ["{}/configs/CMakeLists.txt".format(DBT_ROOT), \
                "{}/configs/CMakeGraphVizOptions.cmake".format(DBT_ROOT), \
                "{}/{}".format(RELEASE_PATH, DAQ_BUILDORDER_PKGLIST)
                ]:
    copy(dbtfile, SRCDIR)

copy("{}/{}".format(RELEASE_PATH, UPS_PKGLIST), "{}/{}".format(TARGETDIR, DBT_AREA_FILE))

os.symlink("{}/env.sh".format(DBT_ROOT), "{}/dbt-env.sh".format(TARGETDIR))

print("Setting up the Python subsystem. Please be patient, this should take O(1 minute)...")

cmd=sh.Command("{}/scripts/dbt-create-pyvenv.sh".format(DBT_ROOT))
cmd("{}/{}".format(RELEASE_PATH, PY_PKGLIST))

stringio_obj4 = io.StringIO()
sh.date(_out=stringio_obj4)
endtime_d=stringio_obj4.getvalue().strip()

stringio_obj5 = io.StringIO()
sh.date("+%s", _out=stringio_obj5)
endtime_s=stringio_obj5.getvalue().strip()

print("""
Total time to run {}: {} seconds
Start time: {}
End time:   {}

See https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-buildtools/index.html for build instructions

Script completed successfully

""".format(__file__, int(endtime_s) - int(starttime_s), starttime_d, endtime_d))

