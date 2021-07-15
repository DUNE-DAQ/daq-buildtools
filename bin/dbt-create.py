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
parser.add_argument("-n", "--nightly", nargs='?', const="no value")
parser.add_argument("-r", "--release-path", nargs='?', const="no value", action='store', dest='release_path')
parser.add_argument("-l", "--list", action="store_true", dest='list_arg')
parser.add_argument("release_tag_arg", nargs='?', const="no value")
parser.add_argument("workarea_dir", nargs='?', const="no value")

args = parser.parse_args()

RELEASE_BASEPATH=""
if args.release_path and args.release_path != "no value":
    RELEASE_BASEPATH=args.release_path
elif not args.nightly:
    RELEASE_BASEPATH=PROD_BASEPATH
elif args.nightly != "no value":
    RELEASE_BASEPATH="{}/{}".format(NIGHTLY_BASEPATH, args.nightly)

if args.list_arg:
    list_releases(RELEASE_BASEPATH)
    sys.exit(0)

# ...Figure out how to get -l -n to work...

RELEASE=args.release_tag_arg

stringio_obj = io.StringIO()
sh.realpath("-m", "{}/{}".format(RELEASE_BASEPATH, RELEASE), _out=stringio_obj)
RELEASE_PATH=stringio_obj.getvalue().strip()

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
    
sh.date(_out=stringio_obj)
starttime_d=stringio_obj.getvalue().strip()

sh.date("+%s", _out=stringio_obj)
starttime_s=stringio_obj.getvalue().strip()

if not os.path.exists(TARGETDIR):
    os.mkdir(TARGETDIR)

os.chdir(TARGETDIR)

BUILDDIR="{}/build".format(TARGETDIR)
LOGDIR="{}/log".format(TARGETDIR)
SRCDIR="{}/sourcecode".format(TARGETDIR)

# Deal with USER and HOSTNAME here

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
    copy(dbtfile, "/tmp")

copy("{}/{}".format(RELEASE_PATH, UPS_PKGLIST), "{}/{}".format(TARGETDIR, DBT_AREA_FILE))

os.symlink("{}/env.sh".format(DBT_ROOT), "{}/dbt-env.sh".format(TARGETDIR))
